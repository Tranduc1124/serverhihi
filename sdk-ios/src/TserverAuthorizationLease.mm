#import "TserverAuthorizationLease.h"
#import "TserverAuthorizationKeys.h"
#import "TserverClientIdentity.h"
#import "TserverSecurity.h"
#import "TserverSealedConstants.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <mach/mach_time.h>
#import <math.h>

@interface TserverStorage : NSObject
+ (NSDictionary *)authorizationLeaseWatermark;
+ (BOOL)saveAuthorizationLeaseWatermark:(NSDictionary *)watermark;
@end

static dispatch_queue_t gLeaseQueue;
static NSData *gLeaseEnvelopeData;
static NSData *gLeasePayloadDigest;
static NSData *gLeaseBindingDigest;
static TserverAuthorizationState gLeaseState = TserverAuthorizationStateUninitialized;
static uint64_t gLeaseMonotonicAnchor = 0;
static int64_t gLeaseServerAnchor = 0;
static int64_t gLeaseHighestIssuedAt = 0;
static uint64_t gLeaseGeneration = 0;
static dispatch_source_t gLeaseExpiryTimer;
static TserverAuthorizationRevocationBlock gLeaseRevocationHandler;

static const NSUInteger kTserverLeaseMaximumPayloadBytes = 32768;
static const int64_t kTserverLeaseMaximumLifetimeSeconds = 900;
static const int64_t kTserverLeaseMaximumInstallAgeSeconds = 300;

static void TserverLeaseInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLeaseQueue = dispatch_queue_create("com.tserver.authorization-lease", DISPATCH_QUEUE_SERIAL);
    });
}

static NSData *TserverLeaseSHA256(NSData *data) {
    if (data.length == 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static BOOL TserverLeaseConstantTimeEqual(NSData *left, NSData *right) {
    if (left.length != right.length || left.length == 0) return NO;
    const uint8_t *leftBytes = (const uint8_t *)left.bytes;
    const uint8_t *rightBytes = (const uint8_t *)right.bytes;
    uint8_t difference = 0;
    for (NSUInteger index = 0; index < left.length; index++) {
        difference |= leftBytes[index] ^ rightBytes[index];
    }
    return difference == 0;
}

static NSString *TserverLeaseHex(NSData *data) {
    if (data.length == 0) return @"";
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger index = 0; index < data.length; index++) {
        [hex appendFormat:@"%02x", bytes[index]];
    }
    return hex;
}

static NSString *TserverLeaseHash(NSString *label, NSString *value) {
    NSString *material = [NSString stringWithFormat:@"%@:v1:%@", label ?: @"", value ?: @""];
    NSData *digest = TserverLeaseSHA256([material dataUsingEncoding:NSUTF8StringEncoding]);
    return TserverLeaseHex(digest);
}

static BOOL TserverLeaseStringMatches(NSString *value, NSString *pattern, NSUInteger maximumLength) {
    if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > maximumLength) return NO;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return expression && [expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

static BOOL TserverLeaseIsHexDigest(NSString *value) {
    return TserverLeaseStringMatches(value, @"^[0-9a-f]{64}$", 64);
}

static BOOL TserverLeaseReadInteger(id value, int64_t *output) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    int64_t integer = [value longLongValue];
    if (!isfinite(number) || number != (double)integer) return NO;
    if (output) *output = integer;
    return YES;
}

static NSData *TserverLeaseBase64URLDecode(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > 65536) return nil;
    if (!TserverLeaseStringMatches(value, @"^[A-Za-z0-9_-]+$", 65536)) return nil;
    NSMutableString *base64 = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4) [base64 appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static NSDictionary *TserverLeaseCanonicalEnvelope(NSDictionary *source) {
    if (![source isKindOfClass:NSDictionary.class] || source.count > 4) return nil;
    if (![source[@"v"] isKindOfClass:NSNumber.class] || [source[@"v"] integerValue] != 1) return nil;
    NSString *algorithm = [source[@"alg"] isKindOfClass:NSString.class] ? source[@"alg"] : @"";
    NSString *payload = [source[@"payload"] isKindOfClass:NSString.class] ? source[@"payload"] : @"";
    NSArray *sourceSignatures = [source[@"signatures"] isKindOfClass:NSArray.class] ? source[@"signatures"] : nil;
    if (![algorithm isEqualToString:@"ES256"] || payload.length == 0 || sourceSignatures.count == 0 || sourceSignatures.count > 3) return nil;

    NSMutableArray *signatures = [NSMutableArray arrayWithCapacity:sourceSignatures.count];
    NSMutableSet *keyIds = [NSMutableSet setWithCapacity:sourceSignatures.count];
    for (id item in sourceSignatures) {
        if (![item isKindOfClass:NSDictionary.class] || [(NSDictionary *)item count] != 2) return nil;
        NSString *kid = [item[@"kid"] isKindOfClass:NSString.class] ? item[@"kid"] : @"";
        NSString *signature = [item[@"signature"] isKindOfClass:NSString.class] ? item[@"signature"] : @"";
        if (!TserverLeaseStringMatches(kid, @"^[A-Za-z0-9._-]{1,64}$", 64) ||
            !TserverLeaseStringMatches(signature, @"^[A-Za-z0-9_-]+$", 256) ||
            [keyIds containsObject:kid]) {
            return nil;
        }
        [keyIds addObject:kid];
        [signatures addObject:@{ @"kid": kid, @"signature": signature }];
    }
    return @{ @"v": @1, @"alg": @"ES256", @"payload": payload, @"signatures": [signatures copy] };
}

static SecKeyRef TserverLeaseCopyPublicKey(NSString *kid) {
    size_t count = TserverAuthorizationPublicKeyCount();
    for (size_t index = 0; index < count; index++) {
        const char *candidate = TserverAuthorizationPublicKeyId(index);
        NSString *candidateKid = candidate ? [NSString stringWithUTF8String:candidate] : @"";
        if (![candidateKid isEqualToString:kid]) continue;
        uint8_t bytes[512] = {0};
        int length = TserverAuthorizationPublicKeyCopy(index, bytes, sizeof(bytes));
        if (length <= 0) return nil;
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
        memset(bytes, 0, sizeof(bytes));
        NSDictionary *attributes = @{
            (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
            (__bridge id)kSecAttrKeySizeInBits: @256
        };
        CFErrorRef error = NULL;
        SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)attributes, &error);
        if (error) CFRelease(error);
        return key;
    }
    return nil;
}

