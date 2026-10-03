#define APICLIENT_NO_AUTO_SETUP 1
#import "APIClient.h"
#import "TserverAuthorizationLease.h"
#import "TserverFridaGuard.h"
#import "TserverAuthBootstrap.h"
#import "TserverAuth.h"
#import "TserverUUIDCallback.h"
#import "TserverCallbackDedup.h"
#import "TserverAuthorizationLease.h"
#import "TserverActivationAttempt.h"
#import "TserverSealedConstants.h"
#import "TserverStringCrypto.h"
#import "TserverGateUI.h"

@interface TserverStorage : NSObject
+ (NSDictionary *)lastValidPayload;
@end

static id APIClientTerminalObserver = nil;
static APIClientTerminalEventBlock APIClientTerminalHandler = nil;
static NSMutableArray<NSURL *> *APIClientPendingCallbackURLs = nil;

static BOOL APIClientCallbackShapeIsValid(NSURL *url) {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path.lowercaseString ?: @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789+.-"];
    BOOL schemeLooksSupported = scheme.length >= 2 && scheme.length <= 64 &&
        [scheme rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
    const char *issuer = TserverSealedStringAt(kTserverSealedStr_Issuer);
    NSString *expectedHost = (issuer && issuer[0]) ? @(issuer) : TS_OBF_NS("tserver");
    BOOL routeLooksSupported = ([host isEqualToString:expectedHost] || host.length == 0) &&
        ([path containsString:TS_OBF_NS("callback")] || [path isEqualToString:@"/"] || path.length == 0);
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    BOOL hasSessionToken = NO;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:TS_OBF_NS("sessionToken")] && item.value.length >= 16 && item.value.length <= 1024) {
            hasSessionToken = YES;
            break;
        }
    }
    return schemeLooksSupported && routeLooksSupported && hasSessionToken;
}

void TserverAuthDrainPendingCallbackURLs(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSURL *> *pending;
        @synchronized(NSProcessInfo.processInfo) {
            pending = [APIClientPendingCallbackURLs copy] ?: @[];
            [APIClientPendingCallbackURLs removeAllObjects];
        }
        for (NSURL *url in pending) {
            if (!TserverCallbackURLShouldProcess(url)) continue;
            BOOL accepted = [TserverUUIDCallback handleIncomingURL:url];
            TserverCallbackURLCommit(url, accepted);
        }
    });
}

static NSString *APIClientString(id value) {
    if ([value isKindOfClass:NSString.class]) return (NSString *)value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSNumber *APIClientNumber(id value) {
    if ([value isKindOfClass:NSNumber.class]) return (NSNumber *)value;
    if ([value isKindOfClass:NSString.class]) return @([(NSString *)value doubleValue]);
    return nil;
}

static NSString *APIClientBoundedString(id value, NSUInteger maximumLength) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *text = (NSString *)value;
    if (text.length > maximumLength) text = [text substringToIndex:maximumLength];
    return text ?: @"";
}

static id APIClientSafeScalar(id value) {
    if ([value isKindOfClass:NSString.class]) return APIClientBoundedString(value, 512);
    if ([value isKindOfClass:NSNumber.class] || value == NSNull.null) return value;
    return nil;
}

static NSDictionary *APIClientSafeLicensePayload(NSDictionary *source) {
    if (![source isKindOfClass:NSDictionary.class]) return @{};
    NSArray<NSString *> *keys = @[
        @"licenseRef", @"maskedKey", @"licenseKeyMasked", @"licenseType",
        @"expiresAt", @"effectiveExpiresAt", @"licenseExpiresAt", @"maxDevices",
        @"isLifetime", @"startsOnActivation", @"remainingSeconds", @"features"
    ];
    NSMutableDictionary *safe = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = source[key];
        if ([key isEqualToString:@"features"] && [value isKindOfClass:NSArray.class]) {
            NSMutableArray *features = [NSMutableArray array];
            for (id feature in (NSArray *)value) {
                if (features.count >= 32) break;
                id safeFeature = APIClientSafeScalar(feature);
                if (safeFeature) [features addObject:safeFeature];
            }
            if (features.count > 0) safe[key] = [features copy];
        } else {
            id safeValue = APIClientSafeScalar(value);
            if (safeValue) safe[key] = safeValue;
        }
    }
    return [safe copy];
}

