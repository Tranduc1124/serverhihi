#import "TserverAuth.h"
#import "TserverClientApiKey.h"
#import "TserverSecurity.h"
#import "TserverSecurityPolicy.h"
#import "TserverRuntimeIntegrity.h"
#import "TserverTransportSession.h"
#import "TserverAuthEndpoint.h"
#import "TserverAuthorizationLease.h"
#import "TserverActivationAttempt.h"
#import "TserverSealedConstants.h"
#import "TserverStringCrypto.h"
#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT void TserverCallbackBridgePrepare(void);

NSString * const TserverStatusValid = @"VALID";
NSString * const TserverStatusNeedUUID = @"NEED_UUID";
NSString * const TserverStatusNeedKey = @"NEED_KEY";
NSString * const TserverStatusExpired = @"EXPIRED";
NSString * const TserverStatusRevoked = @"REVOKED";
NSString * const TserverStatusInvalidKey = @"INVALID_KEY";
NSString * const TserverStatusDeviceMismatch = @"DEVICE_MISMATCH";
NSString * const TserverStatusDeviceBlocked = @"DEVICE_BLOCKED";
NSString * const TserverStatusBadSession = @"BAD_SESSION";
NSString * const TserverStatusServerError = @"SERVER_ERROR";
NSString * const TserverStatusNetworkError = @"NETWORK_ERROR";
NSString * const TserverStatusTrialAlreadyUsed = @"TRIAL_ALREADY_USED";
NSString * const TserverStatusOfflineGraceValid = @"OFFLINE_GRACE_VALID";
NSString * const TserverStatusOfflineGraceExpired = @"OFFLINE_GRACE_EXPIRED";
NSString * const TserverStatusBadResponseSignature = @"BAD_RESPONSE_SIGNATURE";
NSString * const TserverStatusInvalidApiKey = @"INVALID_API_KEY";
NSString * const TserverStatusInvalidClientApiKey = @"INVALID_CLIENT_API_KEY";
NSString * const TserverStatusClientKeyUnavailable = @"CLIENT_KEY_UNAVAILABLE";
NSString * const TserverStatusPackageBundleDenied = @"PACKAGE_BUNDLE_DENIED";
NSString * const TserverStatusBadPackageSession = @"BAD_PACKAGE_SESSION";
NSString * const TserverStatusUpdateRequired = @"UPDATE_REQUIRED";
NSString * const TserverStatusMaintenance = @"MAINTENANCE";
NSString * const TserverStatusBadClientSignature = @"BAD_CLIENT_SIGNATURE";
NSString * const TserverStatusReplayRequest = @"REPLAY_REQUEST";
NSString * const TserverStatusRateLimited = @"RATE_LIMITED";
NSString * const TserverStatusAuthorizationLeaseInvalid = @"AUTHORIZATION_LEASE_INVALID";
NSString * const TserverStatusActivationTimeout = @"ACTIVATION_TIMEOUT";
NSString * const TserverStatusActivationCancelled = @"ACTIVATION_CANCELLED";
NSString * const TserverStatusUnsafeEnvironment = @"UNSAFE_ENVIRONMENT";
NSString * const TserverStatusCallbackFailure = @"CALLBACK_FAILURE";
NSString * const TserverStatusUIFailure = @"UI_FAILURE";
NSString * const TserverStatusTransportSessionError = @"TRANSPORT_SESSION_ERROR";

NSString * const TserverSDKBuildIdentifier = @"2.1.0";
static NSString * const TserverSDKVersion = @"2.1.0";

static NSString *TserverSealedNSString(size_t index) {
    const char *value = TserverSealedStringAt(index);
    return value && value[0] ? [NSString stringWithUTF8String:value] : @"";
}

static NSString *TserverSealedHTTPSBaseURL(void) {
    NSString *host = TserverSealedNSString(kTserverSealedStr_ApiHost);
    NSString *scheme = TserverSealedNSString(kTserverSealedStr_HttpsScheme);
    if (host.length == 0 || scheme.length == 0) return @"";
    return [scheme stringByAppendingString:host];
}

static NSString *TserverEndpoint = nil;
static NSArray<NSString *> *TserverEndpoints = nil;
static NSString *TserverPackageToken = nil;
static NSString *TserverReturnScheme = nil;
static TserverCompletion TserverProfileFlowCompletion = nil;

// TserverHttp stores client-only status/header data here so its annotations do
// not become part of the signed server response. Flatten it only after the
// signature verdict has been determined.
static NSDictionary *TserverResponseWithClientMetadata(NSDictionary *response) {
    if (![response isKindOfClass:NSDictionary.class]) return response;
    NSMutableDictionary *output = [response mutableCopy];
    NSDictionary *meta = [output[@"_tserverClientResponseMeta"] isKindOfClass:NSDictionary.class]
        ? output[@"_tserverClientResponseMeta"]
        : nil;
    [output removeObjectForKey:@"_tserverClientResponseMeta"];
    id requestId = meta[@"requestId"];
    id httpStatus = meta[@"httpStatus"];
    if (!output[@"requestId"] && [requestId isKindOfClass:NSString.class] && [requestId length] > 0) {
        output[@"requestId"] = requestId;
    }
    if (!output[@"httpStatus"] && [httpStatus respondsToSelector:@selector(integerValue)] && [httpStatus integerValue] > 0) {
        output[@"httpStatus"] = httpStatus;
    }
    return [output copy];
}
static BOOL TserverProfileFlowInFlight = NO;
static BOOL TserverAwaitingProfileConfirmation = NO;
static BOOL TserverProfileRefreshInFlight = NO;
static NSMutableArray<TserverCompletion> *TserverProfileRefreshCompletions = nil;
static const NSTimeInterval TserverProfileConfirmationWindowSeconds = 90.0;

@interface TserverHttp : NSObject
+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void (^)(NSDictionary *result, NSError *error))completion;
@end

@interface TserverStorage : NSObject
+ (void)configureNamespaceWithPackageToken:(NSString *)packageToken bundleId:(NSString *)bundleId;
+ (NSString *)sessionToken;
+ (void)saveSessionToken:(NSString *)sessionToken;
+ (void)clearSessionToken;
+ (NSString *)packageSessionToken;
+ (void)savePackageSessionToken:(NSString *)token;
+ (void)clearPackageSessionToken;
+ (NSDictionary *)authSessionPair;
+ (void)saveAuthSessionPair:(NSDictionary *)pair;
+ (void)clearAuthSessionPair;
+ (NSDictionary *)pendingProfileState;
+ (void)savePendingProfileState:(NSDictionary *)state;
+ (void)clearPendingProfileState;
+ (NSString *)clientInstallId;
+ (NSDictionary *)lastValidPayload;
+ (void)saveLastValidPayload:(NSDictionary *)payload;
+ (NSDictionary *)lastAuthUiConfig;
+ (void)saveLastAuthUiConfig:(NSDictionary *)config;
+ (NSString *)lastWorkingEndpoint;
+ (void)saveLastWorkingEndpoint:(NSString *)endpoint;
+ (void)clearAuthState;
@end

@interface TserverCrypto : NSObject
+ (NSString *)jsonStringForObject:(id)object;
+ (NSString *)sha256String:(NSString *)string;
+ (BOOL)verifyResponse:(NSDictionary *)response
             apiSecret:(NSString *)apiSecret
requiredSignatureScope:(NSString *)requiredSignatureScope;
@end

extern "C" BOOL TserverAuthUiConfigIntegrityAllowsPersist(NSDictionary *result) {
    NSDictionary *authUi = [result[@"authUiConfig"] isKindOfClass:NSDictionary.class] ? result[@"authUiConfig"] : nil;
    if (!authUi) return YES;
    NSString *expected = [result[@"authUiConfigSha256"] isKindOfClass:NSString.class]
        ? [result[@"authUiConfigSha256"] lowercaseString]
        : @"";
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    if (expected.length != 64 || [expected rangeOfCharacterFromSet:invalid].location != NSNotFound) return NO;
    NSString *actual = [[TserverCrypto sha256String:[TserverCrypto jsonStringForObject:authUi]] lowercaseString];
    return actual.length == 64 && [actual isEqualToString:expected];
}

static NSDictionary *TserverResponseByDroppingInvalidAuthUi(NSDictionary *result) {
    if (![result[@"authUiConfig"] isKindOfClass:NSDictionary.class] ||
        TserverAuthUiConfigIntegrityAllowsPersist(result)) return result;
    NSMutableDictionary *sanitized = [result mutableCopy];
    [sanitized removeObjectForKey:@"authUiConfig"];
    [sanitized removeObjectForKey:@"authUiVersion"];
    [sanitized removeObjectForKey:@"authUiTemplate"];
    [sanitized removeObjectForKey:@"authUiConfigSha256"];
    return [sanitized copy];
}

