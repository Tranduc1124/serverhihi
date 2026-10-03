#import "TserverGateUI.h"
#import "TserverAuth.h"
#import "TserverActivationAttempt.h"
#import "TserverTemplateRegistry.h"
#import "APIClient.h"
#import "TserverAuthorizationLease.h"
#import <signal.h>
#import <unistd.h>
#import <stdio.h>

@interface TserverStorage : NSObject
+ (NSDictionary *)lastAuthUiConfig;
+ (NSString *)clientInstallId;
@end

NSString * const TserverGateEventNeedUUID = @"NEED_UUID";
NSString * const TserverGateEventNeedKey = @"NEED_KEY";
NSString * const TserverGateEventExpired = @"EXPIRED";
NSString * const TserverGateEventRevoked = @"REVOKED";
NSString * const TserverGateEventValid = @"VALID";
NSString * const TserverGateEventDismissed = @"DISMISSED";

NSString * const TserverGateFatalConfigErrorCode = @"return_scheme_not_registered";

BOOL TserverGateResultIsFatalConfigError(NSDictionary *result) {
    if (![result isKindOfClass:NSDictionary.class]) return NO;
    id code = result[@"errorCode"];
    if (![code isKindOfClass:NSString.class]) return NO;
    return [(NSString *)code caseInsensitiveCompare:TserverGateFatalConfigErrorCode] == NSOrderedSame;
}

NSString *TserverGateFatalConfigCloseButtonTitle(void) {
    return @"Đóng";
}

// Only the first tap quits; a second one must not race the dying process.
static BOOL gTserverGateTerminating = NO;

void TserverGateTerminateApp(void) {
    if (gTserverGateTerminating) return;
    gTserverGateTerminating = YES;
    fflush(stdout);
    fflush(stderr);
    // UIKit has no public "terminate" API, so exit() is how a user-initiated
    // quit ends the process.
    exit(0);
    // Reachable only when a hook swapped exit() for a no-op. Staying alive would
    // strand the user on a non-dismissible overlay whose only button does
    // nothing, so kill the process instead — same reasoning as TserverFridaGuard.
    kill(getpid(), SIGKILL);
    _exit(0);
}

static NSString *TserverGateInfoString(NSDictionary *source, NSString *key) {
    id value = source[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSDictionary *TserverGateInfoLicenseDictionary(NSDictionary *result) {
    id license = result[@"license"];
    return [license isKindOfClass:NSDictionary.class] ? license : @{};
}

static NSString *TserverGateFormattedExpiry(NSDictionary *license) {
    if (!license.count) return @"";
    id isLifetime = license[@"isLifetime"];
    if ([isLifetime respondsToSelector:@selector(boolValue)] && [isLifetime boolValue]) {
        return @"Vĩnh viễn";
    }
    // remainingSeconds is the authoritative countdown the server already computed;
    // effectiveExpiresAt is the fallback when a lifetime/never-expiring license has none.
    id remaining = license[@"remainingSeconds"];
    if ([remaining respondsToSelector:@selector(doubleValue)] && [remaining doubleValue] > 0) {
        double total = [remaining doubleValue];
        NSInteger days = (NSInteger)(total / 86400.0);
        NSInteger hours = (NSInteger)((total - days * 86400.0) / 3600.0);
        NSInteger minutes = (NSInteger)((total - days * 86400.0 - hours * 3600.0) / 60.0);
        if (days > 0) return [NSString stringWithFormat:@"%ld ngày %ld giờ", (long)days, (long)hours];
        if (hours > 0) return [NSString stringWithFormat:@"%ld giờ %ld phút", (long)hours, (long)minutes];
        return [NSString stringWithFormat:@"%ld phút", (long)MAX(1, minutes)];
    }
    NSString *expiresAt = TserverGateInfoString(license, @"effectiveExpiresAt");
    if (expiresAt.length == 0) expiresAt = TserverGateInfoString(license, @"expiresAt");
    if (expiresAt.length == 0) return @"Không xác định";
    // Server sends ISO-8601 UTC; trim to a readable local-agnostic day/hour.
    NSString *trimmed = [expiresAt stringByReplacingOccurrencesOfString:@"Z" withString:@""];
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"T"];
    if (parts.count == 2) {
        NSString *day = parts[0];
        NSString *time = [[parts[1] componentsSeparatedByString:@"."].firstObject
                          componentsSeparatedByString:@"-"].firstObject;
        return time.length > 0 ? [NSString stringWithFormat:@"%@ %@", day, time] : day;
    }
    return trimmed;
}

NSDictionary *TserverGateLicenseInfoFromResult(NSDictionary *result) {
    if (![result isKindOfClass:NSDictionary.class]) return @{};
    NSDictionary *license = TserverGateInfoLicenseDictionary(result);

    // Prefer the masked key: the raw key is never part of a bootstrap response.
    NSString *keyText = TserverGateInfoString(license, @"maskedKey");
    if (keyText.length == 0) keyText = TserverGateInfoString(license, @"licenseKeyMasked");

    // The device identifier the SDK stores per install is the only value it holds
    // locally; the server never sends the raw UDID back.
    NSString *deviceText = [TserverStorage clientInstallId] ?: @"";

    NSString *expiryText = TserverGateFormattedExpiry(license);

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (keyText.length > 0) info[@"keyText"] = keyText;
    if (expiryText.length > 0) info[@"expiryText"] = expiryText;
    if (deviceText.length > 0) info[@"deviceText"] = deviceText;
    return info;
}

UIView *TserverGateLicenseInfoView(NSDictionary *info,
                                   UIColor *textColor,
                                   UIColor *mutedTextColor,
                                   UIFont *valueFont) {
    if (![info isKindOfClass:NSDictionary.class] || info.count == 0) return [UIView new];
    UIColor *valueColor = textColor ?: UIColor.whiteColor;
    UIColor *labelColor = mutedTextColor ?: [UIColor colorWithWhite:0.75 alpha:1];
    UIFont *resolvedValueFont = valueFont ?: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"Key đang dùng", info[@"keyText"] ?: @""],
        @[@"Hết hạn", info[@"expiryText"] ?: @""],
        @[@"UUID máy", info[@"deviceText"] ?: @""]
    ];
    for (NSArray<NSString *> *row in rows) {
        NSString *label = row[0];
        NSString *value = row[1];
        if (![value isKindOfClass:NSString.class] || value.length == 0) continue;
        UILabel *labelLabel = [UILabel new];
        labelLabel.translatesAutoresizingMaskIntoConstraints = NO;
        labelLabel.text = label;
        labelLabel.textColor = labelColor;
        labelLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        UILabel *valueLabel = [UILabel new];
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        valueLabel.text = value;
        valueLabel.textColor = valueColor;
        valueLabel.font = resolvedValueFont;
        valueLabel.numberOfLines = 0;
        valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [stack addArrangedSubview:labelLabel];
        [stack addArrangedSubview:valueLabel];
    }
    return stack;
}

@interface TserverUIConfig : NSObject
@property(nonatomic, strong) NSDictionary *rawConfig;
+ (instancetype)configFromDictionary:(NSDictionary *)dict;
+ (instancetype)defaultConfig;
@end

typedef void (^TserverGateActivateBlock)(NSString *key);

@interface TserverGateView : UIView
- (instancetype)initWithConfig:(TserverUIConfig *)config;
- (BOOL)renderNotice:(NSDictionary *)notice
             onClose:(dispatch_block_t)onClose
            onSnooze:(dispatch_block_t)onSnooze;
- (void)renderStatus:(NSString *)status
              result:(NSDictionary *)result
               retry:(dispatch_block_t)retry
          onNeedUUID:(dispatch_block_t)needUUID
          onActivate:(TserverGateActivateBlock)activate
       onShowNeedKey:(dispatch_block_t)showNeedKey
          onContinue:(dispatch_block_t)onContinue;
@end

