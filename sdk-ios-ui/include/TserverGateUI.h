#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^TserverGateCompletion)(NSDictionary * _Nullable result);
typedef void (^TserverGateValidCallback)(NSDictionary * _Nullable result);

// Once any declaration in this header carries a nullability annotation, clang's
// -Wnullability-completeness audit (and -Werror in the release build) requires
// every pointer here to be annotated too. Constants and the interface below
// state their guarantee explicitly; config/result parameters the renderers
// nil-check are marked _Nullable.
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateEventNeedUUID;
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateEventNeedKey;
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateEventExpired;
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateEventRevoked;
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateEventValid;
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateEventDismissed;

/// `errorCode` stamped by the SDK when the host app ships without a usable URL
/// scheme in `CFBundleURLTypes`. Only a rebuild of the host app can clear it, so
/// the gate must never route the user into retry / key-entry loops for it.
FOUNDATION_EXPORT NSString * _Nonnull const TserverGateFatalConfigErrorCode;

/// YES when `result` is that build-time configuration defect rather than a
/// recoverable authorization outcome.
FOUNDATION_EXPORT BOOL TserverGateResultIsFatalConfigError(NSDictionary * _Nullable result);

/// Label shared by every renderer for a fatal config error: one Close button
/// instead of a retry/change-key button that leads nowhere.
FOUNDATION_EXPORT NSString * _Nonnull TserverGateFatalConfigCloseButtonTitle(void);

/// Quit the process. Used by the fatal config error button because the gate is a
/// full-screen overlay with no way back to the host app.
FOUNDATION_EXPORT void TserverGateTerminateApp(void);

/// What the VALID screen reports once authentication succeeded, read from the
/// signed server response: `keyText` (masked key in use), `expiryText` (when the
/// key runs out) and `deviceText` (this device's identifier). Any entry is absent
/// when the server did not send enough data, so renderers can skip empty rows.
FOUNDATION_EXPORT NSDictionary * _Nonnull TserverGateLicenseInfoFromResult(NSDictionary * _Nullable result);

/// Vertical label/value stack for the entries of `TserverGateLicenseInfoFromResult`.
/// Exposed so every renderer can show the same rows without duplicating layout.
/// Every argument is optional: the implementation falls back to white, a muted
/// grey and the system semibold font when they are nil.
FOUNDATION_EXPORT UIView * _Nonnull TserverGateLicenseInfoView(NSDictionary * _Nullable info,
                                                               UIColor * _Nullable textColor,
                                                               UIColor * _Nullable mutedTextColor,
                                                               UIFont * _Nullable valueFont);

/// `screens.valid.continueMode` resolved to the two supported behaviours.
///
/// "auto" (auto-continue with no button) is no longer offered by the portal and is
/// folded into "anywhere": the VALID screen always reports what was authorized, so
/// dismissing it on a timer would only hide information the user just asked for.
FOUNDATION_EXPORT NSString * _Nonnull TserverGateNormalizedValidContinueMode(NSString * _Nullable mode);

NS_ASSUME_NONNULL_BEGIN

@interface TserverGateUI : NSObject

/// config/result/message arguments are nil-tolerant: the renderers fall back to
/// built-in copy when they are absent, which is the normal state before the
/// signed server config arrives.
+ (void)configureWithAuthConfig:(nullable NSDictionary *)config;
+ (void)clearAuthConfig;

+ (void)setOnValid:(nullable TserverGateValidCallback)callback;

+ (void)showWithResult:(nullable NSDictionary *)result;

/// Present a signed package announcement outside the authorization gate.
/// The SDK shows one alert at a time and persists only the local 3-hour snooze.
+ (void)presentNoticeIfNeeded:(nullable NSDictionary *)result;

+ (void)showLoadingWithMessage:(nullable NSString *)message;

/// Transparent full-screen touch blocker used before the web-selected native
/// pack arrives. It renders no card/text and never grants authorization.
+ (void)showBlockingOverlay;

+ (void)showNeedUUIDWithConfig:(nullable NSDictionary *)config;

+ (void)showNeedKeyWithConfig:(nullable NSDictionary *)config;

+ (void)showExpiredWithConfig:(nullable NSDictionary *)config;

+ (void)showRevokedWithConfig:(nullable NSDictionary *)config;

+ (void)showDeviceMismatchWithConfig:(nullable NSDictionary *)config;

+ (void)showNetworkErrorWithConfig:(nullable NSDictionary *)config
                             retry:(nullable dispatch_block_t)retry;

+ (void)showServerErrorWithConfig:(nullable NSDictionary *)config
                             retry:(nullable dispatch_block_t)retry;

+ (void)dismiss;

+ (BOOL)isVisible;

@end

NS_ASSUME_NONNULL_END
