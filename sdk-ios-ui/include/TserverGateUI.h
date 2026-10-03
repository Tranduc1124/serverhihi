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
