#import "TserverAuthBootstrap.h"
#import "TserverAuth.h"
#import "TserverAuthConfig.h"
#import "TserverAuthEndpoint.h"
#import "TserverSecurity.h"
#import "TserverSecurityPolicy.h"
#import "TserverLogGuard.h"
#import "TserverTransportSession.h"
#import "TserverGateUI.h"
#import "TserverFridaGuard.h"
#import "TserverModReady.h"
#import "TserverUUIDCallback.h"
#import "TserverAuthorizationLease.h"
#import "TserverActivationAttempt.h"
#import "TserverTemplateRegistry.h"
#import "APIClient.h"
#import <UIKit/UIKit.h>

/// Implemented in TserverGateWindow.mm. Declared here so the auth lifecycle can
/// keep capture protection alive after the gate is dismissed.
@interface TserverGateWindow : NSObject
+ (instancetype)shared;
- (void)setHostCaptureProtectionActive:(BOOL)active;
@end

FOUNDATION_EXPORT void TserverCallbackBridgePrepare(void);
#ifdef __cplusplus
extern "C" {
#endif
BOOL TserverAuthUiConfigIntegrityAllowsPersist(NSDictionary *result);
NSDictionary *TserverAuthUiVerifiedCacheEnvelope(NSDictionary *result);
#ifdef __cplusplus
}
#endif

static BOOL gTserverAuthStarted = NO;
static BOOL gTserverAuthChecking = NO;
static BOOL gTserverProfileReconcileInFlight = NO;
static BOOL gTserverAuthScheduled = NO;
static BOOL gTserverAuthHeartbeatScheduled = NO;
static BOOL gTserverAuthHeartbeatInFlight = NO;
static BOOL gTserverAuthLeaseWasAuthorized = NO;
static NSUInteger gTserverAuthAuthorizationEpoch = 1;
static NSUInteger gTserverAuthDeliveredEpoch = 0;
static TserverAuthReadyBlock gTserverAuthOnValid = nil;
static NSString *gTserverRuntimePackageToken = nil;
static NSString *gTserverRuntimeReturnScheme = nil;
static NSDictionary *gTserverInitialAuthUiConfig = nil;
static NSUInteger gTserverBootstrapConfigGeneration = 1;

static void TserverAuthRunCheck(void);
static void TserverAuthScheduleCheck(NSInteger attempt);
static void TserverAuthScheduleHeartbeat(NSTimeInterval delay);
static void TserverAuthRunHeartbeat(void);
static void TserverAuthObserveLeaseState(void);
static void TserverAuthDispatchValidIfNeeded(void);
static void TserverAuthReconcilePendingProfile(NSInteger attempt);
static BOOL TserverAuthHostLooksReady(void);
static BOOL TserverPackageTokenLooksConfigured(NSString *packageToken);

static void GVTAuthShowLoadingGate(void);

static NSString * const kGVTFirstResourceSyncKey = @"com.gvt.mod.firstResourceSyncDone";

@interface TserverStorage : NSObject
+ (void)configureNamespaceWithPackageToken:(NSString *)packageToken bundleId:(NSString *)bundleId;
+ (NSDictionary *)lastValidPayload;
+ (NSDictionary *)lastAuthUiConfig;
+ (void)saveLastAuthUiConfig:(NSDictionary *)config;
@end

static NSDictionary *GVTAuthCachedPayload(void) {
    NSDictionary *payload = [TserverStorage lastValidPayload];
    return [payload isKindOfClass:NSDictionary.class] ? payload : nil;
}