@interface TserverGateWindow : NSObject
+ (instancetype)shared;
- (void)showGateView:(UIView *)view;
- (void)showGateView:(UIView *)view makeKey:(BOOL)makeKey;
- (void)refreshCaptureProtection;
- (void)dismiss;
- (BOOL)isVisible;
- (UIViewController *)presentationViewController;
- (void)prepareForExternalPresentation;
@end

static NSDictionary *TserverGateGlobalConfig = nil;
static TserverGateValidCallback TserverGateOnValid = nil;
// Reuse one gate view so LOADING ↔ NEED_* transitions do not tear down/recreate the host overlay (flash loop).
static TserverGateView *TserverGateCurrentView = nil;
static UIView *TserverGateBlockingView = nil;
static NSString *TserverGateCurrentStatus = nil;
static NSString *TserverGateCurrentMessage = nil;
static NSString *TserverGateCurrentTemplateKey = nil;
static NSString *TserverGateCurrentAttemptId = nil;
static UIAlertController *TserverGateSystemAlert = nil;
static UIAlertController *TserverGateNoticeAlert = nil;
static NSString *TserverGateCurrentNoticeId = nil;
static BOOL TserverGateCurrentNoticeSnoozed = NO;
// A signed announcement can arrive while the host window is still being built
// (right after the loading gate finishes). Keep the payload and retry briefly
// instead of silently dropping the message the operator published.
static NSDictionary *TserverGatePendingNoticeResult = nil;
static NSUInteger TserverGateNoticeRetryCount = 0;
static const NSTimeInterval TserverGateNoticeRetryInterval = 0.25;
static const NSUInteger TserverGateNoticeRetryBudget = 12;
static NSString * const TserverGateNoticeDismissalDefaultsKey = @"com.tserver.sdk.noticeDismissals.v1";
static BOOL TserverGateUsingSystemAlert = NO;
static BOOL TserverGateUUIDLaunchInFlight = NO;
static NSTimeInterval TserverGateLoadingStartTime = 0;

@interface TserverGateUI ()
+ (NSDictionary *)noticeFromResult:(NSDictionary *)result;
+ (NSDictionary *)noticeDismissals;
+ (BOOL)noticeIsHidden:(NSString *)noticeId;
+ (void)hideNoticeForThreeHours:(NSString *)noticeId;
+ (BOOL)presentNoticeFromResult:(NSDictionary *)result completion:(dispatch_block_t)completion;
+ (void)presentThemedNotice:(NSDictionary *)notice completion:(dispatch_block_t)completion;
+ (void)presentNoticeIfNeeded:(NSDictionary *)result;
+ (NSString *)licenseSummaryText:(NSDictionary *)result;
@end

static NSString *TserverGateTemplateKey(NSDictionary *config) {
    return [TserverTemplateRegistry templateFingerprintForConfig:config ?: @{}];
}

@implementation TserverGateUI

+ (BOOL)isValidStatus:(NSString *)status {
    return [status isEqualToString:TserverStatusValid] ||
           [status isEqualToString:TserverStatusOfflineGraceValid];
}

NSString *TserverGateNormalizedValidContinueMode(NSString *mode) {
    NSString *value = [mode isKindOfClass:NSString.class] ? mode.lowercaseString : @"";
    if ([value isEqualToString:@"tap"] || [value isEqualToString:@"any"] || [value isEqualToString:@"fullscreen"]) {
        value = @"anywhere";
    }
    // "auto" is no longer offered by the portal. It resolved to a no-button screen
    // that dismissed itself on a timer, which contradicts a VALID screen that now
    // reports key/expiry/device. Treat it as the closest supported mode.
    if ([value isEqualToString:@"auto"] || [value isEqualToString:@"tap_anywhere"]) {
        value = @"anywhere";
    }
    return [value isEqualToString:@"button"] ? @"button" : @"anywhere";
}

+ (NSString *)normalizedContinueMode:(NSString *)mode {
    return TserverGateNormalizedValidContinueMode(mode);
}

+ (NSString *)validContinueModeFromConfigDictionary:(NSDictionary *)config {
    NSDictionary *safeConfig = [config isKindOfClass:NSDictionary.class] ? config : @{};
    NSDictionary *screens = [safeConfig[@"screens"] isKindOfClass:NSDictionary.class] ? safeConfig[@"screens"] : @{};
    NSDictionary *valid = [screens[@"valid"] isKindOfClass:NSDictionary.class] ? screens[@"valid"] : @{};
    NSString *mode = [valid[@"continueMode"] isKindOfClass:NSString.class] ? valid[@"continueMode"] : @"";
    if (mode.length == 0) mode = [valid[@"validContinueMode"] isKindOfClass:NSString.class] ? valid[@"validContinueMode"] : @"";
    if (mode.length == 0) {
        id showButton = valid[@"showButton"];
        if ([showButton respondsToSelector:@selector(boolValue)] && ![showButton boolValue]) {
            mode = @"anywhere";
        }
    }
    if (mode.length == 0) {
        NSDictionary *flow = [safeConfig[@"flow"] isKindOfClass:NSDictionary.class] ? safeConfig[@"flow"] : @{};
        mode = [flow[@"validAction"] isKindOfClass:NSString.class] ? flow[@"validAction"] : @"button";
    }
    return [self normalizedContinueMode:mode];
}

+ (NSDictionary *)noticeFromResult:(NSDictionary *)result {
    if (![result isKindOfClass:NSDictionary.class]) return nil;
    id raw = result[@"notice"];
    if (![raw isKindOfClass:NSDictionary.class]) raw = result[@"announcement"];
    if (![raw isKindOfClass:NSDictionary.class]) return nil;

    NSString *noticeId = [raw[@"id"] isKindOfClass:NSString.class] ? raw[@"id"] : @"";
    NSString *title = [raw[@"title"] isKindOfClass:NSString.class] ? raw[@"title"] : @"";
    NSString *message = [raw[@"message"] isKindOfClass:NSString.class] ? raw[@"message"] : @"";
    NSString *audience = [raw[@"audience"] isKindOfClass:NSString.class] ? raw[@"audience"] : @"";
    noticeId = [noticeId stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    message = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (noticeId.length == 0 || noticeId.length > 128 || title.length == 0 || message.length == 0) return nil;
    if (![audience isEqualToString:@"ALL_SDK_UI"]) return nil;
    if (title.length > 120) title = [title substringToIndex:120];
    if (message.length > 2000) message = [message substringToIndex:2000];
    NSString *type = [raw[@"type"] isKindOfClass:NSString.class] ? raw[@"type"] : @"info";
    return @{
        @"id": [noticeId copy],
        @"title": [title copy],
        @"message": [message copy],
        @"type": [type copy]
    };
}

+ (NSDictionary *)noticeDismissals {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:TserverGateNoticeDismissalDefaultsKey];
    return [raw isKindOfClass:NSDictionary.class] ? raw : @{};
}

+ (BOOL)noticeIsHidden:(NSString *)noticeId {
    if (noticeId.length == 0) return NO;
    id value = [self noticeDismissals][noticeId];
    if (![value respondsToSelector:@selector(doubleValue)]) return NO;
    return [value doubleValue] > [NSDate date].timeIntervalSince1970;
}

