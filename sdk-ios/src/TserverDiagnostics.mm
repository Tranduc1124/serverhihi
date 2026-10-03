#import "APIClient.h"
#import "TserverAuthorizationLease.h"
#import "TserverAuth.h"
#import <UIKit/UIKit.h>

/// In-memory diagnostics for integrators and support.
///
/// Design rules, in order of importance:
///  1. Never store a secret. No package token, session token, license key,
///     client private key or signed payload body is ever written here.
///  2. Never print. The SDK already silences console output; this ring buffer is
///     read back only by the host app via TserverRecentEvents / TserverDebugSnapshot.
///  3. Presentation only. Nothing here can grant or extend authorization.
///
/// The auth layer feeds the facts it already knows (status, endpoint host, lease
/// timing) through TserverDiagnosticsUpdateRuntime, so this file never reaches
/// into private storage.

NSNotificationName const TserverStatusDidChangeNotification = @"TserverStatusDidChangeNotification";
NSNotificationName const TserverNoticeDidArriveNotification = @"TserverNoticeDidArriveNotification";
NSNotificationName const TserverNetworkDidChangeNotification = @"TserverNetworkDidChangeNotification";
NSNotificationName const TserverLeaseDidChangeNotification = @"TserverLeaseDidChangeNotification";
NSNotificationName const TserverDiagnosticDidAppendNotification = @"TserverDiagnosticDidAppendNotification";

NSString * const TserverStatusCodeStringUserInfoKey = @"status";
NSString * const TserverStatusEnumUserInfoKey = @"statusEnum";
NSString * const TserverResultUserInfoKey = @"result";
NSString * const TserverNoticeUserInfoKey = @"notice";
NSString * const TserverNetworkOnlineUserInfoKey = @"online";
NSString * const TserverNetworkLatencyMsUserInfoKey = @"latencyMs";
NSString * const TserverLeaseAuthorizedUserInfoKey = @"authorized";
NSString * const TserverLeaseRemainingUserInfoKey = @"remainingSeconds";
NSString * const TserverDiagnosticUserInfoKey = @"entry";

static const NSUInteger TserverDiagnosticsCapacity = 120;

static TserverLogLevel TserverDiagnosticsLevel = TserverLogLevelInfo;

static NSMutableArray<NSDictionary *> *TserverDiagnosticsEvents(void) {
    static NSMutableArray<NSDictionary *> *events = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ events = [NSMutableArray array]; });
    return events;
}

static NSMutableDictionary *TserverDiagnosticsRuntime(void) {
    static NSMutableDictionary *runtime = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ runtime = [NSMutableDictionary dictionary]; });
    return runtime;
}

static NSString *TserverDiagText(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    return trimmed.length > 200 ? [[trimmed substringToIndex:200] stringByAppendingString:@"…"] : trimmed;
}

static BOOL TserverDiagLevelAllows(TserverLogLevel required) {
    if (TserverDiagnosticsLevel == TserverLogLevelOff) return NO;
    return TserverDiagnosticsLevel >= required;
}

static void TserverDiagnosticsAppend(NSString *kind,
                                     NSString *_Nullable message,
                                     NSDictionary *_Nullable fields,
                                     TserverLogLevel required) {
    if (!TserverDiagLevelAllows(required)) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"at"] = @([[NSDate date] timeIntervalSince1970]);
    entry[@"kind"] = TserverDiagText(kind) ?: @"info";
    NSString *safeMessage = TserverDiagText(message);
    if (safeMessage) entry[@"message"] = safeMessage;
    if (fields.count > 0) entry[@"fields"] = [fields copy];

    NSMutableArray<NSDictionary *> *events = TserverDiagnosticsEvents();
    @synchronized (events) {
        [events addObject:[entry copy]];
        while (events.count > TserverDiagnosticsCapacity) [events removeObjectAtIndex:0];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TserverDiagnosticDidAppendNotification
                                                            object:nil
                                                          userInfo:@{ TserverDiagnosticUserInfoKey: [entry copy] }];
    });
}

#pragma mark - Posts