static NSString *TserverTrimConfigString(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static NSString *TserverConfiguredPackageToken(void) {
    NSString *runtime = TserverTrimConfigString(gTserverRuntimePackageToken);
    if (TserverPackageTokenLooksConfigured(runtime)) return runtime;
    // Prefer obfuscated embed when enabled (see TserverAuthConfig.h helper).
    NSString *resolved = TserverResolvedPackageToken();
    if (TserverPackageTokenLooksConfigured(resolved)) return TserverTrimConfigString(resolved);
    return TserverTrimConfigString(kTserverPackageToken);
}

static NSString *TserverConfiguredReturnScheme(void) {
    NSString *runtime = TserverTrimConfigString(gTserverRuntimeReturnScheme);
    if (runtime.length > 0) return runtime;
    NSString *compiled = TserverTrimConfigString(kTserverReturnScheme);
    return compiled.length > 0 ? compiled : @"auto";
}

static BOOL TserverPackageTokenLooksConfigured(NSString *packageToken) {
    NSString *token = TserverTrimConfigString(packageToken);
    if (token.length < 24) return NO;
    if ([token rangeOfString:@"REPLACE" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    return YES;
}

void TserverAuthBootstrapConfigure(NSString *packageToken) {
    @synchronized([TserverAuth class]) {
        NSString *nextToken = TserverTrimConfigString(packageToken);
        BOOL nextConfigured = TserverPackageTokenLooksConfigured(nextToken);
        BOOL currentConfigured = TserverPackageTokenLooksConfigured(gTserverRuntimePackageToken);
        BOOL identityChanged = nextConfigured && currentConfigured && ![nextToken isEqualToString:gTserverRuntimePackageToken];
        if (nextConfigured || !currentConfigured) {
            if (identityChanged) {
                TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
                [TserverTransportSession clear];
            }
            gTserverRuntimePackageToken = [nextToken copy];
            [TserverStorage configureNamespaceWithPackageToken:gTserverRuntimePackageToken bundleId:[TserverAuth currentBundleId]];
        }
        // UI selection belongs only to the package configuration on the web.
        // Do not guess from a build hint, catalog default, or previous cache. Keep a
        // transparent touch blocker until this run receives a hash-verified config.
        gTserverInitialAuthUiConfig = nil;
        [TserverGateUI clearAuthConfig];
        gTserverBootstrapConfigGeneration++;
        gTserverRuntimeReturnScheme = @"auto";
    }
}

static void TserverAuthObserveLeaseState(void) {
    BOOL authorized = TserverAuthorizationLeaseIsAuthorized();
    if (!authorized && gTserverAuthLeaseWasAuthorized) {
        gTserverAuthLeaseWasAuthorized = NO;
        gTserverAuthAuthorizationEpoch++;
        return;
    }
    if (authorized) {
        gTserverAuthLeaseWasAuthorized = YES;
    }
}

static void TserverAuthDispatchValidIfNeeded(void) {
    TserverAuthObserveLeaseState();
    if (!TserverAuthorizationLeaseIsAuthorized() ||
        gTserverAuthDeliveredEpoch == gTserverAuthAuthorizationEpoch) {
        return;
    }

    NSUInteger epoch = gTserverAuthAuthorizationEpoch;
    NSDictionary *leaseInfo = TserverAuthorizationLeaseLicenseInfo();
    TserverDiagnosticsPostLease(YES, [leaseInfo[@"remainingSeconds"] doubleValue]);
    // The gate is about to be dismissed and its own cover goes with it. Protect
    // the host content for as long as the paid capability stays unlocked.
    [[TserverGateWindow shared] setHostCaptureProtectionActive:YES];
    TserverDiagnosticsPostStatus(TserverStatusCodeString(TserverStatusCodeValid), @{
        @"status": TserverStatusCodeString(TserverStatusCodeValid),
        @"message": @"paid capability unlocked"
    });
    [TserverGateUI dismiss];
    // Ask the server once shortly after the paid menu opens. A package notice
    // published before this launch only exists in a fresh signed response, so the
    // first check must not wait for the regular 60s heartbeat. TserverAuthScheduleHeartbeat
    // keeps only the earliest pending timer, so the 60s cadence resumes after it.
    TserverAuthScheduleHeartbeat(1.5);
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kGVTFirstResourceSyncKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    TserverModReadyDispatch(^{
        if (epoch != gTserverAuthAuthorizationEpoch ||
            gTserverAuthDeliveredEpoch == epoch ||
            !TserverAuthorizationLeaseAllowsCapability(@"paid")) {
            return;
        }
        gTserverAuthDeliveredEpoch = epoch;
        TserverAuthReadyBlock unlock = [gTserverAuthOnValid copy];
        if (unlock) {
            unlock();
        }
    });
}

static NSDictionary *GVTAuthBootstrapLoadingConfig(void) {
    NSDictionary *base = [gTserverInitialAuthUiConfig isKindOfClass:NSDictionary.class]
        ? gTserverInitialAuthUiConfig
        : @{};
    if (base.count == 0) {
        NSDictionary *lastCached = [TserverStorage lastAuthUiConfig];
        if ([lastCached[@"config"] isKindOfClass:NSDictionary.class]) {
            base = lastCached[@"config"];
            gTserverInitialAuthUiConfig = [base copy];
        }
    }
    if (base.count == 0) {
        // Cold launch / no cache: still show spinner card, never transparent blocker.
        return [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:@{}];
    }
    NSMutableDictionary *config = [base mutableCopy];
    NSMutableDictionary *screens = [([base[@"screens"] isKindOfClass:NSDictionary.class]
        ? base[@"screens"]
        : @{}) mutableCopy];
    NSMutableDictionary *loading = [([screens[@"loading"] isKindOfClass:NSDictionary.class]
        ? screens[@"loading"]
        : @{}) mutableCopy];
    if (![loading[@"title"] isKindOfClass:NSString.class] || [loading[@"title"] length] == 0) {
        loading[@"title"] = @"Đang kiểm tra";
    }
    loading[@"subtitle"] = @"Vui lòng chờ trong giây lát…";
    screens[@"loading"] = [loading copy];
    config[@"screens"] = [screens copy];
    return [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:config];
}

static void GVTAuthShowLoadingGate(void) {
    if ([TserverGateUI isVisible]) return;
    if (TserverAuthorizationLeaseIsAuthorized() && gTserverAuthDeliveredEpoch == gTserverAuthAuthorizationEpoch) return;
    NSDictionary *loadingConfig = GVTAuthBootstrapLoadingConfig();
    [TserverGateUI configureWithAuthConfig:loadingConfig];
    [TserverGateUI showLoadingWithMessage:@"Đang kiểm tra bản quyền…"];
}

static void TserverAuthBootstrapStartPrepared(TserverAuthReadyBlock onValid,
                                               TserverAuthBootstrapPreparedBlock onPrepared) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // A key-confirmation caller may prepare the gate without replacing an
        // already registered paid/bootstrap callback.
        if (onValid && gTserverAuthOnValid != onValid) {
            gTserverAuthOnValid = [onValid copy];
        }

        TserverSecurityStartWatchdog();
        // Silence accidental console output without treating jailbreak/debug tools
        // as authorization failures. Signed transport and lease proofs remain mandatory.
        TserverLogGuardStart();
        if (TserverSecurityPolicyForceUpdate()) {
            NSMutableDictionary *failure = [@{
                @"ok": @NO,
                @"terminal": @YES,
                @"status": TserverStatusUpdateRequired,
                @"message": @"Cần cập nhật bản mod mới.",
                @"stage": @"configuration",
                @"errorCode": @"force_update"
            } mutableCopy];
            NSString *updateUrl = TserverSecurityPolicyForceUpdateUrl();
            if (updateUrl.length > 0) failure[@"updateUrl"] = updateUrl;
            [TserverGateUI showWithResult:failure];
            [TserverActivationAttempt publishTerminalResult:failure];
            if (onPrepared) onPrepared([failure copy]);
            return;
        }

        // baseURL + client API key are baked/runtime-gated (not customer config).
        // Customer only supplies packageToken via TserverAuthConfig.h.
        NSMutableArray<NSString *> *endpoints = [NSMutableArray array];
        NSString *primary = TserverCompiledPrimaryEndpoint();
        NSString *fallback = TserverCompiledFallbackEndpoint();
        if (primary.length > 0) [endpoints addObject:primary];
        if (fallback.length > 0) [endpoints addObject:fallback];
        NSString *packageToken = TserverConfiguredPackageToken();
        if (endpoints.count == 0 || !TserverPackageTokenLooksConfigured(packageToken)) {
            NSDictionary *failure = @{
                @"ok": @NO,
                @"terminal": @YES,
                @"status": TserverStatusServerError,
                @"message": @"Thiếu cấu hình xác thực.",
                @"stage": @"configuration",
                @"errorCode": @"missing_auth_config"
            };
            [TserverGateUI showWithResult:failure];
            [TserverActivationAttempt publishTerminalResult:failure];
            if (onPrepared) onPrepared([failure copy]);
            return;
        }
        [TserverAuth configureWithEndpoints:endpoints
                              packageToken:packageToken
                              returnScheme:TserverConfiguredReturnScheme()];
        // A Device Verify flow is impossible without a URL scheme registered by
         // the host app. Fail closed before opening Safari so a missing scheme
         // cannot bounce the user out of the app or create a callback loop.
         if (![TserverAuth isReturnSchemeRegisteredInHostApp]) {
             NSDictionary *failure = @{
                 @"ok": @NO,
                 @"terminal": @YES,
                 @"status": TserverStatusUIFailure,
                 @"message": @"App chưa khai báo URL Scheme. Hãy thêm CFBundleURLSchemes vào Info.plist rồi build lại.",
                 @"stage": @"configuration",
                 @"errorCode": @"return_scheme_not_registered"
             };
             [TserverGateUI showWithResult:failure];
             [TserverActivationAttempt publishTerminalResult:failure];
             if (onPrepared) onPrepared([failure copy]);
             return;
         }

         TserverCallbackBridgePrepare();
        TserverAuthDrainPendingCallbackURLs();

        if (!gTserverAuthStarted) {
            gTserverAuthStarted = YES;
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
                // Re-check before anything else: a hook can be attached while
                // the app sits in the background.
                [TserverFridaGuard enforceAndTerminateIfPresent];
                if (TserverAuthorizationLeaseIsAuthorized()) {
                    [[TserverGateWindow shared] setHostCaptureProtectionActive:YES];
                    TserverDiagnosticsPostNetwork(YES, 0);
                    TserverAuthDispatchValidIfNeeded();
                    TserverAuthScheduleHeartbeat(1.0);
                    return;
                }
                if (gTserverAuthChecking || [TserverAuth isActivationInFlight]) {
                    return;
                }
                if ([TserverAuth isAwaitingProfileConfirmation]) {
                    TserverAuthReconcilePendingProfile(0);
                    return;
                }
                // Gate visibility is presentation state, not authorization state.
                // A Profile Service custom-scheme callback can be lost, so every
                // unauthorized foreground must reconcile with the server even
                // while the UUID/key gate remains visible.
                TserverAuthScheduleCheck(0);
            }];
            [[NSNotificationCenter defaultCenter]
                addObserverForName:TserverUUIDCallbackDidReceiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) {
                if ([TserverAuth isActivationInFlight]) {
                    return;
                }
                if (TserverAuthorizationLeaseIsAuthorized()) {
                    TserverAuthDispatchValidIfNeeded();
                    return;
                }
                NSDictionary *callbackResult = [note.userInfo[@"result"] isKindOfClass:NSDictionary.class]
                    ? note.userInfo[@"result"]
                    : nil;
                [TserverGateUI showLoadingWithMessage:@"Dang dong bo xac nhan thiet bi..."];
                NSString *callbackStatus = [callbackResult[@"status"] isKindOfClass:NSString.class]
                    ? callbackResult[@"status"]
                    : @"";
                if (callbackResult.count > 0 && ![callbackStatus isEqualToString:TserverStatusNeedUUID]) {
                    [TserverGateUI showWithResult:callbackResult];
                    return;
                }
                TserverAuthReconcilePendingProfile(0);
            }];
            [TserverGateUI setOnValid:^(__unused NSDictionary *result) {
                // UI is never an authorization authority. It may only complete
                // the transition after the server lease has already verified.
                TserverAuthDispatchValidIfNeeded();
            }];
        }

        GVTAuthShowLoadingGate();
        NSUInteger loadingGeneration = gTserverBootstrapConfigGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (loadingGeneration == gTserverBootstrapConfigGeneration) GVTAuthShowLoadingGate();
        });

        if (onPrepared) onPrepared(nil);
        TserverAuthScheduleCheck(0);
    });
}

