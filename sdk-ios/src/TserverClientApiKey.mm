#import "TserverClientApiKey.h"
#import "TserverSecretStore.h"
#import "TserverSecurity.h"

// Thin wrapper — real material assembled in TserverSecretStore.mm after security gate.

FOUNDATION_EXPORT NSString *TserverCompiledClientApiKey(void) {
    if (!TserverSecurityAllowSensitiveWork()) {
        return @"";
    }
    return TserverRuntimeClientApiKey();
}
