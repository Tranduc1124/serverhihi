#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import "TserverPinning.h"
#import "TserverSealedConstants.h"

static BOOL TserverPinningHexDigestLooksValid(NSString *value) {
    if (value.length != CC_SHA256_DIGEST_LENGTH * 2) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static NSData *TserverPinningDecodeHexPin(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return nil;
    NSString *hex = [[[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        lowercaseString] stringByReplacingOccurrencesOfString:@":" withString:@""];
    hex = [hex stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (!TserverPinningHexDigestLooksValid(hex)) return nil;
    uint8_t bytes[CC_SHA256_DIGEST_LENGTH] = {0};
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        NSString *pair = [hex substringWithRange:NSMakeRange(index * 2, 2)];
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&byte] || !scanner.isAtEnd) {
            memset(bytes, 0, sizeof(bytes));
            return nil;
        }
        bytes[index] = (uint8_t)byte;
    }
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    memset(bytes, 0, sizeof(bytes));
    return data;
}

static NSArray<NSData *> *TserverBakedSpkiDigests(void) {
    static NSArray<NSData *> *baked;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSData *> *decoded = [NSMutableArray array];
        NSArray<NSString *> *configured = @[
#if defined(TSERVER_TLS_SPKI_PIN)
            @TSERVER_TLS_SPKI_PIN,
#endif
#if defined(TSERVER_TLS_SPKI_PIN_BACKUP)
            @TSERVER_TLS_SPKI_PIN_BACKUP,
#endif
        ];
        for (NSString *raw in configured) {
            NSData *pin = TserverPinningDecodeHexPin(raw);
            if (pin.length == CC_SHA256_DIGEST_LENGTH) [decoded addObject:pin];
        }
        baked = [decoded copy];
    });
    return baked ?: @[];
}

static NSMutableArray<NSData *> *gAdvertisedSpkiPins = nil;
static dispatch_queue_t gAdvertisedPinQueue;

static void TserverAdvertisedPinInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gAdvertisedPinQueue = dispatch_queue_create("com.tserver.tls-advertised-pins", DISPATCH_QUEUE_SERIAL);
        gAdvertisedSpkiPins = [NSMutableArray array];
    });
}

static BOOL TserverPinDataEqual(NSData *left, NSData *right) {
    if (left.length != right.length || left.length == 0) return NO;
    const uint8_t *a = (const uint8_t *)left.bytes;
    const uint8_t *b = (const uint8_t *)right.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < left.length; i++) diff |= a[i] ^ b[i];
    return diff == 0;
}

static NSArray<NSData *> *TserverPinnedSpkiDigests(void) {
    NSArray<NSData *> *baked = TserverBakedSpkiDigests();
    TserverAdvertisedPinInit();
    __block NSArray<NSData *> *extra = nil;
    dispatch_sync(gAdvertisedPinQueue, ^{
        extra = [gAdvertisedSpkiPins copy];
    });
    if (extra.count == 0) return baked;
    NSMutableArray<NSData *> *combined = [NSMutableArray arrayWithArray:baked];
    for (NSData *pin in extra) {
        BOOL duplicate = NO;
        for (NSData *existing in combined) {
            if (TserverPinDataEqual(existing, pin)) {
                duplicate = YES;
                break;
            }
        }
        if (duplicate) continue;
        [combined addObject:pin];
        if (combined.count >= 4) break;
    }
    return [combined copy];
}

void TserverPinningUnionAdvertisedSpkiPins(NSArray<NSString *> *hexPins) {
    // Never replace baked pins with empty advertised list — ignore empty/nil.
    if (![hexPins isKindOfClass:NSArray.class] || hexPins.count == 0) return;
    TserverAdvertisedPinInit();
    NSArray<NSData *> *baked = TserverBakedSpkiDigests();
    NSUInteger bakedCount = baked.count;
    if (bakedCount == 0) return; // fail closed: no baked pin → refuse advertised-only
    NSUInteger room = bakedCount >= 4 ? 0 : (4 - bakedCount);
    if (room == 0) return;
    NSMutableArray<NSData *> *decoded = [NSMutableArray array];
    for (NSString *raw in hexPins) {
        NSData *pin = TserverPinningDecodeHexPin(raw);
        if (pin.length != CC_SHA256_DIGEST_LENGTH) continue;
        BOOL duplicate = NO;
        for (NSData *existing in baked) {
            if (TserverPinDataEqual(existing, pin)) {
                duplicate = YES;
                break;
            }
        }
        if (duplicate) continue;
        for (NSData *existing in decoded) {
            if (TserverPinDataEqual(existing, pin)) {
                duplicate = YES;
                break;
            }
        }
        if (duplicate) continue;
        [decoded addObject:pin];
        if (decoded.count >= room) break;
    }
    if (decoded.count == 0) return;
    dispatch_sync(gAdvertisedPinQueue, ^{
        [gAdvertisedSpkiPins removeAllObjects];
        [gAdvertisedSpkiPins addObjectsFromArray:decoded];
    });
}

static NSString *TserverPinnedProductionHost(void) {
    const char *sealedHost = TserverSealedStringAt(kTserverSealedStr_ApiHost);
    if (!(sealedHost && sealedHost[0])) return @"";
    return [[NSString stringWithUTF8String:sealedHost] lowercaseString];
}

