#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Frida-specific presence check and termination policy.
///
/// Deliberately separate from the general runtime risk heuristics. Those remain
/// telemetry only: a jailbroken device, an attached debugger, an injected dylib
/// or a modified binary must never by themselves break a valid license. This
/// guard answers one narrower question — is Frida (or a fork such as Gadget /
/// frida-server / quickjs) attached to this process — and terminates when it is,
/// because that is how paid logic and license keys are lifted at runtime.
///
/// Design notes:
///  * Detection is Frida specific. Presence of Cydia, /var/jb, bash, Substrate
///    or any other jailbreak artefact is NOT a reason to terminate.
///  * A positive result is sticky, a negative result is not cached: Frida can be
///    attached at any moment, so the cheap checks run again on every call.
///  * Termination uses SIGKILL, not exit()/abort(). Those are the two functions a
///    hook script replaces first, so a soft exit would be exactly the case this
///    guard exists to stop.
@interface TserverFridaGuard : NSObject

/// YES when Frida is currently attached or installed and reachable.
+ (BOOL)isPresent;

/// Enable or disable automatic termination. Enabled by default.
+ (void)setEnabled:(BOOL)enabled;
+ (BOOL)isEnabled;

/// Terminate the process when Frida is present. Returns NO when the device is
/// clean or the guard is disabled, so callers can assert on the result.
+ (BOOL)enforceAndTerminateIfPresent;

@end

NS_ASSUME_NONNULL_END
