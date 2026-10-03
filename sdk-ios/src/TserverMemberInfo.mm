#import "TserverMemberInfo.h"
#import "TserverAuthConfig.h"
#import "TserverAuthEndpoint.h"
#import "TserverSecurity.h"
#import "TserverStringCrypto.h"
#import "TserverSealedConstants.h"

@interface TserverHttp : NSObject
+ (void)get:(NSString *)url
    headers:(NSDictionary *)headers
 completion:(void (^)(NSDictionary *result, NSError *error))completion;
+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void (^)(NSDictionary *result, NSError *error))completion;
@end

static NSString *gTserverMemberApiKey = nil;
static NSString *gTserverMemberPackageId = nil;

static NSString *TserverInfoTrim(id value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static NSString *TserverInfoApiKey(void) {
    NSString *runtime = TserverInfoTrim(gTserverMemberApiKey);
    if (runtime.length > 0) return runtime;
    return TserverInfoTrim(kTserverMemberApiKey);
}

static NSString *TserverInfoPackageId(void) {
    NSString *runtime = TserverInfoTrim(gTserverMemberPackageId);
    if (runtime.length > 0) return runtime;
    return TserverInfoTrim(kTserverMemberPackageId);
}

static BOOL TserverInfoConfigured(void) {
    NSString *apiKey = TserverInfoApiKey();
    NSString *packageId = TserverInfoPackageId();
    return [apiKey hasPrefix:@"mk_"] && apiKey.length >= 24 && packageId.length > 0;
}

static NSString *TserverInfoEndpoint(void) {
    NSString *endpoint = TserverCompiledPrimaryEndpoint();
    while ([endpoint hasSuffix:@"/"]) {
        endpoint = [endpoint substringToIndex:endpoint.length - 1];
    }
    return endpoint ?: @"";
}

static NSString *TserverInfoURL(NSString *path) {
    NSString *endpoint = TserverInfoEndpoint();
    if (endpoint.length == 0 || path.length == 0) return @"";
    const char *prefix = TserverSealedStringAt(kTserverSealedStr_V1MemberApi);
    NSString *apiPrefix = (prefix && prefix[0]) ? [NSString stringWithUTF8String:prefix] : @"";
    return [NSString stringWithFormat:@"%@%@%@", endpoint, apiPrefix, path];
}

static NSString *TserverInfoQuery(NSString *value) {
    NSCharacterSet *allowed = NSCharacterSet.URLQueryAllowedCharacterSet;
    return [TserverInfoTrim(value) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSDictionary *TserverInfoHeaders(void) {
    NSString *apiKey = TserverInfoApiKey();
    const char *hAuth = TserverSealedStringAt(kTserverSealedStr_HeaderAuthorization);
    const char *hBearer = TserverSealedStringAt(kTserverSealedStr_BearerPrefix);
    NSString *authKey = (hAuth && hAuth[0]) ? [NSString stringWithUTF8String:hAuth] : @"";
    NSString *bearerPrefix = (hBearer && hBearer[0]) ? [NSString stringWithUTF8String:hBearer] : @"";
    return (apiKey.length > 0 && authKey.length > 0) ? @{ authKey: [NSString stringWithFormat:@"%@%@", bearerPrefix, apiKey] } : @{};
}

static NSDictionary *TserverInfoError(NSString *status, NSString *message) {
    return @{
        @"ok": @NO,
        @"status": status ?: @"ERROR",
        @"message": message ?: @"Member info request failed"
    };
}

static NSString *TserverInfoString(id value) {
    if ([value isKindOfClass:NSString.class]) return (NSString *)value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSNumber *TserverInfoNumber(id value) {
    if ([value isKindOfClass:NSNumber.class]) return (NSNumber *)value;
    if ([value isKindOfClass:NSString.class]) {
        return @([(NSString *)value doubleValue]);
    }
    return nil;
}

static BOOL TserverInfoBool(id value) {
    if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    return NO;
}

static NSDictionary *TserverInfoDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : nil;
}

static NSArray *TserverInfoArray(id value) {
    return [value isKindOfClass:NSArray.class] ? (NSArray *)value : nil;
}

static NSDictionary *TserverInfoFindPackage(NSArray *packages) {
    NSString *packageId = TserverInfoPackageId();
    for (id item in packages ?: @[]) {
        NSDictionary *pkg = TserverInfoDictionary(item);
        if ([TserverInfoString(pkg[@"packageId"]) isEqualToString:packageId]) {
            return pkg;
        }
    }
    return nil;
}

static NSDictionary *TserverInfoFindOnlinePackage(NSArray *items) {
    NSString *packageId = TserverInfoPackageId();
    for (id item in items ?: @[]) {
        NSDictionary *pkg = TserverInfoDictionary(item);
        if ([TserverInfoString(pkg[@"packageId"]) isEqualToString:packageId]) {
            return pkg;
        }
    }
    return nil;
}

static void TserverInfoComplete(TserverMemberInfoCompletion completion, NSDictionary *result) {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result ?: TserverInfoError(@"EMPTY", @"Empty member info result"));
    });
}

