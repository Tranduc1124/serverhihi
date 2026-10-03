#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import "TserverStringCrypto.h"

#define TserverKeychainService TS_OBF_NS("com.tserver.auth")
#define TserverSessionTokenAccount TS_OBF_NS("session_token")
#define TserverPackageSessionTokenAccount TS_OBF_NS("package_session_token")
#define TserverClientInstallIdAccount TS_OBF_NS("client_install_id")
#define TserverLastValidPayloadAccount TS_OBF_NS("last_valid_payload")
#define TserverLeaseDisplayAccount TS_OBF_NS("lease_display_v2")
#define TserverLastAuthUiConfigAccount TS_OBF_NS("last_auth_ui_config")
#define TserverAuthSessionPairAccount TS_OBF_NS("auth_session_pair_v1")
#define TserverPendingProfileStateAccount TS_OBF_NS("pending_profile_state_v1")
#define TserverAuthorizationLeaseWatermarkAccount TS_OBF_NS("authorization_lease_watermark_v1")
#define TserverLastWorkingEndpointKey TS_OBF_NS("com.tserver.lastWorkingEndpoint")
#define TserverClientInstallIdFallbackKey TS_OBF_NS("com.tserver.auth.clientInstallId.v1")
#define TserverStorageNamespaceFallback TS_OBF_NS("legacy")
static NSString *gTserverStorageNamespace = nil;
static NSData *gTserverWatermarkKey = nil;

static NSData *TserverHMACSHA256(NSData *key, NSData *message) {
    // HMAC per RFC 2104, instantiated with SHA-256.
    uint8_t keyBlock[64] = {0};
    if (key.length > 64) {
        CC_SHA256_CTX c;
        CC_SHA256_Init(&c);
        CC_SHA256_Update(&c, key.bytes, (CC_LONG)key.length);
        uint8_t kd[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(kd, &c);
        memcpy(keyBlock, kd, sizeof(kd));
    } else {
        memcpy(keyBlock, key.bytes, (size_t)MIN((NSUInteger)key.length, (NSUInteger)64));
    }
    uint8_t ipad[64];
    uint8_t opad[64];
    for (NSUInteger i = 0; i < 64; i++) {
        ipad[i] = keyBlock[i] ^ 0x36;
        opad[i] = keyBlock[i] ^ 0x5c;
    }
    CC_SHA256_CTX innerCtx;
    CC_SHA256_Init(&innerCtx);
    CC_SHA256_Update(&innerCtx, ipad, 64);
    if (message.length > 0) CC_SHA256_Update(&innerCtx, message.bytes, (CC_LONG)message.length);
    uint8_t inner[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(inner, &innerCtx);
    CC_SHA256_CTX outerCtx;
    CC_SHA256_Init(&outerCtx);
    CC_SHA256_Update(&outerCtx, opad, 64);
    CC_SHA256_Update(&outerCtx, inner, sizeof(inner));
    uint8_t out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(out, &outerCtx);
    return [NSData dataWithBytes:out length:sizeof(out)];
}

static NSString *TserverHex(NSData *data) {
    NSMutableString *result = [NSMutableString stringWithCapacity:data.length * 2];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        [result appendFormat:@"%02x", bytes[i]];
    }
    return result ?: @"";
}

static NSString *TserverStorageHexDigest(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:24];
    for (NSUInteger index = 0; index < 12; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

static NSString *TserverScopedAccount(NSString *account) {
    NSString *scope = gTserverStorageNamespace.length > 0 ? gTserverStorageNamespace : TserverStorageNamespaceFallback;
    return [NSString stringWithFormat:@"%@.%@", account ?: @"", scope];
}

static NSString *TserverScopedDefaultsKey(NSString *key) {
    NSString *scope = gTserverStorageNamespace.length > 0 ? gTserverStorageNamespace : TserverStorageNamespaceFallback;
    return [NSString stringWithFormat:@"%@.%@", key ?: @"", scope];
}

static id TserverPropertyListValue(id value) {
    if (!value || value == NSNull.null) {
        return nil;
    }
    if ([value isKindOfClass:NSString.class] ||
        [value isKindOfClass:NSNumber.class] ||
        [value isKindOfClass:NSDate.class] ||
        [value isKindOfClass:NSData.class]) {
        return value;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *safe = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            id normalized = TserverPropertyListValue(item);
            if (normalized) {
                [safe addObject:normalized];
            }
        }
        return [safe copy];
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *safe = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
            NSString *safeKey = [key isKindOfClass:NSString.class] ? key : [key description];
            id normalized = TserverPropertyListValue(object);
            if (safeKey.length > 0 && normalized) {
                safe[safeKey] = normalized;
            }
        }];
        return [safe copy];
    }
    return [value description] ?: @"";
}