extern "C" NSDictionary *TserverAuthUiVerifiedCacheEnvelope(NSDictionary *result) {
    NSDictionary *config = [result[@"authUiConfig"] isKindOfClass:NSDictionary.class] ? result[@"authUiConfig"] : nil;
    if (!config || !TserverAuthUiConfigIntegrityAllowsPersist(result)) return nil;
    NSString *templateId = [config[@"templateName"] isKindOfClass:NSString.class] ? config[@"templateName"] : @"";
    NSDictionary *renderer = [config[@"renderer"] isKindOfClass:NSDictionary.class] ? config[@"renderer"] : @{};
    NSString *rendererId = [renderer[@"id"] isKindOfClass:NSString.class] ? renderer[@"id"] : @"";
    NSNumber *rendererRevision = [renderer[@"revision"] isKindOfClass:NSNumber.class] ? renderer[@"revision"] : @0;
    if (templateId.length == 0 || rendererId.length == 0) return nil;
    return @{
        @"v": @1,
        @"config": config,
        @"sha256": [result[@"authUiConfigSha256"] lowercaseString],
        @"templateId": templateId,
        @"rendererId": rendererId,
        @"rendererRevision": rendererRevision,
        @"authUiVersion": [result[@"authUiVersion"] isKindOfClass:NSNumber.class] ? result[@"authUiVersion"] : @0,
        @"bundleId": [TserverAuth currentBundleId] ?: @"",
        @"savedAt": @(NSDate.date.timeIntervalSince1970)
    };
}

@implementation TserverAuth

#pragma mark - Configuration

+ (void)configureWithEndpoint:(NSString *)endpoint
                 packageToken:(NSString *)packageToken
                 returnScheme:(NSString *)returnScheme {
    [self configureWithEndpoints:endpoint ? @[endpoint] : @[]
                  packageToken:packageToken
                  returnScheme:returnScheme];
}

+ (void)configureWithEndpoints:(NSArray<NSString *> *)endpoints
                  packageToken:(NSString *)packageToken
                  returnScheme:(NSString *)returnScheme {
    NSMutableArray *normalized = [NSMutableArray array];
    for (NSString *endpoint in endpoints) {
        NSString *value = [self normalizedEndpoint:endpoint];
        if (value.length > 0) [normalized addObject:value];
    }
    TserverEndpoints = [normalized copy];
    TserverEndpoint = [TserverEndpoints firstObject];
    TserverPackageToken = [packageToken copy];
    [TserverStorage configureNamespaceWithPackageToken:TserverPackageToken bundleId:[self currentBundleId]];
    TserverReturnScheme = [[self normalizedReturnScheme:returnScheme] copy];
}

+ (void)configureWithEndpoint:(NSString *)endpoint
                      storeId:(NSString *)storeId
                        appId:(NSString *)appId
                 returnScheme:(NSString *)returnScheme {
    [self configureWithEndpoint:endpoint storeId:storeId appId:appId returnScheme:returnScheme apiSecret:nil];
}

+ (void)configureWithEndpoint:(NSString *)endpoint
                      storeId:(NSString *)storeId
                        appId:(NSString *)appId
                 returnScheme:(NSString *)returnScheme
                    apiSecret:(NSString *)apiSecret {
    [self configureWithEndpoints:endpoint ? @[endpoint] : @[]
                         storeId:storeId
                           appId:appId
                    returnScheme:returnScheme
                       apiSecret:apiSecret];
}

+ (void)configureWithEndpoints:(NSArray<NSString *> *)endpoints
                       storeId:(NSString *)storeId
                         appId:(NSString *)appId
                  returnScheme:(NSString *)returnScheme
                     apiSecret:(NSString *)apiSecret {
    (void)storeId;
    (void)appId;
    (void)apiSecret;
    [self configureWithEndpoints:endpoints packageToken:TserverPackageToken returnScheme:returnScheme];
}

#pragma mark - Profile / UUID flow

+ (NSDictionary *)pendingProfileStateIfActive {
    NSDictionary *state = [TserverStorage pendingProfileState];
    NSNumber *expiresAt = [state[@"expiresAt"] isKindOfClass:NSNumber.class] ? state[@"expiresAt"] : nil;
    if (!expiresAt || expiresAt.doubleValue <= NSDate.date.timeIntervalSince1970) {
        if (state) [TserverStorage clearPendingProfileState];
        return nil;
    }
    return state;
}

+ (void)recordPendingProfileStartURL:(NSString *)startURL {
    if (startURL.length == 0) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *pair = [TserverStorage authSessionPair] ?: @{};
    // Persist only reconciliation metadata. The profile grant and session token
    // stay out of this record so a later foreground refresh cannot replay them.
    [TserverStorage savePendingProfileState:@{
        @"startedAt": @(now),
        @"expiresAt": @(now + TserverProfileConfirmationWindowSeconds),
        @"pairGeneration": pair[@"generation"] ?: @0
    }];
}

+ (void)clearPendingProfileState {
    TserverAwaitingProfileConfirmation = NO;
    [TserverStorage clearPendingProfileState];
}

+ (NSString *)packageSessionTokenPairedWithProfileSession:(NSString *)profileSessionToken {
    NSDictionary *pair = [TserverStorage authSessionPair];
    NSString *pairedProfile = [pair[@"profileSessionToken"] isKindOfClass:NSString.class] ? pair[@"profileSessionToken"] : @"";
    NSString *package = [pair[@"packageSessionToken"] isKindOfClass:NSString.class] ? pair[@"packageSessionToken"] : @"";
    return pairedProfile.length > 0 && [pairedProfile isEqualToString:profileSessionToken] ? package : @"";
}

+ (void)startProfileFlow {
    [self startProfileFlowFromViewController:nil completion:nil];
}

+ (void)startProfileFlowFromViewController:(UIViewController *)viewController {
    [self startProfileFlowFromViewController:viewController completion:nil];
}

+ (void)startProfileFlowFromViewController:(UIViewController *)viewController
                               completion:(TserverCompletion)completion {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startProfileFlowFromViewController:viewController completion:completion];
        });
        return;
    }
    TserverCallbackBridgePrepare();
    if (TserverProfileFlowInFlight) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusServerError
                                                              message:@"Dang mo trang xac minh UUID. Vui long doi."]];
        return;
    }
    TserverProfileFlowInFlight = YES;
    TserverProfileFlowCompletion = [completion copy];
    if (![self hasRequiredConfig]) {
        [self completeProfileFlow:[self localResultWithStatus:TserverStatusServerError
                                                      message:@"TserverAuth is not configured"]];
        return;
    }

    void (^openProfile)(NSString *) = ^(NSString *profileStartUrl) {
        if (profileStartUrl.length == 0) {
            [self completeProfileFlow:[self localResultWithStatus:TserverStatusServerError
                                                          message:@"Server khong tra ve du lieu mo trang ho so"]];
            return;
        }
        NSString *installUrl = [self profileInstallURLFromStartURL:profileStartUrl];
        [self openURLString:installUrl fromViewController:viewController completion:^(BOOL opened) {
            if (opened) {
                [self recordPendingProfileStartURL:profileStartUrl];
                [self setAwaitingProfileConfirmation:YES];
                [self completeProfileFlow:@{
                    @"ok": @YES,
                    @"status": @"PROFILE_OPENED",
                    @"message": @"Da mo trang cai ho so. Cai xong trong Cai dat roi quay lai app.",
                    @"profileStartUrl": profileStartUrl ?: @""
                }];
                return;
            }
            [self completeProfileFlow:@{
                @"ok": @NO,
                @"status": TserverStatusServerError,
                @"message": @"Khong mo duoc trinh duyet de cai ho so"
            }];
        }];
    };

    // Do not reuse an in-memory profile URL. Profile grants are short-lived and a
    // foreground refresh may already have recovered NEED_KEY/VALID. Every tap
    // starts with a fresh bootstrap for this stable install identity.
    [self packageBootstrapWithSessionToken:[self savedSessionToken]
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:^(NSDictionary *result) {
        NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";
        if ([status isEqualToString:TserverStatusNeedUUID]) {
            NSString *profileStartUrl = [result[@"profileStartUrl"] isKindOfClass:NSString.class]
                ? result[@"profileStartUrl"]
                : nil;
            NSString *profileSessionToken = [result[@"sessionToken"] isKindOfClass:NSString.class]
                ? result[@"sessionToken"]
                : @"";
            // Persist the server-created profile session before Safari is opened.
            // Some iOS/browser combinations discard the return-scheme callback;
            // the next bootstrap must still use this exact session rather than
            // allocate another NEED_UUID cycle.
            if (profileSessionToken.length > 0) {
                [self saveSessionToken:profileSessionToken];
            }
            [self recordPendingProfileStartURL:profileStartUrl];
            openProfile(profileStartUrl);
            return;
        }
        [self completeProfileFlow:result];
    }];
}

