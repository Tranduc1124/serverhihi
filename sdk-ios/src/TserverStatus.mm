#import "APIClient.h"

/// Single source of truth for the SDK's status vocabulary.
///
/// The wire format stays a string (older servers and older app sources depend on
/// it); this table only adds a typed view so integrators stop hard-coding
/// literals that can never match. The order here is the order of the enum in
/// APIClient.h and must stay in sync with it.
typedef struct {
    __unsafe_unretained NSString *name;
    TserverStatusCode status;
} TserverStatusTableEntry;

static NSArray<NSString *> *TserverStatusTable(void) {
    static NSArray<NSString *> *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @[
            @"UNKNOWN",
            @"VALID",
            @"OFFLINE_GRACE_VALID",
            @"NEED_UUID",
            @"NEED_KEY",
            @"INVALID_KEY",
            @"EXPIRED",
            @"OFFLINE_GRACE_EXPIRED",
            @"PROFILE_EXPIRED",
            @"REVOKED",
            @"DEVICE_BLOCKED",
            @"DEVICE_MISMATCH",
            @"UPDATE_REQUIRED",
            @"NETWORK_ERROR",
            @"SERVER_ERROR",
            @"RATE_LIMITED",
            @"VALIDATION_ERROR",
            @"BAD_RESPONSE_SIGNATURE",
            @"AUTHORIZATION_LEASE_INVALID",
            @"UNSAFE_ENVIRONMENT",
            @"MAINTENANCE",
            @"APP_DISABLED",
            @"STORE_DISABLED",
            @"PACKAGE_DISABLED",
            @"PACKAGE_MAINTENANCE",
            @"PACKAGE_BUNDLE_DENIED",
            @"BAD_PACKAGE_SESSION",
            @"INVALID_API_KEY",
            @"CLIENT_KEY_UNAVAILABLE",
            @"MISSING_AUTH_CONFIG",
            @"RETURN_SCHEME_NOT_REGISTERED",
            @"UI_FAILURE",
            @"NOTICE"
        ];
    });
    return table;
}

static NSString *TserverStatusCanonical(NSString *status) {
    if (![status isKindOfClass:NSString.class]) return @"UNKNOWN";
    NSString *trimmed = [status stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? [trimmed uppercaseString] : @"UNKNOWN";
}

TserverStatusCode TserverStatusCodeFromString(NSString *status) {
    NSString *canonical = TserverStatusCanonical(status);
    NSArray<NSString *> *table = TserverStatusTable();
    NSUInteger index = [table indexOfObject:canonical];
    if (index == NSNotFound || index >= (NSUInteger)TserverStatusCodeNotice + 1) return TserverStatusCodeUnknown;
    return (TserverStatusCode)index;
}

NSString *TserverStatusCodeString(TserverStatusCode status) {
    NSArray<NSString *> *table = TserverStatusTable();
    NSInteger index = (NSInteger)status;
    if (index < 0 || index >= (NSInteger)table.count) return @"UNKNOWN";
    return table[(NSUInteger)index];
}

NSArray<NSString *> *TserverStatusCodeAllStrings(void) {
    return TserverStatusTable();
}

BOOL TserverStatusCodeIsValid(TserverStatusCode status) {
    return status == TserverStatusCodeValid || status == TserverStatusCodeOfflineGraceValid;
}

BOOL TserverStatusCodeNeedsKey(TserverStatusCode status) {
    return status == TserverStatusCodeNeedKey || status == TserverStatusCodeInvalidKey;
}
