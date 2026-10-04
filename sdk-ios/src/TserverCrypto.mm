#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonCryptor.h>
#import <Security/Security.h>
#import <math.h>
#import <dlfcn.h>
#import "TserverSealedConstants.h"
#import "TserverStringCrypto.h"
#import "TserverClientIdentity.h"

// Resolve GCM entry points at runtime via dlsym. Never hard-link SPI symbols —
// ObjC++ previously mangled `CCCryptorGCM` and DYLD aborted with "Symbol missing".
typedef CCCryptorStatus (*TserverCCCryptorGCMFn)(
    CCOperation op, CCAlgorithm alg,
    const void *key, size_t keyLength,
    const void *iv, size_t ivLen,
    const void *aData, size_t aDataLen,
    const void *dataIn, size_t dataInLength,
    void *dataOut,
    void *tag, size_t *tagLength);
typedef CCCryptorStatus (*TserverCCCryptorCreateWithModeFn)(
    CCOperation op, CCMode mode, CCAlgorithm alg, CCPadding padding,
    const void *iv, const void *key, size_t keyLength,
    const void *tweak, size_t tweakLength, int numRounds, CCModeOptions options,
    CCCryptorRef *cryptorRef);
typedef CCCryptorStatus (*TserverCCCryptorGCMAddAADFn)(CCCryptorRef cryptorRef, const void *aData, size_t aDataLen);
typedef CCCryptorStatus (*TserverCCCryptorGCMSetIVFn)(CCCryptorRef cryptorRef, const void *iv, size_t ivLen);
typedef CCCryptorStatus (*TserverCCCryptorGCMFinalizeFn)(CCCryptorRef cryptorRef, void *tag, size_t *tagLength);

enum {
    kTserverGCMIVBytes = 12,
    kTserverGCMTagBytes = 16,
    kTserverModeGCM = 11 // equals kCCModeGCM on Apple SDKs
};

@interface TserverCrypto : NSObject
+ (NSString *)jsonStringForObject:(id)object;
+ (NSString *)sha256String:(NSString *)string;
+ (NSString *)hmacSHA256String:(NSString *)string secret:(NSString *)secret;
+ (NSString *)randomNonce;
+ (NSNumber *)currentTimestamp;
+ (NSDictionary *)signedHeadersForMethod:(NSString *)method
                                    path:(NSString *)path
                                    body:(NSDictionary *)body
                               apiSecret:(NSString *)apiSecret
                                 storeId:(NSString *)storeId;
+ (BOOL)verifyResponse:(NSDictionary *)response
             apiSecret:(NSString *)apiSecret
requiredSignatureScope:(NSString *)requiredSignatureScope;
+ (NSDictionary *)encryptTransportPayloadV3:(id)payload
                                     rawKey:(NSData *)rawKey
                                  sessionId:(NSString *)sessionId
                                  direction:(NSString *)direction
                                     method:(NSString *)method
                                       path:(NSString *)path
                                      nonce:(NSString *)nonce
                                 statusCode:(NSInteger)statusCode;
+ (NSDictionary *)decryptTransportEnvelopeV3:(NSDictionary *)envelope
                                      rawKey:(NSData *)rawKey
                                   sessionId:(NSString *)sessionId
                                   direction:(NSString *)direction
                                      method:(NSString *)method
                                        path:(NSString *)path
                                       nonce:(NSString *)nonce
                                  statusCode:(NSInteger)statusCode;
+ (BOOL)isTransportEnvelopeV3:(id)value;
+ (NSDictionary *)clientIdentityHeadersForMethod:(NSString *)method
                                            path:(NSString *)path
                                            body:(NSDictionary *)body
                                       timestamp:(NSString *)timestamp
                                           nonce:(NSString *)nonce;
@end

static NSString *TserverHexString(const unsigned char *bytes, NSUInteger length);
static id TserverStableJSONValue(id value);
static NSString *TserverStableJSONString(id value);
static NSString *TserverJSONStringForString(NSString *string);
static NSString *TserverJSONStringForNumber(NSNumber *number);