+ (void)completeProfileFlow:(NSDictionary *)result {
    TserverCompletion completion = TserverProfileFlowCompletion;
    TserverProfileFlowCompletion = nil;
    TserverProfileFlowInFlight = NO;
    if (completion) {
        [self complete:completion result:result ?: @{}];
    }
}

+ (BOOL)isAwaitingProfileConfirmation {
    return TserverAwaitingProfileConfirmation || [self pendingProfileStateIfActive] != nil;
}

+ (void)setAwaitingProfileConfirmation:(BOOL)awaiting {
    TserverAwaitingProfileConfirmation = awaiting;
    if (!awaiting) {
        [TserverStorage clearPendingProfileState];
    }
}

+ (void)refreshAuthAfterProfileInstallWithCompletion:(TserverCompletion)completion {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAuthAfterProfileInstallWithCompletion:completion];
        });
        return;
    }
    if (!TserverProfileRefreshCompletions) {
        TserverProfileRefreshCompletions = [NSMutableArray array];
    }
    if (completion) {
        [TserverProfileRefreshCompletions addObject:[completion copy]];
    }
    if (TserverProfileRefreshInFlight) {
        return;
    }

    TserverProfileRefreshInFlight = YES;
    [self setAwaitingProfileConfirmation:YES];
    [self packageBootstrapWithSessionToken:[self savedSessionToken]
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:^(NSDictionary *result) {
        TserverProfileRefreshInFlight = NO;
        NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";
        if (![status isEqualToString:TserverStatusNeedUUID]) {
            [self clearPendingProfileState];
        } else if (![self pendingProfileStateIfActive]) {
            [self setAwaitingProfileConfirmation:NO];
        }

        NSArray<TserverCompletion> *completions = [TserverProfileRefreshCompletions copy];
        [TserverProfileRefreshCompletions removeAllObjects];
        for (TserverCompletion pendingCompletion in completions) {
            [self complete:pendingCompletion result:result ?: @{}];
        }
    }];
}

+ (BOOL)handleCallbackURL:(NSURL *)url
               completion:(TserverCompletion)completion {
    if (!url) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusBadSession message:@"Callback URL is nil"]];
        return NO;
    }
    if (![self isTserverCallbackURL:url]) {
        return NO;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *sessionToken = [self queryValue:@"sessionToken" components:components];
    if (sessionToken.length == 0) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusBadSession
                                                             message:@"Missing sessionToken in callback URL"]];
        return NO;
    }

    NSString *callbackBundleId = [self queryValue:@"bundleId" components:components];
    if (callbackBundleId.length > 0 && ![callbackBundleId isEqualToString:[self currentBundleId]]) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusBadSession
                                                             message:@"Callback context does not match this app"]];
        return NO;
    }

    [self saveSessionToken:sessionToken];
    [self clearPendingProfileState];
    [self packageBootstrapWithSessionToken:sessionToken
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:completion];
    return YES;
}

+ (void)claimProfileWithSessionToken:(NSString *)sessionToken
                          completion:(TserverCompletion)completion {
    if (sessionToken.length == 0) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusNeedUUID
                                                              message:@"Hay xac minh UUID thiet bi truoc"]];
        return;
    }
    [self saveSessionToken:sessionToken];
    [self packageBootstrapWithSessionToken:sessionToken
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:completion];
}

+ (void)confirmCurrentDeviceWithCompletion:(TserverCompletion)completion {
    [self packageBootstrapWithSessionToken:[self savedSessionToken]
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:completion];
}

#pragma mark - Bootstrap / license

+ (void)bootstrapWithCompletion:(TserverCompletion)completion {
    // Establish ECDH transport session (best-effort) before package bootstrap.
    NSString *base = TserverCompiledPrimaryEndpoint();
    if (base.length == 0) base = TserverSealedHTTPSBaseURL();
    [TserverTransportSession ensureSessionWithBaseURL:base completion:^(__unused BOOL ok) {
        [self packageBootstrapWithSessionToken:[self savedSessionToken]
                              allowSessionRetry:YES
                                   endpointIndex:0
                                    completion:completion];
    }];
}

+ (void)bootstrapWithSessionToken:(NSString *)sessionToken
                       completion:(TserverCompletion)completion {
    [self packageBootstrapWithSessionToken:sessionToken
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:completion];
}

+ (void)activateKey:(NSString *)licenseKey
         completion:(TserverCompletion)completion {
    [self activateKey:licenseKey sessionToken:[self savedSessionToken] completion:completion];
}

+ (void)activateKey:(NSString *)licenseKey
       sessionToken:(NSString *)sessionToken
         completion:(TserverCompletion)completion {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self activateKey:licenseKey sessionToken:sessionToken completion:completion];
        });
        return;
    }
    TserverActivationAttempt *attempt = [TserverActivationAttempt beginWithCompletion:^(NSDictionary *terminalResult) {
        [self complete:completion result:[self normalizedClientResult:terminalResult]];
    }];
    void (^completeActivation)(NSDictionary *, NSString *, NSString *) = ^(NSDictionary *result,
                                                                            NSString *stage,
                                                                            NSString *errorCode) {
        [attempt finishWithResult:[self normalizedClientResult:result]
                            stage:stage
                        errorCode:errorCode];
    };

    if (licenseKey.length == 0) {
        completeActivation([self localResultWithStatus:TserverStatusInvalidKey message:@"License key is empty"],
                           @"preflight", @"empty_key");
        return;
    }
    if (![self hasRequiredConfig]) {
        NSDictionary *missing = [self missingConfigResult];
        NSString *status = [missing[@"status"] isKindOfClass:NSString.class] ? missing[@"status"] : @"";
        completeActivation(missing, @"preflight",
                           [status isEqualToString:TserverStatusClientKeyUnavailable]
                               ? @"client_key_unavailable"
                               : @"missing_config");
        return;
    }
    if (sessionToken.length == 0) {
        completeActivation([self localResultWithStatus:TserverStatusBadSession
                                                message:@"Profile session không khả dụng cho lần kích hoạt này."],
                           @"preflight", @"profile_session_missing");
        return;
    }

    [attempt updateStage:@"package_session"];

    __block void (^runActivate)(NSString *) = nil;
    runActivate = ^(NSString *packageSessionToken) {
        if (packageSessionToken.length == 0) {
            completeActivation([self localResultWithStatus:TserverStatusBadPackageSession
                                                    message:@"Package session token is missing"],
                               @"package_session", @"package_session_missing");
            return;
        }
        [attempt updateStage:@"activation_request"];
        NSMutableDictionary *body = [@{
            @"sessionToken": sessionToken,
            @"licenseKey": licenseKey,
            @"activationAttemptId": attempt.attemptId ?: @""
        } mutableCopy];
        NSDictionary *clientSecurity = TserverRuntimeIntegrityContext();
        if (clientSecurity.count > 0) body[@"clientSecurity"] = clientSecurity;
        [self postPackageLicensePath:TserverSealedNSString(kTserverSealedStr_V1PackageActivate)
                                body:body
                 packageSessionToken:packageSessionToken
                      retryBootstrap:YES
                          completion:^(NSDictionary *result) {
            completeActivation(result, @"activation_response", nil);
        }];
    };

    // Refresh ECDH session if missing/near expiry before activate (body uses session key only).
    NSString *base = TserverCompiledPrimaryEndpoint();
    if (base.length == 0) base = TserverSealedHTTPSBaseURL();
    if (![TserverTransportSession hasUsableSession]) {
        [TserverTransportSession ensureSessionWithBaseURL:base completion:^(BOOL ok) {
            if (!ok) {
                completeActivation([self localResultWithStatus:TserverStatusTransportSessionError
                                                        message:@"Không tạo được transport session. Vui lòng thử lại."],
                                   @"transport_handshake", @"transport_handshake_failed");
                return;
            }
            if (![attempt isCurrent]) return;
            NSString *paired = [self packageSessionTokenPairedWithProfileSession:sessionToken];
            if (paired.length > 0) {
                runActivate(paired);
            } else {
                [self packageBootstrapWithSessionToken:sessionToken
                                      allowSessionRetry:YES
                                           endpointIndex:0
                                            completion:^(NSDictionary *bootstrapResult) {
                    NSString *status = [bootstrapResult[@"status"] isKindOfClass:NSString.class]
                        ? bootstrapResult[@"status"]
                        : @"";
                    NSString *ps = [bootstrapResult[@"packageSessionToken"] isKindOfClass:NSString.class]
                        ? bootstrapResult[@"packageSessionToken"]
                        : @"";
                    if (ps.length == 0) {
                        NSDictionary *failure = bootstrapResult;
                        if ([status isEqualToString:TserverStatusNeedKey]) {
                            failure = [self localResultWithStatus:TserverStatusBadPackageSession
                                                           message:@"Package session bootstrap did not return a bearer."];
                        }
                        completeActivation(failure, @"package_bootstrap", @"package_session_missing_after_bootstrap");
                    } else if ([status isEqualToString:TserverStatusNeedKey] ||
                               [status isEqualToString:TserverStatusExpired] ||
                               [status isEqualToString:TserverStatusRevoked] ||
                               [status isEqualToString:TserverStatusValid]) {
                        runActivate(ps);
                    } else {
                        completeActivation(bootstrapResult, @"package_bootstrap", nil);
                    }
                }];
            }
        }];
        return;
    };

    // A package bearer is valid only with the profile session from the same
    // bootstrap generation. Never activate through a lone/stale Keychain value.
    NSString *packageSessionToken = [self packageSessionTokenPairedWithProfileSession:sessionToken];
    NSDictionary *pendingProfile = [self pendingProfileStateIfActive];
    if (packageSessionToken.length > 0 && !pendingProfile) {
        runActivate(packageSessionToken);
        return;
    }

    [self packageBootstrapWithSessionToken:sessionToken
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:^(NSDictionary *bootstrapResult) {
        NSString *status = [bootstrapResult[@"status"] isKindOfClass:NSString.class] ? bootstrapResult[@"status"] : @"";
        NSString *ps = [bootstrapResult[@"packageSessionToken"] isKindOfClass:NSString.class]
            ? bootstrapResult[@"packageSessionToken"]
            : [self packageSessionTokenPairedWithProfileSession:sessionToken];
        if (ps.length == 0) {
            NSDictionary *failure = bootstrapResult;
            if ([status isEqualToString:TserverStatusNeedKey]) {
                failure = [self localResultWithStatus:TserverStatusBadPackageSession
                                               message:@"Package session bootstrap did not return a bearer."];
            }
            completeActivation(failure, @"package_bootstrap", @"package_session_missing_after_bootstrap");
            return;
        }
        if ([status isEqualToString:TserverStatusNeedKey] || [status isEqualToString:TserverStatusExpired] ||
            [status isEqualToString:TserverStatusRevoked] || [status isEqualToString:TserverStatusValid]) {
            runActivate(ps);
            return;
        }
        completeActivation(bootstrapResult, @"package_bootstrap", nil);
    }];
}