@implementation TserverMemberInfo

+ (void)configureWithMemberApiKey:(NSString *)memberApiKey packageId:(NSString *)packageId {
    @synchronized(self) {
        gTserverMemberApiKey = [TserverInfoTrim(memberApiKey) copy];
        gTserverMemberPackageId = [TserverInfoTrim(packageId) copy];
    }
}

+ (BOOL)isConfigured {
    return TserverInfoConfigured();
}

+ (NSString *)configuredPackageId {
    return TserverInfoPackageId();
}

+ (void)getPath:(NSString *)path completion:(TserverMemberInfoCompletion)completion {
    if (!TserverInfoConfigured()) {
        TserverInfoComplete(completion, TserverInfoError(@"NOT_CONFIGURED", @"Set member API key (mk_...) and packageId before using TserverMemberInfo"));
        return;
    }
    NSString *url = TserverInfoURL(path);
    if (url.length == 0) {
        TserverInfoComplete(completion, TserverInfoError(@"BAD_ENDPOINT", @"Tserver endpoint is missing"));
        return;
    }
    [TserverHttp get:url headers:TserverInfoHeaders() completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            TserverInfoComplete(completion, TserverInfoError(@"NETWORK_ERROR", error.localizedDescription ?: @"Network error"));
            return;
        }
        TserverInfoComplete(completion, result ?: TserverInfoError(@"EMPTY", @"Empty server response"));
    }];
}

+ (void)postPath:(NSString *)path body:(NSDictionary *)body completion:(TserverMemberInfoCompletion)completion {
    if (!TserverInfoConfigured()) {
        TserverInfoComplete(completion, TserverInfoError(@"NOT_CONFIGURED", @"Set member API key (mk_...) and packageId before using TserverMemberInfo"));
        return;
    }
    NSString *url = TserverInfoURL(path);
    if (url.length == 0) {
        TserverInfoComplete(completion, TserverInfoError(@"BAD_ENDPOINT", @"Tserver endpoint is missing"));
        return;
    }
    [TserverHttp post:url body:body ?: @{} headers:TserverInfoHeaders() completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            TserverInfoComplete(completion, TserverInfoError(@"NETWORK_ERROR", error.localizedDescription ?: @"Network error"));
            return;
        }
        TserverInfoComplete(completion, result ?: TserverInfoError(@"EMPTY", @"Empty server response"));
    }];
}

+ (void)loadPackageInfoWithCompletion:(TserverMemberInfoCompletion)completion {
    const char *pPath = TserverSealedStringAt(kTserverSealedStr_MemberPackages);
    NSString *path = (pPath && pPath[0]) ? [NSString stringWithUTF8String:pPath] : @"";
    [self getPath:path completion:^(NSDictionary *result) {
        if (![result[@"ok"] boolValue]) {
            TserverInfoComplete(completion, result);
            return;
        }
        NSArray *packages = TserverInfoArray(result[@"packages"]);
        NSDictionary *pkg = TserverInfoFindPackage(packages);
        if (!pkg) {
            TserverInfoComplete(completion, TserverInfoError(@"PACKAGE_NOT_FOUND", @"Package id does not belong to this member API key"));
            return;
        }
        TserverInfoComplete(completion, @{
            @"ok": @YES,
            @"status": @"OK",
            @"packageId": TserverInfoPackageId(),
            @"package": pkg,
            @"packages": packages ?: @[]
        });
    }];
}

+ (void)loadOnlineWithCompletion:(TserverMemberInfoCompletion)completion {
    const char *oPath = TserverSealedStringAt(kTserverSealedStr_MemberOnline);
    NSString *path = (oPath && oPath[0]) ? [NSString stringWithUTF8String:oPath] : @"";
    [self getPath:path completion:^(NSDictionary *result) {
        if (![result[@"ok"] boolValue]) {
            TserverInfoComplete(completion, result);
            return;
        }
        NSDictionary *online = TserverInfoDictionary(result[@"online"]) ?: @{};
        NSArray *byPackage = TserverInfoArray(online[@"byPackage"]);
        NSDictionary *onlinePackage = TserverInfoFindOnlinePackage(byPackage);
        if (!onlinePackage) {
            onlinePackage = @{
                @"packageId": TserverInfoPackageId(),
                @"onlineCount": @0,
                @"lastSeenAt": [NSNull null]
            };
        }
        TserverInfoComplete(completion, @{
            @"ok": @YES,
            @"status": @"OK",
            @"packageId": TserverInfoPackageId(),
            @"online": online,
            @"onlinePackage": onlinePackage
        });
    }];
}

