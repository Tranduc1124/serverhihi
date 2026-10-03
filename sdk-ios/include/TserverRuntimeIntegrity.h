#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lightweight, privacy-safe runtime integrity context included in encrypted
/// package requests. It is telemetry/attestation evidence, never a local
/// authorization decision.
FOUNDATION_EXPORT void TserverRuntimeIntegrityInitialize(void);
FOUNDATION_EXPORT NSUInteger TserverRuntimeIntegrityFlags(void);
FOUNDATION_EXPORT NSString *TserverRuntimeIntegrityCodeSignatureStatus(void);
FOUNDATION_EXPORT NSString *TserverRuntimeIntegrityExecutableStatus(void);
FOUNDATION_EXPORT NSDictionary *TserverRuntimeIntegrityContext(void);

NS_ASSUME_NONNULL_END