static BOOL TserverLeaseVerifySignature(NSDictionary *envelope, NSData **payloadOut) {
    if ([envelope[@"v"] integerValue] != 1 || ![envelope[@"alg"] isEqualToString:@"ES256"]) return NO;
    NSData *payload = TserverLeaseBase64URLDecode(envelope[@"payload"]);
    NSArray *signatures = [envelope[@"signatures"] isKindOfClass:NSArray.class] ? envelope[@"signatures"] : nil;
    if (payload.length == 0 || payload.length > kTserverLeaseMaximumPayloadBytes || signatures.count == 0 || signatures.count > 3) return NO;
    for (id item in signatures) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *kid = [item[@"kid"] isKindOfClass:NSString.class] ? item[@"kid"] : @"";
        NSData *signature = TserverLeaseBase64URLDecode(item[@"signature"]);
        SecKeyRef key = TserverLeaseCopyPublicKey(kid);
        if (!key || signature.length < 64 || signature.length > 80) {
            if (key) CFRelease(key);
            continue;
        }
        CFErrorRef error = NULL;
        BOOL valid = SecKeyVerifySignature(
            key,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)payload,
            (__bridge CFDataRef)signature,
            &error
        );
        CFRelease(key);
        if (error) CFRelease(error);
        if (valid) {
            if (payloadOut) *payloadOut = payload;
            return YES;
        }
    }
    return NO;
}

static BOOL TserverLeaseCapabilitiesAreValid(id value) {
    if (![value isKindOfClass:NSArray.class] || [(NSArray *)value count] == 0 || [(NSArray *)value count] > 64) return NO;
    NSMutableSet *seen = [NSMutableSet set];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:NSString.class] ||
            !TserverLeaseStringMatches(item, @"^[a-z0-9._-]{1,64}$", 64) ||
            [seen containsObject:item]) {
            return NO;
        }
        [seen addObject:item];
    }
    return [seen containsObject:@"paid"];
}

