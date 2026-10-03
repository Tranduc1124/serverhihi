#import "TserverClientIdentity.h"
#import "TserverSecurity.h"
#import "TserverStringCrypto.h"

#include <Security/Security.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif
const char *TserverClientIdentityKidCStr(void);
int TserverFillClientIdentityPrivateKeyDER(uint8_t *out, size_t outCap, size_t *outLen);
int TserverClientIdentityDataEmbedOk(void);
#ifdef __cplusplus
}
#endif

static SecKeyRef gPrivateKey = NULL;
static dispatch_once_t gOnce;

static void TserverClientIdentityLoadOnce(void) {
    if (!TserverSecurityAllowSensitiveWork()) {
        return;
    }
    if (TserverClientIdentityDataEmbedOk() != 0) {
        return;
    }
    // 97-byte X9.63 private: 0x04 || X(32) || Y(32) || d(32) for SecKeyCreateWithData.
    uint8_t raw[128];
    size_t rawLen = 0;
    memset(raw, 0, sizeof(raw));
    if (TserverFillClientIdentityPrivateKeyDER(raw, sizeof(raw), &rawLen) != 0 || rawLen != 97 || raw[0] != 0x04) {
        TserverSecureMemZero(raw, sizeof(raw));
        return;
    }
    NSData *keyData = [NSData dataWithBytes:raw length:rawLen];
    TserverSecureMemZero(raw, sizeof(raw));

    NSDictionary *attrs = @{
        (__bridge NSString *)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge NSString *)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge NSString *)kSecAttrKeySizeInBits: @256,
    };
    CFErrorRef err = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyData, (__bridge CFDictionaryRef)attrs, &err);
    if (err) {
        CFRelease(err);
        err = NULL;
    }
    if (!key) {
        return;
    }
    gPrivateKey = key;
}

NSString *TserverClientIdentityKid(void) {
    if (!TserverSecurityAllowSensitiveWork()) {
        return @"";
    }
    const char *kid = TserverClientIdentityKidCStr();
    if (!kid || kid[0] == '\0') {
        return @"";
    }
    return [[NSString alloc] initWithUTF8String:kid] ?: @"";
}

SecKeyRef TserverClientIdentityPrivateKey(void) {
    dispatch_once(&gOnce, ^{
        TserverClientIdentityLoadOnce();
    });
    return gPrivateKey;
}

NSData *TserverClientIdentitySignUTF8Payload(NSString *payload) {
    if (payload.length == 0) {
        return nil;
    }
    SecKeyRef key = TserverClientIdentityPrivateKey();
    if (!key) {
        return nil;
    }
    NSData *msg = [payload dataUsingEncoding:NSUTF8StringEncoding];
    if (msg.length == 0) {
        return nil;
    }
    if (!SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeSign, kSecKeyAlgorithmECDSASignatureMessageX962SHA256)) {
        return nil;
    }
    CFErrorRef err = NULL;
    CFDataRef sig = SecKeyCreateSignature(key,
                                          kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                          (__bridge CFDataRef)msg,
                                          &err);
    if (err) {
        CFRelease(err);
        return nil;
    }
    if (!sig) {
        return nil;
    }
    return CFBridgingRelease(sig);
}

BOOL TserverClientIdentityEmbedOk(void) {
    return TserverClientIdentityDataEmbedOk() == 0 && TserverClientIdentityKid().length > 0;
}
