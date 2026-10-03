#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, TserverRuntimeRiskFlags) {
    TserverRuntimeRiskNone = 0,
    TserverRuntimeRiskDebugger = 1u << 0,
    TserverRuntimeRiskInjectedImage = 1u << 1,
    TserverRuntimeRiskInjectedEnvironment = 1u << 2,
    TserverRuntimeRiskDebugParent = 1u << 3,
    TserverRuntimeRiskHookDrift = 1u << 4,
    TserverRuntimeRiskPatchDrift = 1u << 5,
    TserverRuntimeRiskJailbreak = 1u << 6,
    TserverRuntimeRiskHardwareDebug = 1u << 7,
    TserverRuntimeRiskExceptionPort = 1u << 8,
    TserverRuntimeRiskFridaDetected = 1u << 9,
    TserverRuntimeRiskMemoryTampered = 1u << 10,
  TserverRuntimeRiskCodeSignature = 1u << 11,
  TserverRuntimeRiskExecutableChanged = 1u << 12,
};

// Compatibility function retained for internal call sites. Runtime heuristics are
// telemetry only: cryptographic proof validity is the authorization boundary.
FOUNDATION_EXPORT BOOL TserverSecurityAllowSensitiveWork(void);
FOUNDATION_EXPORT TserverRuntimeRiskFlags TserverSecurityRuntimeRiskFlags(void);

// Enforces anti-debugging mechanisms (PT_DENY_ATTACH, exception ports isolation)
FOUNDATION_EXPORT void TserverSecurityEnforceAntiDebug(void);

// Starts best-effort risk collection and anti-dump baselines. It never revokes an
// otherwise valid authorization lease merely because the device is jailbroken,
// debugged, or running injected frameworks.
FOUNDATION_EXPORT void TserverSecurityStartWatchdog(void);

/// Terminate immediately when Frida is attached. Called automatically by
/// TserverSecurityStartWatchdog and on every foreground; safe to call again.
FOUNDATION_EXPORT void TserverFridaGuardEnforceAtStartup(void);