static BOOL TserverHostRequiresPin(NSString *host) {
    NSString *normalized = [[host ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        lowercaseString];
    NSString *productionHost = TserverPinnedProductionHost();
    return productionHost.length > 0 && [normalized isEqualToString:productionHost];
}

static BOOL TserverConstantTimeDataEqual(NSData *left, NSData *right) {
    if (left.length != right.length || left.length == 0) return NO;
    const uint8_t *leftBytes = (const uint8_t *)left.bytes;
    const uint8_t *rightBytes = (const uint8_t *)right.bytes;
    uint8_t difference = 0;
    for (NSUInteger index = 0; index < left.length; index++) {
        difference |= leftBytes[index] ^ rightBytes[index];
    }
    return difference == 0;
}

static NSData *TserverP256SubjectPublicKeyInfo(SecKeyRef key) {
    if (!key) return nil;
    NSDictionary *attributes = CFBridgingRelease(SecKeyCopyAttributes(key));
    if (![attributes[(__bridge id)kSecAttrKeyType] isEqual:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom] ||
        [attributes[(__bridge id)kSecAttrKeySizeInBits] integerValue] != 256) {
        return nil;
    }

    CFErrorRef error = NULL;
    CFDataRef raw = SecKeyCopyExternalRepresentation(key, &error);
    if (!raw) {
        if (error) CFRelease(error);
        return nil;
    }
    NSData *point = CFBridgingRelease(raw);
    if (error) CFRelease(error);
    if (point.length != 65 || ((const uint8_t *)point.bytes)[0] != 0x04) return nil;

    static const uint8_t prefix[] = {
        0x30, 0x59, 0x30, 0x13,
        0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
        0x03, 0x42, 0x00
    };
    NSMutableData *spki = [NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
    [spki appendData:point];
    return spki;
}

static NSData *TserverLeafSpkiDigest(SecTrustRef trust) {
    if (!trust) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecCertificateRef certificate = SecTrustGetCertificateAtIndex(trust, 0);
#pragma clang diagnostic pop
    if (!certificate) return nil;
    SecKeyRef key = SecCertificateCopyKey(certificate);
    if (!key) return nil;
    NSData *spki = TserverP256SubjectPublicKeyInfo(key);
    CFRelease(key);
    if (spki.length == 0) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(spki.bytes, (CC_LONG)spki.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static BOOL TserverLeafSpkiMatchesPins(SecTrustRef trust) {
    NSArray<NSData *> *pins = TserverPinnedSpkiDigests();
    if (pins.count == 0) return NO;
    NSData *leafDigest = TserverLeafSpkiDigest(trust);
    if (leafDigest.length != CC_SHA256_DIGEST_LENGTH) return NO;
    for (NSData *pin in pins) {
        if (TserverConstantTimeDataEqual(leafDigest, pin)) return YES;
    }
    return NO;
}

static dispatch_queue_t gTserverPinEvidenceQueue;
static NSMapTable<NSURLSession *, NSString *> *gTserverValidatedSessions;

static void TserverPinEvidenceInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gTserverPinEvidenceQueue = dispatch_queue_create("com.tserver.tls-pin-evidence", DISPATCH_QUEUE_SERIAL);
        gTserverValidatedSessions = [NSMapTable weakToStrongObjectsMapTable];
    });
}

static void TserverPinningRecordValidatedSession(NSURLSession *session, NSString *host) {
    if (!session || !TserverHostRequiresPin(host)) return;
    TserverPinEvidenceInit();
    dispatch_sync(gTserverPinEvidenceQueue, ^{
        [gTserverValidatedSessions setObject:host.lowercaseString forKey:session];
    });
}

BOOL TserverPinningConsumeValidatedSession(NSURLSession *session, NSString *host) {
    if (!session || !TserverHostRequiresPin(host)) return NO;
    TserverPinEvidenceInit();
    __block NSString *validatedHost = nil;
    dispatch_sync(gTserverPinEvidenceQueue, ^{
        validatedHost = [gTserverValidatedSessions objectForKey:session];
        [gTserverValidatedSessions removeObjectForKey:session];
    });
    return validatedHost.length > 0 && [validatedHost caseInsensitiveCompare:host] == NSOrderedSame;
}

static BOOL TserverSystemTrustIsValidForHost(SecTrustRef trust, NSString *host) {
    if (!trust || host.length == 0) return NO;
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)host);
    if (!policy) return NO;
    OSStatus policyStatus = SecTrustSetPolicies(trust, policy);
    CFRelease(policy);
    if (policyStatus != errSecSuccess) return NO;

    if (@available(iOS 12.0, *)) {
        CFErrorRef error = NULL;
        BOOL trusted = SecTrustEvaluateWithError(trust, &error);
        if (error) CFRelease(error);
        return trusted;
    }

    SecTrustResultType result = kSecTrustResultInvalid;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = SecTrustEvaluate(trust, &result);
#pragma clang diagnostic pop
    return status == errSecSuccess &&
        (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

@implementation TserverPinning

+ (instancetype)shared {
    static TserverPinning *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [TserverPinning new]; });
    return instance;
}

- (void)URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    (void)session;
    if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    NSString *host = challenge.protectionSpace.host ?: @"";
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    if (!trust || !TserverHostRequiresPin(host) || [TserverPinnedSpkiDigests() count] == 0) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    BOOL systemTrustValid = TserverSystemTrustIsValidForHost(trust, host);
    BOOL pinMatches = TserverLeafSpkiMatchesPins(trust);
    if (!systemTrustValid || !pinMatches) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    TserverPinningRecordValidatedSession(session, host);
    completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session;
    (void)task;
    (void)response;
    (void)request;
    // Package endpoints are fixed and request signatures bind the original path.
    // Following a redirect could forward bearer headers or ciphertext to another
    // host and would invalidate the signed request context. Always fail closed.
    completionHandler(nil);
}

@end