static BOOL TserverLeaseClaimsSchemaIsValid(NSDictionary *claims) {
    if (![claims isKindOfClass:NSDictionary.class] || claims.count != 21) return NO;
    static NSSet<NSString *> *allowedKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowedKeys = [NSSet setWithArray:@[
            @"v", @"iss", @"aud", @"jti", @"iat", @"nbf", @"exp",
            @"packageId", @"packageAudience", @"bundleId", @"clientKid", @"install",
            @"profile", @"packageSession", @"device", @"licenseRef",
            @"maskedKey", @"licenseType", @"licenseExpiresAt", @"maxDevices",
            @"capabilities"
        ]];
    });
    for (id key in claims) {
        if (![key isKindOfClass:NSString.class] || ![allowedKeys containsObject:key]) return NO;
    }
    int64_t version = 0;
    int64_t issuedAt = 0;
    int64_t notBefore = 0;
    int64_t expiresAt = 0;
    int64_t maxDevices = 0;
    if (!TserverLeaseReadInteger(claims[@"v"], &version) || version != 1 ||
        !TserverLeaseReadInteger(claims[@"iat"], &issuedAt) ||
        !TserverLeaseReadInteger(claims[@"nbf"], &notBefore) ||
        !TserverLeaseReadInteger(claims[@"exp"], &expiresAt) ||
        !TserverLeaseReadInteger(claims[@"maxDevices"], &maxDevices)) {
        return NO;
    }
    if (issuedAt <= 0 || notBefore > issuedAt || issuedAt - notBefore > 30 ||
        expiresAt <= issuedAt || expiresAt - issuedAt > kTserverLeaseMaximumLifetimeSeconds ||
        maxDevices < 1 || maxDevices > 100000) {
        return NO;
    }
    if (!TserverLeaseStringMatches(claims[@"jti"], @"^al_[A-Za-z0-9_-]{8,96}$", 99) ||
        !TserverLeaseStringMatches(claims[@"packageId"], @"^[A-Za-z0-9._:-]{1,128}$", 128) ||
        !TserverLeaseStringMatches(claims[@"bundleId"], @"^[A-Za-z0-9.-]{1,255}$", 255) ||
        !TserverLeaseStringMatches(claims[@"clientKid"], @"^cid_[a-f0-9]{16}$", 20) ||
        !TserverLeaseIsHexDigest(claims[@"packageAudience"]) ||
        !TserverLeaseIsHexDigest(claims[@"install"]) ||
        !TserverLeaseIsHexDigest(claims[@"profile"]) ||
        !TserverLeaseIsHexDigest(claims[@"packageSession"]) ||
        !TserverLeaseIsHexDigest(claims[@"device"]) ||
        !TserverLeaseStringMatches(claims[@"licenseRef"], @"^[^\\r\\n]{1,256}$", 256) ||
        !TserverLeaseStringMatches(claims[@"maskedKey"], @"^[^\\r\\n]{1,256}$", 256) ||
        !TserverLeaseStringMatches(claims[@"licenseType"], @"^[A-Za-z0-9._ -]{1,64}$", 64) ||
        !TserverLeaseCapabilitiesAreValid(claims[@"capabilities"])) {
        return NO;
    }
    id licenseExpiry = claims[@"licenseExpiresAt"];
    if (licenseExpiry != NSNull.null &&
        (![licenseExpiry isKindOfClass:NSString.class] || [(NSString *)licenseExpiry length] > 64 ||
         [(NSString *)licenseExpiry rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)) {
        return NO;
    }
    return YES;
}

static NSData *TserverLeaseBindingDigestForClaims(NSDictionary *claims) {
    if (!TserverLeaseClaimsSchemaIsValid(claims)) return nil;
    NSArray<NSString *> *keys = @[
        @"iss", @"aud", @"packageId", @"packageAudience", @"bundleId", @"clientKid",
        @"install", @"profile", @"packageSession", @"device"
    ];
    NSMutableData *material = [NSMutableData data];
    for (NSString *key in keys) {
        NSString *value = [claims[key] isKindOfClass:NSString.class] ? claims[key] : @"";
        NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t length = CFSwapInt32HostToBig((uint32_t)bytes.length);
        [material appendBytes:&length length:sizeof(length)];
        [material appendData:bytes];
    }
    return TserverLeaseSHA256(material);
}