void TserverDiagnosticsPostStatus(NSString *status, NSDictionary *sanitizedResult) {
    TserverStatusCode typed = TserverStatusCodeFromString(status);
    NSString *safeStatus = TserverStatusCodeString(typed);
    NSString *safeMessage = nil;
    if ([sanitizedResult isKindOfClass:NSDictionary.class]) {
        // Only the human readable summary is kept. Key material never reaches it.
        safeMessage = TserverDiagText(sanitizedResult[@"message"]);
    }
    TserverDiagnosticsUpdateRuntime(@{ @"lastStatus": safeStatus });
    TserverDiagnosticsAppend(@"status", safeMessage.length > 0 ? safeMessage : safeStatus, @{
        @"status": safeStatus,
        @"statusEnum": @(typed),
        @"valid": @(TserverStatusCodeIsValid(typed))
    }, safeMessage.length > 0 ? TserverLogLevelInfo : TserverLogLevelError);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[TserverStatusCodeStringUserInfoKey] = safeStatus;
        userInfo[TserverStatusEnumUserInfoKey] = @(typed);
        if ([sanitizedResult isKindOfClass:NSDictionary.class]) {
            userInfo[TserverResultUserInfoKey] = [sanitizedResult copy];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:TserverStatusDidChangeNotification
                                                            object:nil
                                                          userInfo:[userInfo copy]];
    });
}

void TserverDiagnosticsPostNotice(NSDictionary *notice) {
    if (![notice isKindOfClass:NSDictionary.class]) return;
    TserverDiagnosticsAppend(@"notice", notice[@"title"], @{
        @"noticeId": TserverDiagText(notice[@"id"]) ?: @"",
        @"type": TserverDiagText(notice[@"type"]) ?: @"info"
    }, TserverLogLevelInfo);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TserverNoticeDidArriveNotification
                                                            object:nil
                                                          userInfo:@{ TserverNoticeUserInfoKey: [notice copy] }];
    });
}

void TserverDiagnosticsPostNetwork(BOOL online, NSTimeInterval latencyMs) {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    fields[TserverNetworkOnlineUserInfoKey] = @(online);
    if (latencyMs > 0) fields[TserverNetworkLatencyMsUserInfoKey] = @((NSInteger)llround(latencyMs));
    TserverDiagnosticsAppend(@"network", online ? @"reachable" : @"unreachable", [fields copy],
                             online ? TserverLogLevelInfo : TserverLogLevelError);
    NSMutableDictionary *runtimeUpdate = [NSMutableDictionary dictionary];
    runtimeUpdate[@"online"] = @(online);
    if (latencyMs > 0) runtimeUpdate[@"lastLatencyMs"] = @((NSInteger)llround(latencyMs));
    runtimeUpdate[@"lastRequestAt"] = @([[NSDate date] timeIntervalSince1970]);
    TserverDiagnosticsUpdateRuntime([runtimeUpdate copy]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TserverNetworkDidChangeNotification
                                                            object:nil
                                                          userInfo:[fields copy]];
    });
}

void TserverDiagnosticsPostLease(BOOL authorized, NSTimeInterval remainingSeconds) {
    TserverDiagnosticsAppend(@"lease", authorized ? @"authorized" : @"invalidated", @{
        TserverLeaseAuthorizedUserInfoKey: @(authorized),
        TserverLeaseRemainingUserInfoKey: @(remainingSeconds > 0 ? (NSInteger)llround(remainingSeconds) : 0)
    }, TserverLogLevelInfo);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TserverLeaseDidChangeNotification
                                                            object:nil
                                                          userInfo:@{
                                                              TserverLeaseAuthorizedUserInfoKey: @(authorized),
                                                              TserverLeaseRemainingUserInfoKey:
                                                                  @(remainingSeconds > 0 ? (NSInteger)llround(remainingSeconds) : 0)
                                                          }];
    });
}

void TserverDiagnosticsRecord(NSString *kind, NSString *message, NSDictionary *fields) {
    TserverDiagnosticsAppend(kind, message, fields, TserverLogLevelDebug);
}

