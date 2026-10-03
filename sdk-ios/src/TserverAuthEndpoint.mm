#import "TserverAuthEndpoint.h"
#import "TserverSecretStore.h"
#import "TserverSecurity.h"

// Thin wrapper — URL assembled at runtime after anti-tamper checks.

FOUNDATION_EXPORT NSString *TserverCompiledPrimaryEndpoint(void) {
    if (!TserverSecurityAllowSensitiveWork()) {
        return @"";
    }
    return TserverRuntimeBaseURL();
}

FOUNDATION_EXPORT NSString *TserverCompiledFallbackEndpoint(void) {
    return @"";
}