+ (void)hideNoticeForThreeHours:(NSString *)noticeId {
    if (noticeId.length == 0) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableDictionary *dismissals = [[self noticeDismissals] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in dismissals.allKeys.copy) {
        id value = dismissals[key];
        if (![value respondsToSelector:@selector(doubleValue)] || [value doubleValue] <= now) {
            [dismissals removeObjectForKey:key];
        }
    }
    dismissals[noticeId] = @(now + (3.0 * 3600.0));
    if (dismissals.count > 64) {
        NSString *oldestKey = dismissals.allKeys.firstObject;
        if (oldestKey) [dismissals removeObjectForKey:oldestKey];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[dismissals copy] forKey:TserverGateNoticeDismissalDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    TserverGateCurrentNoticeSnoozed = YES;
}

+ (BOOL)presentNoticeFromResult:(NSDictionary *)result completion:(dispatch_block_t)completion {
    NSDictionary *notice = [self noticeFromResult:result];
    NSString *noticeId = notice[@"id"];
    if (!notice || [self noticeIsHidden:noticeId]) {
        TserverGatePendingNoticeResult = nil;
        TserverGateNoticeRetryCount = 0;
        return NO;
    }
    if ([TserverGateCurrentNoticeId isEqualToString:noticeId]) {
        if (TserverGateCurrentNoticeSnoozed) {
            // The persisted three-hour snooze has expired; allow this notice
            // to be shown again in the same long-lived process.
            TserverGateCurrentNoticeId = nil;
            TserverGateCurrentNoticeSnoozed = NO;
        } else {
            return NO;
        }
    }
    TserverGateCurrentNoticeId = [noticeId copy];
    TserverGateCurrentNoticeSnoozed = NO;
    TserverGatePendingNoticeResult = [result copy];
    // Presentation only: the host app can react to an announcement without
    // reaching into gate internals.
    TserverDiagnosticsPostNotice(notice);
    TserverGateNoticeRetryCount = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL appIsActive = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
        UIViewController *presenter = appIsActive ? [self systemAlertPresenter] : nil;
        if (!presenter) {
            // The host window is not ready yet (or the app is not foreground).
            // Retry briefly so a notice that arrives exactly when loading
            // finishes is still shown instead of being dropped silently.
            if (appIsActive && TserverGateNoticeRetryCount < TserverGateNoticeRetryBudget) {
                TserverGateNoticeRetryCount++;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TserverGateNoticeRetryInterval * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self presentNoticeFromResult:result completion:completion];
                });
                return;
            }
            // Do not consume the runtime notice ID when there is no visible
            // host yet; the next heartbeat/foreground check can retry safely.
            TserverGateCurrentNoticeId = nil;
            TserverGateCurrentNoticeSnoozed = NO;
            TserverGateNoticeRetryCount = 0;
            if (completion) completion();
            return;
        }

        UIAlertController *previous = TserverGateNoticeAlert;
        if (previous.presentingViewController) {
            // A new signed announcement supersedes an old visible alert. Do not
            // leave the authorization transition blocked behind stale content.
            [previous dismissViewControllerAnimated:NO completion:^{
                TserverGateCurrentNoticeId = nil;
                TserverGateCurrentNoticeSnoozed = NO;
                TserverGateNoticeRetryCount = 0;
                [self presentNoticeFromResult:result completion:completion];
            }];
            return;
        }

        // The package picks its own UI on the web. Apple System Alert is the only
        // template whose signature look IS a UIAlertController; every other pack
        // must render the announcement in its own theme, otherwise an operator
        // choosing Cyber Terminal sees an Apple dialog in the middle of it.
        if (![self shouldUseSystemAlertForConfig:[self configDictionaryFromResultOrConfig:result]]) {
            [self presentThemedNotice:notice completion:completion];
            return;
        }

        NSString *title = notice[@"title"];
        NSString *message = notice[@"message"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                          message:message
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController *weakAlert = alert;
        __block BOOL finished = NO;
        dispatch_block_t finish = ^{
            if (finished) return;
            finished = YES;
            if (TserverGateNoticeAlert == weakAlert) TserverGateNoticeAlert = nil;
            TserverGatePendingNoticeResult = nil;
            TserverGateNoticeRetryCount = 0;
            if (completion) completion();
        };
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(__unused UIAlertAction *action) {
            finish();
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng trong 3 giờ"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self hideNoticeForThreeHours:noticeId];
            finish();
        }]];
        TserverGateNoticeAlert = alert;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
    return YES;
}

/// Announcement rendered by the package's own native UI pack. It reuses the same
/// gate window/themed card as the authorization screens, so the notice matches
/// the template the operator selected on the web instead of the iOS system look.
+ (void)presentThemedNotice:(NSDictionary *)notice completion:(dispatch_block_t)completion {
    NSDictionary *configDictionary = [self configDictionaryFromResultOrConfig:TserverGateGlobalConfig ?: @{}];
    NSDictionary *resolvedConfig = [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:
                                     [self cleanConfigDictionary:configDictionary]];
    TserverUIConfig *config = [TserverUIConfig configFromDictionary:resolvedConfig];
    TserverGateView *view = [[TserverGateView alloc] initWithConfig:config];

    TserverGateCurrentView = view;
    TserverGateCurrentStatus = @"NOTICE";
    TserverGateCurrentMessage = [notice[@"message"] isKindOfClass:NSString.class] ? [notice[@"message"] copy] : @"";
    TserverGateCurrentTemplateKey = TserverGateTemplateKey([self cleanConfigDictionary:configDictionary]);

    __block BOOL finished = NO;
    dispatch_block_t finish = ^{
        if (finished) return;
        finished = YES;
        TserverGatePendingNoticeResult = nil;
        TserverGateNoticeRetryCount = 0;
        if (TserverGateCurrentView == view) {
            TserverGateCurrentView = nil;
            TserverGateCurrentStatus = nil;
            TserverGateCurrentMessage = nil;
            TserverGateCurrentTemplateKey = nil;
            [[TserverGateWindow shared] dismiss];
        }
        if (completion) completion();
    };

    NSString *noticeId = [notice[@"id"] isKindOfClass:NSString.class] ? [notice[@"id"] copy] : @"";
    if (![view renderNotice:notice
                    onClose:finish
                   onSnooze:^{
        [self hideNoticeForThreeHours:noticeId];
        finish();
    }]) {
        // No native pack for this renderer: release the caller instead of
        // blocking on an empty overlay.
        finish();
        return;
    }
    // Never steal keyWindow from the host game (Unity crashes on keyWindow swap).
    [[TserverGateWindow shared] showGateView:view makeKey:NO];
}

+ (void)presentNoticeIfNeeded:(NSDictionary *)result {
    // Prefer a freshly signed notice; otherwise retry one that could not be
    // presented yet because the host window was still coming up.
    NSDictionary *payload = [self noticeFromResult:result] ? result : TserverGatePendingNoticeResult;
    if (![payload isKindOfClass:NSDictionary.class]) return;
    [self presentNoticeFromResult:payload completion:nil];
}

+ (void)completeValidResult:(NSDictionary *)validResult {
    NSDictionary *safeResult = [validResult isKindOfClass:NSDictionary.class] ? [validResult copy] : @{};
    // Gate UI status is not authorization authority — require a live paid lease.
    if (!TserverAuthorizationLeaseIsAuthorized() ||
        !TserverAuthorizationLeaseAllowsCapability(@"paid")) {
        [self showNeedKeyWithConfig:safeResult];
        return;
    }
    dispatch_block_t finish = ^{
        [self dismiss];
        if (TserverGateOnValid) {
            dispatch_async(dispatch_get_main_queue(), ^{
                TserverGateOnValid(safeResult);
            });
        }
    };
    // A package announcement is an explicit operator message, separate from
    // the auth-result popup policy. It is signed with the package response and
    // must be acknowledged before the paid menu is handed to the host app.
    if ([self presentNoticeFromResult:safeResult completion:finish]) return;
    finish();
}

+ (void)configureWithAuthConfig:(NSDictionary *)config {
    NSDictionary *clean = [self cleanConfigDictionary:config];
    if (clean.count == 0) return;
    TserverGateGlobalConfig = clean;
}

+ (void)clearAuthConfig {
    TserverGateGlobalConfig = nil;
    TserverGateCurrentTemplateKey = nil;
    // A new authorization lifecycle may show a notice that was only closed
    // during the previous lifecycle; the explicit 3-hour snooze remains in
    // NSUserDefaults and is still honored.
    TserverGateCurrentNoticeId = nil;
    TserverGateCurrentNoticeSnoozed = NO;
    TserverGatePendingNoticeResult = nil;
    TserverGateNoticeRetryCount = 0;
}