void TserverDiagnosticsUpdateRuntime(NSDictionary *fields) {
    if (![fields isKindOfClass:NSDictionary.class] || fields.count == 0) return;
    static NSSet<NSString *> *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSSet setWithArray:@[@"lastStatus", @"online", @"lastLatencyMs", @"lastRequestAt",
                                       @"packageTemplate", @"bundleId", @"endpointHost"]];
    });
    NSMutableDictionary *safe = [NSMutableDictionary dictionary];
    for (NSString *key in fields) {
        if (![allowed containsObject:key]) continue;
        id value = fields[key];
        if ([value isKindOfClass:NSString.class]) {
            NSString *text = TserverDiagText(value);
            if (text) safe[key] = text;
        } else if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSDate.class]) {
            safe[key] = value;
        }
    }
    if (safe.count == 0) return;
    @synchronized (TserverDiagnosticsRuntime()) {
        [TserverDiagnosticsRuntime() addEntriesFromDictionary:safe];
    }
}

#pragma mark - Read back

NSArray<NSDictionary *> *TserverRecentEvents(NSUInteger limit) {
    NSMutableArray<NSDictionary *> *events = TserverDiagnosticsEvents();
    @synchronized (events) {
        if (limit == 0 || limit >= events.count) return [events copy];
        return [events subarrayWithRange:NSMakeRange(events.count - limit, limit)];
    }
}

void TserverSetLogLevel(TserverLogLevel level) {
    TserverDiagnosticsLevel = level;
    TserverDiagnosticsRecord(@"config", @"log level changed", @{ @"level": @(level) });
}

TserverLogLevel TserverCurrentLogLevel(void) {
    return TserverDiagnosticsLevel;
}

NSDictionary *TserverDebugSnapshot(void) {
    NSDictionary *licenseInfo = TserverAuthorizationLeaseLicenseInfo();
    BOOL authorized = TserverAuthorizationLeaseIsAuthorized();

    NSMutableDictionary *runtime = [NSMutableDictionary dictionary];
    @synchronized (TserverDiagnosticsRuntime()) {
        [runtime addEntriesFromDictionary:TserverDiagnosticsRuntime()];
    }

    NSInteger statusChanges = 0;
    NSInteger noticesShown = 0;
    NSInteger networkFailures = 0;
    for (NSDictionary *entry in TserverRecentEvents(0)) {
        NSString *kind = entry[@"kind"];
        if ([kind isEqualToString:@"status"]) statusChanges += 1;
        if ([kind isEqualToString:@"notice"]) noticesShown += 1;
        if ([kind isEqualToString:@"network"] && ![entry[@"fields"][@"online"] boolValue]) networkFailures += 1;
    }

    NSString *remaining = TserverDiagText(licenseInfo[@"remainingSeconds"]);
    return @{
        @"sdkVersion": TserverDiagText(TserverSDKBuildIdentifier) ?: @"unknown",
        @"status": TserverStatusCodeString(TserverStatusCodeFromString(runtime[@"lastStatus"])),
        @"leaseAuthorized": @(authorized),
        @"leaseRemainingSeconds": remaining.length > 0 ? @(remaining.integerValue) : @0,
        @"endpointHost": runtime[@"endpointHost"] ?: @"unknown",
        @"packageTemplate": runtime[@"packageTemplate"] ?: @"unknown",
        @"bundleId": runtime[@"bundleId"] ?: @"unknown",
        @"online": runtime[@"online"] ?: @NO,
        @"lastLatencyMs": runtime[@"lastLatencyMs"] ?: @0,
        @"lastRequestAt": runtime[@"lastRequestAt"] ?: @0,
        @"osVersion": TserverDiagText(UIDevice.currentDevice.systemVersion) ?: @"unknown",
        @"counts": @{
            @"statusChanges": @(statusChanges),
            @"noticesShown": @(noticesShown),
            @"networkFailures": @(networkFailures)
        },
        @"logLevel": @(TserverDiagnosticsLevel)
    };
}