+ (void)listKeysWithCompletion:(TserverMemberInfoCompletion)completion {
    const char *kPath = TserverSealedStringAt(kTserverSealedStr_MemberKeys);
    NSString *basePath = (kPath && kPath[0]) ? [NSString stringWithUTF8String:kPath] : @"";
    NSString *path = [NSString stringWithFormat:@"%@?packageId=%@&includeRaw=false&limit=500", basePath, TserverInfoQuery(TserverInfoPackageId())];
    [self getPath:path completion:^(NSDictionary *result) {
        if (![result[@"ok"] boolValue]) {
            TserverInfoComplete(completion, result);
            return;
        }
        NSMutableDictionary *out = [result mutableCopy] ?: [NSMutableDictionary dictionary];
        out[@"packageId"] = TserverInfoPackageId();
        TserverInfoComplete(completion, [out copy]);
    }];
}

+ (void)checkKey:(NSString *)licenseKey completion:(TserverMemberInfoCompletion)completion {
    NSString *key = [TserverInfoTrim(licenseKey) uppercaseString];
    if (key.length == 0) {
        TserverInfoComplete(completion, TserverInfoError(@"EMPTY_KEY", @"License key is empty"));
        return;
    }
    NSDictionary *body = @{
        @"licenseKey": key,
        @"packageId": TserverInfoPackageId(),
        @"includeRaw": @NO
    };
    const char *rPath = TserverSealedStringAt(kTserverSealedStr_MemberKeysRemaining);
    NSString *path = (rPath && rPath[0]) ? [NSString stringWithUTF8String:rPath] : @"";
    [self postPath:path body:body completion:^(NSDictionary *result) {
        if (![result[@"ok"] boolValue]) {
            TserverInfoComplete(completion, result);
            return;
        }
        NSDictionary *keyInfo = TserverInfoDictionary(result[@"key"]);
        NSString *keyPackageId = TserverInfoString(keyInfo[@"packageId"]);
        if (keyPackageId.length > 0 && ![keyPackageId isEqualToString:TserverInfoPackageId()]) {
            TserverInfoComplete(completion, TserverInfoError(@"PACKAGE_MISMATCH", @"License key is not in configured packageId"));
            return;
        }
        NSMutableDictionary *out = [result mutableCopy] ?: [NSMutableDictionary dictionary];
        out[@"packageId"] = TserverInfoPackageId();
        TserverInfoComplete(completion, [out copy]);
    }];
}

+ (void)loadInfoForKey:(NSString *)licenseKey completion:(TserverMemberInfoCompletion)completion {
    [self loadPackageInfoWithCompletion:^(NSDictionary *packageResult) {
        if (![packageResult[@"ok"] boolValue]) {
            TserverInfoComplete(completion, packageResult);
            return;
        }
        [self loadOnlineWithCompletion:^(NSDictionary *onlineResult) {
            TserverMemberInfoCompletion finish = ^(NSDictionary *keyResult) {
                NSMutableDictionary *info = [NSMutableDictionary dictionary];
                info[@"ok"] = @YES;
                info[@"status"] = @"OK";
                info[@"packageId"] = TserverInfoPackageId();
                info[@"package"] = TserverInfoDictionary(packageResult[@"package"]) ?: @{};
                info[@"online"] = TserverInfoDictionary(onlineResult[@"online"]) ?: @{};
                info[@"onlinePackage"] = TserverInfoDictionary(onlineResult[@"onlinePackage"]) ?: @{};
                if ([keyResult[@"ok"] boolValue]) {
                    NSDictionary *key = TserverInfoDictionary(keyResult[@"key"]);
                    NSArray *keys = TserverInfoArray(keyResult[@"keys"]);
                    if (key) info[@"key"] = key;
                    if (keys) info[@"keys"] = keys;
                    if (!key && keys.count > 0 && [keys[0] isKindOfClass:NSDictionary.class]) {
                        info[@"key"] = keys[0];
                    }
                } else {
                    info[@"keyError"] = keyResult ?: @{};
                }
                TserverInfoComplete(completion, [info copy]);
            };
            if (TserverInfoTrim(licenseKey).length > 0) {
                [self checkKey:licenseKey completion:finish];
            } else {
                [self listKeysWithCompletion:finish];
            }
        }];
    }];
}