@interface TserverCrypto : NSObject
+ (NSString *)randomNonce;
@end

@interface TserverStorage : NSObject
+ (void)configureNamespaceWithPackageToken:(NSString *)packageToken bundleId:(NSString *)bundleId;
+ (NSString *)sessionToken;
+ (void)saveSessionToken:(NSString *)sessionToken;
+ (void)clearSessionToken;
+ (NSString *)packageSessionToken;
+ (void)savePackageSessionToken:(NSString *)token;
+ (void)clearPackageSessionToken;
+ (NSDictionary *)authSessionPair;
+ (void)saveAuthSessionPair:(NSDictionary *)pair;
+ (void)clearAuthSessionPair;
+ (NSDictionary *)pendingProfileState;
+ (void)savePendingProfileState:(NSDictionary *)state;
+ (void)clearPendingProfileState;
+ (NSString *)clientInstallId;
+ (NSDictionary *)lastValidPayload;
+ (void)saveLastValidPayload:(NSDictionary *)payload;
+ (NSDictionary *)authorizationLeaseWatermark;
+ (BOOL)saveAuthorizationLeaseWatermark:(NSDictionary *)watermark;
+ (NSDictionary *)lastAuthUiConfig;
+ (void)saveLastAuthUiConfig:(NSDictionary *)config;
+ (NSString *)lastWorkingEndpoint;
+ (void)saveLastWorkingEndpoint:(NSString *)endpoint;
+ (void)clearAuthState;
@end

@implementation TserverStorage