+ (void)setOnValid:(TserverGateValidCallback)callback {
    TserverGateOnValid = [callback copy];
}

+ (BOOL)shouldUseSystemAlertForConfig:(NSDictionary *)config {
    NSDictionary *renderer = [config[@"renderer"] isKindOfClass:NSDictionary.class] ? config[@"renderer"] : @{};
    NSString *rendererId = [renderer[@"id"] isKindOfClass:NSString.class] ? renderer[@"id"] : @"";
    return [rendererId isEqualToString:@"apple_glass"];
}

+ (NSString *)systemAlertScreenNameForStatus:(NSString *)status {
    if ([status isEqualToString:@"LOADING"]) return @"loading";
    if ([status isEqualToString:TserverStatusNeedUUID]) return @"needUuid";
    if ([status isEqualToString:TserverStatusNeedKey] || [status isEqualToString:TserverStatusInvalidKey]) return @"needKey";
    if ([self isValidStatus:status]) return @"valid";
    if ([status isEqualToString:TserverStatusExpired] || [status isEqualToString:@"OFFLINE_GRACE_EXPIRED"] || [status isEqualToString:@"PROFILE_EXPIRED"]) return @"expired";
    if ([status isEqualToString:TserverStatusRevoked]) return @"revoked";
    if ([status isEqualToString:TserverStatusDeviceBlocked]) return @"deviceBlocked";
    if ([status isEqualToString:TserverStatusDeviceMismatch]) return @"deviceMismatch";
    if ([status isEqualToString:TserverStatusUpdateRequired]) return @"updateRequired";
    if ([status isEqualToString:TserverStatusNetworkError] || [status isEqualToString:@"BAD_CLIENT_SIGNATURE"] || [status isEqualToString:@"REPLAY_REQUEST"] || [status isEqualToString:TserverStatusRateLimited] || [status isEqualToString:TserverStatusBadResponseSignature]) return @"networkError";
    if ([status isEqualToString:TserverStatusServerError] || [status isEqualToString:TserverStatusAuthorizationLeaseInvalid] || [status isEqualToString:TserverStatusActivationTimeout] || [status isEqualToString:TserverStatusActivationCancelled] || [status isEqualToString:TserverStatusTransportSessionError] || [status isEqualToString:TserverStatusCallbackFailure] || [status isEqualToString:TserverStatusUIFailure]) return @"serverError";
    if ([status isEqualToString:TserverStatusMaintenance] || [status isEqualToString:@"APP_DISABLED"] || [status isEqualToString:@"STORE_DISABLED"] || [status isEqualToString:@"PACKAGE_DISABLED"] || [status isEqualToString:@"PACKAGE_MAINTENANCE"]) return @"maintenance";
    if ([status isEqualToString:TserverStatusUnsafeEnvironment]) return @"serverError";
    return @"serverError";
}

+ (UIViewController *)systemAlertPresenter {
    UIViewController *controller = [[TserverGateWindow shared] presentationViewController];
    if ([controller isKindOfClass:UIAlertController.class]) controller = controller.presentingViewController;
    while (controller) {
        UIViewController *presented = controller.presentedViewController;
        if (!presented || presented.isBeingDismissed) break;
        if ([presented isKindOfClass:UIAlertController.class]) {
            controller = presented.presentingViewController ?: controller;
            break;
        }
        controller = presented;
    }
    if (controller.viewIfLoaded.window) return controller;

    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (window.hidden || !window.rootViewController || !window.rootViewController.viewIfLoaded.window) continue;
        controller = window.rootViewController;
        while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
            controller = controller.presentedViewController;
            if ([controller isKindOfClass:UIAlertController.class]) {
                controller = controller.presentingViewController ?: controller;
                break;
            }
        }
        if (controller.viewIfLoaded.window) return controller;
    }
    return nil;
}

+ (void)ensureSystemAlertBlocker {
    if ([self isVisible]) return;
    UIView *blocker = [UIView new];
    blocker.backgroundColor = UIColor.clearColor;
    blocker.userInteractionEnabled = YES;
    blocker.multipleTouchEnabled = YES;
    blocker.accessibilityLabel = @"Đang xác thực";
    [[TserverGateWindow shared] showGateView:blocker makeKey:NO];
}

/// One-line license summary for the system-alert VALID screen, which cannot host
/// the multi-row view the renderers use. Returns nil when the response carried no
/// license, so nothing is added to the alert.
+ (NSString *)licenseSummaryText:(NSDictionary *)result {
    NSDictionary *info = TserverGateLicenseInfoFromResult(result);
    if (info.count == 0) return nil;
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSString *keyText = info[@"keyText"];
    NSString *expiryText = info[@"expiryText"];
    NSString *deviceText = info[@"deviceText"];
    if ([keyText isKindOfClass:NSString.class] && keyText.length > 0) {
        [rows addObject:[NSString stringWithFormat:@"Key: %@", keyText]];
    }
    if ([expiryText isKindOfClass:NSString.class] && expiryText.length > 0) {
        [rows addObject:[NSString stringWithFormat:@"Hết hạn: %@", expiryText]];
    }
    if ([deviceText isKindOfClass:NSString.class] && deviceText.length > 0) {
        [rows addObject:[NSString stringWithFormat:@"UUID: %@", deviceText]];
    }
    return rows.count > 0 ? [rows componentsJoinedByString:@"\n"] : nil;
}

