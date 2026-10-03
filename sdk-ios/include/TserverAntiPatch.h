#import <Foundation/Foundation.h>
#import <stdint.h>

// Anti patch-call / IMP swizzle / function-pointer replace.
// Complements TserverAntiHook (prologue bytes) with:
// - Cached absolute addresses of critical C functions (encrypted offset table at rest)
// - ObjC IMP integrity for a few selectors if used
// - Fail closed when a watched pointer changes after baseline arm

#ifdef __cplusplus
extern "C" {
#endif

/// Arm baseline of critical function pointers (call once after dyld settle).
void TserverAntiPatchArm(void);

/// YES if all watched call targets still match baseline.
BOOL TserverAntiPatchLooksClean(void);

/// Watchdog re-check (idempotent).
void TserverAntiPatchStartWatchdog(void);

#ifdef __cplusplus
}
#endif