void TserverAuthBootstrapStart(TserverAuthReadyBlock onValid) {
    TserverAuthBootstrapStartPrepared(onValid, nil);
}

void TserverAuthBootstrapStartWithPrepared(
    TserverAuthReadyBlock onValid,
    TserverAuthBootstrapPreparedBlock onPrepared
) {
    TserverAuthBootstrapStartPrepared(onValid, onPrepared);
}

BOOL TserverAuthBootstrapIsValid(void) {
    return TserverAuthorizationLeaseIsAuthorized();
}

static BOOL TserverAuthHostLooksReady(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState == UIApplicationStateBackground) {
        return NO;
    }
    for (UIWindow *window in app.windows) {
        if (!window || window.hidden || !window.rootViewController) continue;
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (top.isViewLoaded && top.view.window) {
            return YES;
        }
    }
    if ([app respondsToSelector:@selector(connectedScenes)]) {
        @try {
            NSSet *scenes = [app valueForKey:@"connectedScenes"];
            for (id scene in scenes) {
                if (![NSStringFromClass([scene class]) containsString:@"WindowScene"]) continue;
                NSArray *sceneWindows = [scene valueForKey:@"windows"];
                for (UIWindow *window in sceneWindows) {
                    if (window && !window.hidden && window.rootViewController) {
                        return YES;
                    }
                }
            }
        } @catch (__unused NSException *exception) {
        }
    }
    for (UIWindow *window in app.windows) {
        if (window && !window.hidden && window.rootViewController) return YES;
    }
    return NO;
}