+ (BOOL)isActivationInFlight {
    return [TserverActivationAttempt isActivationInFlight];
}

+ (NSUInteger)activationGeneration {
    return [TserverActivationAttempt currentGeneration];
}

+ (void)verifyWithCompletion:(TserverCompletion)completion {
    [self verifyWithSessionToken:[self savedSessionToken] completion:completion];
}

+ (void)verifyWithSessionToken:(NSString *)sessionToken
                    completion:(TserverCompletion)completion {
    if (sessionToken.length == 0) {
        [self packageBootstrapWithSessionToken:nil
                              allowSessionRetry:YES
                                   endpointIndex:0
                                    completion:^(NSDictionary *result) {
            [self complete:completion result:[self normalizedClientResult:result]];
        }];
        return;
    }

    void (^runVerify)(NSString *) = ^(NSString *packageSessionToken) {
        NSMutableDictionary *body = [@{ @"sessionToken": sessionToken } mutableCopy];
        NSDictionary *clientSecurity = TserverRuntimeIntegrityContext();
        if (clientSecurity.count > 0) body[@"clientSecurity"] = clientSecurity;
        [self postPackageLicensePath:TserverSealedNSString(kTserverSealedStr_V1PackageVerify)
                                body:body
                 packageSessionToken:packageSessionToken
                      retryBootstrap:YES
                          completion:^(NSDictionary *result) {
            [self complete:completion result:[self normalizedClientResult:result]];
        }];
    };

    NSString *packageSessionToken = [self packageSessionTokenPairedWithProfileSession:sessionToken];
    if (packageSessionToken.length > 0) {
        runVerify(packageSessionToken);
        return;
    }

    [self packageBootstrapWithSessionToken:sessionToken
                          allowSessionRetry:YES
                               endpointIndex:0
                                completion:^(NSDictionary *bootstrapResult) {
        NSString *ps = [bootstrapResult[@"packageSessionToken"] isKindOfClass:NSString.class]
            ? bootstrapResult[@"packageSessionToken"]
            : [self packageSessionTokenPairedWithProfileSession:sessionToken];
        NSString *status = [bootstrapResult[@"status"] isKindOfClass:NSString.class] ? bootstrapResult[@"status"] : @"";
        if ([status isEqualToString:TserverStatusValid]) {
            [self complete:completion result:[self normalizedClientResult:bootstrapResult]];
            return;
        }
        if (ps.length == 0) {
            [self complete:completion result:[self normalizedClientResult:bootstrapResult]];
            return;
        }
        runVerify(ps);
    }];
}

#pragma mark - Storage passthrough

+ (NSString *)savedSessionToken {
    return [TserverStorage sessionToken];
}

+ (void)saveSessionToken:(NSString *)sessionToken {
    [TserverStorage saveSessionToken:sessionToken];
}

+ (void)clearSession {
    TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
    [TserverTransportSession clear];
    [TserverStorage clearAuthState];
    [self clearPendingProfileState];
}

+ (NSString *)currentBundleId {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    return bundleId.length > 0 ? bundleId : @"";
}

+ (NSString *)configuredReturnScheme {
    return TserverReturnScheme ?: @"";
}