static NSDictionary *APIClientSafeResult(NSDictionary *result) {
    NSDictionary *source = [result isKindOfClass:NSDictionary.class] ? result : @{};
    NSString *status = APIClientBoundedString(source[@"status"], 64);
    if (status.length == 0) status = TserverStatusServerError;
    BOOL sourceOK = [source[@"ok"] respondsToSelector:@selector(boolValue)] && [source[@"ok"] boolValue];
    BOOL leasePaid = TserverAuthorizationLeaseAllowsCapability(@"paid");
    BOOL valid = sourceOK && [status isEqualToString:TserverStatusValid] && leasePaid;
    if (!valid && [status isEqualToString:TserverStatusValid]) status = TserverStatusAuthorizationLeaseInvalid;

    NSMutableDictionary *safe = [NSMutableDictionary dictionary];
    safe[@"ok"] = @(valid);
    safe[@"status"] = status;
    safe[@"terminal"] = @YES;
    for (NSString *key in @[@"message", @"errorCode", @"stage", @"diagnosticId", @"requestId", @"updateUrl"]) {
        id value = source[key];
        id safeValue = APIClientSafeScalar(value);
        if (safeValue) safe[key] = safeValue;
    }
    if (valid) {
        NSDictionary *license = APIClientSafeLicensePayload(TserverAuthorizationLeaseLicenseInfo());
        if (license.count > 0) safe[@"license"] = license;
        if (safe[@"message"] == nil) safe[@"message"] = @"Key hợp lệ.";
    }
    return [safe copy];
}

static NSString *APIClientSafeResultJSON(NSDictionary *result) {
    NSDictionary *safe = APIClientSafeResult(result);
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:nil];
    if (data.length == 0) return @"{\"ok\":false,\"status\":\"SERVER_ERROR\"}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{\"ok\":false,\"status\":\"SERVER_ERROR\"}";
}

static void APIClientSendJSONCallback(apiclient_dict_callback callback, NSDictionary *result) {
    if (!callback) return;
    NSString *json = APIClientSafeResultJSON(result);
    dispatch_async(dispatch_get_main_queue(), ^{
        const char *utf8 = json.UTF8String;
        if (utf8) callback(utf8);
    });
}

static NSDictionary *APIClientFailureResult(NSString *status, NSString *message, NSString *errorCode) {
    return @{
        @"ok": @NO,
        @"terminal": @YES,
        @"status": status.length > 0 ? status : TserverStatusServerError,
        @"message": message.length > 0 ? message : @"Xác nhận key thất bại.",
        @"errorCode": errorCode.length > 0 ? errorCode : @"key_confirmation_failed"
    };
}

static NSDictionary *APIClientLicensePayload(void) {
    NSDictionary *lease = TserverAuthorizationLeaseLicenseInfo();
    if (lease.count > 0) return lease;
    NSDictionary *payload = [TserverStorage lastValidPayload];
    NSDictionary *license = [payload[@"license"] isKindOfClass:NSDictionary.class] ? payload[@"license"] : nil;
    return license ?: @{};
}

static NSString *APIClientFormatRemainingSeconds(NSNumber *seconds, BOOL isLifetime, BOOL startsOnActivation) {
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

void APIClientConfigure(NSString *packageToken) {
    TserverAuthBootstrapConfigure(packageToken);
}

void APIClientStartAuthorizationWithEvents(dispatch_block_t onAuthorized,
                                           dispatch_block_t onRevoked,
                                           APIClientTerminalEventBlock onTerminal) {
    [TserverGateUI showLoadingWithMessage:@"Đang kiểm tra bản quyền…"];
    __block BOOL deliveredAuthorized = NO;
    if (APIClientTerminalObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:APIClientTerminalObserver];
        APIClientTerminalObserver = nil;
    }
    APIClientTerminalHandler = [onTerminal copy];
    if (APIClientTerminalHandler) {
        APIClientTerminalObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:TserverActivationAttemptDidFinishNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
            NSDictionary *result = [note.userInfo[@"result"] isKindOfClass:NSDictionary.class]
                ? note.userInfo[@"result"]
                : @{
                    @"ok": @NO,
                    @"terminal": @YES,
                    @"status": TserverStatusServerError,
                    @"errorCode": @"empty_terminal_event"
                };
            // Public terminal events use the same bounded projection as the Logos JSON
            // callback; never forward session/bearer material.
            APIClientTerminalEventBlock handler = APIClientTerminalHandler;
             if (handler) handler(APIClientSafeResult(result));
        }];
    }
    TserverAuthorizationLeaseSetRevocationHandler(^(TserverAuthorizationState state) {
        (void)state;
        if (!deliveredAuthorized) return;
        deliveredAuthorized = NO;
        if (onRevoked) onRevoked();
    });
    TserverAuthBootstrapStart(^{
        if (TserverAuthorizationLeaseAllowsCapability(@"paid")) {
            deliveredAuthorized = YES;
            if (onAuthorized) onAuthorized();
        }
    });
}

