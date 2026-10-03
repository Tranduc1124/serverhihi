#import <Foundation/Foundation.h>

// ============================================================
// CUSTOMER CONFIG — package token and return scheme
// ============================================================
// Copy the package token from the Packages page.
// Prefer obfuscated embed (harder for casual `strings` dump):
//   python3 sdk-ios/scripts/obfuscate_package_token.py 'pkg_...'
// then paste the generated arrays below and set UseObfuscated = 1.
// Plain string form still works for simple builds.

// --- Plain token (default / easy path) ---
static NSString * const kTserverPackageToken = @"REPLACE_WITH_YOUR_PACKAGE_TOKEN";

// --- Optional obfuscated token (set UseObfuscated = 1 and fill arrays) ---
static const int kTserverPackageTokenUseObfuscated = 0;
static const unsigned char kTserverPackageTokenEnc[] = { 0x00 };
static const unsigned char kTserverPackageTokenMask[] = { 0x00 };
static const unsigned kTserverPackageTokenEncLen = 0;

// Optional only for customer-made "key info" pages in source dylib.
// Leave empty if unused. The SDK will not show/configure this in the server UI.
// Your source can call TserverMemberInfo and use placeholders such as:
// %tserver_key%, %tserver_key_status%, %tserver_key_remaining%, %tserver_online%, %tserver_package_name%.
static NSString * const kTserverMemberApiKey = @"";      // mk_...
static NSString * const kTserverMemberPackageId = @"";   // mp_...

// "auto" prefers a valid URL scheme already declared by the host app.
static NSString * const kTserverReturnScheme = @"auto";

// Fast handoff after VALID: dismiss gate and enter menu immediately once host view is ready.
static const NSTimeInterval kTserverModReadySettleSecondsConfig = 0.0;
static const NSTimeInterval kTserverModReadyRetrySecondsConfig = 0.05;
static const NSInteger kTserverModReadyMaxAttemptsConfig = 120;

// Unity/splash: start auth as soon as the host window is ready.
// Gate UI is shown only when the request starts, so this should stay low.
static const NSTimeInterval kTserverGateColdStartDelaySecondsConfig = 0.05;
static const NSInteger kTserverGateColdStartMinAttemptsConfig = 0;

// Helper used by bootstrap — reconstructs package token (plain or XOR).
static inline NSString *TserverResolvedPackageToken(void) {
    if (kTserverPackageTokenUseObfuscated && kTserverPackageTokenEncLen > 0) {
        NSMutableData *data = [NSMutableData dataWithLength:kTserverPackageTokenEncLen];
        unsigned char *out = (unsigned char *)data.mutableBytes;
        for (unsigned i = 0; i < kTserverPackageTokenEncLen; i++) {
            out[i] = (unsigned char)(kTserverPackageTokenEnc[i] ^ kTserverPackageTokenMask[i]);
        }
        NSString *token = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        // Best-effort wipe
        if (out) memset(out, 0, kTserverPackageTokenEncLen);
        return token ?: @"";
    }
    return kTserverPackageToken ?: @"";
}