+ (void)presentSystemAlertStatus:(NSString *)status
                          result:(NSDictionary *)result
                          config:(NSDictionary *)configDictionary
                          retry:(dispatch_block_t)retry
                       needUUID:(dispatch_block_t)needUUID
                       activate:(TserverGateActivateBlock)activate
                  showNeedKey:(dispatch_block_t)showNeedKey
                   continueAuth:(dispatch_block_t)continueAuth {
    NSDictionary *safeConfig = [configDictionary isKindOfClass:NSDictionary.class] ? configDictionary : @{};
    NSDictionary *screens = [safeConfig[@"screens"] isKindOfClass:NSDictionary.class] ? safeConfig[@"screens"] : @{};
    NSString *screenName = [self systemAlertScreenNameForStatus:status];
    NSDictionary *screen = [screens[screenName] isKindOfClass:NSDictionary.class] ? screens[screenName] : @{};
    NSString *serverMessage = [result[@"message"] isKindOfClass:NSString.class] ? result[@"message"] : @"";
    NSString *screenMessage = [screen[@"subtitle"] isKindOfClass:NSString.class] ? screen[@"subtitle"] : @"";
    NSString *message = serverMessage.length > 0 ? serverMessage : screenMessage;

    NSString *fallbackTitle = @"Tserver";
    if ([status isEqualToString:@"LOADING"]) fallbackTitle = @"Đang kiểm tra";
    else if ([status isEqualToString:TserverStatusNeedUUID]) fallbackTitle = @"Xác minh thiết bị";
    else if ([status isEqualToString:TserverStatusNeedKey]) fallbackTitle = @"Nhập license key";
    else if ([status isEqualToString:TserverStatusInvalidKey]) fallbackTitle = @"License key không hợp lệ";
    else if ([self isValidStatus:status]) fallbackTitle = @"Đã kích hoạt";
    else if ([status isEqualToString:TserverStatusExpired] || [status isEqualToString:@"PROFILE_EXPIRED"]) fallbackTitle = @"Key đã hết hạn";
    else if ([status isEqualToString:TserverStatusRevoked]) fallbackTitle = @"Key đã bị thu hồi";
    else if ([status isEqualToString:TserverStatusDeviceBlocked]) fallbackTitle = @"Thiết bị bị chặn";
    else if ([status isEqualToString:TserverStatusDeviceMismatch]) fallbackTitle = @"Sai thiết bị";
    else if ([status isEqualToString:TserverStatusUpdateRequired]) fallbackTitle = @"Cần cập nhật";
    else if ([status isEqualToString:TserverStatusNetworkError]) fallbackTitle = @"Lỗi kết nối";
    else fallbackTitle = @"Không thể tiếp tục";
    NSString *title = [screen[@"title"] isKindOfClass:NSString.class] && [screen[@"title"] length] > 0 ? screen[@"title"] : fallbackTitle;
    NSString *buttonText = [screen[@"buttonText"] isKindOfClass:NSString.class] ? screen[@"buttonText"] : @"";

    // On VALID the license rows belong in the message body: Key / Hết hạn / UUID
    // as text. They used to be added as a UIAlertAction, which rendered the key
    // as a tappable row between the message and the continue button.
    NSString *licenseSummary = nil;
    if ([self isValidStatus:status]) {
        licenseSummary = [self licenseSummaryText:result];
        if (licenseSummary.length > 0) {
            message = message.length > 0
                ? [NSString stringWithFormat:@"%@\n\n%@", message, licenseSummary]
                : licenseSummary;
        }
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert = alert;
    BOOL isKeyEntry = [status isEqualToString:TserverStatusNeedKey] || [status isEqualToString:TserverStatusInvalidKey];
    if (isKeyEntry) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = [screen[@"placeholder"] isKindOfClass:NSString.class] ? screen[@"placeholder"] : @"TSRV-XXXX-XXXX";
            field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.spellCheckingType = UITextSpellCheckingTypeNo;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.accessibilityLabel = @"Mã license key";
        }];
    }

    if (TserverGateResultIsFatalConfigError(result)) {
        // Only one action, and it quits: nothing else can fix a missing scheme.
        NSString *closeTitle = [screen[@"closeButtonText"] isKindOfClass:NSString.class] && [screen[@"closeButtonText"] length] > 0
            ? screen[@"closeButtonText"]
            : TserverGateFatalConfigCloseButtonTitle();
        [alert addAction:[UIAlertAction actionWithTitle:closeTitle style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
            TserverGateTerminateApp();
        }]];
    } else if ([self isValidStatus:status]) {
        // The license rows are already in the message body, so the alert only
        // carries the continue action.
        NSString *validButton = buttonText.length > 0 ? buttonText : @"Tiếp tục";
        [alert addAction:[UIAlertAction actionWithTitle:validButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (continueAuth) continueAuth();
        }]];
    } else if (isKeyEntry) {
        NSString *activateButton = buttonText.length > 0 ? buttonText : @"Kích hoạt";
        [alert addAction:[UIAlertAction actionWithTitle:activateButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *key = [weakAlert.textFields.firstObject.text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString;
            if (activate) activate(key);
        }]];
    } else if ([status isEqualToString:TserverStatusNeedUUID]) {
        NSString *uuidButton = buttonText.length > 0 ? buttonText : @"Cài hồ sơ UUID";
        [alert addAction:[UIAlertAction actionWithTitle:uuidButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (needUUID) needUUID();
        }]];
    } else if ([status isEqualToString:TserverStatusExpired] || [status isEqualToString:TserverStatusRevoked] || [status isEqualToString:TserverStatusDeviceMismatch] || [status isEqualToString:TserverStatusInvalidKey]) {
        NSString *changeButton = buttonText.length > 0 ? buttonText : @"Nhập key mới";
        [alert addAction:[UIAlertAction actionWithTitle:changeButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (showNeedKey) showNeedKey();
        }]];
    } else if ([status isEqualToString:TserverStatusUpdateRequired]) {
        NSString *updateButton = buttonText.length > 0 ? buttonText : @"Cập nhật";
        [alert addAction:[UIAlertAction actionWithTitle:updateButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *raw = [result[@"updateUrl"] isKindOfClass:NSString.class] ? result[@"updateUrl"] : @"";
            NSURL *url = raw.length > 0 ? [NSURL URLWithString:raw] : nil;
            if (url && url.scheme.length > 0) {
                [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            }
        }]];
    } else if (![status isEqualToString:@"LOADING"] && retry) {
        NSString *retryButton = buttonText.length > 0 ? buttonText : @"Thử lại";
        [alert addAction:[UIAlertAction actionWithTitle:retryButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            retry();
        }]];
    } else if (![status isEqualToString:@"LOADING"] && showNeedKey) {
        NSString *changeButton = buttonText.length > 0 && ![buttonText isEqualToString:@"Thử lại"] ? buttonText : @"Đổi key khác";
        [alert addAction:[UIAlertAction actionWithTitle:changeButton style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            showNeedKey();
        }]];
    } else if (![status isEqualToString:@"LOADING"]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
            if (continueAuth) continueAuth();
        }]];
    }

    UIAlertController *previous = TserverGateSystemAlert;
    TserverGateSystemAlert = alert;
    void (^present)(void) = ^{
        TserverGateSystemAlert = alert;
        UIViewController *presenter = [self systemAlertPresenter];
        if (!presenter) {
            TserverGateSystemAlert = nil;
            [[TserverGateWindow shared] dismiss];
            return;
        }
        [presenter presentViewController:alert animated:YES completion:nil];
    };
    if (previous.presentingViewController) {
        [previous dismissViewControllerAnimated:NO completion:present];
    } else {
        present();
    }
}