void APIClientStartAuthorization(dispatch_block_t onAuthorized, dispatch_block_t onRevoked) {
    APIClientStartAuthorizationWithEvents(onAuthorized, onRevoked, nil);
}

BOOL APIClientPerformAuthorized(NSString *capability, dispatch_block_t work, dispatch_block_t denied) {
    return TserverAuthorizationLeasePerformCapability(capability ?: @"paid", work, denied);
}

static NSString *APIClientNormalizedInputKey(NSString *key) {
    NSString *normalized = [key isKindOfClass:NSString.class]
        ? [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    if (normalized.length == 0 || normalized.length > 512) return nil;
    for (NSUInteger index = 0; index < normalized.length; index++) {
        unichar character = [normalized characterAtIndex:index];
        if (character < 0x20 || character == 0x7f) return nil;
    }
    return normalized;
}

void APIClientOpenPaid(dispatch_block_t onPaid) {
    APIClientStartAuthorization(^{
        // A bootstrap callback is a transition notification, not the final
        // capability decision. Re-check the signed lease at the paid boundary.
        APIClientPerformAuthorized(@"paid", onPaid, nil);
    }, nil);
}

void APIClientConfirmKey(NSString *key,
                          APIClientTerminalEventBlock success,
                          APIClientTerminalEventBlock failure) {
    NSString *normalizedKey = APIClientNormalizedInputKey(key);
    if (!normalizedKey) {
        NSDictionary *result = APIClientFailureResult(
            TserverStatusInvalidKey,
            @"Key không hợp lệ.",
            @"invalid_key_input"
        );
        if (failure) dispatch_async(dispatch_get_main_queue(), ^{ failure(APIClientSafeResult(result)); });
        return;
    }
    if (!success && !failure) return;

    __block BOOL finished = NO;
    void (^finish)(NSDictionary *, BOOL) = ^(NSDictionary *result, BOOL ok) {
        if (finished) return;
        finished = YES;
        NSDictionary *safe = APIClientSafeResult(result);
        if (ok && [safe[@"ok"] boolValue]) {
            if (success) success(safe);
        } else if (failure) {
            failure(safe);
        }
    };

    TserverAuthBootstrapStartWithPrepared(nil, ^(NSDictionary *preparedResult) {
        if (finished) return;
        if (preparedResult) {
            finish(preparedResult, NO);
            return;
        }
        uint64_t leaseGenerationBeforeActivation = TserverAuthorizationLeaseGeneration();
        [TserverAuth activateKey:normalizedKey completion:^(NSDictionary *result) {
            NSDictionary *safe = APIClientSafeResult(result);
            uint64_t leaseGenerationAfterActivation = TserverAuthorizationLeaseGeneration();
            BOOL freshLease = leaseGenerationAfterActivation > leaseGenerationBeforeActivation;
            if ([safe[@"ok"] boolValue] && !freshLease) {
                NSMutableDictionary *stale = [safe mutableCopy];
                stale[@"ok"] = @NO;
                stale[@"status"] = TserverStatusAuthorizationLeaseInvalid;
                stale[@"message"] = @"Lease xác nhận không còn hiệu lực cho key vừa kiểm tra.";
                stale[@"errorCode"] = @"stale_authorization_lease";
                safe = [stale copy];
            }
            finish(safe, [safe[@"ok"] boolValue]);
        }];
    });
}

void apiclient_paid(apiclient_callback callback) {
    APIClientOpenPaid(^{
        if (callback) callback();
    });
}

void apiclient_on_login(const char *inputKey,
                         apiclient_dict_callback success,
                         apiclient_dict_callback failure) {
    NSString *key = inputKey ? [NSString stringWithUTF8String:inputKey] : @"";
    APIClientConfirmKey(key, ^(NSDictionary *result) {
        APIClientSendJSONCallback(success, result);
    }, ^(NSDictionary *result) {
        APIClientSendJSONCallback(failure, result);
    });
}

void APIClientStart(dispatch_block_t onPaid) {
    APIClientOpenPaid(onPaid);
}

BOOL APIClientIsValid(void) {
    return TserverAuthorizationLeaseIsAuthorized();
}

BOOL APIClientHandleOpenURL(NSURL *url) {
    if (!APIClientCallbackShapeIsValid(url)) {
        if (url) {
            [TserverActivationAttempt publishTerminalResult:@{
                @"ok": @NO,
                @"status": TserverStatusCallbackFailure,
                @"stage": @"callback",
                @"errorCode": @"callback_shape_rejected",
                @"message": @"Callback URL không hợp lệ."
            }];
        }
        return NO;
    }
    if ([TserverAuth configuredReturnScheme].length == 0) {
        @synchronized(NSProcessInfo.processInfo) {
            APIClientPendingCallbackURLs = APIClientPendingCallbackURLs ?: [NSMutableArray array];
            NSString *candidate = url.absoluteString ?: @"";
            BOOL duplicate = NO;
            for (NSURL *pending in APIClientPendingCallbackURLs) {
                if ([pending.absoluteString isEqualToString:candidate]) {
                    duplicate = YES;
                    break;
                }
            }
            if (!duplicate) {
                if (APIClientPendingCallbackURLs.count >= 4) [APIClientPendingCallbackURLs removeObjectAtIndex:0];
                [APIClientPendingCallbackURLs addObject:url];
            }
        }
        return YES;
    }
    if (!TserverCallbackURLShouldProcess(url)) return YES;
    BOOL accepted = [TserverUUIDCallback handleIncomingURL:url];
    TserverCallbackURLCommit(url, accepted);
    if (!accepted) {
        [TserverActivationAttempt publishTerminalResult:@{
            @"ok": @NO,
            @"status": TserverStatusCallbackFailure,
            @"stage": @"callback",
            @"errorCode": @"callback_context_rejected",
            @"message": @"Callback không khớp phiên hoặc ứng dụng hiện tại."
        }];
    }
    return accepted;
}

@implementation APIClient

+ (void)start:(dispatch_block_t)onPaid {
    APIClientStartAuthorization(onPaid, nil);
}

+ (void)startAuthorization:(dispatch_block_t)onAuthorized
                 onRevoked:(dispatch_block_t)onRevoked {
    APIClientStartAuthorization(onAuthorized, onRevoked);
}

+ (void)startAuthorization:(dispatch_block_t)onAuthorized
                 onRevoked:(dispatch_block_t)onRevoked
                onTerminal:(APIClientTerminalEventBlock)onTerminal {
    APIClientStartAuthorizationWithEvents(onAuthorized, onRevoked, onTerminal);
}

+ (BOOL)performAuthorized:(NSString *)capability
                     work:(dispatch_block_t)work
                   denied:(dispatch_block_t)denied {
    return APIClientPerformAuthorized(capability, work, denied);
}

+ (void)openPaid:(dispatch_block_t)onPaid {
    APIClientOpenPaid(onPaid);
}

+ (void)confirmKey:(NSString *)key
          success:(APIClientTerminalEventBlock)success
          failure:(APIClientTerminalEventBlock)failure {
    APIClientConfirmKey(key, success, failure);
}

+ (void)paid:(dispatch_block_t)onPaid {
    APIClientOpenPaid(onPaid);
}

+ (BOOL)isValid {
    return APIClientIsValid();
}

void APIClientSetFridaGuardEnabled(BOOL enabled) {
    [TserverFridaGuard setEnabled:enabled];
}

BOOL APIClientFridaGuardEnabled(void) {
    return [TserverFridaGuard isEnabled];
}

+ (TserverStatusCode)currentStatus {
    NSArray<NSDictionary *> *events = TserverRecentEvents(6);
    for (NSDictionary *entry in events.reverseObjectEnumerator.allObjects) {
        if (![entry[@"kind"] isEqualToString:@"status"]) continue;
        NSString *status = entry[@"fields"][@"status"];
        if ([status isKindOfClass:NSString.class]) return TserverStatusCodeFromString(status);
    }
    // Nothing observed yet: report the live lease instead of a blind "unknown".
    return TserverAuthorizationLeaseIsAuthorized() ? TserverStatusCodeValid : TserverStatusCodeUnknown;
}

+ (NSDictionary *)debugSnapshot {
    return TserverDebugSnapshot();
}

+ (NSArray<NSDictionary *> *)recentEvents:(NSUInteger)limit {
    return TserverRecentEvents(limit);
}

+ (NSDictionary *)currentKeyInfo {
    return APIClientLicensePayload();
}

+ (NSString *)currentKeyText {
    NSDictionary *license = APIClientLicensePayload();
    NSString *raw = APIClientString(license[@"licenseKey"]);
    if (raw.length > 0) return raw;
    NSString *masked = APIClientString(license[@"maskedKey"]);
    return masked.length > 0 ? masked : APIClientString(license[@"licenseKeyMasked"]);
}

+ (NSString *)currentKeyRemainingText {
    NSDictionary *license = APIClientLicensePayload();
    BOOL isLifetime = [license[@"isLifetime"] respondsToSelector:@selector(boolValue)] && [license[@"isLifetime"] boolValue];
    BOOL startsOnActivation = [license[@"startsOnActivation"] respondsToSelector:@selector(boolValue)] && [license[@"startsOnActivation"] boolValue];
    return APIClientFormatRemainingSeconds(APIClientNumber(license[@"remainingSeconds"]), isLifetime, startsOnActivation);
}

+ (NSInteger)currentKeyMaxDevices {
    NSInteger maxDevices = [APIClientNumber(APIClientLicensePayload()[@"maxDevices"]) integerValue];
    return MAX(0, maxDevices);
}

+ (NSString *)renderTemplate:(NSString *)templateText {
    return APIClientRenderTemplate(templateText);
}

@end

NSString *APIClientRenderTemplate(NSString *templateText) {
    NSString *input = [templateText isKindOfClass:NSString.class] ? templateText : @"";
    if (input.length == 0) return @"";

    NSDictionary *license = APIClientLicensePayload();
    NSString *masked = APIClientString(license[@"maskedKey"]);
    if (masked.length == 0) masked = APIClientString(license[@"licenseKeyMasked"]);
    if (masked.length == 0) masked = APIClientString(license[@"licenseKey"]);

    BOOL isLifetime = [license[@"isLifetime"] respondsToSelector:@selector(boolValue)] && [license[@"isLifetime"] boolValue];
    BOOL startsOnActivation = [license[@"startsOnActivation"] respondsToSelector:@selector(boolValue)] && [license[@"startsOnActivation"] boolValue];
    NSNumber *remainingSeconds = APIClientNumber(license[@"remainingSeconds"]);
    if (!remainingSeconds) {
        // Lease carries licenseExpiresAt (ISO / epoch); derive remaining for menu labels.
        id expiresRaw = license[@"effectiveExpiresAt"] ?: license[@"licenseExpiresAt"] ?: license[@"expiresAt"];
        if ([expiresRaw isKindOfClass:NSNumber.class]) {
            NSTimeInterval exp = [(NSNumber *)expiresRaw doubleValue];
            // Heuristic: values > 1e12 are ms; > 1e9 are seconds; otherwise treat as relative seconds.
            if (exp > 1000000000000.0) exp /= 1000.0;
            if (exp > 1000000000.0) {
                remainingSeconds = @((NSInteger)MAX(0, floor(exp - NSDate.date.timeIntervalSince1970)));
            } else if (exp > 0) {
                remainingSeconds = @((NSInteger)MAX(0, floor(exp)));
            }
        } else if ([expiresRaw isKindOfClass:NSString.class] && [(NSString *)expiresRaw length] > 0) {
            NSString *text = (NSString *)expiresRaw;
            NSDate *date = nil;
            NSDateFormatter *iso = [[NSDateFormatter alloc] init];
            iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            iso.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
            date = [iso dateFromString:text];
            if (!date) {
                iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
                date = [iso dateFromString:text];
            }
            if (!date) {
                // NSISO8601DateFormatter is iOS 10+; keep selector check for older toolchains.
                if ([NSISO8601DateFormatter class]) {
                    date = [[[NSISO8601DateFormatter alloc] init] dateFromString:text];
                }
            }
            if (date) {
                remainingSeconds = @((NSInteger)MAX(0, floor(date.timeIntervalSince1970 - NSDate.date.timeIntervalSince1970)));
            }
        }
    }

    // Lifetime / unactivated flags may only exist on member-api payloads; infer from lease type when absent.
    NSString *licenseType = APIClientString(license[@"licenseType"]).lowercaseString;
    if (!isLifetime && ([licenseType containsString:@"lifetime"] || [licenseType isEqualToString:@"forever"])) {
        isLifetime = YES;
    }

    NSString *remainingText = APIClientFormatRemainingSeconds(remainingSeconds, isLifetime, startsOnActivation);
    NSString *maxDevices = [NSString stringWithFormat:@"%ld", (long)MAX(0, [APIClientNumber(license[@"maxDevices"]) integerValue])];
    NSString *remainingSecondsText = remainingSeconds ? [remainingSeconds stringValue] : @"";
    NSString *licenseRef = APIClientString(license[@"licenseRef"]);
    NSString *licenseTypeRaw = APIClientString(license[@"licenseType"]);
    id expiresDisplay = license[@"effectiveExpiresAt"] ?: license[@"licenseExpiresAt"] ?: license[@"expiresAt"];
    NSString *expiresAtText = @"";
    if ([expiresDisplay isKindOfClass:NSString.class]) {
        expiresAtText = (NSString *)expiresDisplay;
    } else if ([expiresDisplay isKindOfClass:NSNumber.class] && ![(NSNumber *)expiresDisplay isEqual:NSNull.null]) {
        expiresAtText = [(NSNumber *)expiresDisplay stringValue];
    }
    if ([expiresAtText isEqualToString:@"<null>"]) expiresAtText = @"";

    NSArray *features = [license[@"features"] isKindOfClass:NSArray.class] ? license[@"features"] : @[];
    NSMutableArray<NSString *> *caps = [NSMutableArray array];
    for (id item in features) {
        NSString *cap = APIClientString(item);
        if (cap.length > 0) [caps addObject:cap];
    }
    NSString *capabilitiesText = [caps componentsJoinedByString:@", "];
    BOOL leaseLive = TserverAuthorizationLeaseIsAuthorized();
    NSString *statusText = leaseLive ? @"VALID" : @"";

    NSDictionary *replacements = @{
        @"%tserver_timekeyt%": remainingText ?: @"—",
        @"%tserver_key_remaining%": remainingText ?: @"—",
        @"%tserver_remaining_seconds%": remainingSecondsText ?: @"",
        @"%tserver_key%": masked ?: @"",
        @"%tserver_key_masked%": masked ?: @"",
        @"%tserver_key_type%": licenseTypeRaw ?: @"",
        @"%tserver_license_type%": licenseTypeRaw ?: @"",
        @"%tserver_key_id%": licenseRef ?: @"",
        @"%tserver_license_ref%": licenseRef ?: @"",
        @"%tserver_key_status%": statusText ?: @"",
        @"%tserver_expires_at%": expiresAtText ?: @"",
        @"%tserver_max_devices%": maxDevices ?: @"0",
        @"%tserver_is_lifetime%": isLifetime ? @"true" : @"false",
        @"%tserver_starts_on_activation%": startsOnActivation ? @"true" : @"false",
        @"%tserver_capabilities%": capabilitiesText ?: @""
    };

    NSString *output = input;
    for (NSString *placeholder in replacements) {
        output = [output stringByReplacingOccurrencesOfString:placeholder
                                                   withString:APIClientString(replacements[placeholder])];
    }
    return output ?: @"";
}
