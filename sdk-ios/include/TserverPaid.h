#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TserverPaid : NSObject

/// Compatibility one-shot bootstrap. Prefer APIClientStartAuthorization +
/// APIClientPerformAuthorized at each paid feature boundary.
+ (void)paid:(dispatch_block_t)onPaid
    __attribute__((deprecated("Use APIClientStartAuthorization + APIClientPerformAuthorized")));

@end

NS_ASSUME_NONNULL_END