+ (BOOL)isReturnSchemeRegisteredInHostApp {
    NSString *scheme = [self configuredReturnScheme];
    if (scheme.length == 0) return NO;
    id urlTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
    if (![urlTypes isKindOfClass:NSArray.class]) return NO;
    for (id entry in (NSArray *)urlTypes) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id schemes = ((NSDictionary *)entry)[@"CFBundleURLSchemes"];
        if (![schemes isKindOfClass:NSArray.class]) continue;
        for (id item in (NSArray *)schemes) {
            if ([item isKindOfClass:NSString.class] &&
                [((NSString *)item).lowercaseString isEqualToString:scheme.lowercaseString]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (NSString *)profileStartURL {
    // Profile grants are intentionally never retained after launch.
    return @"";
}

#pragma mark - Package HTTP

+ (NSDictionary *)packageBootstrapBodyWithSessionToken:(NSString *)sessionToken {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"bundleId"] = [self currentBundleId];
    body[@"returnScheme"] = TserverReturnScheme ?: @"";
    body[@"clientInstallId"] = [TserverStorage clientInstallId] ?: @"";
    body[@"sdkVersion"] = TserverSDKVersion;
    NSString *leaseVersionKey = TserverSealedNSString(kTserverSealedStr_AuthorizationLeaseVersion);
    if (leaseVersionKey.length > 0) body[leaseVersionKey] = @1;
    NSString *appVersion = [self hostAppVersion];
    if (appVersion.length > 0) {
        body[@"appVersion"] = appVersion;
    }
    if (sessionToken.length > 0) {
        body[@"sessionToken"] = sessionToken;
    }
    NSDictionary *clientSecurity = TserverRuntimeIntegrityContext();
    if (clientSecurity.count > 0) body[@"clientSecurity"] = clientSecurity;
    return body;
}

+ (void)packageBootstrapWithSessionToken:(NSString *)sessionToken
                        allowSessionRetry:(BOOL)allowSessionRetry
                             endpointIndex:(NSUInteger)endpointIndex
                                  completion:(TserverCompletion)completion {
    if (![self hasRequiredConfig]) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusServerError
                                                              message:@"TserverAuth is not configured"]];
        return;
    }
    NSArray<NSString *> *ordered = [self orderedEndpoints];
    if (endpointIndex >= ordered.count) {
        [self complete:completion result:[self offlineGraceOrNetworkError:@"All endpoints failed"]];
        return;
    }

    NSString *endpoint = ordered[endpointIndex];
    NSString *tokenApi = TserverSealedNSString(kTserverSealedStr_TokenApi);
    NSString *hClient = TserverSealedNSString(kTserverSealedStr_XClientApiKey);
    NSString *hApi = TserverSealedNSString(kTserverSealedStr_XApiKey);
    if (tokenApi.length == 0 || hClient.length == 0 || hApi.length == 0) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusServerError
                                                              message:@"Sealed auth material unavailable"]];
        return;
    }
    NSString *url = [NSString stringWithFormat:@"%@%@", endpoint, tokenApi];
    NSDictionary *body = [self packageBootstrapBodyWithSessionToken:sessionToken ?: @""];
    NSString *requestActivationId = [[TserverActivationAttempt currentAttemptId] copy] ?: @"";
    NSString *clientKey = TserverCompiledClientApiKey() ?: @"";
    if (clientKey.length < 16) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusClientKeyUnavailable
                                                              message:@"Client auth material unavailable in this process"]];
        return;
    }
    // Dual-auth headers; TserverHttp adds x-ts-* request signature automatically.
    NSDictionary *headers = @{
        hClient: clientKey,
        hApi: TserverPackageToken ?: @""
    };

    [TserverHttp post:url body:body headers:headers completion:^(NSDictionary *result, NSError *error) {
        if (requestActivationId.length > 0 &&
            ![requestActivationId isEqualToString:[TserverActivationAttempt currentAttemptId] ?: @""]) {
            [self complete:completion result:[self localResultWithStatus:TserverStatusActivationCancelled
                                                                  message:@"Bootstrap superseded by activation."]];
            return;
        }
        if (error) {
            [self packageBootstrapWithSessionToken:sessionToken
                                  allowSessionRetry:allowSessionRetry
                                       endpointIndex:endpointIndex + 1
                                        completion:completion];
            return;
        }

        NSDictionary *processed = [self processPackageBootstrapResponse:result
                                                               endpoint:endpoint
                                                         verifySecret:TserverPackageToken];
        NSString *status = [processed[@"status"] isKindOfClass:NSString.class] ? processed[@"status"] : @"";

        if ([status isEqualToString:TserverStatusBadPackageSession] && allowSessionRetry) {
            [TserverStorage clearPackageSessionToken];
            [self packageBootstrapWithSessionToken:sessionToken
                                  allowSessionRetry:NO
                                       endpointIndex:endpointIndex
                                        completion:completion];
            return;
        }

        if (![status isEqualToString:TserverStatusNeedUUID]) {
            [self clearPendingProfileState];
        }

        NSString *finalStatus = [processed[@"status"] isKindOfClass:NSString.class] ? processed[@"status"] : @"";
        if ([finalStatus isEqualToString:TserverStatusNeedUUID]) {
            NSString *freshProfileSession = [processed[@"sessionToken"] isKindOfClass:NSString.class]
                ? processed[@"sessionToken"]
                : @"";
            NSDictionary *pair = [TserverStorage authSessionPair] ?: @{};
            NSString *pairedProfileSession = [pair[@"profileSessionToken"] isKindOfClass:NSString.class]
                ? pair[@"profileSessionToken"]
                : @"";
            if (freshProfileSession.length > 0 && ![freshProfileSession isEqualToString:pairedProfileSession]) {
                // A server-side device removal intentionally rotates the profile
                // session. Discard only the stale package pair and pending browser
                // metadata; clientInstallId remains stable for re-enrollment.
                [TserverStorage clearPackageSessionToken];
                [TserverStorage clearPendingProfileState];
                [TserverStorage saveSessionToken:freshProfileSession];
            }
        }
        if (![finalStatus isEqualToString:TserverStatusValid] &&
            ![finalStatus isEqualToString:TserverStatusNetworkError] &&
            ![finalStatus isEqualToString:TserverStatusServerError] &&
            ![TserverActivationAttempt isActivationInFlight] &&
            !TserverAuthorizationLeaseIsAuthorized()) {
            TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
        }
        [self complete:completion result:[self normalizedClientResult:processed]];
    }];
}

+ (void)postPackageLicensePath:(NSString *)path
                          body:(NSDictionary *)body
           packageSessionToken:(NSString *)packageSessionToken
                retryBootstrap:(BOOL)retryBootstrap
                    completion:(TserverCompletion)completion {
    if (![self hasRequiredConfig]) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusServerError
                                                              message:@"TserverAuth is not configured"]];
        return;
    }
    if (packageSessionToken.length == 0) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusBadPackageSession
                                                              message:@"Package session token is missing"]];
        return;
    }

    [self postPackageLicensePath:path
                            body:body
             packageSessionToken:packageSessionToken
                  retryBootstrap:retryBootstrap
                     endpointIndex:0
                        completion:completion];
}

+ (void)postPackageLicensePath:(NSString *)path
                          body:(NSDictionary *)body
           packageSessionToken:(NSString *)packageSessionToken
                retryBootstrap:(BOOL)retryBootstrap
                   endpointIndex:(NSUInteger)endpointIndex
                      completion:(TserverCompletion)completion {
    NSArray<NSString *> *ordered = [self orderedEndpoints];
    if (endpointIndex >= ordered.count) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusNetworkError
                                                              message:@"Không nhận được kết quả kích hoạt. Vui lòng thử lại."]];
        return;
    }

    NSString *endpoint = ordered[endpointIndex];
    NSString *url = [NSString stringWithFormat:@"%@%@", endpoint, path];
    NSString *clientKey = TserverCompiledClientApiKey() ?: @"";
    if (clientKey.length < 16) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusClientKeyUnavailable
                                                              message:@"Client auth material unavailable in this process"]];
        return;
    }
    NSString *hClient = TserverSealedNSString(kTserverSealedStr_XClientApiKey);
    if (hClient.length == 0) {
        [self complete:completion result:[self localResultWithStatus:TserverStatusServerError
                                                              message:@"Sealed auth material unavailable"]];
        return;
    }
    NSDictionary *headers = @{
        hClient: clientKey,
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", packageSessionToken]
    };

    [TserverHttp post:url body:body headers:headers completion:^(NSDictionary *result, NSError *error) {
        NSString *requestAttemptId = [body[@"activationAttemptId"] isKindOfClass:NSString.class]
            ? body[@"activationAttemptId"]
            : @"";
        if (requestAttemptId.length > 0 &&
            ![requestAttemptId isEqualToString:[TserverActivationAttempt currentAttemptId] ?: @""]) {
            return;
        }
        if (error) {
            NSArray<NSString *> *endpoints = [self orderedEndpoints];
            if (endpointIndex + 1 >= endpoints.count) {
                [self complete:completion result:[self localResultWithStatus:TserverStatusNetworkError
                                                                      message:@"Không nhận được kết quả kích hoạt. Vui lòng thử lại."]];
                return;
            }
            [self postPackageLicensePath:path
                                    body:body
                     packageSessionToken:packageSessionToken
                          retryBootstrap:retryBootstrap
                             endpointIndex:endpointIndex + 1
                                completion:completion];
            return;
        }

        // Keep the exact request-bound profile/package sessions for lease install.
        // A concurrent bootstrap can rewrite Keychain while this response is in
        // flight; verifying against that mutable storage causes false
        // AUTHORIZATION_LEASE_INVALID after a valid server response.
        NSString *requestProfileSession = [body[@"sessionToken"] isKindOfClass:NSString.class]
            ? body[@"sessionToken"]
            : @"";
        NSDictionary *processed = [self processPackageLicenseResponse:result
                                                             endpoint:endpoint
                                                         verifySecret:packageSessionToken
                                                  requestProfileSession:requestProfileSession];
        NSString *status = [processed[@"status"] isKindOfClass:NSString.class] ? processed[@"status"] : @"";

        BOOL needsFreshTransportSession = [status isEqualToString:@"TRANSPORT_SESSION_REQUIRED"] ||
                                         [status isEqualToString:@"BAD_TRANSPORT_CRYPTO"];
        if (needsFreshTransportSession && retryBootstrap) {
            [TserverTransportSession clear];
            NSString *base = TserverCompiledPrimaryEndpoint();
            if (base.length == 0) base = TserverSealedHTTPSBaseURL();
            [TserverTransportSession ensureSessionWithBaseURL:base completion:^(BOOL ok) {
                if (!ok) {
                    [self complete:completion result:[self localResultWithStatus:TserverStatusTransportSessionError
                                                                          message:@"Không thể làm mới transport session."]];
                    return;
                }
                [self postPackageLicensePath:path
                                        body:body
                         packageSessionToken:packageSessionToken
                              retryBootstrap:NO
                                 endpointIndex:0
                                    completion:completion];
            }];
            return;
        }

        BOOL needsFreshPackagePair = [status isEqualToString:TserverStatusBadPackageSession] ||
                                     [status isEqualToString:TserverStatusBadSession];
        if (needsFreshPackagePair && retryBootstrap) {
            // The server may have rotated the package bearer while a foreground
            // refresh was running. Preserve the captured profile token, discard
            // only its package pair, bootstrap once, then retry with that pair.
            [TserverStorage clearPackageSessionToken];
            [self packageBootstrapWithSessionToken:body[@"sessionToken"]
                                  allowSessionRetry:NO
                                       endpointIndex:0
                                        completion:^(NSDictionary *bootstrapResult) {
                NSString *capturedProfile = [body[@"sessionToken"] isKindOfClass:NSString.class] ? body[@"sessionToken"] : @"";
                NSString *bootstrapProfile = [bootstrapResult[@"sessionToken"] isKindOfClass:NSString.class]
                    ? bootstrapResult[@"sessionToken"]
                    : capturedProfile;
                NSString *ps = [bootstrapResult[@"packageSessionToken"] isKindOfClass:NSString.class]
                    ? bootstrapResult[@"packageSessionToken"]
                    : [self packageSessionTokenPairedWithProfileSession:bootstrapProfile];
                NSString *bootstrapStatus = [bootstrapResult[@"status"] isKindOfClass:NSString.class] ? bootstrapResult[@"status"] : @"";
                if (ps.length == 0 || bootstrapProfile.length == 0 ||
                    (![bootstrapStatus isEqualToString:TserverStatusNeedKey] &&
                     ![bootstrapStatus isEqualToString:TserverStatusExpired] &&
                     ![bootstrapStatus isEqualToString:TserverStatusRevoked] &&
                     ![bootstrapStatus isEqualToString:TserverStatusValid])) {
                    [self complete:completion result:[self normalizedClientResult:bootstrapResult]];
                    return;
                }
                // Bootstrap may recover or rotate the profile session for this
                // stable install. Retry with the session actually paired to the
                // fresh package bearer; never resend the captured stale token.
                NSMutableDictionary *retryBody = [body mutableCopy];
                retryBody[@"sessionToken"] = bootstrapProfile;
                [self postPackageLicensePath:path
                                        body:retryBody
                         packageSessionToken:ps
                              retryBootstrap:NO
                                 endpointIndex:0
                                    completion:completion];
            }];
            return;
        }

        // A validly signed INVALID_KEY response is terminal for this key entry.
        // Never reinterpret it as a session/profile failure or trigger bootstrap,
        // otherwise typing a wrong key can misleadingly bounce the UI to UUID.
        if ([status isEqualToString:TserverStatusInvalidKey]) {
            [self complete:completion result:[self normalizedClientResult:processed]];
            return;
        }

        NSString *finalStatus = [processed[@"status"] isKindOfClass:NSString.class] ? processed[@"status"] : @"";
    if (![finalStatus isEqualToString:TserverStatusValid] &&
        ![finalStatus isEqualToString:TserverStatusNetworkError] &&
        ![finalStatus isEqualToString:TserverStatusServerError]) {
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
    }
    [self complete:completion result:[self normalizedClientResult:processed]];
    }];
}