+ (void)configureNamespaceWithPackageToken:(NSString *)packageToken bundleId:(NSString *)bundleId {
    NSString *token = [packageToken stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *bundle = [bundleId stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (token.length == 0 || bundle.length == 0) return;
    NSString *next = TserverStorageHexDigest([NSString stringWithFormat:@"%@|%@", token, bundle.lowercaseString]);
    if ([gTserverStorageNamespace isEqualToString:next]) return;
    gTserverStorageNamespace = [next copy];
    // Watermark integrity key is bound to the server-issued package token and
    // the bundle id, so a watermark blob copied off-device (or replayed under a
    // different package/bundle) fails verification instead of rolling state back.
    gTserverWatermarkKey = [self sha256DataForString:[NSString stringWithFormat:@"tserver-watermark-v1|%@|%@", token, bundle.lowercaseString]];

    NSArray<NSString *> *accounts = @[
        TserverSessionTokenAccount,
        TserverPackageSessionTokenAccount,
        TserverAuthSessionPairAccount,
        TserverPendingProfileStateAccount,
        TserverLastValidPayloadAccount,
        TserverLeaseDisplayAccount,
        TserverAuthorizationLeaseWatermarkAccount,
        TserverLastAuthUiConfigAccount
    ];
    for (NSString *account in accounts) {
        NSString *scoped = TserverScopedAccount(account);
        NSData *scopedData = [self keychainDataForAccount:scoped];
        NSData *legacy = [self keychainDataForAccount:account];
        if (scopedData.length > 0) {
            // Migration is single-consumer: once this configured package owns a
            // scoped value, remove the unscoped copy so another package cannot
            // import it later.
            if (legacy.length > 0) [self deleteKeychainAccount:account];
            continue;
        }
        if (legacy.length > 0 && [self saveKeychainData:legacy account:scoped]) {
            // Delete only after the scoped write is confirmed by Keychain.
            [self deleteKeychainAccount:account];
        }
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *scopedEndpointKey = TserverScopedDefaultsKey(TserverLastWorkingEndpointKey);
    NSString *legacyEndpoint = [defaults stringForKey:TserverLastWorkingEndpointKey];
    NSString *scopedEndpoint = [defaults stringForKey:scopedEndpointKey];
    if (scopedEndpoint.length > 0) {
        if (legacyEndpoint.length > 0) [defaults removeObjectForKey:TserverLastWorkingEndpointKey];
    } else if (legacyEndpoint.length > 0) {
        [defaults setObject:legacyEndpoint forKey:scopedEndpointKey];
        if ([[defaults stringForKey:scopedEndpointKey] isEqualToString:legacyEndpoint]) {
            [defaults removeObjectForKey:TserverLastWorkingEndpointKey];
        }
    }
    [defaults synchronize];
}

+ (NSString *)sessionToken {
    return [self keychainStringForAccount:TserverScopedAccount(TserverSessionTokenAccount)];
}

+ (void)saveSessionToken:(NSString *)sessionToken {
    NSString *account = TserverScopedAccount(TserverSessionTokenAccount);
    if (sessionToken.length == 0) {
        [self deleteKeychainAccount:account];
        return;
    }
    [self saveKeychainString:sessionToken account:account];
}

+ (void)clearSessionToken {
    [self deleteKeychainAccount:TserverScopedAccount(TserverSessionTokenAccount)];
    [self deleteKeychainAccount:TserverScopedAccount(TserverLastValidPayloadAccount)];
    [self deleteKeychainAccount:TserverScopedAccount(TserverLeaseDisplayAccount)];
}

+ (NSString *)packageSessionToken {
    return [self keychainStringForAccount:TserverScopedAccount(TserverPackageSessionTokenAccount)];
}

+ (void)savePackageSessionToken:(NSString *)token {
    if (token.length == 0) {
        [self clearPackageSessionToken];
        return;
    }
    [self saveKeychainString:token account:TserverScopedAccount(TserverPackageSessionTokenAccount)];
}

+ (void)clearPackageSessionToken {
    [self deleteKeychainAccount:TserverScopedAccount(TserverPackageSessionTokenAccount)];
    [self clearAuthSessionPair];
}

+ (NSDictionary *)authSessionPair {
    NSData *data = [self keychainDataForAccount:TserverScopedAccount(TserverAuthSessionPairAccount)];
    if (data.length == 0) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

+ (void)saveAuthSessionPair:(NSDictionary *)pair {
    if (![pair isKindOfClass:NSDictionary.class]) return;
    NSDictionary *safe = TserverPropertyListValue(pair);
    NSString *profile = [safe[@"profileSessionToken"] isKindOfClass:NSString.class] ? safe[@"profileSessionToken"] : @"";
    NSString *package = [safe[@"packageSessionToken"] isKindOfClass:NSString.class] ? safe[@"packageSessionToken"] : @"";
    if (profile.length == 0 || package.length == 0) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:&error];
    if (error || data.length == 0) return;
    [self saveKeychainData:data account:TserverScopedAccount(TserverAuthSessionPairAccount)];
}

+ (void)clearAuthSessionPair {
    [self deleteKeychainAccount:TserverScopedAccount(TserverAuthSessionPairAccount)];
}

+ (NSDictionary *)pendingProfileState {
    NSData *data = [self keychainDataForAccount:TserverScopedAccount(TserverPendingProfileStateAccount)];
    if (data.length == 0) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

+ (void)savePendingProfileState:(NSDictionary *)state {
    if (![state isKindOfClass:NSDictionary.class]) return;
    NSDictionary *safe = TserverPropertyListValue(state);
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:&error];
    if (error || data.length == 0) return;
    [self saveKeychainData:data account:TserverScopedAccount(TserverPendingProfileStateAccount)];
}

+ (void)clearPendingProfileState {
    [self deleteKeychainAccount:TserverScopedAccount(TserverPendingProfileStateAccount)];
}

+ (NSString *)clientInstallId {
    // Keychain is the only source of truth. The NSUserDefaults mirror is gone:
    // it survived Keychain wipes, so it let a stable, correlatable install id
    // persist across reinstalls. A fresh/unavailable Keychain simply yields a
    // new in-memory id rather than resurrecting a stale one.
    NSString *value = [self keychainStringForAccount:TserverScopedAccount(TserverClientInstallIdAccount)];
    if (value.length == 0) {
        value = [self keychainStringForAccount:TserverClientInstallIdAccount];
        if (value.length > 0) {
            [self saveKeychainString:value account:TserverScopedAccount(TserverClientInstallIdAccount)];
        }
    }
    if (value.length == 0) {
        value = [TserverCrypto randomNonce];
        if (value.length > 0) {
            [self saveKeychainString:value account:TserverScopedAccount(TserverClientInstallIdAccount)];
        }
    }
    // Best-effort: scrub any legacy fallback so it cannot be used to resurrect
    // a prior identity on the next launch.
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:TserverClientInstallIdFallbackKey];
    return value;
}

+ (NSDictionary *)lastValidPayload {
    // V2 never trusts the legacy full VALID cache. Delete it on first access so
    // upgrades cannot keep raw license keys or six-hour wall-clock grants.
    [self deleteKeychainAccount:TserverScopedAccount(TserverLastValidPayloadAccount)];
    NSData *data = [self keychainDataForAccount:TserverScopedAccount(TserverLeaseDisplayAccount)];
    if (data.length == 0) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

+ (void)saveLastValidPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:NSDictionary.class]) return;
    NSDictionary *license = [payload[@"license"] isKindOfClass:NSDictionary.class] ? payload[@"license"] : @{};
    NSDictionary *minimal = @{ @"license": TserverPropertyListValue(license) ?: @{} };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:minimal options:0 error:&error];
    if (error || data.length == 0) return;
    [self deleteKeychainAccount:TserverScopedAccount(TserverLastValidPayloadAccount)];
    [self saveKeychainData:data account:TserverScopedAccount(TserverLeaseDisplayAccount)];
}