static BOOL TserverLeaseClaimsMatch(
    NSDictionary *claims,
    NSString *packageToken,
    NSString *profileSessionToken,
    NSString *packageSessionToken,
    NSString *clientInstallId,
    NSString *bundleId,
    NSString **mismatchReason
) {
    if (!TserverLeaseClaimsSchemaIsValid(claims)) {
        if (mismatchReason) *mismatchReason = @"claims_schema_invalid";
        return NO;
    }
    const char *issuer = TserverSealedStringAt(kTserverSealedStr_Issuer);
    const char *audience = TserverSealedStringAt(kTserverSealedStr_AuthorizationAudience);
    if (!(issuer && issuer[0] && audience && audience[0])) {
        if (mismatchReason) *mismatchReason = @"sealed_strings_unavailable";
        return NO;
    }
    if (![claims[@"iss"] isEqualToString:@(issuer)]) {
        if (mismatchReason) *mismatchReason = [NSString stringWithFormat:@"iss_mismatch(got:%@,expected:%s)", claims[@"iss"], issuer];
        return NO;
    }
    if (![claims[@"aud"] isEqualToString:@(audience)]) {
        if (mismatchReason) *mismatchReason = [NSString stringWithFormat:@"aud_mismatch(got:%@,expected:%s)", claims[@"aud"], audience];
        return NO;
    }

    NSString *cleanBundle = [[bundleId ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    NSString *claimBundle = [[claims[@"bundleId"] isKindOfClass:NSString.class] ? claims[@"bundleId"] : @"" lowercaseString];
    if (![claimBundle isEqualToString:cleanBundle]) {
        if (mismatchReason) *mismatchReason = [NSString stringWithFormat:@"bundle_mismatch(got:%@,claim:%@)", cleanBundle, claimBundle];
        return NO;
    }

    NSString *localKid = [[TserverClientIdentityKid() ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    NSString *claimKid = [[claims[@"clientKid"] isKindOfClass:NSString.class] ? claims[@"clientKid"] : @"" lowercaseString];
    if (localKid.length == 0 || ![claimKid isEqualToString:localKid]) {
        if (mismatchReason) *mismatchReason = [NSString stringWithFormat:@"client_kid_mismatch(got:%@,claim:%@)", localKid, claimKid];
        return NO;
    }

    NSString *cleanToken = [packageToken ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![claims[@"packageAudience"] isEqualToString:TserverLeaseHash(@"package-audience", cleanToken)]) {
        if (mismatchReason) *mismatchReason = @"package_audience_mismatch";
        return NO;
    }

    NSString *cleanInstall = [clientInstallId ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![claims[@"install"] isEqualToString:TserverLeaseHash(@"install", cleanInstall)]) {
        if (mismatchReason) *mismatchReason = @"client_install_mismatch";
        return NO;
    }

    NSString *cleanProfile = [profileSessionToken ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![claims[@"profile"] isEqualToString:TserverLeaseHash(@"profile", cleanProfile)]) {
        if (mismatchReason) *mismatchReason = @"profile_session_mismatch";
        return NO;
    }

    NSString *cleanPkgSession = [packageSessionToken ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![claims[@"packageSession"] isEqualToString:TserverLeaseHash(@"package-session", cleanPkgSession)]) {
        if (mismatchReason) *mismatchReason = @"package_session_mismatch";
        return NO;
    }
    return YES;
}

static double TserverLeaseMonotonicSecondsSince(uint64_t anchor) {
    if (anchor == 0) return 0;
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    uint64_t now = mach_continuous_time();
    if (now < anchor) return 0;
    uint64_t delta = now - anchor;
    long double nanos = (long double)delta * (long double)info.numer / (long double)info.denom;
    return (double)(nanos / 1000000000.0L);
}

static int64_t TserverLeaseTrustedNowLocked(void) {
    if (!gLeaseEnvelopeData || gLeaseMonotonicAnchor == 0 || gLeaseServerAnchor <= 0) return 0;
    int64_t monotonicNow = gLeaseServerAnchor + (int64_t)floor(TserverLeaseMonotonicSecondsSince(gLeaseMonotonicAnchor));
    int64_t wallNow = (int64_t)floor(NSDate.date.timeIntervalSince1970);
    return MAX(monotonicNow, wallNow);
}

static TserverAuthorizationRevocationBlock TserverLeaseTransitionLocked(TserverAuthorizationState state) {
    if (gLeaseExpiryTimer) {
        dispatch_source_cancel(gLeaseExpiryTimer);
        gLeaseExpiryTimer = nil;
    }
    BOOL wasAuthorized = gLeaseState == TserverAuthorizationStateAuthorized;
    gLeaseEnvelopeData = nil;
    gLeasePayloadDigest = nil;
    gLeaseBindingDigest = nil;
    gLeaseMonotonicAnchor = 0;
    gLeaseServerAnchor = 0;
    gLeaseState = state;
    gLeaseGeneration++;
    return wasAuthorized ? [gLeaseRevocationHandler copy] : nil;
}

static void TserverLeaseDispatchRevocation(TserverAuthorizationRevocationBlock handler, TserverAuthorizationState state) {
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(state); });
}

static NSDictionary *TserverLeaseCopyVerifiedClaims(uint64_t requiredGeneration, uint64_t *generationOut) {
    if (TserverAuthorizationPublicKeyringReady() != 0) return nil;
    TserverLeaseInit();

    __block NSData *envelopeData = nil;
    __block NSData *expectedPayloadDigest = nil;
    __block NSData *expectedBindingDigest = nil;
    __block uint64_t generation = 0;
    __block int64_t trustedNow = 0;
    dispatch_sync(gLeaseQueue, ^{
        if (gLeaseState != TserverAuthorizationStateAuthorized || !gLeaseEnvelopeData ||
            !gLeasePayloadDigest || !gLeaseBindingDigest ||
            (requiredGeneration != 0 && gLeaseGeneration != requiredGeneration)) {
            return;
        }
        envelopeData = gLeaseEnvelopeData;
        expectedPayloadDigest = gLeasePayloadDigest;
        expectedBindingDigest = gLeaseBindingDigest;
        generation = gLeaseGeneration;
        trustedNow = TserverLeaseTrustedNowLocked();
    });
    if (!envelopeData || trustedNow <= 0) return nil;

    NSError *parseError = nil;
    id parsedEnvelope = [NSJSONSerialization JSONObjectWithData:envelopeData options:0 error:&parseError];
    NSDictionary *envelope = TserverLeaseCanonicalEnvelope(parsedEnvelope);
    NSData *payload = nil;
    BOOL cryptographicallyValid = envelope && TserverLeaseVerifySignature(envelope, &payload);
    NSData *payloadDigest = cryptographicallyValid ? TserverLeaseSHA256(payload) : nil;
    NSDictionary *claims = nil;
    if (cryptographicallyValid && TserverLeaseConstantTimeEqual(payloadDigest, expectedPayloadDigest)) {
        id parsedClaims = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&parseError];
        if ([parsedClaims isKindOfClass:NSDictionary.class] && TserverLeaseClaimsSchemaIsValid(parsedClaims)) {
            NSData *bindingDigest = TserverLeaseBindingDigestForClaims(parsedClaims);
            if (TserverLeaseConstantTimeEqual(bindingDigest, expectedBindingDigest)) claims = parsedClaims;
        }
    }

    int64_t issuedAt = 0;
    int64_t notBefore = 0;
    int64_t expiresAt = 0;
    BOOL timeValid = claims &&
        TserverLeaseReadInteger(claims[@"iat"], &issuedAt) &&
        TserverLeaseReadInteger(claims[@"nbf"], &notBefore) &&
        TserverLeaseReadInteger(claims[@"exp"], &expiresAt) &&
        trustedNow >= notBefore && trustedNow < expiresAt &&
        expiresAt - issuedAt <= kTserverLeaseMaximumLifetimeSeconds;

    __block BOOL current = NO;
    __block TserverAuthorizationRevocationBlock handler = nil;
    __block TserverAuthorizationState transitionState = TserverAuthorizationStateCompromised;
    dispatch_sync(gLeaseQueue, ^{
        current = gLeaseState == TserverAuthorizationStateAuthorized &&
            gLeaseGeneration == generation &&
            (requiredGeneration == 0 || generation == requiredGeneration) &&
            TserverLeaseConstantTimeEqual(gLeasePayloadDigest, expectedPayloadDigest) &&
            TserverLeaseConstantTimeEqual(gLeaseBindingDigest, expectedBindingDigest);
        if (!current) return;
        if (!claims || !cryptographicallyValid) {
            transitionState = TserverAuthorizationStateCompromised;
            handler = TserverLeaseTransitionLocked(transitionState);
            current = NO;
            return;
        }
        if (!timeValid) {
            transitionState = TserverAuthorizationStateExpired;
            handler = TserverLeaseTransitionLocked(transitionState);
            current = NO;
        }
    });
    TserverLeaseDispatchRevocation(handler, transitionState);
    if (!current || !timeValid) return nil;
    if (generationOut) *generationOut = generation;
    return [claims copy];
}

static void TserverLeaseExpireGeneration(uint64_t generation) {
    (void)TserverLeaseCopyVerifiedClaims(generation, NULL);
}

void TserverAuthorizationLeaseInvalidate(TserverAuthorizationState state) {
    TserverLeaseInit();
    __block TserverAuthorizationRevocationBlock handler;
    dispatch_sync(gLeaseQueue, ^{
        handler = TserverLeaseTransitionLocked(state);
    });
    TserverLeaseDispatchRevocation(handler, state);
}

BOOL TserverAuthorizationLeaseInstall(
    NSDictionary *response,
    NSString *packageToken,
    NSString *profileSessionToken,
    NSString *packageSessionToken,
    NSString *clientInstallId,
    NSString *bundleId,
    NSError **error
) {
    TserverLeaseInit();
    NSDictionary *sourceEnvelope = [response[@"authorizationLease"] isKindOfClass:NSDictionary.class]
        ? response[@"authorizationLease"]
        : nil;
    NSDictionary *envelope = TserverLeaseCanonicalEnvelope(sourceEnvelope);
    if (!envelope) {
        if (error) *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Lease envelope missing or malformed"}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
        return NO;
    }
    NSData *envelopeData = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    if (envelopeData.length == 0 || envelopeData.length > 131072) {
        if (error) *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Lease envelope serialization failed"}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
        return NO;
    }
    NSData *payload = nil;
    if (!TserverLeaseVerifySignature(envelope, &payload)) {
        if (error) *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Lease signature invalid"}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateCompromised);
        return NO;
    }
    NSError *parseError = nil;
    id parsedClaims = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&parseError];
    NSDictionary *claims = [parsedClaims isKindOfClass:NSDictionary.class] ? parsedClaims : nil;
    if (!claims || !TserverLeaseClaimsSchemaIsValid(claims)) {
        if (error) *error = parseError ?: [NSError errorWithDomain:@"TserverAuthorizationLease" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Lease claims malformed"}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
        return NO;
    }
    NSString *mismatchReason = nil;
    if (!TserverLeaseClaimsMatch(claims, packageToken, profileSessionToken, packageSessionToken, clientInstallId, bundleId, &mismatchReason)) {
        NSString *detail = [NSString stringWithFormat:@"Lease claims do not match: %@", mismatchReason ?: @"unknown"];
        if (error) *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:5 userInfo:@{NSLocalizedDescriptionKey: detail}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateDenied);
        return NO;
    }

    int64_t now = (int64_t)floor(NSDate.date.timeIntervalSince1970);
    int64_t issuedAt = 0;
    int64_t notBefore = 0;
    int64_t expiresAt = 0;
    TserverLeaseReadInteger(claims[@"iat"], &issuedAt);
    TserverLeaseReadInteger(claims[@"nbf"], &notBefore);
    TserverLeaseReadInteger(claims[@"exp"], &expiresAt);
    // Allow generous clock skew tolerance (300 seconds) between device carrier time and server NTP
    const int64_t kClockSkewTolerance = 300;
    if (issuedAt <= 0 || expiresAt <= issuedAt ||
        now < (notBefore - kClockSkewTolerance) ||
        now >= (expiresAt + kClockSkewTolerance) ||
        (now - (kTserverLeaseMaximumInstallAgeSeconds + kClockSkewTolerance) > issuedAt) ||
        (issuedAt - now > kClockSkewTolerance) ||
        (expiresAt - issuedAt > kTserverLeaseMaximumLifetimeSeconds + kClockSkewTolerance)) {
        NSString *timeReason = [NSString stringWithFormat:@"Lease time window invalid (now:%lld, iat:%lld, nbf:%lld, exp:%lld)", (long long)now, (long long)issuedAt, (long long)notBefore, (long long)expiresAt];
        if (error) *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:6 userInfo:@{NSLocalizedDescriptionKey: timeReason}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateExpired);
        return NO;
    }

    NSData *payloadDigest = TserverLeaseSHA256(payload);
    NSData *bindingDigest = TserverLeaseBindingDigestForClaims(claims);
    NSString *payloadDigestHex = TserverLeaseHex(payloadDigest);
    NSString *jti = claims[@"jti"];
    if (payloadDigest.length != CC_SHA256_DIGEST_LENGTH || bindingDigest.length != CC_SHA256_DIGEST_LENGTH ||
        payloadDigestHex.length != CC_SHA256_DIGEST_LENGTH * 2 || jti.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Lease digest invalid"}];
        TserverAuthorizationLeaseInvalidate(TserverAuthorizationStateCompromised);
        return NO;
    }

    __block BOOL accepted = NO;
    __block BOOL rollbackRejected = NO;
    __block BOOL watermarkFailed = NO;
    dispatch_sync(gLeaseQueue, ^{
        NSDictionary *watermark = [TserverStorage authorizationLeaseWatermark];
        int64_t persistedIssuedAt = 0;
        if (watermark && !TserverLeaseReadInteger(watermark[@"iat"], &persistedIssuedAt)) {
            // Unparseable watermark — do not abort, treat as first install
            persistedIssuedAt = 0;
        }
        // Rollback check: allow equal iat or higher; if clock jumped backward significantly, reject
        if (issuedAt < gLeaseHighestIssuedAt) {
            rollbackRejected = YES;
            return;
        }
        if (persistedIssuedAt > 0 && issuedAt < (persistedIssuedAt - kClockSkewTolerance)) {
            rollbackRejected = YES;
            return;
        }
        if (persistedIssuedAt == issuedAt) {
            NSString *persistedJti = [watermark[@"jti"] isKindOfClass:NSString.class] ? watermark[@"jti"] : @"";
            NSString *persistedDigest = [watermark[@"payloadDigest"] isKindOfClass:NSString.class] ? watermark[@"payloadDigest"] : @"";
            if ((persistedJti.length == 0) != (persistedDigest.length == 0)) {
                watermarkFailed = YES;
                return;
            }
            // Equal-second leases can be legitimately minted by concurrent bootstrap
            // and activation. Exact replay is harmless; a different signed lease in
            // the same second remains bounded by its own signed expiry.
        }
        NSDictionary *nextWatermark = @{ @"iat": @(issuedAt), @"jti": jti, @"payloadDigest": payloadDigestHex };
        if (![TserverStorage saveAuthorizationLeaseWatermark:nextWatermark]) {
            watermarkFailed = YES;
            return;
        }
        gLeaseHighestIssuedAt = MAX(gLeaseHighestIssuedAt, issuedAt);
        if (gLeaseExpiryTimer) {
            dispatch_source_cancel(gLeaseExpiryTimer);
            gLeaseExpiryTimer = nil;
        }
        gLeaseEnvelopeData = [envelopeData copy];
        gLeasePayloadDigest = [payloadDigest copy];
        gLeaseBindingDigest = [bindingDigest copy];
        gLeaseServerAnchor = now;
        gLeaseMonotonicAnchor = mach_continuous_time();
        gLeaseState = TserverAuthorizationStateAuthorized;
        gLeaseGeneration++;
        uint64_t generation = gLeaseGeneration;
        NSTimeInterval secondsUntilExpiry = MAX(0.0, (NSTimeInterval)(expiresAt - now));
        gLeaseExpiryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gLeaseQueue);
        dispatch_source_set_timer(
            gLeaseExpiryTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(secondsUntilExpiry * NSEC_PER_SEC)),
            DISPATCH_TIME_FOREVER,
            0
        );
        dispatch_source_set_event_handler(gLeaseExpiryTimer, ^{
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                TserverLeaseExpireGeneration(generation);
            });
        });
        dispatch_resume(gLeaseExpiryTimer);
        accepted = YES;
    });
    if (!accepted && error) {
        NSInteger code = rollbackRejected ? 7 : 8;
        NSString *message = rollbackRejected ? @"Lease rollback rejected" : @"Lease watermark persistence failed";
        if (watermarkFailed) message = @"Lease watermark is invalid or unavailable";
        *error = [NSError errorWithDomain:@"TserverAuthorizationLease" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    if (!accepted) TserverAuthorizationLeaseInvalidate(rollbackRejected ? TserverAuthorizationStateDenied : TserverAuthorizationStateCompromised);
    return accepted;
}

BOOL TserverAuthorizationLeaseIntegrityCheck(void) {
    return TserverLeaseCopyVerifiedClaims(0, NULL) != nil;
}

BOOL TserverAuthorizationLeaseIsAuthorized(void) {
    return TserverAuthorizationLeaseIntegrityCheck();
}

BOOL TserverAuthorizationLeaseAllowsCapability(NSString *capability) {
    NSString *needle = [[capability ?: @"paid" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (!TserverLeaseStringMatches(needle, @"^[a-z0-9._-]{1,64}$", 64)) return NO;
    NSDictionary *claims = TserverLeaseCopyVerifiedClaims(0, NULL);
    NSArray *capabilities = [claims[@"capabilities"] isKindOfClass:NSArray.class] ? claims[@"capabilities"] : @[];
    return claims && [capabilities containsObject:needle];
}

NSDictionary *TserverAuthorizationLeaseLicenseInfo(void) {
    NSDictionary *claims = TserverLeaseCopyVerifiedClaims(0, NULL);
    if (!claims) return @{};
    id expiresRaw = claims[@"licenseExpiresAt"];
    NSNumber *remainingSeconds = nil;
    NSString *licenseType = [claims[@"licenseType"] isKindOfClass:NSString.class]
        ? [(NSString *)claims[@"licenseType"] lowercaseString]
        : @"";
    BOOL isLifetime = [licenseType containsString:@"lifetime"] || [licenseType isEqualToString:@"forever"];
    if ([expiresRaw isKindOfClass:NSString.class] && [(NSString *)expiresRaw length] > 0) {
        NSDate *date = nil;
        if ([NSISO8601DateFormatter class]) {
            date = [[[NSISO8601DateFormatter alloc] init] dateFromString:(NSString *)expiresRaw];
        }
        if (!date) {
            NSDateFormatter *iso = [[NSDateFormatter alloc] init];
            iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            iso.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
            date = [iso dateFromString:(NSString *)expiresRaw];
            if (!date) {
                iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
                date = [iso dateFromString:(NSString *)expiresRaw];
            }
        }
        if (date) remainingSeconds = @((NSInteger)MAX(0, floor(date.timeIntervalSince1970 - NSDate.date.timeIntervalSince1970)));
    }
    NSMutableDictionary *row = [@{
        @"licenseRef": claims[@"licenseRef"] ?: @"",
        @"maskedKey": claims[@"maskedKey"] ?: @"",
        @"licenseKeyMasked": claims[@"maskedKey"] ?: @"",
        @"licenseType": claims[@"licenseType"] ?: @"",
        @"effectiveExpiresAt": claims[@"licenseExpiresAt"] ?: NSNull.null,
        @"licenseExpiresAt": claims[@"licenseExpiresAt"] ?: NSNull.null,
        @"maxDevices": claims[@"maxDevices"] ?: @0,
        @"features": claims[@"capabilities"] ?: @[],
        @"isLifetime": @(isLifetime)
    } mutableCopy];
    if (remainingSeconds) row[@"remainingSeconds"] = remainingSeconds;
    return [row copy];
}

TserverAuthorizationState TserverAuthorizationLeaseCurrentState(void) {
    TserverLeaseInit();
    __block TserverAuthorizationState state;
    dispatch_sync(gLeaseQueue, ^{ state = gLeaseState; });
    return state;
}

uint64_t TserverAuthorizationLeaseGeneration(void) {
    TserverLeaseInit();
    __block uint64_t generation;
    dispatch_sync(gLeaseQueue, ^{ generation = gLeaseGeneration; });
    return generation;
}

void TserverAuthorizationLeaseSetRevocationHandler(TserverAuthorizationRevocationBlock handler) {
    TserverLeaseInit();
    dispatch_sync(gLeaseQueue, ^{ gLeaseRevocationHandler = [handler copy]; });
}

BOOL TserverAuthorizationLeasePerformCapability(NSString *capability, dispatch_block_t work, dispatch_block_t denied) {
    NSString *requestedCapability = [[capability ?: @"paid" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (!TserverLeaseStringMatches(requestedCapability, @"^[a-z0-9._-]{1,64}$", 64)) {
        if (denied) dispatch_async(dispatch_get_main_queue(), denied);
        return NO;
    }
    uint64_t generation = 0;
    NSDictionary *claims = TserverLeaseCopyVerifiedClaims(0, &generation);
    NSArray *capabilities = [claims[@"capabilities"] isKindOfClass:NSArray.class] ? claims[@"capabilities"] : @[];
    BOOL allowed = claims && [capabilities containsObject:requestedCapability];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (allowed) {
            NSDictionary *freshClaims = TserverLeaseCopyVerifiedClaims(generation, NULL);
            NSArray *freshCapabilities = [freshClaims[@"capabilities"] isKindOfClass:NSArray.class]
                ? freshClaims[@"capabilities"]
                : @[];
            if (freshClaims && [freshCapabilities containsObject:requestedCapability]) {
                if (work) work();
                return;
            }
        }
        if (denied) denied();
    });
    return allowed;
}