+ (BOOL)shouldAcceptUnsignedPackageError:(NSDictionary *)result {
    if (![result isKindOfClass:NSDictionary.class]) return NO;
    if ([result[@"responseSignature"] isKindOfClass:NSString.class]) return NO;
    NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";
    NSArray<NSString *> *allowed = @[
        TserverStatusInvalidApiKey,
        TserverStatusInvalidClientApiKey,
        TserverStatusBadClientSignature,
        TserverStatusReplayRequest,
        TserverStatusRateLimited,
        TserverStatusPackageBundleDenied,
        TserverStatusBadPackageSession,
        TserverStatusServerError,
        TserverStatusNetworkError,
        @"TRANSPORT_SESSION_REQUIRED",
        @"TRANSPORT_HANDSHAKE_FAILED",
        @"BAD_TRANSPORT_CRYPTO",
        @"TRANSPORT_ENCRYPT_FAILED",
        @"VALIDATION_ERROR",
        @"APP_DISABLED",
        @"STORE_DISABLED",
        @"PACKAGE_DISABLED",
        @"PACKAGE_MAINTENANCE"
    ];
    return [allowed containsObject:status];
}

+ (NSDictionary *)processPackageBootstrapResponse:(NSDictionary *)result
                                         endpoint:(NSString *)endpoint
                                     verifySecret:(NSString *)verifySecret {
    if (![result isKindOfClass:NSDictionary.class]) {
        return [self localResultWithStatus:TserverStatusServerError message:@"Empty server response"];
    }

    BOOL signatureValid = [TserverCrypto verifyResponse:result
                                               apiSecret:verifySecret
                                   requiredSignatureScope:@"package-token"];
    if (!signatureValid) {
        if (![self shouldAcceptUnsignedPackageError:result]) {
            TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateCompromised);
            return [self localResultWithStatus:TserverStatusBadResponseSignature message:@"Bad response signature"];
        }
        return TserverResponseWithClientMetadata(result);
    }
    result = TserverResponseByDroppingInvalidAuthUi(TserverResponseWithClientMetadata(result));

    NSString *profileSessionToken = [result[@"sessionToken"] isKindOfClass:NSString.class]
        ? result[@"sessionToken"]
        : [TserverStorage sessionToken];
    NSString *packageSessionToken = [result[@"packageSessionToken"] isKindOfClass:NSString.class]
        ? result[@"packageSessionToken"]
        : [self packageSessionTokenPairedWithProfileSession:profileSessionToken];
    NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";
    if ([status isEqualToString:TserverStatusValid]) {
        NSError *leaseError = nil;
        BOOL leaseValid = TserverAuthorizationLeaseInstall(
            result,
            TserverPackageToken ?: @"",
            profileSessionToken ?: @"",
            packageSessionToken ?: @"",
            [TserverStorage clientInstallId] ?: @"",
            [self currentBundleId],
            &leaseError
        );
        if (!leaseValid) {
            NSMutableDictionary *err = [result mutableCopy] ?: [NSMutableDictionary dictionary];
            err[@"ok"] = @NO;
            err[@"status"] = TserverStatusAuthorizationLeaseInvalid;
            NSString *detail = leaseError.localizedDescription.length > 0
                ? leaseError.localizedDescription
                : @"Authorization lease invalid";
            err[@"message"] = detail;
            err[@"errorCode"] = [NSString stringWithFormat:@"lease_install_%ld", (long)(leaseError ? leaseError.code : 0)];
            return [err copy];
        }
    }
    if (profileSessionToken.length > 0) [TserverStorage saveSessionToken:profileSessionToken];
    if ([status isEqualToString:TserverStatusNeedUUID]) {
        NSDictionary *previousPair = [TserverStorage authSessionPair] ?: @{};
        NSString *previousProfile = [previousPair[@"profileSessionToken"] isKindOfClass:NSString.class]
            ? previousPair[@"profileSessionToken"]
            : @"";
        if (previousProfile.length > 0 && ![previousProfile isEqualToString:profileSessionToken]) {
            [TserverStorage clearPackageSessionToken];
        }
    }
    if (packageSessionToken.length > 0) [TserverStorage savePackageSessionToken:packageSessionToken];
    if (packageSessionToken.length > 0 && profileSessionToken.length > 0) {
        NSDictionary *previousPair = [TserverStorage authSessionPair] ?: @{};
        NSUInteger generation = [previousPair[@"generation"] unsignedIntegerValue] + 1;
        [TserverStorage saveAuthSessionPair:@{
            @"profileSessionToken": profileSessionToken,
            @"packageSessionToken": packageSessionToken,
            @"generation": @(MAX((NSUInteger)1, generation)),
            @"createdAt": @(NSDate.date.timeIntervalSince1970)
        }];
    }

    [TserverStorage saveLastWorkingEndpoint:endpoint];
    // Remote security policy (signed with response) — hook/log/forceUpdate switches.
    if (&TserverSecurityPolicyApplyFromResponse) {
        TserverSecurityPolicyApplyFromResponse(result);
    }
    // Cache package Auth UI on ANY signed bootstrap (NEED_UUID / NEED_KEY / VALID…),
    // not only VALID — so cold loading and first-key screens use the assigned template.
    // When authUiConfigSha256 is present it must match; mismatch skips UI cache only.
    NSDictionary *authUiEnvelope = TserverAuthUiVerifiedCacheEnvelope(result);
    if (authUiEnvelope.count > 0 && [TserverStorage respondsToSelector:@selector(saveLastAuthUiConfig:)]) {
        [TserverStorage saveLastAuthUiConfig:authUiEnvelope];
    }
    if ([status isEqualToString:TserverStatusValid]) {
        [TserverStorage saveLastValidPayload:@{ @"license": TserverAuthorizationLeaseLicenseInfo() ?: @{} }];
    }
    return result;
}

+ (NSDictionary *)processPackageLicenseResponse:(NSDictionary *)result
                                       endpoint:(NSString *)endpoint
                                   verifySecret:(NSString *)verifySecret {
    return [self processPackageLicenseResponse:result
                                      endpoint:endpoint
                                  verifySecret:verifySecret
                           requestProfileSession:nil];
}