+ (NSDictionary *)authorizationLeaseWatermark {
    // Read both stores and merge: pick the *highest verified* watermark. A
    // single-store read let an attacker roll state back by clearing that one
    // store; requiring a valid HMAC also blocks forging an older iat.
    NSData *keychainData = [self keychainDataForAccount:TserverScopedAccount(TserverAuthorizationLeaseWatermarkAccount)];
    NSData *defaultsData = [[NSUserDefaults standardUserDefaults] dataForKey:TserverScopedDefaultsKey(TserverAuthorizationLeaseWatermarkAccount)];
    NSDictionary *best = nil;
    NSArray<NSData *> *candidates = @[keychainData ?: [NSData data], defaultsData ?: [NSData data]];
    for (NSData *data in candidates) {
        NSDictionary *value = [self watermarkFromData:data];
        if (!value) continue;
        if (!best) {
            best = value;
            continue;
        }
        int64_t bestIat = 0;
        int64_t curIat = 0;
        [[best objectForKey:@"iat"] respondsToSelector:@selector(longLongValue)] && (bestIat = [[best objectForKey:@"iat"] longLongValue]);
        [[value objectForKey:@"iat"] respondsToSelector:@selector(longLongValue)] && (curIat = [[value objectForKey:@"iat"] longLongValue]);
        if (curIat > bestIat) {
            best = value;
        } else if (curIat == bestIat) {
            NSString *bk = [NSString stringWithFormat:@"%@|%@", best[@"jti"] ?: @"", best[@"payloadDigest"] ?: @""];
            NSString *ck = [NSString stringWithFormat:@"%@|%@", value[@"jti"] ?: @"", value[@"payloadDigest"] ?: @""];
            if ([ck compare:bk] == NSOrderedDescending) best = value;
        }
    }
    if (best) {
        // Self-heal: re-persist the best verified watermark to both stores.
        NSData *data = [NSJSONSerialization dataWithJSONObject:best options:0 error:nil];
        if (data.length > 0) {
            [self saveKeychainData:data account:TserverScopedAccount(TserverAuthorizationLeaseWatermarkAccount)];
            [[NSUserDefaults standardUserDefaults] setObject:data forKey:TserverScopedDefaultsKey(TserverAuthorizationLeaseWatermarkAccount)];
        }
        return best;
    }
    return nil;
}