+ (NSString *)formatRemainingSeconds:(NSNumber *)seconds
                          isLifetime:(BOOL)isLifetime
                   startsOnActivation:(BOOL)startsOnActivation {
    if (isLifetime) return @"Lifetime";
    if (startsOnActivation) return @"Bat dau tinh khi kich hoat";
    if (!seconds) return @"—";
    NSInteger total = MAX(0, [seconds integerValue]);
    if (total <= 0) return @"Da het han";
    NSInteger days = total / 86400;
    NSInteger hours = (total % 86400) / 3600;
    NSInteger minutes = (total % 3600) / 60;
    if (days > 0) return [NSString stringWithFormat:@"%ld ngay %ld gio", (long)days, (long)hours];
    if (hours > 0) return [NSString stringWithFormat:@"%ld gio %ld phut", (long)hours, (long)minutes];
    return [NSString stringWithFormat:@"%ld phut", (long)MAX(1, minutes)];
}

+ (NSString *)renderTemplate:(NSString *)templateText withInfo:(NSDictionary *)info {
    NSString *output = [templateText isKindOfClass:NSString.class] ? templateText : @"";
    if (output.length == 0) return @"";

    NSDictionary *pkg = TserverInfoDictionary(info[@"package"]) ?: @{};
    NSDictionary *onlinePackage = TserverInfoDictionary(info[@"onlinePackage"]) ?: @{};
    NSDictionary *key = TserverInfoDictionary(info[@"key"]);
    NSArray *keys = TserverInfoArray(info[@"keys"]);
    if (!key && keys.count > 0) key = TserverInfoDictionary(keys[0]);
    key = key ?: @{};

    BOOL isLifetime = TserverInfoBool(key[@"isLifetime"]);
    BOOL startsOnActivation = TserverInfoBool(key[@"startsOnActivation"]);
    NSNumber *remainingSeconds = TserverInfoNumber(key[@"remainingSeconds"]);
    NSString *remainingText = [self formatRemainingSeconds:remainingSeconds
                                                isLifetime:isLifetime
                                         startsOnActivation:startsOnActivation];
    NSString *keyText = TserverInfoString(key[@"licenseKey"]);
    if (keyText.length == 0) keyText = TserverInfoString(key[@"licenseKeyMasked"]);

    NSDictionary *replacements = @{
        @"%tserver_package_id%": TserverInfoPackageId(),
        @"%tserver_member_package_id%": TserverInfoString(pkg[@"id"]),
        @"%tserver_package_name%": TserverInfoString(pkg[@"name"]),
        @"%tserver_package_status%": TserverInfoString(pkg[@"packageStatus"]),
        @"%tserver_bundle_id%": TserverInfoString(pkg[@"bundleId"]),
        @"%tserver_key_count%": TserverInfoString(pkg[@"keyCount"]),
        @"%tserver_keys_count%": [NSString stringWithFormat:@"%lu", (unsigned long)keys.count],
        @"%tserver_online%": TserverInfoString(onlinePackage[@"onlineCount"]),
        @"%tserver_online_last_seen%": TserverInfoString(onlinePackage[@"lastSeenAt"]),
        @"%tserver_key%": keyText,
        @"%tserver_key_id%": TserverInfoString(key[@"id"]),
        @"%tserver_key_masked%": TserverInfoString(key[@"licenseKeyMasked"]),
        @"%tserver_key_status%": TserverInfoString(key[@"computedStatus"]).length > 0 ? TserverInfoString(key[@"computedStatus"]) : TserverInfoString(key[@"status"]),
        @"%tserver_key_raw_status%": TserverInfoString(key[@"status"]),
        @"%tserver_key_type%": TserverInfoString(key[@"licenseType"]),
        @"%tserver_key_remaining%": remainingText,
        @"%tserver_remaining_seconds%": remainingSeconds ? [remainingSeconds stringValue] : @"",
        @"%tserver_device_count%": TserverInfoString(key[@"deviceCount"]),
        @"%tserver_max_devices%": TserverInfoString(key[@"maxDevices"]),
        @"%tserver_expires_at%": TserverInfoString(key[@"effectiveExpiresAt"]).length > 0 ? TserverInfoString(key[@"effectiveExpiresAt"]) : TserverInfoString(key[@"expiresAt"]),
        @"%tserver_created_at%": TserverInfoString(key[@"createdAt"]),
        @"%tserver_starts_on_activation%": startsOnActivation ? @"true" : @"false",
        @"%tserver_is_lifetime%": isLifetime ? @"true" : @"false"
    };

    for (NSString *placeholder in replacements) {
        output = [output stringByReplacingOccurrencesOfString:placeholder withString:TserverInfoString(replacements[placeholder])];
    }
    return output;
}

+ (void)renderTemplate:(NSString *)templateText
            licenseKey:(NSString *)licenseKey
            completion:(TserverMemberInfoTemplateCompletion)completion {
    [self loadInfoForKey:licenseKey completion:^(NSDictionary *result) {
        NSString *rendered = [self renderTemplate:templateText withInfo:result ?: @{}];
        if (!completion) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(rendered ?: @"", result ?: @{});
        });
    }];
}

@end
