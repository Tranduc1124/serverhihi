#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TserverAuthReadyBlock)(void);
/// Called on the main queue after the gate has been configured. A nil result
/// means configuration completed; a non-nil result is a terminal setup failure.
/// This is used by the compatibility key-confirmation entry point so it can
/// submit a key without treating a local configuration flag as authorization.
typedef void (^TserverAuthBootstrapPreparedBlock)(NSDictionary * _Nullable result);

/// Optional runtime config used by the two-file APIClient.h + libAPIClient.a integration.
FOUNDATION_EXTERN void TserverAuthBootstrapConfigure(NSString * _Nullable packageToken);

/// Starts auth gate flow. Calls onValid once per verified authorization epoch after a
/// saved-session or interactive authorization succeeds and the host UI is safe.
FOUNDATION_EXTERN void TserverAuthBootstrapStart(TserverAuthReadyBlock onValid);

/// Starts the same gate flow and reports when configuration is ready (or failed)
/// without waiting for a currently valid license.
FOUNDATION_EXTERN void TserverAuthBootstrapStartWithPrepared(
    TserverAuthReadyBlock _Nullable onValid,
    TserverAuthBootstrapPreparedBlock _Nullable onPrepared
);

/// Returns YES after a successful VALID unlock in this process.
FOUNDATION_EXTERN BOOL TserverAuthBootstrapIsValid(void);

NS_ASSUME_NONNULL_END