static BOOL TserverAuthShouldFastPath(void) {
    if ([TserverAuth savedSessionToken].length > 0) {
        return YES;
    }
    if (GVTAuthCachedPayload() != nil) {
        return YES;
    }
    return NO;
}

static void TserverAuthScheduleCheck(NSInteger attempt) {
    TserverAuthObserveLeaseState();
    if ([TserverAuth isActivationInFlight]) {
        return;
    }
    if (TserverAuthorizationLeaseIsAuthorized() && gTserverAuthDeliveredEpoch == gTserverAuthAuthorizationEpoch) {
        TserverAuthDispatchValidIfNeeded();
        return;
    }
    if (gTserverAuthChecking) {
        return;
    }
    if (gTserverAuthScheduled && attempt == 0) {
        return;
    }
    gTserverAuthScheduled = YES;

    BOOL fastPath = TserverAuthShouldFastPath();
    NSInteger maxWindowAttempts = fastPath ? 8 : 48;
    NSTimeInterval pollInterval = fastPath ? 0.1 : 0.25;

    if (!TserverAuthHostLooksReady() && attempt < maxWindowAttempts) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pollInterval * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            gTserverAuthScheduled = NO;
            TserverAuthScheduleCheck(attempt + 1);
        });
        return;
    }

    if (!fastPath && attempt < (NSInteger)kTserverGateColdStartMinAttemptsConfig) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pollInterval * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            gTserverAuthScheduled = NO;
            TserverAuthScheduleCheck(attempt + 1);
        });
        return;
    }

    NSTimeInterval settle = fastPath ? 0.05 : kTserverGateColdStartDelaySecondsConfig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(settle * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gTserverAuthScheduled = NO;
        TserverAuthRunCheck();
    });
}

