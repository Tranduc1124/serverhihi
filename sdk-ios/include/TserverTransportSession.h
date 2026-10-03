#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ECDH transport session — short-lived AES-GCM master for package API bodies (v3).
// Handshake itself is plaintext + client-identity attestation (no body crypto).
@interface TserverTransportSession : NSObject

+ (nullable NSString *)sessionId;
+ (nullable NSData *)sessionKey; // 32-byte v3 master key when active
+ (NSInteger)transportVersion;
+ (BOOL)hasUsableSession;
+ (NSTimeInterval)secondsRemaining;
+ (void)clear;

/// Ensures a session exists (handshake if missing/near expiry). completion on main queue.
+ (void)ensureSessionWithBaseURL:(nullable NSString *)baseURL
                      completion:(nullable void (^)(BOOL ok))completion;

/// True for package encrypt paths that must NOT use long-term key for body crypto.
+ (BOOL)isHandshakeURL:(nullable NSString *)url;

@end

NS_ASSUME_NONNULL_END