static NSData *TserverHMACData(NSData *key, NSData *message) {
    if (key.length == 0) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, message.bytes, message.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static NSMutableData *TserverHKDFSHA256(NSData *inputKey, NSData *salt, NSData *info, NSUInteger outputLength) {
    if (inputKey.length == 0 || outputLength == 0 || outputLength > 255 * CC_SHA256_DIGEST_LENGTH) return nil;
    NSData *effectiveSalt = salt.length > 0 ? salt : [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    NSData *prk = TserverHMACData(effectiveSalt, inputKey);
    if (prk.length != CC_SHA256_DIGEST_LENGTH) return nil;
    NSMutableData *output = [NSMutableData dataWithCapacity:outputLength];
    NSData *previous = [NSData data];
    uint8_t counter = 1;
    while (output.length < outputLength) {
        NSMutableData *material = [NSMutableData dataWithData:previous];
        if (info.length > 0) [material appendData:info];
        [material appendBytes:&counter length:1];
        previous = TserverHMACData(prk, material);
        if (previous.length == 0) return nil;
        NSUInteger remaining = outputLength - output.length;
        [output appendBytes:previous.bytes length:MIN(remaining, previous.length)];
        counter++;
    }
    return output;
}

static BOOL TserverTransportContextValid(NSString *sessionId, NSString *direction, NSString *method, NSString *path, NSString *nonce, NSInteger statusCode) {
    if (!([direction isEqualToString:TS_OBF_NS("c2s")] || [direction isEqualToString:TS_OBF_NS("s2c")])) return NO;
    if (![sessionId hasPrefix:TS_OBF_NS("ts_")] || sessionId.length < 20 || sessionId.length > 128) return NO;
    NSCharacterSet *idInvalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet];
    if ([sessionId rangeOfCharacterFromSet:idInvalid].location != NSNotFound) return NO;
    NSString *upperMethod = method.uppercaseString;
    NSCharacterSet *methodInvalid = [[NSCharacterSet uppercaseLetterCharacterSet] invertedSet];
    if (upperMethod.length < 3 || upperMethod.length > 12 || [upperMethod rangeOfCharacterFromSet:methodInvalid].location != NSNotFound) return NO;
    if (path.length < 1 || path.length > 2048 || [path containsString:@"|"] || [path containsString:@"?"]) return NO;
    if (nonce.length < 16 || nonce.length > 256 || [nonce rangeOfCharacterFromSet:idInvalid].location != NSNotFound) return NO;
    return statusCode >= 0 && statusCode <= 999;
}

static NSMutableData *TserverTransportV3EncKey(NSData *masterKey, NSString *sessionId, NSString *direction) {
    if (masterKey.length != 32) return nil;
    NSData *saltMaterial = [[NSString stringWithFormat:TS_OBF_NS("tserver-transport-v3|%@"), sessionId ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t saltBytes[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(saltMaterial.bytes, (CC_LONG)saltMaterial.length, saltBytes);
    NSData *salt = [NSData dataWithBytes:saltBytes length:sizeof(saltBytes)];
    NSData *encInfo = [[NSString stringWithFormat:TS_OBF_NS("tserver-v3|%@|enc"), direction ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *encKey = TserverHKDFSHA256(masterKey, salt, encInfo, 32);
    return encKey.length == 32 ? encKey : nil;
}

/// AAD: ts3|direction|sessionId|method|path|nonce|statusCode — NO trailing pipe (unlike v2).
static NSData *TserverTransportV3AAD(NSString *direction, NSString *sessionId, NSString *method, NSString *path, NSString *nonce, NSInteger statusCode) {
    NSString *aad = [NSString stringWithFormat:TS_OBF_NS("ts3|%@|%@|%@|%@|%@|%ld"),
        direction, sessionId, method.uppercaseString, path, nonce, (long)statusCode];
    return [aad dataUsingEncoding:NSUTF8StringEncoding];
}

typedef struct {
    TserverCCCryptorGCMFn oneShot;
    TserverCCCryptorCreateWithModeFn createWithMode;
    TserverCCCryptorGCMSetIVFn setIV;
    TserverCCCryptorGCMAddAADFn addAAD;
    TserverCCCryptorGCMFinalizeFn finalize;
} TserverGCMFns;

static TserverGCMFns TserverResolveGCMFns(void) {
    static TserverGCMFns fns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fns.oneShot = (TserverCCCryptorGCMFn)dlsym(RTLD_DEFAULT, "CCCryptorGCM");
        fns.createWithMode = (TserverCCCryptorCreateWithModeFn)dlsym(RTLD_DEFAULT, "CCCryptorCreateWithMode");
        fns.setIV = (TserverCCCryptorGCMSetIVFn)dlsym(RTLD_DEFAULT, "CCCryptorGCMSetIV");
        fns.addAAD = (TserverCCCryptorGCMAddAADFn)dlsym(RTLD_DEFAULT, "CCCryptorGCMAddAAD");
        fns.finalize = (TserverCCCryptorGCMFinalizeFn)dlsym(RTLD_DEFAULT, "CCCryptorGCMFinalize");
    });
    return fns;
}

/// AES-256-GCM via CommonCrypto (aes-256-gcm-hkdf). All SPI resolved with dlsym.
/// Fail closed — never abort process on missing symbols.
static BOOL TserverAES256GCMCrypt(CCOperation op,
                                  NSData *key,
                                  NSData *iv,
                                  NSData *aad,
                                  NSData *dataIn,
                                  NSMutableData *dataOut,
                                  NSMutableData *tag) {
    if (key.length != 32 || iv.length != kTserverGCMIVBytes || dataIn == nil || dataOut == nil || tag == nil) return NO;
    size_t tagLength = kTserverGCMTagBytes;
    if (tag.length < tagLength) [tag setLength:tagLength];
    TserverGCMFns fns = TserverResolveGCMFns();

    if (fns.oneShot) {
        [dataOut setLength:dataIn.length];
        CCCryptorStatus st = fns.oneShot(op,
                                         kCCAlgorithmAES,
                                         key.bytes, key.length,
                                         iv.bytes, iv.length,
                                         aad.bytes, aad.length,
                                         dataIn.bytes, dataIn.length,
                                         dataOut.mutableBytes,
                                         tag.mutableBytes, &tagLength);
        if (st == kCCSuccess && tagLength == kTserverGCMTagBytes) {
            [dataOut setLength:dataIn.length];
            [tag setLength:kTserverGCMTagBytes];
            return YES;
        }
        [dataOut setLength:0];
    }

    if (!fns.createWithMode || !fns.setIV || !fns.finalize) {
        [dataOut setLength:0];
        return NO;
    }

    CCCryptorRef cryptor = NULL;
    CCCryptorStatus st = fns.createWithMode(op,
                                            (CCMode)kTserverModeGCM,
                                            kCCAlgorithmAES,
                                            ccNoPadding,
                                            NULL,
                                            key.bytes,
                                            key.length,
                                            NULL,
                                            0,
                                            0,
                                            0,
                                            &cryptor);
    if (st != kCCSuccess || !cryptor) {
        [dataOut setLength:0];
        return NO;
    }

    st = fns.setIV(cryptor, iv.bytes, iv.length);
    if (st == kCCSuccess && aad.length > 0 && fns.addAAD) {
        st = fns.addAAD(cryptor, aad.bytes, aad.length);
    }
    size_t moved = 0;
    if (st == kCCSuccess) {
        [dataOut setLength:CCCryptorGetOutputLength(cryptor, dataIn.length, true)];
        st = CCCryptorUpdate(cryptor, dataIn.bytes, dataIn.length, dataOut.mutableBytes, dataOut.length, &moved);
    }
    size_t finalMoved = 0;
    if (st == kCCSuccess) {
        st = CCCryptorFinal(cryptor,
                            ((uint8_t *)dataOut.mutableBytes) + moved,
                            dataOut.length - moved,
                            &finalMoved);
        moved += finalMoved;
    }
    tagLength = kTserverGCMTagBytes;
    if (st == kCCSuccess) {
        st = fns.finalize(cryptor, tag.mutableBytes, &tagLength);
    }
    CCCryptorRelease(cryptor);
    if (st != kCCSuccess || tagLength != kTserverGCMTagBytes) {
        [dataOut setLength:0];
        return NO;
    }
    [dataOut setLength:moved];
    [tag setLength:kTserverGCMTagBytes];
    return YES;
}

static void TserverWipeMutableData(NSMutableData *data) {
    if (data.length > 0) memset(data.mutableBytes, 0, data.length);
}

@implementation TserverCrypto

+ (NSString *)jsonStringForObject:(id)object {
    // Match server stableJsonStringify: JSON.stringify(sortValue(value)).
    // NSJSONSerialization escapes non-ASCII and forward slashes on some iOS versions,
    // which breaks HMAC verification for authUiConfig Vietnamese text. Build JSON manually.
    return TserverStableJSONString(TserverStableJSONValue(object ?: @{})) ?: @"{}";
}

+ (NSString *)sha256String:(NSString *)string {
    NSData *data = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return TserverHexString(digest, CC_SHA256_DIGEST_LENGTH);
}

+ (NSString *)hmacSHA256String:(NSString *)string secret:(NSString *)secret {
    NSData *keyData = [(secret ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *messageData = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, keyData.bytes, keyData.length, messageData.bytes, messageData.length, digest);
    return TserverHexString(digest, CC_SHA256_DIGEST_LENGTH);
}

+ (NSString *)randomNonce {
    uint8_t bytes[16];
    int status = SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes);
    if (status != errSecSuccess) {
        arc4random_buf(bytes, sizeof(bytes));
    }
    NSMutableString *nonce = [NSMutableString stringWithCapacity:sizeof(bytes) * 2];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) {
        [nonce appendFormat:@"%02x", bytes[i]];
    }
    return nonce;
}

+ (NSNumber *)currentTimestamp {
    NSTimeInterval seconds = [[NSDate date] timeIntervalSince1970];
    return @((long long)seconds);
}

+ (NSDictionary *)signedHeadersForMethod:(NSString *)method
                                    path:(NSString *)path
                                    body:(NSDictionary *)body
                               apiSecret:(NSString *)apiSecret
                                 storeId:(NSString *)storeId {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (storeId.length > 0) {
        headers[@"x-store-id"] = storeId;
    }
    if (apiSecret.length == 0) {
        return headers;
    }

    NSString *timestamp = [NSString stringWithFormat:@"%@", body[@"timestamp"] ?: @""];
    NSString *nonce = [NSString stringWithFormat:@"%@", body[@"nonce"] ?: @""];
    NSString *bodyJson = [self jsonStringForObject:body ?: @{}];
    NSString *bodyHash = [self sha256String:bodyJson];
    NSString *payload = [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
                         [method.uppercaseString length] ? method.uppercaseString : @"POST",
                         path ?: @"",
                         timestamp,
                         nonce,
                         bodyHash];
    NSString *signature = [self hmacSHA256String:payload secret:apiSecret];

    headers[@"x-timestamp"] = timestamp;
    headers[@"x-nonce"] = nonce;
    headers[@"x-signature"] = signature;
    return headers;
}

+ (BOOL)verifyResponse:(NSDictionary *)response
             apiSecret:(NSString *)apiSecret
requiredSignatureScope:(NSString *)requiredSignatureScope {
    if (apiSecret.length == 0 || requiredSignatureScope.length == 0) return NO;
    if (![response isKindOfClass:NSDictionary.class]) return NO;
    NSString *signature = [response[@"responseSignature"] isKindOfClass:NSString.class] ? response[@"responseSignature"] : nil;
    NSString *scope = [response[@"signatureScope"] isKindOfClass:NSString.class] ? response[@"signatureScope"] : nil;
    if (signature.length != 64 || ![scope isEqualToString:requiredSignatureScope]) return NO;
    for (NSUInteger index = 0; index < signature.length; index++) {
        unichar c = [signature characterAtIndex:index];
        BOOL isHex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!isHex) return NO;
    }

    NSMutableDictionary *payload = [response mutableCopy];
    // Must match server packageResponse.service / responseSign.service.
    // This reserved key is supplied by TserverHttp after decrypting a response;
    // it must never be part of server-authenticated bytes.
    [payload removeObjectForKey:@"responseSignature"];
    [payload removeObjectForKey:@"authUiConfig"];
    [payload removeObjectForKey:@"authUiVersion"];
    [payload removeObjectForKey:@"authUiTemplate"];
    [payload removeObjectForKey:@"_tserverClientResponseMeta"];
    NSString *json = [self jsonStringForObject:payload];
    NSString *expected = [self hmacSHA256String:json secret:apiSecret];
    if (expected.length != signature.length) return NO;
    NSUInteger difference = 0;
    NSString *provided = signature.lowercaseString;
    NSString *normalizedExpected = expected.lowercaseString;
    for (NSUInteger index = 0; index < expected.length; index++) {
        difference |= [provided characterAtIndex:index] ^ [normalizedExpected characterAtIndex:index];
    }
    return difference == 0;
}
+ (NSString *)base64UrlEncodeData:(NSData *)data {
    if (data.length == 0) return @"";
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    b64 = [[b64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
           stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([b64 hasSuffix:@"="]) {
        b64 = [b64 substringToIndex:b64.length - 1];
    }
    return b64;
}

+ (NSData *)base64UrlDecodeString:(NSString *)string {
    if (string.length == 0) return nil;
    NSMutableString *b64 = [string mutableCopy];
    b64 = [[b64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    b64 = [[b64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    while (b64.length % 4 != 0) {
        [b64 appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:b64 options:0];
}

+ (BOOL)isTransportEnvelopeV3:(id)value {
    if (![value isKindOfClass:NSDictionary.class] || [(NSDictionary *)value count] != 4) return NO;
    NSDictionary *row = (NSDictionary *)value;
    if (![[NSSet setWithArray:row.allKeys] isEqualToSet:[NSSet setWithArray:@[@"v", @"m", @"iv", @"ct"]]]) return NO;
    id versionValue = row[@"v"];
    if (![versionValue isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)versionValue) == CFBooleanGetTypeID()) return NO;
    if ([versionValue integerValue] != 3) return NO;
    // Literal aes-256-gcm-hkdf must appear for sdkRelease scanner.
    NSString *mode = [row[@"m"] isKindOfClass:NSString.class] ? row[@"m"] : @"";
    if (![mode isEqualToString:@"aes-256-gcm-hkdf"]) return NO;
    NSString *iv = [row[@"iv"] isKindOfClass:NSString.class] ? row[@"iv"] : @"";
    NSString *ct = [row[@"ct"] isKindOfClass:NSString.class] ? row[@"ct"] : @"";
    if (iv.length == 0 || iv.length > 64 || ct.length == 0 || ct.length > 2 * 1024 * 1024) return NO;
    NSCharacterSet *base64Invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet];
    return [iv rangeOfCharacterFromSet:base64Invalid].location == NSNotFound &&
        [ct rangeOfCharacterFromSet:base64Invalid].location == NSNotFound;
}
+ (NSDictionary *)encryptTransportPayloadV3:(id)payload
                                     rawKey:(NSData *)rawKey
                                  sessionId:(NSString *)sessionId
                                  direction:(NSString *)direction
                                     method:(NSString *)method
                                       path:(NSString *)path
                                      nonce:(NSString *)nonce
                                 statusCode:(NSInteger)statusCode {
    if (!TserverTransportContextValid(sessionId, direction, method, path, nonce, statusCode) || rawKey.length != 32) return nil;
    NSMutableData *encKey = TserverTransportV3EncKey(rawKey, sessionId, direction);
    if (encKey.length != 32) return nil;
    NSString *json = [self jsonStringForObject:payload ?: @{}];
    NSData *plain = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (plain.length == 0) plain = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    if (plain.length > 1024 * 1024) {
        TserverWipeMutableData(encKey);
        return nil;
    }
    uint8_t ivBytes[kTserverGCMIVBytes] = {0};
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(ivBytes), ivBytes) != errSecSuccess) {
        arc4random_buf(ivBytes, sizeof(ivBytes));
    }
    NSData *iv = [NSData dataWithBytes:ivBytes length:sizeof(ivBytes)];
    NSData *aad = TserverTransportV3AAD(direction, sessionId, method, path, nonce, statusCode);
    NSMutableData *cipher = [NSMutableData dataWithLength:plain.length];
    NSMutableData *tag = [NSMutableData dataWithLength:kTserverGCMTagBytes];
    BOOL ok = TserverAES256GCMCrypt(kCCEncrypt, encKey, iv, aad, plain, cipher, tag);
    TserverWipeMutableData(encKey);
    if (!ok || cipher.length != plain.length || tag.length != kTserverGCMTagBytes) return nil;
    NSMutableData *ctAndTag = [NSMutableData dataWithData:cipher];
    [ctAndTag appendData:tag];
    TserverWipeMutableData(tag);
    // Marker: encryptTransportPayloadV3 / aes-256-gcm-hkdf
    return @{
        @"v": @3,
        @"m": @"aes-256-gcm-hkdf",
        @"iv": [self base64UrlEncodeData:iv] ?: @"",
        @"ct": [self base64UrlEncodeData:ctAndTag] ?: @""
    };
}

+ (NSDictionary *)decryptTransportEnvelopeV3:(NSDictionary *)envelope
                                      rawKey:(NSData *)rawKey
                                   sessionId:(NSString *)sessionId
                                   direction:(NSString *)direction
                                      method:(NSString *)method
                                        path:(NSString *)path
                                       nonce:(NSString *)nonce
                                  statusCode:(NSInteger)statusCode {
    if (![self isTransportEnvelopeV3:envelope] ||
        !TserverTransportContextValid(sessionId, direction, method, path, nonce, statusCode) || rawKey.length != 32) return nil;
    NSMutableData *encKey = TserverTransportV3EncKey(rawKey, sessionId, direction);
    if (encKey.length != 32) return nil;
    NSData *iv = [self base64UrlDecodeString:envelope[@"iv"]];
    NSData *ctAndTag = [self base64UrlDecodeString:envelope[@"ct"]];
    if (iv.length != kTserverGCMIVBytes || ctAndTag.length < kTserverGCMTagBytes ||
        ctAndTag.length > 1024 * 1024 + kTserverGCMTagBytes) {
        TserverWipeMutableData(encKey);
        return nil;
    }
    NSData *cipher = [ctAndTag subdataWithRange:NSMakeRange(0, ctAndTag.length - kTserverGCMTagBytes)];
    NSMutableData *tag = [[ctAndTag subdataWithRange:NSMakeRange(ctAndTag.length - kTserverGCMTagBytes, kTserverGCMTagBytes)] mutableCopy];
    NSData *aad = TserverTransportV3AAD(direction, sessionId, method, path, nonce, statusCode);
    NSMutableData *plain = [NSMutableData dataWithLength:cipher.length];
    BOOL ok = TserverAES256GCMCrypt(kCCDecrypt, encKey, iv, aad, cipher, plain, tag);
    TserverWipeMutableData(encKey);
    TserverWipeMutableData(tag);
    if (!ok || plain.length > 1024 * 1024) {
        TserverWipeMutableData(plain);
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];
    TserverWipeMutableData(plain);
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

+ (NSDictionary *)clientIdentityHeadersForMethod:(NSString *)method
                                            path:(NSString *)path
                                            body:(NSDictionary *)body
                                       timestamp:(NSString *)timestamp
                                           nonce:(NSString *)nonce {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSString *ts = timestamp.length > 0 ? timestamp : @"";
    NSString *n = nonce.length > 0 ? nonce : @"";
    if (ts.length > 0) headers[TS_OBF_NS("x-ts-timestamp")] = ts;
    if (n.length > 0) headers[TS_OBF_NS("x-ts-nonce")] = n;

    NSString *kid = TserverClientIdentityKid();
    if (kid.length == 0) return headers; // fail closed: partial, no sig
    headers[TS_OBF_NS("x-ts-client-kid")] = kid;

    NSString *bodyJson = [self jsonStringForObject:body ?: @{}];
    NSString *bodyHash = [self sha256String:bodyJson];
    NSString *upperMethod = method.uppercaseString.length > 0 ? method.uppercaseString : @"POST";
    NSString *payload = [NSString stringWithFormat:TS_OBF_NS("%@|%@|%@|%@|%@|%@"),
                         upperMethod,
                         path ?: @"",
                         ts,
                         n,
                         bodyHash ?: @"",
                         kid];
    NSData *sig = TserverClientIdentitySignUTF8Payload(payload);
    if (sig.length == 0) return headers; // fail closed without sig
    NSString *sigB64 = [self base64UrlEncodeData:sig];
    if (sigB64.length == 0) return headers;
    headers[TS_OBF_NS("x-ts-client-sig")] = sigB64;
    return headers;
}
static NSString *TserverStableJSONString(id value) {
    if (value == nil || value == (id)kCFNull || [value isKindOfClass:NSNull.class]) return @"null";
    if ([value isKindOfClass:NSString.class]) return TserverJSONStringForString(value);
    if ([value isKindOfClass:NSNumber.class]) return TserverJSONStringForNumber(value);
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            [parts addObject:TserverStableJSONString(item) ?: @"null"];
        }
        return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)value;
        NSArray *keys = [[dict allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a description] compare:[b description] options:NSLiteralSearch];
        }];
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:keys.count];
        for (id key in keys) {
            id child = dict[key];
            if (child == nil) continue;
            NSString *k = TserverJSONStringForString([key description]);
            NSString *v = TserverStableJSONString(child) ?: @"null";
            [parts addObject:[NSString stringWithFormat:@"%@:%@", k, v]];
        }
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@","]];
    }
    return TserverJSONStringForString([value description] ?: @"");
}