static void TserverAuthReconcilePendingProfile(NSInteger attempt) {
    if ([TserverAuth isActivationInFlight]) {
        return;
    }
    if (TserverAuthorizationLeaseIsAuthorized()) {
        gTserverProfileReconcileInFlight = NO;
        TserverAuthDispatchValidIfNeeded();
        return;
    }
    if (gTserverProfileReconcileInFlight && attempt == 0) {
        return;
    }
    gTserverProfileReconcileInFlight = YES;
    NSUInteger reconcileGeneration = [TserverAuth activationGeneration];
    [TserverGateUI showLoadingWithMessage:attempt == 0
        ? @"Dang xac minh thiet bi..."
        : @"Dang kiem tra xac nhan thiet bi..."];
    [TserverAuth refreshAuthAfterProfileInstallWithCompletion:^(NSDictionary *result) {
        // This request may have started before a key activation. Its NEED_KEY /
        // NEED_UUID result is stale and must never replace the activation UI.
        if ([TserverAuth isActivationInFlight] || reconcileGeneration != [TserverAuth activationGeneration]) {
            gTserverProfileReconcileInFlight = NO;
            return;
        }
        if (TserverAuthorizationLeaseIsAuthorized() && gTserverAuthDeliveredEpoch == gTserverAuthAuthorizationEpoch) {
            gTserverProfileReconcileInFlight = NO;
            TserverAuthDispatchValidIfNeeded();
            return;
        }
        NSDictionary *safeResult = [result isKindOfClass:NSDictionary.class] ? result : @{};
        NSString *status = [safeResult[@"status"] isKindOfClass:NSString.class] ? safeResult[@"status"] : TserverStatusServerError;
        if ([status isEqualToString:TserverStatusNeedUUID] && [TserverAuth isAwaitingProfileConfirmation]) {
            if (attempt < 6) {
                NSTimeInterval delay = MIN(5.0, 0.6 + (attempt * 0.7));
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    TserverAuthReconcilePendingProfile(attempt + 1);
                });
                return;
            }
            // Stop continuous polling after the retry budget, but preserve the
            // durable pending marker. A missed custom-scheme callback must still
            // be reconciled on the next foreground instead of being rendered as
            // permission to allocate another UUID profile immediately.
            [TserverAuth setAwaitingProfileConfirmation:YES];
        }
        gTserverProfileReconcileInFlight = NO;
        [TserverGateUI showWithResult:safeResult];
    }];
}

