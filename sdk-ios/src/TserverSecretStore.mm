#import "TserverSecretStore.h"
#import "TserverSecurity.h"
#import "TserverAntiHook.h"
#import "TserverSecureBlob.h"
#import "TserverSealedConstants.h"
#import <Foundation/Foundation.h>
#import <string.h>

// Declared in TserverClientApiKeyData.gen.mm (XOR-obfuscated key material).
#ifdef __cplusplus
extern "C" {
#endif
int TserverFillClientApiKeyHex(char *out, size_t outCap);
int TserverClientApiKeyEmbedOk(void);
#ifdef __cplusplus
}
#endif

FOUNDATION_EXPORT NSString *TserverRuntimeBaseURL(void) {
    if (!TserverSecurityAllowSensitiveWork()) return @"";
    const char *host = TserverSealedStringAt(kTserverSealedStr_ApiHost);
    const char *scheme = TserverSealedStringAt(kTserverSealedStr_HttpsScheme);
    if (!(host && host[0] && scheme && scheme[0])) return @"";
    return [@(scheme) stringByAppendingString:[NSString stringWithUTF8String:host]];
}

FOUNDATION_EXPORT NSString *TserverRuntimeClientApiKey(void) {
    if (!TserverSecurityAllowSensitiveWork()) return @"";
    if (TserverClientApiKeyEmbedOk() != 0) return @"";
    // Hook/injection heuristics are telemetry only. The embedded build credential
    // is not an authorization secret; server-issued signed proofs remain mandatory.

    // Stack buffer only — never a global / never logged. Wiped before return.
    char buf[65];
    memset(buf, 0, sizeof(buf));
    TserverAntiDumpLock(buf, sizeof(buf));
    if (TserverFillClientApiKeyHex(buf, sizeof(buf)) != 0) {
        TserverAntiDumpUnlockAndWipe(buf, sizeof(buf));
        return @"";
    }
    // Validate hex-64 shape before promoting to NSString.
    size_t n = strnlen(buf, 64);
    if (n != 64) {
        TserverAntiDumpUnlockAndWipe(buf, sizeof(buf));
        return @"";
    }
    for (size_t i = 0; i < 64; i++) {
        unsigned char c = (unsigned char)buf[i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        if (!ok) {
            TserverAntiDumpUnlockAndWipe(buf, sizeof(buf));
            return @"";
        }
    }
    // Copy into NSString then wipe stack so dump of heap-only window is shorter-lived.
    NSString *key = [[NSString alloc] initWithBytes:buf length:64 encoding:NSUTF8StringEncoding];
    TserverAntiDumpUnlockAndWipe(buf, sizeof(buf));
    return key ?: @"";
}