+ (void)showWithResult:(NSDictionary *)result {
    NSDictionary *safeResult = [result isKindOfClass:NSDictionary.class] ? result : @{};
    NSString *resultAttemptId = [safeResult[@"attemptId"] isKindOfClass:NSString.class] ? safeResult[@"attemptId"] : @"";
    NSString *liveAttemptId = [TserverActivationAttempt currentAttemptId] ?: @"";
    if (resultAttemptId.length > 0) {
        if (liveAttemptId.length > 0 && ![resultAttemptId isEqualToString:liveAttemptId]) return;
        TserverGateCurrentAttemptId = [resultAttemptId copy];
    }
    NSString *status = [safeResult[@"status"] isKindOfClass:NSString.class] ? safeResult[@"status"] : TserverStatusServerError;

    // Smooth loading hold: ensure the loading animation was visible for at least 1.2s
    if (TserverGateLoadingStartTime > 0) {
        NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - TserverGateLoadingStartTime;
        const NSTimeInterval minLoading = 1.2;
        if (elapsed < minLoading) {
            NSTimeInterval remaining = minLoading - elapsed;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self showWithResult:result];
            });
            return;
        }
    }
    TserverGateLoadingStartTime = 0;

    // Always prefer package authUiConfig from the latest API response so NEED_KEY / LOADING
    // use the same template the member assigned on the package (not built-in default).
    NSDictionary *config = [self configDictionaryFromResultOrConfig:safeResult];
    if (![config isKindOfClass:NSDictionary.class] || config.count == 0) {
        NSDictionary *lastCached = [TserverStorage lastAuthUiConfig];
        if ([lastCached[@"config"] isKindOfClass:NSDictionary.class]) {
            config = lastCached[@"config"];
        } else {
            config = [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:@{}];
        }
    }
    if ([config isKindOfClass:NSDictionary.class] && config.count > 0) {
        [self configureWithAuthConfig:config];
    } else {
        config = [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:@{}];
        [self configureWithAuthConfig:config];
    }

    if (TserverGateResultIsFatalConfigError(safeResult)) {
        // The host app declares no URL scheme, so the Device Verify callback can
        // never come back: retry and key entry are both dead ends (activating
        // needs the session token this app could never obtain). Show the fatal
        // config screen instead, with no retry handler attached so no downstream
        // branch can swap in a button that leads nowhere.
        [self presentStatus:status result:safeResult config:config retry:nil];
        return;
    }

    if ([self isValidStatus:status]) {
        // The VALID screen always presents. A self-dismissing variant existed once
        // ("auto"), but the screen now reports key/expiry/device, so it must stay
        // until the user chooses to continue.
        NSDictionary *validResult = [safeResult copy];
        [self presentStatus:status result:validResult config:config retry:nil];
        return;
    }
    if ([status isEqualToString:@"PROFILE_NOT_INSTALLED"] ||
        [status isEqualToString:@"PROFILE_DOWNLOAD_REQUIRED"] ||
        [status isEqualToString:@"BAD_PROFILE_PAYLOAD"] ||
        [status hasPrefix:@"PROFILE_CALLBACK_"]) {
        NSMutableDictionary *profileError = [safeResult mutableCopy];
        if (![profileError[@"message"] isKindOfClass:NSString.class] ||
            [profileError[@"message"] length] == 0) {
            profileError[@"message"] = @"Ho so chua duoc cai. Mo lai Safari, vao Cai dat > Ho so da tai > Cai dat, sau do quay lai app.";
        }
        [self presentStatus:status result:profileError config:config retry:^{
            [self showLoadingWithMessage:@"Dang dong bo lai trang thai ho so..."];
            [TserverAuth refreshAuthAfterProfileInstallWithCompletion:^(NSDictionary *retryResult) {
                [self showWithResult:retryResult ?: profileError];
            }];
        }];
        return;
    }
    if ([status isEqualToString:TserverStatusNeedUUID]) {
        [self showNeedUUIDWithConfig:safeResult];
        return;
    }
    if ([status isEqualToString:TserverStatusNeedKey] || [status isEqualToString:TserverStatusInvalidKey]) {
        [self presentStatus:status result:safeResult config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusExpired] || [status isEqualToString:@"PROFILE_EXPIRED"]) {
        [self showExpiredWithConfig:safeResult];
        return;
    }
    if ([status isEqualToString:TserverStatusRevoked]) {
        [self showRevokedWithConfig:safeResult];
        return;
    }
    if ([status isEqualToString:TserverStatusDeviceBlocked]) {
        [self presentStatus:status result:safeResult config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusDeviceMismatch]) {
        [self showDeviceMismatchWithConfig:safeResult];
        return;
    }
    if ([status isEqualToString:TserverStatusInvalidApiKey]) {
        NSMutableDictionary *apiError = [safeResult mutableCopy];
        apiError[@"message"] = @"Package token khong hop le. Kiem tra token pkg_... trong dylib.";
        [self presentStatus:status result:apiError config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusInvalidClientApiKey]) {
        NSMutableDictionary *clientError = [safeResult mutableCopy];
        if (![clientError[@"message"] isKindOfClass:NSString.class] || [clientError[@"message"] length] == 0) {
            clientError[@"message"] = @"Client auth bi tu choi boi server. Kiem tra ban dylib dang inject co dung SHA-256 da xac nhan.";
        }
        [self presentStatus:status result:clientError config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusClientKeyUnavailable]) {
        NSMutableDictionary *localClientError = [safeResult mutableCopy];
        localClientError[@"message"] = @"Client auth khong kha dung trong process nay. Tat debugger, Frida, SSL-bypass va dung ban dylib da xac nhan.";
        [self presentStatus:status result:localClientError config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusPackageBundleDenied]) {
        NSMutableDictionary *bundleError = [safeResult mutableCopy];
        if (bundleError[@"message"] == nil) {
            bundleError[@"message"] = @"App/package khong hop le cho thiet bi nay.";
        }
        [self presentStatus:status result:bundleError config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusBadResponseSignature]) {
        NSMutableDictionary *sigError = [safeResult mutableCopy];
        if (sigError[@"message"] == nil) {
            sigError[@"message"] = @"Bad response signature";
        }
        [self presentStatus:status result:sigError config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusBadPackageSession]) {
        [self showServerErrorWithConfig:safeResult retry:^{
            [self showLoadingWithMessage:@"Dang thu ket noi lai..."];
            [TserverAuth bootstrapWithCompletion:^(NSDictionary *retryResult) {
                [self showWithResult:retryResult ?: @{}];
            }];
        }];
        return;
    }
    if ([status isEqualToString:TserverStatusNetworkError]) {
        [self showNetworkErrorWithConfig:safeResult retry:^{ [self showNeedKeyWithConfig:safeResult]; }];
        return;
    }
    if ([status isEqualToString:TserverStatusServerError]) {
        [self showServerErrorWithConfig:safeResult retry:^{ [self showNeedKeyWithConfig:safeResult]; }];
        return;
    }
    if ([status isEqualToString:TserverStatusActivationTimeout] ||
        [status isEqualToString:TserverStatusActivationCancelled] ||
        [status isEqualToString:TserverStatusTransportSessionError] ||
        [status isEqualToString:TserverStatusAuthorizationLeaseInvalid] ||
        [status isEqualToString:TserverStatusCallbackFailure] ||
        [status isEqualToString:TserverStatusUIFailure]) {
        [self presentStatus:status result:safeResult config:config retry:^{ [self showNeedKeyWithConfig:safeResult]; }];
        return;
    }
    if ([status isEqualToString:TserverStatusUnsafeEnvironment]) {
        [self presentStatus:status result:safeResult config:config retry:nil];
        return;
    }
    if ([status isEqualToString:TserverStatusUpdateRequired] ||
        [status isEqualToString:TserverStatusMaintenance] ||
        [status isEqualToString:@"APP_DISABLED"] ||
        [status isEqualToString:@"STORE_DISABLED"] ||
        [status isEqualToString:@"PACKAGE_DISABLED"] ||
        [status isEqualToString:@"PACKAGE_MAINTENANCE"]) {
        [self presentStatus:status result:safeResult config:config retry:nil];
        return;
    }
    [self presentStatus:status result:safeResult config:config retry:nil];
}

+ (void)showBlockingOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self isVisible]) return;
        UIView *blocker = [UIView new];
        blocker.backgroundColor = UIColor.clearColor;
        blocker.userInteractionEnabled = YES;
        blocker.multipleTouchEnabled = YES;
        blocker.accessibilityLabel = @"Đang tải cấu hình xác thực";
        TserverGateBlockingView = blocker;
        TserverGateCurrentView = nil;
        TserverGateCurrentStatus = @"BLOCKING";
        TserverGateCurrentMessage = nil;
        TserverGateCurrentTemplateKey = nil;
        [[TserverGateWindow shared] showGateView:blocker makeKey:NO];
    });
}

+ (void)showLoadingWithMessage:(NSString *)message {
    NSString *text = message.length > 0 ? message : @"Đang kiểm tra bản quyền…";
    if (TserverGateLoadingStartTime == 0) {
        TserverGateLoadingStartTime = [NSDate timeIntervalSinceReferenceDate];
    }
    // Avoid recreating the overlay when we are already on the same loading message.
    if ([TserverGateUI isVisible] &&
        [TserverGateCurrentStatus isEqualToString:@"LOADING"] &&
        [TserverGateCurrentMessage isEqualToString:text]) {
        return;
    }
    NSDictionary *result = @{
        @"ok": @NO,
        @"status": @"LOADING",
        @"message": text
    };
    NSDictionary *config = TserverGateGlobalConfig;
    if (![config isKindOfClass:NSDictionary.class] || config.count == 0) {
        NSDictionary *lastCached = [TserverStorage lastAuthUiConfig];
        if ([lastCached[@"config"] isKindOfClass:NSDictionary.class]) {
            config = lastCached[@"config"];
        } else {
            config = [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:@{}];
        }
    }
    config = [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:config];
    [self presentStatus:@"LOADING" result:result config:config retry:nil];
}

+ (void)showNeedUUIDWithConfig:(NSDictionary *)config {
    NSDictionary *result = [self resultWithStatus:TserverStatusNeedUUID
                                           config:config
                                          message:@"Can lay UUID thiet bi"
                                      sourceResult:config];
    [self presentStatus:TserverStatusNeedUUID
                 result:result
                 config:[self configDictionaryFromResultOrConfig:config]
                  retry:nil];
}

+ (void)showNeedKeyWithConfig:(NSDictionary *)config {
    TserverGateCurrentAttemptId = nil;
    NSDictionary *uiConfig = [self configDictionaryFromResultOrConfig:config ?: @{}];
    NSDictionary *result = [self resultWithStatus:TserverStatusNeedKey
                                           config:uiConfig
                                          message:@"Please enter license key"
                                      sourceResult:config];
    [self presentStatus:TserverStatusNeedKey result:result config:uiConfig retry:nil];
}