+ (NSDictionary *)watermarkFromData:(NSData *)data {
    if (data.length == 0) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *dict = [value isKindOfClass:NSDictionary.class] ? value : nil;
    if (!dict) return nil;
    NSNumber *iat = [dict[@"iat"] isKindOfClass:NSNumber.class] ? dict[@"iat"] : nil;
    NSString *jti = [dict[@"jti"] isKindOfClass:NSString.class] ? dict[@"jti"] : @"";
    NSString *digest = [dict[@"payloadDigest"] isKindOfClass:NSString.class] ? dict[@"payloadDigest"] : @"";
    if (!iat || iat.longLongValue <= 0 || jti.length == 0 || digest.length != 64) return nil;
    // Accept only MAC-verified v1 records. A record without a valid HMAC is
    // treated as missing, not trusted — so a forged "iat=0" cannot reset state.
    if ([dict[@"v"] integerValue] == 1 && [dict[@"mac"] isKindOfClass:NSString.class]) {
        NSString *hex = dict[@"mac"];
        NSMutableData *mac = [NSMutableData dataWithCapacity:hex.length / 2];
        BOOL validHex = hex.length > 0 && hex.length % 2 == 0;
        for (NSUInteger i = 0; validHex && i + 1 < hex.length; i += 2) {
            unsigned int byte = 0;
            NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]];
            if (![scanner scanHexInt:&byte]) { validHex = NO; break; }
            uint8_t b = (uint8_t)byte;
            [mac appendBytes:&b length:1];
        }
        if (!validHex || mac.length == 0) return nil;
        NSData *expected = TserverHMACSHA256(gTserverWatermarkKey ?: [NSData data],
                                             [[NSString stringWithFormat:@"%lld|%@|%@", iat.longLongValue, jti, digest] dataUsingEncoding:NSUTF8StringEncoding]);
        if (mac.length != expected.length || ![mac isEqual:expected]) {
            return nil;
        }
        return dict;
    }
    // Legacy (unauthenticated) records are not trusted for rollback decisions.
    return nil;
}

+ (BOOL)saveAuthorizationLeaseWatermark:(NSDictionary *)watermark {
    if (![watermark isKindOfClass:NSDictionary.class]) return NO;
    NSNumber *issuedAt = [watermark[@"iat"] isKindOfClass:NSNumber.class] ? watermark[@"iat"] : nil;
    NSString *jti = [watermark[@"jti"] isKindOfClass:NSString.class] ? watermark[@"jti"] : @"";
    NSString *digest = [watermark[@"payloadDigest"] isKindOfClass:NSString.class] ? watermark[@"payloadDigest"] : @"";
    if (issuedAt.longLongValue <= 0 || jti.length == 0 || digest.length != 64) return NO;
    NSData *mac = TserverHMACSHA256(gTserverWatermarkKey ?: [NSData data],
                                    [[NSString stringWithFormat:@"%lld|%@|%@", issuedAt.longLongValue, jti, digest] dataUsingEncoding:NSUTF8StringEncoding]);
    NSDictionary *safe = @{
        @"v": @1,
        @"iat": issuedAt,
        @"jti": jti,
        @"payloadDigest": digest,
        @"mac": TserverHex(mac)
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:nil];
    if (data.length == 0) return NO;
    (void)[self saveKeychainData:data account:TserverScopedAccount(TserverAuthorizationLeaseWatermarkAccount)];
    // Second copy survives a Keychain reset; verified by HMAC on every read.
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:TserverScopedDefaultsKey(TserverAuthorizationLeaseWatermarkAccount)];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return YES;
}