static void TserverAuthScheduleHeartbeat(NSTimeInterval delay) {
    if (!TserverAuthorizationLeaseIsAuthorized() || gTserverAuthHeartbeatScheduled || gTserverAuthHeartbeatInFlight) {
        return;
    }
    gTserverAuthHeartbeatScheduled = YES;
    NSTimeInterval safeDelay = delay > 0 ? delay : 60.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(safeDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gTserverAuthHeartbeatScheduled = NO;
        TserverAuthRunHeartbeat();
    });
}

static void TserverAuthRunHeartbeat(void) {
    if (!TserverAuthorizationLeaseIsAuthorized() || gTserverAuthHeartbeatInFlight) {
        return;
    }
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState == UIApplicationStateBackground) {
        TserverAuthScheduleHeartbeat(60.0);
        return;
    }
    gTserverAuthHeartbeatInFlight = YES;
    NSUInteger heartbeatActivationGeneration = [TserverAuth activationGeneration];
    [TserverAuth verifyWithCompletion:^(NSDictionary *result) {
        gTserverAuthHeartbeatInFlight = NO;
        if ([TserverAuth isActivationInFlight] ||
            heartbeatActivationGeneration != [TserverAuth activationGeneration]) {
            TserverAuthScheduleHeartbeat(60.0);
            return;
        }
        NSDictionary *safeResult = [result isKindOfClass:NSDictionary.class] ? result : @{};
        NSString *status = [safeResult[@"status"] isKindOfClass:NSString.class]
            ? safeResult[@"status"]
            : TserverStatusServerError;
        TserverDiagnosticsPostStatus(status, safeResult);
        if (([status isEqualToString:TserverStatusValid] || [status isEqualToString:TserverStatusOfflineGraceValid]) &&
            TserverAuthorizationLeaseIsAuthorized()) {
            // A package operator announcement can arrive while the paid menu is
            // already running. The gate presents it centrally for every native
            // UI pack; it is not an authorization result and cannot grant work.
            [TserverGateUI presentNoticeIfNeeded:safeResult];
            TserverAuthScheduleHeartbeat(60.0);
            return;
        }
        if ([status isEqualToString:TserverStatusNetworkError] || [status isEqualToString:TserverStatusServerError]) {
            TserverAuthScheduleHeartbeat(30.0);
            return;
        }
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
        TserverDiagnosticsPostLease(NO, 0);
        [[TserverGateWindow shared] setHostCaptureProtectionActive:NO];
        [TserverGateUI showWithResult:safeResult.count > 0 ? safeResult : @{
            @"ok": @NO,
            @"status": status,
            @"message": @"Auth heartbeat failed"
        }];
    }];
}

