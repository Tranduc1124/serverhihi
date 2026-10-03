#import "TserverTransportSession.h"
#import "TserverAntiHook.h"
#import "TserverSecureBlob.h"
#import "TserverSealedConstants.h"
#import "TserverStringCrypto.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <string.h>

@interface TserverHttp : NSObject
+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void (^)(NSDictionary *result, NSError *error))completion;
@end

static NSString *gSessionId = nil;
static NSMutableData *gSessionKey = nil;
static NSTimeInterval gSessionExpiresAt = 0;
static NSInteger gTransportVersion = 0;
static BOOL gHandshakeInFlight = NO;
static NSMutableArray *gWaiters = nil;
static dispatch_queue_t gSessionQueue;
static const NSTimeInterval kRefreshSkewSeconds = 90;
static const NSTimeInterval kMaximumSessionLifetimeSeconds = 31 * 60;

static NSString *TserverB64UrlEncode(NSData *data) {
    if (data.length == 0) return @"";
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
        stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([base64 hasSuffix:@"="]) base64 = [base64 substringToIndex:base64.length - 1];
    return base64;
}

static NSData *TserverB64UrlDecode(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > 256) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet];
    if ([value rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    NSMutableString *base64 = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4) [base64 appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static NSString *TserverHex(const uint8_t *bytes, size_t length) {
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (size_t index = 0; index < length; index++) [hex appendFormat:@"%02x", bytes[index]];
    return hex;
}

static BOOL TserverConstantTimeHexEqual(NSString *left, NSString *right) {
    if (left.length != 64 || right.length != 64) return NO;
    NSString *a = left.lowercaseString;
    NSString *b = right.lowercaseString;
    NSUInteger difference = 0;
    for (NSUInteger index = 0; index < 64; index++) {
        difference |= [a characterAtIndex:index] ^ [b characterAtIndex:index];
    }
    return difference == 0;
}

static NSData *TserverHMACSHA256(NSData *key, NSData *message) {
    if (key.length == 0) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, message.bytes, message.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static NSData *TserverHKDFSHA256(NSData *inputKey, NSData *salt, NSData *info, NSUInteger outputLength) {
    if (inputKey.length == 0 || outputLength == 0 || outputLength > 255 * CC_SHA256_DIGEST_LENGTH) return nil;
    NSData *effectiveSalt = salt.length > 0 ? salt : [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    NSData *prk = TserverHMACSHA256(effectiveSalt, inputKey);
    if (prk.length != CC_SHA256_DIGEST_LENGTH) return nil;
    NSMutableData *output = [NSMutableData dataWithCapacity:outputLength];
    NSData *previous = [NSData data];
    uint8_t counter = 1;
    while (output.length < outputLength) {
        NSMutableData *material = [NSMutableData dataWithData:previous];
        if (info.length > 0) [material appendData:info];
        [material appendBytes:&counter length:1];
        previous = TserverHMACSHA256(prk, material);
        if (previous.length == 0) return nil;
        NSUInteger remaining = outputLength - output.length;
        [output appendBytes:previous.bytes length:MIN(remaining, previous.length)];
        counter++;
    }
    return output;
}

static NSData *TserverDeriveV3Master(NSData *shared, NSData *clientPublic, NSData *serverPublic) {
    if (shared.length == 0 || clientPublic.length != 65 || serverPublic.length != 65) return nil;
    NSMutableData *saltMaterial = [NSMutableData dataWithData:[TS_OBF_NS("tserver-ecdh-v3|") dataUsingEncoding:NSUTF8StringEncoding]];
    [saltMaterial appendData:clientPublic];
    [saltMaterial appendData:serverPublic];
    uint8_t saltBytes[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(saltMaterial.bytes, (CC_LONG)saltMaterial.length, saltBytes);
    NSData *salt = [NSData dataWithBytes:saltBytes length:sizeof(saltBytes)];
    NSData *info = [TS_OBF_NS("tserver-transport-v3|master") dataUsingEncoding:NSUTF8StringEncoding];
    return TserverHKDFSHA256(shared, salt, info, CC_SHA256_DIGEST_LENGTH);
}

@implementation TserverTransportSession

+ (void)initialize {
    if (self != TserverTransportSession.class) return;
    gSessionQueue = dispatch_queue_create(TS_OBF_STR("com.tserver.transport-session"), DISPATCH_QUEUE_SERIAL);
    gWaiters = [NSMutableArray array];
}

+ (nullable NSString *)sessionId {
    __block NSString *value = nil;
    dispatch_sync(gSessionQueue, ^{ value = [gSessionId copy]; });
    return [self hasUsableSession] ? value : nil;
}

+ (nullable NSData *)sessionKey {
    if (![self hasUsableSession]) return nil;
    __block NSData *value = nil;
    dispatch_sync(gSessionQueue, ^{ value = [gSessionKey copy]; });
    return value.length == 32 ? value : nil;
}

+ (NSInteger)transportVersion {
    __block NSInteger value = 0;
    dispatch_sync(gSessionQueue, ^{ value = gTransportVersion; });
    return value;
}

+ (BOOL)hasUsableSession {
    __block BOOL usable = NO;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    dispatch_sync(gSessionQueue, ^{
        usable = gTransportVersion == 3 && gSessionId.length >= 20 && gSessionKey.length == 32 &&
            gSessionExpiresAt > now + kRefreshSkewSeconds &&
            gSessionExpiresAt <= now + kMaximumSessionLifetimeSeconds;
    });
    return usable;
}

+ (NSTimeInterval)secondsRemaining {
    __block NSTimeInterval expiresAt = 0;
    dispatch_sync(gSessionQueue, ^{ expiresAt = gSessionExpiresAt; });
    return MAX(0, expiresAt - NSDate.date.timeIntervalSince1970);
}

+ (void)clearLocked {
    if (gSessionKey.length > 0) {
        TserverAntiDumpUnlockAndWipe(gSessionKey.mutableBytes, gSessionKey.length);
    }
    gSessionId = nil;
    gSessionKey = nil;
    gSessionExpiresAt = 0;
    gTransportVersion = 0;
}

+ (void)clear {
    dispatch_sync(gSessionQueue, ^{ [self clearLocked]; });
}

+ (BOOL)isHandshakeURL:(NSString *)url {
    NSString *path = [NSURL URLWithString:url ?: @""].path.lowercaseString ?: @"";
    const char *hs = TserverSealedStringAt(kTserverSealedStr_TransportHandshakePath);
    NSString *hsPath = (hs && hs[0]) ? [NSString stringWithUTF8String:hs] : TS_OBF_NS("/transport/handshake");
    return [path containsString:hsPath];
}

+ (void)finishWaitersLocked:(BOOL)ok {
    NSArray *waiters = [gWaiters copy];
    [gWaiters removeAllObjects];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (void (^block)(BOOL) in waiters) if (block) block(ok);
    });
}

+ (void)ensureSessionWithBaseURL:(NSString *)baseURL completion:(void (^)(BOOL))completion {
    if ([self hasUsableSession]) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
        return;
    }

    __block BOOL shouldStart = NO;
    dispatch_sync(gSessionQueue, ^{
        if (completion) [gWaiters addObject:[completion copy]];
        if (!gHandshakeInFlight) {
            gHandshakeInFlight = YES;
            [self clearLocked];
            shouldStart = YES;
        }
    });
    if (!shouldStart) return;

    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecPrivateKeyAttrs: @{ (__bridge id)kSecAttrIsPermanent: @NO }
    };
    CFErrorRef error = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
    if (error) CFRelease(error);
    if (!privateKey) {
        dispatch_sync(gSessionQueue, ^{ gHandshakeInFlight = NO; [self finishWaitersLocked:NO]; });
        return;
    }
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    CFDataRef publicDataRef = publicKey ? SecKeyCopyExternalRepresentation(publicKey, &error) : NULL;
    if (publicKey) CFRelease(publicKey);
    if (error) CFRelease(error);
    NSData *clientPublic = publicDataRef ? CFBridgingRelease(publicDataRef) : nil;
    if (clientPublic.length != 65 || ((const uint8_t *)clientPublic.bytes)[0] != 0x04) {
        CFRelease(privateKey);
        dispatch_sync(gSessionQueue, ^{ gHandshakeInFlight = NO; [self finishWaitersLocked:NO]; });
        return;
    }

    NSString *base = baseURL ?: @"";
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    const char *handshakePath = TserverSealedStringAt(kTserverSealedStr_TransportHandshake);
    if (!(handshakePath && handshakePath[0])) {
        CFRelease(privateKey);
        dispatch_sync(gSessionQueue, ^{ gHandshakeInFlight = NO; [self finishWaitersLocked:NO]; });
        return;
    }
    NSString *url = [NSString stringWithFormat:@"%@%@", base, @(handshakePath)];
    NSString *clientPublicText = TserverB64UrlEncode(clientPublic);
    // Transport v3 hard-cut: plaintext attested handshake (no x-ts-enc body crypto).
    NSDictionary *body = @{ @"clientPublicKey": clientPublicText ?: @"", @"transportVersion": @3 };

    [TserverHttp post:url body:body headers:@{} completion:^(NSDictionary *result, NSError *requestError) {
        BOOL ok = NO;
        NSMutableData *masterKey = nil;
        NSString *sessionId = nil;
        NSTimeInterval expiresAt = 0;
        if (!requestError && [result isKindOfClass:NSDictionary.class] && [result[@"transportVersion"] integerValue] == 3) {
            sessionId = [result[@"sessionId"] isKindOfClass:NSString.class] ? result[@"sessionId"] : nil;
            NSString *serverPublicText = [result[@"serverPublicKey"] isKindOfClass:NSString.class] ? result[@"serverPublicKey"] : nil;
            NSString *mac = [result[@"mac"] isKindOfClass:NSString.class] ? result[@"mac"] : nil;
            expiresAt = [result[@"expiresAt"] respondsToSelector:@selector(doubleValue)] ? [result[@"expiresAt"] doubleValue] : 0;
            NSData *serverPublic = TserverB64UrlDecode(serverPublicText);
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            BOOL shapeValid = [sessionId hasPrefix:@"ts_"] && sessionId.length >= 20 && sessionId.length <= 128 &&
                serverPublic.length == 65 && ((const uint8_t *)serverPublic.bytes)[0] == 0x04 && mac.length == 64 &&
                expiresAt > now + 60 && expiresAt <= now + kMaximumSessionLifetimeSeconds;
            if (shapeValid) {
                NSDictionary *publicAttributes = @{
                    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
                    (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
                    (__bridge id)kSecAttrKeySizeInBits: @256
                };
                CFErrorRef exchangeError = NULL;
                SecKeyRef serverKey = SecKeyCreateWithData((__bridge CFDataRef)serverPublic,
                    (__bridge CFDictionaryRef)publicAttributes, &exchangeError);
                CFDataRef sharedRef = serverKey ? SecKeyCopyKeyExchangeResult(privateKey,
                    kSecKeyAlgorithmECDHKeyExchangeStandard, serverKey, (__bridge CFDictionaryRef)@{}, &exchangeError) : NULL;
                if (serverKey) CFRelease(serverKey);
                if (exchangeError) CFRelease(exchangeError);
                NSData *shared = sharedRef ? CFBridgingRelease(sharedRef) : nil;
                NSData *derived = TserverDeriveV3Master(shared, clientPublic, serverPublic);
                if (derived.length == 32) {
                    // Marker hs3| required by sdkRelease scanner.
                    NSString *proof = [NSString stringWithFormat:@"hs3|%@|%.0f|%@|%@|3",
                        sessionId, expiresAt, clientPublicText, serverPublicText];
                    NSData *digest = TserverHMACSHA256(derived, [proof dataUsingEncoding:NSUTF8StringEncoding]);
                    NSString *expectedMac = TserverHex((const uint8_t *)digest.bytes, digest.length);
                    if (TserverConstantTimeHexEqual(expectedMac, mac)) {
                        masterKey = [derived mutableCopy];
                        TserverAntiDumpLock(masterKey.mutableBytes, masterKey.length);
                        ok = YES;
                    }
                }
            }
        }
        CFRelease(privateKey);
        dispatch_sync(gSessionQueue, ^{
            gHandshakeInFlight = NO;
            [self clearLocked];
            if (ok) {
                gSessionId = [sessionId copy];
                gSessionKey = masterKey;
                gSessionExpiresAt = expiresAt;
                gTransportVersion = 3;
            }
            [self finishWaitersLocked:ok];
        });
    }];
}

@end
