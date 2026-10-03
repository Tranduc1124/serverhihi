#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^TserverGateCompletion)(NSDictionary *result);
typedef void (^TserverGateValidCallback)(NSDictionary *result);

FOUNDATION_EXPORT NSString * const TserverGateEventNeedUUID;
FOUNDATION_EXPORT NSString * const TserverGateEventNeedKey;
FOUNDATION_EXPORT NSString * const TserverGateEventExpired;
FOUNDATION_EXPORT NSString * const TserverGateEventRevoked;
FOUNDATION_EXPORT NSString * const TserverGateEventValid;
FOUNDATION_EXPORT NSString * const TserverGateEventDismissed;

/// `errorCode` stamped by the SDK when the host app ships without a usable URL
/// scheme in `CFBundleURLTypes`. Only a rebuild of the host app can clear it, so
/// the gate must never route the user into retry / key-entry loops for it.
FOUNDATION_EXPORT NSString * const TserverGateFatalConfigErrorCode;

/// YES when `result` is that build-time configuration defect rather than a
/// recoverable authorization outcome.
FOUNDATION_EXPORT BOOL TserverGateResultIsFatalConfigError(NSDictionary * _Nullable result);

/// Label shared by every renderer for a fatal config error: one Close button
/// instead of a retry/change-key button that leads nowhere.
FOUNDATION_EXPORT NSString *TserverGateFatalConfigCloseButtonTitle(void);

/// Quit the process. Used by the fatal config error button because the gate is a
/// full-screen overlay with no way back to the host app.
FOUNDATION_EXPORT void TserverGateTerminateApp(void);

/// What the VALID screen reports once authentication succeeded, read from the
/// signed server response: `keyText` (masked key in use), `expiryText` (when the
/// key runs out) and `deviceText` (this device's identifier). Any entry is absent
/// when the server did not send enough data, so renderers can skip empty rows.
FOUNDATION_EXPORT NSDictionary *TserverGateLicenseInfoFromResult(NSDictionary * _Nullable result);

/// Vertical label/value stack for the entries of `TserverGateLicenseInfoFromResult`.
/// Exposed so every renderer can show the same rows without duplicating layout.
FOUNDATION_EXPORT UIView *TserverGateLicenseInfoView(NSDictionary * _Nullable info,
                                                     UIColor *textColor,
                                                     UIColor *mutedTextColor,
                                                     UIFont *valueFont);

/// `screens.valid.continueMode` resolved to the two supported behaviours.
///
/// "auto" (auto-continue with no button) is no longer offered by the portal and is
/// folded into "anywhere": the VALID screen always reports what was authorized, so
/// dismissing it on a timer would only hide information the user just asked for.
FOUNDATION_EXPORT NSString *TserverGateNormalizedValidContinueMode(NSString * _Nullable mode);

@interface TserverGateUI : NSObject

+ (void)configureWithAuthConfig:(NSDictionary *)config;
+ (void)clearAuthConfig;

+ (void)setOnValid:(TserverGateValidCallback)callback;

+ (void)showWithResult:(NSDictionary *)result;

/// Present a signed package announcement outside the authorization gate.
/// The SDK shows one alert at a time and persists only the local 3-hour snooze.
+ (void)presentNoticeIfNeeded:(NSDictionary *)result;

+ (void)showLoadingWithMessage:(NSString *)message;

/// Transparent full-screen touch blocker used before the web-selected native
/// pack arrives. It renders no card/text and never grants authorization.
+ (void)showBlockingOverlay;

+ (void)showNeedUUIDWithConfig:(NSDictionary *)config;

+ (void)showNeedKeyWithConfig:(NSDictionary *)config;

+ (void)showExpiredWithConfig:(NSDictionary *)config;

+ (void)showRevokedWithConfig:(NSDictionary *)config;

+ (void)showDeviceMismatchWithConfig:(NSDictionary *)config;

+ (void)showNetworkErrorWithConfig:(NSDictionary *)config
                             retry:(dispatch_block_t)retry;

+ (void)showServerErrorWithConfig:(NSDictionary *)config
                            retry:(dispatch_block_t)retry;

+ (void)dismiss;

+ (BOOL)isVisible;

@end