+ (void)showExpiredWithConfig:(NSDictionary *)config {
    NSDictionary *result = [self resultWithStatus:TserverStatusExpired config:config message:@"License expired"];
    [self presentStatus:TserverStatusExpired result:result config:[self configDictionaryFromResultOrConfig:config] retry:nil];
}

+ (void)showRevokedWithConfig:(NSDictionary *)config {
    NSDictionary *result = [self resultWithStatus:TserverStatusRevoked config:config message:@"License revoked"];
    [self presentStatus:TserverStatusRevoked result:result config:[self configDictionaryFromResultOrConfig:config] retry:nil];
}

+ (void)showDeviceMismatchWithConfig:(NSDictionary *)config {
    NSDictionary *result = [self resultWithStatus:TserverStatusDeviceMismatch config:config message:@"This key is already linked to another device"];
    [self presentStatus:TserverStatusDeviceMismatch result:result config:[self configDictionaryFromResultOrConfig:config] retry:nil];
}

+ (void)showNetworkErrorWithConfig:(NSDictionary *)config
                             retry:(dispatch_block_t)retry {
    NSString *message = [config[@"message"] isKindOfClass:NSString.class] ? config[@"message"] : @"Khong the ket noi toi server.";
    NSDictionary *result = [self resultWithStatus:TserverStatusNetworkError config:config message:message];
    [self presentStatus:TserverStatusNetworkError result:result config:[self configDictionaryFromResultOrConfig:config] retry:retry];
}

+ (void)showServerErrorWithConfig:(NSDictionary *)config
                            retry:(dispatch_block_t)retry {
    NSString *message = [config[@"message"] isKindOfClass:NSString.class] ? config[@"message"] : @"Server dang loi, vui long thu lai.";
    NSDictionary *result = [self resultWithStatus:TserverStatusServerError config:config message:message];
    [self presentStatus:TserverStatusServerError result:result config:[self configDictionaryFromResultOrConfig:config] retry:retry];
}

+ (void)dismiss {
    TserverGateBlockingView = nil;
    TserverGateCurrentView = nil;
    TserverGateCurrentStatus = nil;
    TserverGateCurrentMessage = nil;
    TserverGateCurrentTemplateKey = nil;
    TserverGateCurrentAttemptId = nil;
    TserverGateUsingSystemAlert = NO;
    UIAlertController *systemAlert = TserverGateSystemAlert;
    TserverGateSystemAlert = nil;
    if (systemAlert.presentingViewController) {
        [systemAlert dismissViewControllerAnimated:NO completion:nil];
    }
    UIAlertController *noticeAlert = TserverGateNoticeAlert;
    TserverGateNoticeAlert = nil;
    if (noticeAlert.presentingViewController) {
        [noticeAlert dismissViewControllerAnimated:NO completion:nil];
    }
    [[TserverGateWindow shared] dismiss];
}

+ (BOOL)isVisible {
    return [[TserverGateWindow shared] isVisible];
}

