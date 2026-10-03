#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TserverAuthorizationState) {
    TserverAuthorizationStateUninitialized = 0,
    TserverAuthorizationStateRefreshing,
    TserverAuthorizationStateAuthorized,
    TserverAuthorizationStateExpired,
    TserverAuthorizationStateDenied,
    TserverAuthorizationStateCompromised
};

typedef void (^TserverAuthorizationRevocationBlock)(TserverAuthorizationState state);

FOUNDATION_EXPORT BOOL TserverAuthorizationLeaseInstall(
    NSDictionary *response,
    NSString *packageToken,
    NSString *profileSessionToken,
    NSString *packageSessionToken,
    NSString *clientInstallId,
    NSString *bundleId,
    NSError **error
);
FOUNDATION_EXPORT BOOL TserverAuthorizationLeaseIsAuthorized(void);
FOUNDATION_EXPORT BOOL TserverAuthorizationLeaseAllowsCapability(NSString *capability);
FOUNDATION_EXPORT NSDictionary *TserverAuthorizationLeaseLicenseInfo(void);
FOUNDATION_EXPORT TserverAuthorizationState TserverAuthorizationLeaseCurrentState(void);
/// Monotonic local lease-install generation. A key confirmation must observe a
/// newer generation than before activation; a cached/old lease is not success.
FOUNDATION_EXPORT uint64_t TserverAuthorizationLeaseGeneration(void);
FOUNDATION_EXPORT void TserverAuthorizationLeaseInvalidate(TserverAuthorizationState state);
FOUNDATION_EXPORT void TserverAuthorizationLeaseSetRevocationHandler(TserverAuthorizationRevocationBlock _Nullable handler);

// C entry points are watched by anti-hook/anti-patch modules.
FOUNDATION_EXPORT BOOL TserverAuthorizationLeaseIntegrityCheck(void);
FOUNDATION_EXPORT BOOL TserverAuthorizationLeasePerformCapability(
    NSString *capability,
    dispatch_block_t _Nullable work,
    dispatch_block_t _Nullable denied
);

NS_ASSUME_NONNULL_END
