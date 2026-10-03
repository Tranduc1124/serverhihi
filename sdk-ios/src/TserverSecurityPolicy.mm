#import "TserverSecurityPolicy.h"
#import "TserverLogGuard.h"
#import "TserverAntiHook.h"
#import "TserverAntiPatch.h"
#import "TserverPinning.h"
#import <stdlib.h>

static NSDictionary *gPolicy = nil;
static NSDictionary *gPackageSettings = nil;
static BOOL gHookKill = YES;
static BOOL gLogKill = YES;
static BOOL gForceUpdate = NO;
static NSInteger gMinSdkBuild = 0;
static BOOL gRequireTransportSession = NO;
static BOOL gAllowWithoutKey = NO;
static BOOL gHideScreenCapture = NO;
static BOOL gProtectScreenContent = NO;
static BOOL gRequireLatestSdk = NO;
static NSString *gForceUpdateUrl = nil;
static NSInteger gMinTransportVersion = 3;
static NSArray<NSString *> *gTlsSpkiPins = nil;
static NSArray<NSString *> *gAcceptedClientIdentityKids = nil;

static NSArray<NSString *> *TserverPolicyStringArray(NSDictionary *row, NSString *key) {
    id v = row[key];
    if (![v isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id item in (NSArray *)v) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *s = [(NSString *)item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (s.length == 0) continue;
        [out addObject:s];
    }
    return [out copy];
}

static BOOL TserverPolicyBool(NSDictionary *row, NSString *key, BOOL fallback) {
    id v = row[key];
    if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v boolValue];
    if ([v isKindOfClass:NSString.class]) {
        NSString *s = [(NSString *)v lowercaseString];
        if ([s isEqualToString:@"1"] || [s isEqualToString:@"true"] || [s isEqualToString:@"yes"]) return YES;
        if ([s isEqualToString:@"0"] || [s isEqualToString:@"false"] || [s isEqualToString:@"no"]) return NO;
    }
    return fallback;
}

static NSInteger TserverPolicyInt(NSDictionary *row, NSString *key, NSInteger fallback) {
    id v = row[key];
    if ([v respondsToSelector:@selector(integerValue)]) return [v integerValue];
    return fallback;
}

static void TserverApplyPackageSettings(NSDictionary *row) {
    if (![row isKindOfClass:NSDictionary.class]) return;
    gAllowWithoutKey = TserverPolicyBool(row, @"allowWithoutKey", NO);
    gHideScreenCapture = TserverPolicyBool(row, @"hideScreenCapture", NO);
    gProtectScreenContent = TserverPolicyBool(row, @"protectScreenContent", NO);
    gRequireLatestSdk = TserverPolicyBool(row, @"requireLatestSdk", NO);
    id url = row[@"forceUpdateUrl"];
    gForceUpdateUrl = [url isKindOfClass:NSString.class] && [(NSString *)url length] > 0 ? [(NSString *)url copy] : nil;
    gPackageSettings = [row copy];
    // requireLatestSdk is server-enforced via version compare on bootstrap.
    // Do NOT latch it into local forceUpdate — that would block later auth in the
    // same process even when this client already satisfies the published SDK.
}

void TserverSecurityPolicyApplyFromResponse(NSDictionary *response) {
    if (![response isKindOfClass:NSDictionary.class]) return;

    id packageSettings = response[@"packageSettings"];
    if ([packageSettings isKindOfClass:NSDictionary.class]) {
        TserverApplyPackageSettings((NSDictionary *)packageSettings);
    }

    id raw = response[@"securityPolicy"];
    if ([raw isKindOfClass:NSDictionary.class]) {
        NSDictionary *row = (NSDictionary *)raw;
        gHookKill = TserverPolicyBool(row, @"hookKill", YES);
        gLogKill = TserverPolicyBool(row, @"logKill", YES);
#if defined(TSERVER_RELEASE)
        // Release SDKs ignore remote soft-disable of local enforcement. Debug builds
        // still honor hookKill/logKill=false for investigation.
        if (!gHookKill) gHookKill = YES;
        if (!gLogKill) gLogKill = YES;
#endif
        // Global securityPolicy.forceUpdate only — independent of package requireLatestSdk.
        gForceUpdate = TserverPolicyBool(row, @"forceUpdate", NO);
        gMinSdkBuild = TserverPolicyInt(row, @"minSdkBuild", 0);
        gRequireTransportSession = TserverPolicyBool(row, @"requireTransportSession", NO);
        // Policy v2: transport floor defaults to 3 (hard-cut).
        NSInteger minTv = TserverPolicyInt(row, @"minTransportVersion", 3);
        gMinTransportVersion = minTv < 3 ? 3 : minTv;
        NSArray<NSString *> *pins = TserverPolicyStringArray(row, @"tlsSpkiPins");
        NSMutableArray<NSString *> *validPins = [NSMutableArray array];
        NSCharacterSet *hexInvalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
        for (NSString *raw in pins) {
            NSString *hex = [[[raw lowercaseString] stringByReplacingOccurrencesOfString:@":" withString:@""]
                stringByReplacingOccurrencesOfString:@" " withString:@""];
            if (hex.length != 64) continue;
            if ([hex rangeOfCharacterFromSet:hexInvalid].location != NSNotFound) continue;
            [validPins addObject:hex];
            if (validPins.count >= 4) break;
        }
        gTlsSpkiPins = [validPins copy];
        gAcceptedClientIdentityKids = TserverPolicyStringArray(row, @"acceptedClientIdentityKids");
        gPolicy = [row copy];
        TserverPinningUnionAdvertisedSpkiPins(gTlsSpkiPins);
    }

    // Apply log silence immediately when policy demands it.
    if (gLogKill) {
        TserverLogGuardSilenceConsole();
    }

    // If server re-enabled kills, ensure watchdogs are running.
    if (gHookKill) {
        TserverAntiHookStartWatchdog();
        TserverAntiPatchStartWatchdog();
    }
}

BOOL TserverSecurityPolicyHookKillEnabled(void) { return gHookKill; }
BOOL TserverSecurityPolicyLogKillEnabled(void) { return gLogKill; }
BOOL TserverSecurityPolicyForceUpdate(void) { return gForceUpdate; }
NSInteger TserverSecurityPolicyMinSdkBuild(void) { return gMinSdkBuild; }
BOOL TserverSecurityPolicyRequireTransportSession(void) { return gRequireTransportSession; }
BOOL TserverSecurityPolicyAllowWithoutKey(void) { return gAllowWithoutKey; }
BOOL TserverSecurityPolicyHideScreenCapture(void) { return gHideScreenCapture; }
BOOL TserverSecurityPolicyProtectScreenContent(void) { return gProtectScreenContent; }
BOOL TserverSecurityPolicyRequireLatestSdk(void) { return gRequireLatestSdk; }
NSString *TserverSecurityPolicyForceUpdateUrl(void) { return gForceUpdateUrl; }
NSDictionary *TserverSecurityPolicyCurrent(void) { return gPolicy; }
NSDictionary *TserverSecurityPolicyPackageSettings(void) { return gPackageSettings; }
NSInteger TserverSecurityPolicyMinTransportVersion(void) { return gMinTransportVersion < 3 ? 3 : gMinTransportVersion; }
NSArray<NSString *> *TserverSecurityPolicyTlsSpkiPins(void) { return gTlsSpkiPins ?: @[]; }
NSArray<NSString *> *TserverSecurityPolicyAcceptedClientIdentityKids(void) { return gAcceptedClientIdentityKids ?: @[]; }