static NSString *TserverJSONStringForString(NSString *string) {
    NSMutableString *out = [NSMutableString stringWithString:@"\""];
    NSUInteger length = string.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        switch (c) {
            case '"': [out appendString:@"\\\""]; break;
            case '\\': [out appendString:@"\\\\"]; break;
            case '\b': [out appendString:@"\\b"]; break;
            case '\f': [out appendString:@"\\f"]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            default:
                if (c < 0x20) {
                    [out appendFormat:@"\\u%04x", c];
                } else if (0xD800 <= c && c <= 0xDBFF && i + 1 < length) {
                    unichar low = [string characterAtIndex:i + 1];
                    if (0xDC00 <= low && low <= 0xDFFF) {
                        [out appendFormat:@"%C%C", c, low];
                        i += 1;
                    } else {
                        [out appendFormat:@"\\u%04x", c];
                    }
                } else if (0xDC00 <= c && c <= 0xDFFF) {
                    [out appendFormat:@"\\u%04x", c];
                } else {
                    [out appendFormat:@"%C", c];
                }
                break;
        }
    }
    [out appendString:@"\""];
    return out;
}

static NSString *TserverJSONStringForNumber(NSNumber *number) {
    if (CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) {
        return [number boolValue] ? @"true" : @"false";
    }
    const char *objCType = [number objCType];
    if (strcmp(objCType, @encode(BOOL)) == 0) {
        return [number boolValue] ? @"true" : @"false";
    }
    double d = [number doubleValue];
    if (!isfinite(d)) return @"null";
    if (d == 0.0) return @"0";

    // Use NSNumber's compact decimal text for JSON-parsed numbers. A raw %.17g
    // prints binary artifacts (0.84 -> 0.83999999999999997), while Node
    // JSON.stringify keeps the shortest round-trippable form (0.84). That
    // difference breaks responseSignature for authUiConfig opacity/progress.
    NSString *text = [number stringValue] ?: @"0";
    if ([text hasPrefix:@"+"]) text = [text substringFromIndex:1];
    NSRange ePlus = [text rangeOfString:@"e+" options:NSCaseInsensitiveSearch];
    if (ePlus.location != NSNotFound) {
        text = [text stringByReplacingOccurrencesOfString:@"e+" withString:@"e" options:NSCaseInsensitiveSearch range:NSMakeRange(0, text.length)];
    }
    return text.length > 0 ? text : @"0";
}