static void TserverAuthRunCheck(void) {
    TserverAuthObserveLeaseState();
    if ([TserverAuth isActivationInFlight]) {
        return;
    }
    if (TserverAuthorizationLeaseIsAuthorized() && gTserverAuthDeliveredEpoch == gTserverAuthAuthorizationEpoch) {
        TserverAuthDispatchValidIfNeeded();
        return;
    }
    if (gTserverAuthChecking) {
        return;
    }
    GVTAuthShowLoadingGate();
    gTserverAuthChecking = YES;
    NSUInteger checkGeneration = [TserverAuth activationGeneration];
    [TserverAuth bootstrapWithCompletion:^(NSDictionary *result) {
        gTserverAuthChecking = NO;
        // Activation owns the result/UI until it reaches a terminal status.
        // Discard bootstrap responses that were already in flight when the key
        // was submitted, especially a late NEED_KEY response.
        if ([TserverAuth isActivationInFlight] || checkGeneration != [TserverAuth activationGeneration]) {
            return;
        }
        NSDictionary *safeResult = [result isKindOfClass:NSDictionary.class] ? result : @{
            @"ok": @NO,
            @"status": TserverStatusServerError,
            @"message": @"Empty auth result"
        };
        // Report every status the user can be in, so an integrator can observe
        // the whole journey instead of guessing.
        TserverDiagnosticsPostStatus(safeResult[@"status"], safeResult);
        NSString *status = [safeResult[@"status"] isKindOfClass:NSString.class]
            ? safeResult[@"status"]
            : TserverStatusServerError;
        NSDictionary *config = [safeResult[@"authUiConfig"] isKindOfClass:NSDictionary.class]
            ? safeResult[@"authUiConfig"]
            : @{};
        if (config.count > 0 && TserverAuthUiConfigIntegrityAllowsPersist(safeResult)) {
            gTserverInitialAuthUiConfig = [config copy];
            [TserverGateUI configureWithAuthConfig:config];
            NSDictionary *cacheEnvelope = TserverAuthUiVerifiedCacheEnvelope(safeResult);
            if (cacheEnvelope.count > 0 && [TserverStorage respondsToSelector:@selector(saveLastAuthUiConfig:)]) {
                [TserverStorage saveLastAuthUiConfig:cacheEnvelope];
            }
        }
        BOOL hasVerifiedUi = gTserverInitialAuthUiConfig.count > 0;
        if (!hasVerifiedUi) {
            // Keep spinner visible instead of transparent blocker while waiting for signed UI.
            GVTAuthShowLoadingGate();
            if ([status isEqualToString:TserverStatusNetworkError] ||
                [status isEqualToString:TserverStatusServerError] ||
                [status isEqualToString:@"RATE_LIMITED"] ||
                [status isEqualToString:@"VALIDATION_ERROR"]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ TserverAuthScheduleCheck(0); });
            }
            return;
        }
        if ([status isEqualToString:TserverStatusNetworkError] ||
            [status isEqualToString:@"RATE_LIMITED"] ||
            [status isEqualToString:@"VALIDATION_ERROR"]) {
            [TserverGateUI showNetworkErrorWithConfig:safeResult retry:^{
                [TserverGateUI showLoadingWithMessage:@"Dang thu ket noi lai..."];
                TserverAuthScheduleCheck(0);
            }];
            return;
        }
        if ([status isEqualToString:TserverStatusServerError]) {
            [TserverGateUI showServerErrorWithConfig:safeResult retry:^{
                [TserverGateUI showLoadingWithMessage:@"Dang thu ket noi lai..."];
                TserverAuthScheduleCheck(0);
            }];
            return;
        }
        if ([status isEqualToString:TserverStatusBadResponseSignature]) {
            [TserverGateUI showWithResult:safeResult];
            return;
        }
        if ([status isEqualToString:TserverStatusInvalidApiKey] ||
            [status isEqualToString:TserverStatusPackageBundleDenied]) {
            [TserverGateUI showWithResult:safeResult];
            return;
        }
        [TserverGateUI showWithResult:safeResult];
    }];
}