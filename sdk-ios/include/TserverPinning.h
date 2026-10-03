#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TserverPinning : NSObject <NSURLSessionTaskDelegate>
+ (instancetype)shared;
@end

// Internal response gate. Every ephemeral package session must consume evidence
// recorded only after system trust and the baked SPKI pin both pass.
FOUNDATION_EXPORT BOOL TserverPinningConsumeValidatedSession(NSURLSession *session, NSString *host);

/// Union policy-advertised TLS SPKI pins into the runtime allowlist (cap 4).
/// Never replaces baked compile-time pins with an empty list.
FOUNDATION_EXPORT void TserverPinningUnionAdvertisedSpkiPins(NSArray<NSString *> * _Nullable hexPins);

NS_ASSUME_NONNULL_END