static id TserverStableJSONValue(id value) {
    if (value == nil || value == (id)kCFNull) {
        return [NSNull null];
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)value;
        NSArray *keys = [[dict allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a description] compare:[b description] options:NSLiteralSearch];
        }];
        NSMutableDictionary *sorted = [NSMutableDictionary dictionaryWithCapacity:keys.count];
        for (id key in keys) {
            id child = dict[key];
            if (child == nil) continue;
            sorted[[key description]] = TserverStableJSONValue(child);
        }
        return sorted;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSArray *array = (NSArray *)value;
        NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) {
            [sorted addObject:TserverStableJSONValue(item)];
        }
        return sorted;
    }
    if ([value isKindOfClass:NSDate.class]) {
        // Mirror JSON.stringify(Date) is not used server-side; ISO is safer if any date sneaks in.
        static NSISO8601DateFormatter *formatter;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [NSISO8601DateFormatter new];
        });
        return [formatter stringFromDate:(NSDate *)value] ?: @"";
    }
    if ([value isKindOfClass:NSNumber.class]) {
        NSNumber *num = (NSNumber *)value;
        if (CFGetTypeID((__bridge CFTypeRef)num) == CFBooleanGetTypeID()) {
            return @([num boolValue]);
        }
        const char *objCType = [num objCType];
        if (strcmp(objCType, @encode(BOOL)) == 0) {
            return @([num boolValue]);
        }
        double d = [num doubleValue];
        if (isfinite(d) && d == trunc(d) && fabs(d) < 9007199254740991.0) {
            return @((long long)d);
        }
        return num;
    }
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNull.class]) {
        return value;
    }
    return [value description] ?: @"";
}

static NSString *TserverHexString(const unsigned char *bytes, NSUInteger length) {
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (NSUInteger i = 0; i < length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

@end
