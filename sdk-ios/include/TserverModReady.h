#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Waits until gate UI is gone and game host view is ready, then runs block on main queue.
/// Use this before attaching mod menu / hooks to avoid crashes after auth unlock.
FOUNDATION_EXTERN void TserverModReadyDispatch(dispatch_block_t block);

/// Same as TserverModReadyDispatch but only checks host readiness (no gate wait).
FOUNDATION_EXTERN void TserverModHostReadyDispatch(dispatch_block_t block);

NS_ASSUME_NONNULL_END