+ (NSDictionary *)processPackageLicenseResponse:(NSDictionary *)result
                                       endpoint:(NSString *)endpoint
                                   verifySecret:(NSString *)verifySecret
                            requestProfileSession:(NSString *)requestProfileSession {
    if (![result isKindOfClass:NSDictionary.class]) {
        return [self localResultWithStatus:TserverStatusServerError message:@"Empty server response"];
    }

    NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";

    BOOL signatureValid = [TserverCrypto verifyResponse:result
                                               apiSecret:verifySecret
                                   requiredSignatureScope:@"package-session"];
    if (!signatureValid) {
        if (![self shouldAcceptUnsignedPackageError:result]) {
            TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateCompromised);
            return [self localResultWithStatus:TserverStatusBadResponseSignature message:@"Bad response signature"];
        }
        return TserverResponseWithClientMetadata(result);
    }
    result = TserverResponseWithClientMetadata(result);

    // Prefer the exact profile session that was sent with this request, then the
    // signed response session, and only then mutable Keychain storage.
    NSString *profileSessionToken = [requestProfileSession isKindOfClass:NSString.class] && requestProfileSession.length > 0
        ? requestProfileSession
        : ([result[@"sessionToken"] isKindOfClass:NSString.class]
            ? result[@"sessionToken"]
            : [TserverStorage sessionToken]);
    // The response is authenticated by the exact package-session token supplied
    // to this request. Do not read the mutable global storage slot here: a
    // foreground/bootstrap refresh can replace it while key activation is in
    // flight and make an otherwise valid lease look bound to another session.
    NSString *packageSessionToken = verifySecret ?: @"";
    // Apply packageSettings (capture flags, etc.) even on non-VALID responses so the
    // gate can refresh protection after NEED_KEY / INVALID_KEY / maintenance replies.
    if (&TserverSecurityPolicyApplyFromResponse) {
        TserverSecurityPolicyApplyFromResponse(result);
    }
    if (![status isEqualToString:TserverStatusValid]) {
        return result;
    }
    NSError *leaseError = nil;
    BOOL leaseValid = TserverAuthorizationLeaseInstall(
        result,
        TserverPackageToken ?: @"",
        profileSessionToken ?: @"",
        packageSessionToken ?: @"",
        [TserverStorage clientInstallId] ?: @"",
        [self currentBundleId],
        &leaseError
    );
    if (!leaseValid) {
        NSString *detail = [leaseError.localizedDescription isKindOfClass:NSString.class]
            ? leaseError.localizedDescription
            : @"Authorization lease invalid";
        NSInteger code = leaseError ? leaseError.code : 0;
        NSMutableDictionary *err = [result mutableCopy] ?: [NSMutableDictionary dictionary];
        err[@"ok"] = @NO;
        err[@"status"] = TserverStatusAuthorizationLeaseInvalid;
        err[@"message"] = detail;
        err[@"errorCode"] = [NSString stringWithFormat:@"lease_install_%ld", (long)code];
        err[@"sessionToken"] = profileSessionToken ?: @"";
        err[@"packageSessionToken"] = packageSessionToken ?: @"";
        return [err copy];
    }
    if (profileSessionToken.length > 0) [TserverStorage saveSessionToken:profileSessionToken];
    if (profileSessionToken.length > 0 && packageSessionToken.length > 0) {
        NSDictionary *previousPair = [TserverStorage authSessionPair] ?: @{};
        NSUInteger generation = [previousPair[@"generation"] unsignedIntegerValue] + 1;
        [TserverStorage saveAuthSessionPair:@{
            @"profileSessionToken": profileSessionToken,
            @"packageSessionToken": packageSessionToken,
            @"generation": @(MAX((NSUInteger)1, generation)),
            @"createdAt": @(NSDate.date.timeIntervalSince1970)
        }];
    }

    [TserverStorage saveLastWorkingEndpoint:endpoint];
    if (&TserverSecurityPolicyApplyFromResponse) {
        TserverSecurityPolicyApplyFromResponse(result);
    }
    NSDictionary *authUiEnvelope = TserverAuthUiVerifiedCacheEnvelope(result);
    if (authUiEnvelope.count > 0 && [TserverStorage respondsToSelector:@selector(saveLastAuthUiConfig:)]) {
        [TserverStorage saveLastAuthUiConfig:authUiEnvelope];
    }
    if ([status isEqualToString:TserverStatusValid]) {
        [TserverStorage saveLastValidPayload:@{ @"license": TserverAuthorizationLeaseLicenseInfo() ?: @{} }];
    }
    return result;
}

+ (NSDictionary *)normalizedClientResult:(NSDictionary *)result {
    if (![result isKindOfClass:NSDictionary.class]) {
        return [self localResultWithStatus:TserverStatusServerError message:@"Empty result"];
    }
    NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";
    if (![status isEqualToString:TserverStatusInvalidKey]) {
        return result;
    }
    NSMutableDictionary *fixed = [result mutableCopy];
    fixed[@"message"] = @"Bạn đã nhập sai key";
    fixed[@"ok"] = @NO;
    return fixed;
}

#pragma mark - URL helpers

+ (BOOL)isProfileWebURL:(NSURL *)url {
    NSString *path = url.path.lowercaseString;
    const char *pPrefix = TserverSealedStringAt(kTserverSealedStr_ProfileWebPrefix);
    NSString *prefix = (pPrefix && pPrefix[0]) ? [NSString stringWithUTF8String:pPrefix] : @"";
    return prefix.length > 0 ? [path containsString:prefix] : NO;
}

+ (NSString *)profileInstallURLFromStartURL:(NSString *)urlString {
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return @"";
    const char *pStart = TserverSealedStringAt(kTserverSealedStr_ProfileStartPrefix);
    NSString *startPrefix = (pStart && pStart[0]) ? [NSString stringWithUTF8String:pStart] : @"";
    const char *pSrc = TserverSealedStringAt(kTserverSealedStr_ProfileSrcApp);
    NSString *srcApp = (pSrc && pSrc[0]) ? [NSString stringWithUTF8String:pSrc] : @"";
    const char *pInstall = TserverSealedStringAt(kTserverSealedStr_ProfileInstall);
    NSString *installSuffix = (pInstall && pInstall[0]) ? [NSString stringWithUTF8String:pInstall] : @"";

    if (startPrefix.length > 0 && [trimmed.lowercaseString containsString:startPrefix]) {
        if (srcApp.length > 0 && [trimmed containsString:srcApp]) return trimmed;
        NSString *separator = [trimmed containsString:@"?"] ? @"&" : @"?";
        return srcApp.length > 0 ? [trimmed stringByAppendingFormat:@"%@%@", separator, srcApp] : trimmed;
    }
    if (installSuffix.length > 0 && ![trimmed.lowercaseString containsString:installSuffix]) {
        if ([trimmed hasSuffix:@"/"]) {
            trimmed = [trimmed substringToIndex:trimmed.length - 1];
        }
        trimmed = [trimmed stringByAppendingString:installSuffix];
    }
    if (srcApp.length > 0 && [trimmed containsString:srcApp]) return trimmed;
    NSString *separator = [trimmed containsString:@"?"] ? @"&" : @"?";
    return srcApp.length > 0 ? [trimmed stringByAppendingFormat:@"%@%@", separator, srcApp] : trimmed;
}

+ (void)openURLString:(NSString *)urlString fromViewController:(UIViewController *)viewController {
    [self openURLString:urlString fromViewController:viewController completion:nil];
}