+ (NSDictionary *)lastAuthUiConfig {
    NSData *data = [self keychainDataForAccount:TserverScopedAccount(TserverLastAuthUiConfigAccount)];
    if (data.length == 0) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *envelope = [value isKindOfClass:NSDictionary.class] ? value : nil;
    return [envelope[@"v"] integerValue] == 1 && [envelope[@"config"] isKindOfClass:NSDictionary.class]
        ? envelope
        : nil;
}

+ (void)saveLastAuthUiConfig:(NSDictionary *)config {
    if (![config isKindOfClass:NSDictionary.class] || [config[@"v"] integerValue] != 1 ||
        ![config[@"config"] isKindOfClass:NSDictionary.class] ||
        ![config[@"sha256"] isKindOfClass:NSString.class] || [config[@"sha256"] length] != 64) return;
    NSDictionary *safe = TserverPropertyListValue(config);
    if (![safe isKindOfClass:NSDictionary.class] || safe.count == 0) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:&error];
    if (error || data.length == 0) return;
    [self saveKeychainData:data account:TserverScopedAccount(TserverLastAuthUiConfigAccount)];
}

+ (NSString *)lastWorkingEndpoint {
    NSString *endpoint = [[NSUserDefaults standardUserDefaults] stringForKey:TserverScopedDefaultsKey(TserverLastWorkingEndpointKey)];
    return endpoint.length > 0 ? endpoint : nil;
}

+ (void)saveLastWorkingEndpoint:(NSString *)endpoint {
    if (endpoint.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:endpoint forKey:TserverScopedDefaultsKey(TserverLastWorkingEndpointKey)];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)clearAuthState {
    [self clearSessionToken];
    [self clearPackageSessionToken];
    [self clearAuthSessionPair];
    [self clearPendingProfileState];
    [self deleteKeychainAccount:TserverScopedAccount(TserverLastAuthUiConfigAccount)];
    [self deleteKeychainAccount:TserverScopedAccount(TserverLeaseDisplayAccount)];
}

+ (NSData *)sha256DataForString:(NSString *)value {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

+ (NSString *)keychainStringForAccount:(NSString *)account {
    NSData *data = [self keychainDataForAccount:account];
    if (data.length == 0) return nil;
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return value.length > 0 ? value : nil;
}

+ (NSData *)keychainDataForAccount:(NSString *)account {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: TserverKeychainService,
        (__bridge id)kSecAttrAccount: account ?: @"",
        (__bridge id)kSecReturnData: @YES
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    return CFBridgingRelease(result);
}

+ (void)saveKeychainString:(NSString *)value account:(NSString *)account {
    if (value.length == 0 || account.length == 0) return;
    [self saveKeychainData:[value dataUsingEncoding:NSUTF8StringEncoding] account:account];
}

+ (BOOL)saveKeychainData:(NSData *)data account:(NSString *)account {
    if (data.length == 0 || account.length == 0) return NO;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: TserverKeychainService,
        (__bridge id)kSecAttrAccount: account
    };
    NSDictionary *update = @{(__bridge id)kSecValueData: data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    if (status == errSecSuccess) return YES;
    if (status != errSecItemNotFound) return NO;

    NSMutableDictionary *item = [query mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecSuccess) return YES;
    if (status != errSecDuplicateItem) return NO;
    return SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update) == errSecSuccess;
}

+ (void)deleteKeychainAccount:(NSString *)account {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: TserverKeychainService,
        (__bridge id)kSecAttrAccount: account ?: @""
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