+ (void)presentStatus:(NSString *)status
               result:(NSDictionary *)result
               config:(NSDictionary *)configDictionary
                retry:(dispatch_block_t)retry {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSString *safeStatus = status.length > 0 ? status : TserverStatusServerError;
            NSString *message = [result[@"message"] isKindOfClass:NSString.class] ? result[@"message"] : @"";
            NSDictionary *nativeResolvedConfig = [TserverTemplateRegistry resolvedConfigByApplyingNativePackToConfig:[self cleanConfigDictionary:configDictionary]];
            TserverUIConfig *config = [TserverUIConfig configFromDictionary:nativeResolvedConfig];

            void (^needUUID)(void) = ^{
                if (TserverGateUUIDLaunchInFlight) return;
                TserverGateUUIDLaunchInFlight = YES;
                [self showLoadingWithMessage:@"Dang mo trang xac nhan thiet bi..."];
                TserverGateWindow *gate = [TserverGateWindow shared];
                [gate prepareForExternalPresentation];
                [TserverAuth startProfileFlowFromViewController:[gate presentationViewController]
                                                     completion:^(NSDictionary *profileResult) {
                    TserverGateUUIDLaunchInFlight = NO;
                    NSString *profileStatus = [profileResult[@"status"] isKindOfClass:NSString.class] ? profileResult[@"status"] : @"";
                    if ([profileStatus isEqualToString:@"PROFILE_OPENED"]) {
                        // Do not immediately re-render NEED_UUID. Some game hosts
                        // briefly foreground while Safari is being presented; keep
                        // this stable pending screen until the app actually returns.
                        [self showLoadingWithMessage:@"Da mo trang xac nhan. Cai ho so trong Cai dat, sau do quay lai app de dong bo UUID."];
                        return;
                    }
                    if ([profileStatus isEqualToString:@"PROFILE_ALREADY_CONFIRMED"]) {
                        [self showLoadingWithMessage:@"Dang dong bo xac nhan thiet bi..."];
                        [TserverAuth refreshAuthAfterProfileInstallWithCompletion:^(NSDictionary *syncResult) {
                            [self showWithResult:syncResult ?: profileResult ?: @{}];
                        }];
                        return;
                    }
                    if ([profileStatus isEqualToString:TserverStatusValid]) {
                        [self showWithResult:profileResult];
                        return;
                    }
                    NSMutableDictionary *failed = [profileResult isKindOfClass:NSDictionary.class]
                        ? [profileResult mutableCopy]
                        : [NSMutableDictionary dictionary];
                    if (failed[@"status"] == nil) failed[@"status"] = TserverStatusNeedUUID;
                    if (failed[@"message"] == nil) {
                        failed[@"message"] = @"Khong mo duoc trang cai ho so. Thu lai.";
                    }
                    failed[@"ok"] = @NO;
                    // A UUID tap first rechecks the existing server session. If
                    // that session has already been confirmed, bootstrap returns
                    // NEED_KEY; rendering a forced NEED_UUID screen here made the
                    // button look broken because it could never open another
                    // profile. Always honor the actual server status instead.
                    [self showWithResult:failed];
                }];
            };
            // Prefer the session that produced this key screen. Fall back to the
            // durable Keychain profile session so a redraw that only kept UI config
            // does not force an unnecessary UUID loop.
            NSString *activationSessionToken = [result[@"sessionToken"] isKindOfClass:NSString.class]
                ? [result[@"sessionToken"] copy]
                : @"";
            if (activationSessionToken.length == 0) {
                activationSessionToken = [[TserverAuth savedSessionToken] copy] ?: @"";
            }
            TserverGateActivateBlock onActivate = ^(NSString *key) {
                NSString *sessionForActivate = activationSessionToken.length > 0
                    ? activationSessionToken
                    : ([[TserverAuth savedSessionToken] copy] ?: @"");
                if (sessionForActivate.length == 0) {
                    [self showWithResult:@{
                        @"ok": @NO,
                        @"status": TserverStatusNeedUUID,
                        @"message": @"Cần xác minh thiết bị trước khi kích hoạt key.",
                        @"authUiConfig": [self configDictionaryFromResultOrConfig:result] ?: @{}
                    }];
                    return;
                }
                [self showLoadingWithMessage:@"Dang kich hoat key..."];
                [TserverAuth activateKey:key
                             sessionToken:sessionForActivate
                              completion:^(NSDictionary *activationResult) {
                    NSMutableDictionary *safeResult = [([activationResult isKindOfClass:NSDictionary.class]
                        ? activationResult
                        : @{
                            @"ok": @NO,
                            @"terminal": @YES,
                            @"status": TserverStatusServerError,
                            @"message": @"Empty activate response"
                        }) mutableCopy];
                    // Keep the profile session available for a second key attempt
                    // after INVALID_KEY / network retry on the same device binding.
                    if (![safeResult[@"sessionToken"] isKindOfClass:NSString.class] ||
                        [safeResult[@"sessionToken"] length] == 0) {
                        safeResult[@"sessionToken"] = sessionForActivate;
                    }
                    [self showWithResult:safeResult];
                }];
                TserverGateCurrentAttemptId = [[TserverActivationAttempt currentAttemptId] copy];
            };
            dispatch_block_t onShowNeedKey = ^{
                [self showNeedKeyWithConfig:result ?: @{}];
            };
            dispatch_block_t onContinue = ^{
                if ([self isValidStatus:safeStatus]) {
                    // completeValidResult: re-checks the live lease before dismiss/onValid.
                    [self completeValidResult:result ?: @{}];
                    return;
                }
                // Auth-required screens: Continue must not clear the blocking gate.
                if ([safeStatus isEqualToString:TserverStatusNeedKey] ||
                    [safeStatus isEqualToString:TserverStatusInvalidKey] ||
                    [safeStatus isEqualToString:TserverStatusNeedUUID] ||
                    [safeStatus isEqualToString:@"LOADING"] ||
                    [safeStatus isEqualToString:TserverStatusUnsafeEnvironment]) {
                    return;
                }
                // Soft errors (network/server/etc.): presentation-only dismiss, never unlock.
                [self dismiss];
            };

            BOOL useSystemAlert = [self shouldUseSystemAlertForConfig:configDictionary];
            if (useSystemAlert) {
                BOOL switchingPresentation = !TserverGateUsingSystemAlert;
                TserverGateUsingSystemAlert = YES;
                if (switchingPresentation) [[TserverGateWindow shared] dismiss];
                TserverGateCurrentStatus = [safeStatus copy];
                TserverGateCurrentMessage = [message copy];
                TserverGateCurrentTemplateKey = TserverGateTemplateKey([self cleanConfigDictionary:configDictionary]);
                if (switchingPresentation) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (TserverGateUsingSystemAlert) [self ensureSystemAlertBlocker];
                    });
                } else {
                    [self ensureSystemAlertBlocker];
                }
                [self presentSystemAlertStatus:safeStatus
                                        result:result ?: @{}
                                        config:configDictionary
                                        retry:retry
                                     needUUID:needUUID
                                     activate:onActivate
                                showNeedKey:onShowNeedKey
                                 continueAuth:onContinue];
                return;
            }
            if (TserverGateUsingSystemAlert) {
                TserverGateUsingSystemAlert = NO;
                UIAlertController *systemAlert = TserverGateSystemAlert;
                TserverGateSystemAlert = nil;
                if (systemAlert.presentingViewController) {
                    [systemAlert dismissViewControllerAnimated:NO completion:nil];
                }
            }

            // Re-render in place when the gate is already on screen — prevents flash/jank.
            // BUT if package Auth UI template/style changed, rebuild the view so colors/layout match.
            NSDictionary *cleanConfig = [self cleanConfigDictionary:configDictionary];
            NSString *templateKey = TserverGateTemplateKey(cleanConfig);
            BOOL sameTemplate = TserverGateCurrentTemplateKey.length > 0 &&
                                [TserverGateCurrentTemplateKey isEqualToString:templateKey];
            BOOL canReuse = sameTemplate &&
                            TserverGateCurrentView != nil &&
                            TserverGateCurrentView.superview != nil &&
                            [TserverGateUI isVisible];
            TserverGateView *view = canReuse
                ? TserverGateCurrentView
                : [[TserverGateView alloc] initWithConfig:config];
            [view renderStatus:safeStatus
                        result:result ?: @{}
                         retry:retry
                    onNeedUUID:needUUID
                    onActivate:onActivate
                 onShowNeedKey:onShowNeedKey
                    onContinue:onContinue];
            TserverGateBlockingView = nil;
            TserverGateCurrentView = view;
            TserverGateCurrentStatus = [safeStatus copy];
            TserverGateCurrentMessage = [message copy];
            TserverGateCurrentTemplateKey = [templateKey copy];
            if (!canReuse) {
                // Always overlay on host game view — never steal keyWindow (Unity crashes).
                [[TserverGateWindow shared] showGateView:view makeKey:NO];
            } else {
                // Bootstrap may apply packageSettings (capture flags) after the cold-start
                // LOADING overlay was already mounted with flags=off. Re-apply in place.
                [[TserverGateWindow shared] refreshCaptureProtection];
            }
        } @catch (__unused NSException *exception) {
            NSDictionary *failed = @{
                @"ok": @NO,
                @"terminal": @YES,
                @"status": TserverStatusUIFailure,
                @"message": @"Không thể hiển thị kết quả kích hoạt.",
                @"errorCode": @"presentation_exception"
            };
            [TserverActivationAttempt publishTerminalResult:failed];
            @try {
                TserverUIConfig *fallbackConfig = [TserverUIConfig defaultConfig];
                TserverGateView *fallback = [[TserverGateView alloc] initWithConfig:fallbackConfig];
                [fallback renderStatus:TserverStatusUIFailure
                                result:failed
                                 retry:^{ [self showNeedKeyWithConfig:@{}]; }
                            onNeedUUID:nil
                            onActivate:nil
                         onShowNeedKey:^{ [self showNeedKeyWithConfig:@{}]; }
                            onContinue:nil];
                TserverGateCurrentView = fallback;
                TserverGateCurrentStatus = TserverStatusUIFailure;
                [[TserverGateWindow shared] showGateView:fallback makeKey:NO];
            } @catch (__unused NSException *fallbackException) {
                [self dismiss];
            }
        }
    });
}

+ (NSDictionary *)resultWithStatus:(NSString *)status config:(NSDictionary *)config message:(NSString *)message {
    return [self resultWithStatus:status config:config message:message sourceResult:config];
}

+ (NSDictionary *)resultWithStatus:(NSString *)status
                            config:(NSDictionary *)config
                           message:(NSString *)message
                       sourceResult:(NSDictionary *)sourceResult {
    NSDictionary *uiConfig = [self configDictionaryFromResultOrConfig:config ?: @{}];
    NSMutableDictionary *result = [@{
        @"ok": @NO,
        @"status": status ?: TserverStatusServerError,
        @"message": message ?: @"",
        @"authUiConfig": uiConfig ?: @{}
    } mutableCopy];
    NSDictionary *source = [sourceResult isKindOfClass:NSDictionary.class] ? sourceResult : @{};
    // Preserve the server-issued profile/package session across UI rebuilds.
    // Dropping these tokens is what created the Activate -> UUID -> key loop.
    NSString *sessionToken = [source[@"sessionToken"] isKindOfClass:NSString.class] ? source[@"sessionToken"] : @"";
    if (sessionToken.length == 0) {
        sessionToken = [TserverAuth savedSessionToken] ?: @"";
    }
    if (sessionToken.length > 0) {
        result[@"sessionToken"] = sessionToken;
    }
    NSString *packageSessionToken = [source[@"packageSessionToken"] isKindOfClass:NSString.class]
        ? source[@"packageSessionToken"]
        : @"";
    if (packageSessionToken.length > 0) {
        result[@"packageSessionToken"] = packageSessionToken;
    }
    return [result copy];
}

+ (NSDictionary *)configDictionaryFromResultOrConfig:(NSDictionary *)value {
    if (![value isKindOfClass:NSDictionary.class]) {
        return TserverGateGlobalConfig ?: @{};
    }
    id nested = value[@"authUiConfig"];
    if ([nested isKindOfClass:NSDictionary.class]) {
        return nested;
    }
    if ([value[@"style"] isKindOfClass:NSDictionary.class] || [value[@"screens"] isKindOfClass:NSDictionary.class]) {
        return value;
    }
    return TserverGateGlobalConfig ?: @{};
}

+ (NSDictionary *)cleanConfigDictionary:(NSDictionary *)config {
    return [config isKindOfClass:NSDictionary.class] ? config : @{};
}

@end