+ (void)openURLString:(NSString *)urlString
   fromViewController:(UIViewController *)viewController
           completion:(void (^)(BOOL opened))completion {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    NSString *scheme = url.scheme.lowercaseString;
    BOOL isHttp = [scheme isEqualToString:TS_OBF_NS("http")] || [scheme isEqualToString:TS_OBF_NS("https")];
    if (!url || !isHttp) {
        if (completion) completion(NO);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = UIApplication.sharedApplication;
        __block BOOL finished = NO;
        void (^finish)(BOOL) = ^(BOOL opened) {
            if (finished) return;
            finished = YES;
            if (completion) completion(opened);
        };
        UIViewController *(^resolvePresenter)(void) = ^UIViewController *{
            UIViewController *presenter = viewController;
            if (!presenter.viewIfLoaded.window) presenter = [self activeViewController];
            while (presenter.presentedViewController &&
                   !presenter.presentedViewController.isBeingDismissed &&
                   ![presenter.presentedViewController isKindOfClass:SFSafariViewController.class]) {
                presenter = presenter.presentedViewController;
            }
            return presenter;
        };
        void (^presentSafari)(NSURL *) = ^(NSURL *targetURL) {
            if (finished) return;
            UIViewController *presenter = resolvePresenter();
            if ([presenter.presentedViewController isKindOfClass:SFSafariViewController.class]) {
                finish(YES);
                return;
            }
            if (!presenter.viewIfLoaded.window || presenter.isBeingDismissed || presenter.isBeingPresented) {
                // UIKit can still be finishing a host transition. Retry on the next
                // run loop before reporting a stable launch failure to the gate.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (finished) return;
                    UIViewController *retryPresenter = resolvePresenter();
                    if (!retryPresenter.viewIfLoaded.window || retryPresenter.isBeingDismissed || retryPresenter.isBeingPresented) {
                        finish(NO);
                        return;
                    }
                    @try {
                        SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:targetURL];
                        safari.modalPresentationStyle = UIModalPresentationFullScreen;
                        [retryPresenter presentViewController:safari animated:YES completion:^{
                            finish(safari.presentingViewController != nil || safari.viewIfLoaded.window != nil);
                        }];
                    } @catch (__unused NSException *exception) {
                        finish(NO);
                    }
                });
                return;
            }
            @try {
                [presenter.view endEditing:YES];
                SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:targetURL];
                safari.modalPresentationStyle = UIModalPresentationFullScreen;
                [presenter presentViewController:safari animated:YES completion:^{
                    finish(safari.presentingViewController != nil || safari.viewIfLoaded.window != nil);
                }];
            } @catch (__unused NSException *exception) {
                finish(NO);
            }
        };

        BOOL isProfile = [self isProfileWebURL:url];
        NSURL *targetURL = url;
        if (isProfile) {
            NSString *absolute = url.absoluteString ?: @"";
            if (absolute.length > 0 && ![absolute containsString:@"src=app"]) {
                NSString *separator = [absolute containsString:@"?"] ? @"&" : @"?";
                targetURL = [NSURL URLWithString:[absolute stringByAppendingFormat:@"%@src=app", separator]] ?: url;
            }
        }

        [application openURL:targetURL options:@{} completionHandler:^(BOOL opened) {
            if (!isProfile) {
                if (opened) finish(YES);
                else presentSafari(targetURL);
                return;
            }

            if (!opened) {
                presentSafari(targetURL);
                return;
            }

            // A real Safari handoff moves the host inactive/background. Injected
            // games sometimes swizzle openURL and call completion(YES) without
            // leaving the app; only that foreground no-op needs in-process Safari.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (finished) return;
                if (application.applicationState != UIApplicationStateActive) {
                    finish(YES);
                    return;
                }
                UIViewController *presenter = resolvePresenter();
                if ([presenter.presentedViewController isKindOfClass:SFSafariViewController.class]) {
                    finish(YES);
                    return;
                }
                presentSafari(targetURL);
            });
        }];
    });
}

+ (BOOL)isTserverCallbackURL:(NSURL *)url {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    NSString *expectedHost = TserverSealedNSString(kTserverSealedStr_Issuer);
    if (expectedHost.length == 0) expectedHost = TS_OBF_NS("tserver");
    BOOL hostMatches = [host isEqualToString:expectedHost] || host.length == 0;
    BOOL pathMatches = [path containsString:TS_OBF_NS("callback")] || [path isEqualToString:@"/"] || path.length == 0;
    if (!hostMatches || !pathMatches) return NO;
    if (TserverReturnScheme.length == 0 || ![scheme isEqualToString:TserverReturnScheme.lowercaseString]) {
        return NO;
    }
    return [self isReturnSchemeRegisteredInHostApp];
}

#pragma mark - Config helpers

+ (BOOL)hasRequiredNonSecretConfig {
    return TserverEndpoints.count > 0 &&
           TserverPackageToken.length >= 24 &&
           TserverReturnScheme.length > 0 &&
           [self currentBundleId].length > 0;
}

+ (BOOL)hasRequiredConfig {
    return [self hasRequiredNonSecretConfig] && TserverCompiledClientApiKey().length >= 16;
}

+ (NSDictionary *)missingConfigResult {
    if (![self hasRequiredNonSecretConfig]) {
        return [self localResultWithStatus:TserverStatusServerError
                                   message:@"TserverAuth is not configured"];
    }
    return [self localResultWithStatus:TserverStatusClientKeyUnavailable
                               message:@"Client auth material unavailable in this process"];
}

+ (NSString *)hostAppVersion {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [version isKindOfClass:NSString.class] ? version : @"";
}

+ (NSString *)normalizedEndpoint:(NSString *)endpoint {
    NSString *trimmed = [endpoint stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    return trimmed ?: @"";
}

+ (NSString *)validatedReturnScheme:(id)value {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *candidate = [[(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        lowercaseString];
    NSRange separator = [candidate rangeOfString:@"://"];
    if (separator.location != NSNotFound) {
        candidate = [candidate substringToIndex:separator.location];
    }
    while ([candidate hasSuffix:@":"]) {
        candidate = [candidate substringToIndex:candidate.length - 1];
    }
    if (candidate.length < 2 || candidate.length > 64) return @"";
    NSArray<NSString *> *blocked = @[
        @"about", @"blob", @"data", @"file", @"http", @"https", @"itms-services", @"javascript", @"mailto", @"sms", @"tel"
    ];
    if ([blocked containsObject:candidate]) return @"";
    unichar first = [candidate characterAtIndex:0];
    if (first < 'a' || first > 'z') return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789+.-"];
    if ([candidate rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return @"";
    return candidate;
}

+ (NSString *)registeredReturnScheme {
    id urlTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
    if (![urlTypes isKindOfClass:NSArray.class]) return @"";
    for (id entry in (NSArray *)urlTypes) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id schemes = ((NSDictionary *)entry)[@"CFBundleURLSchemes"];
        if (![schemes isKindOfClass:NSArray.class]) continue;
        for (id value in (NSArray *)schemes) {
            NSString *candidate = [self validatedReturnScheme:value];
            if (candidate.length > 0) return candidate;
        }
    }
    return @"";
}

+ (NSString *)normalizedReturnScheme:(NSString *)returnScheme {
    NSString *trimmed = [[returnScheme ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        lowercaseString];
    if (trimmed.length == 0 || [trimmed isEqualToString:@"auto"]) {
        id urlTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        if ([urlTypes isKindOfClass:NSArray.class]) {
            for (id entry in (NSArray *)urlTypes) {
                if (![entry isKindOfClass:NSDictionary.class]) continue;
                for (id value in ((NSDictionary *)entry)[@"CFBundleURLSchemes"] ?: @[]) {
                    NSString *candidate = [self validatedReturnScheme:value];
                    if ([candidate isEqualToString:@"tserverapp"]) return candidate;
                }
            }
        }
        NSString *registered = [self registeredReturnScheme];
        if (registered.length > 0) return registered;
        return @"tserverapp";
    }
    NSString *validated = [self validatedReturnScheme:trimmed];
    return validated.length > 0 ? validated : @"tserverapp";
}

+ (NSArray<NSString *> *)orderedEndpoints {
    NSMutableArray *ordered = [NSMutableArray array];
    NSString *last = [TserverStorage lastWorkingEndpoint];
    if (last.length > 0 && [TserverEndpoints containsObject:last]) {
        [ordered addObject:last];
    }
    for (NSString *endpoint in TserverEndpoints ?: @[]) {
        if (![ordered containsObject:endpoint]) [ordered addObject:endpoint];
    }
    return ordered;
}

+ (NSDictionary *)offlineGraceOrNetworkError:(NSString *)message {
    if (TserverAuthorizationLeaseIsAuthorized()) {
        return @{
            @"ok": @YES,
            @"status": TserverStatusOfflineGraceValid,
            @"message": @"Signed authorization lease is active",
            @"license": TserverAuthorizationLeaseLicenseInfo() ?: @{}
        };
    }
    return [self localResultWithStatus:TserverStatusNetworkError message:message ?: @"Network error"];
}

+ (NSDate *)dateFromISOString:(NSString *)text {
    if (text.length == 0) return nil;
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    return [formatter dateFromString:text];
}

+ (NSString *)queryValue:(NSString *)name components:(NSURLComponents *)components {
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:name]) {
            return item.value;
        }
    }
    return nil;
}

+ (UIViewController *)activeViewController {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *window = nil;
    for (UIWindow *candidate in application.windows.reverseObjectEnumerator) {
        if (!candidate.hidden && candidate.rootViewController) {
            window = candidate;
            break;
        }
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    while ([controller isKindOfClass:UINavigationController.class]) {
        UIViewController *visible = ((UINavigationController *)controller).visibleViewController;
        if (!visible) break;
        controller = visible;
    }
    while ([controller isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
        if (!selected) break;
        controller = selected;
    }
    return controller;
}

+ (NSDictionary *)localResultWithStatus:(NSString *)status message:(NSString *)message {
    return @{
        @"ok": @NO,
        @"status": status ?: TserverStatusServerError,
        @"message": message ?: @"Unknown error"
    };
}

+ (void)complete:(TserverCompletion)completion result:(NSDictionary *)result {
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result ?: [self localResultWithStatus:TserverStatusServerError message:@"Empty result"]);
    });
}

@end