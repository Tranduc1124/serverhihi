#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

/// Internal ECDSA P-256 client build identity (kid + private key).
/// Material is XOR-scrambled at build time; never document for customers.

FOUNDATION_EXPORT NSString *TserverClientIdentityKid(void);
FOUNDATION_EXPORT SecKeyRef _Nullable TserverClientIdentityPrivateKey(void);
FOUNDATION_EXPORT NSData * _Nullable TserverClientIdentitySignUTF8Payload(NSString *payload);
FOUNDATION_EXPORT BOOL TserverClientIdentityEmbedOk(void);

NS_ASSUME_NONNULL_END
