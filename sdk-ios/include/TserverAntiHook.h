#import <Foundation/Foundation.h>

// Anti-hook / anti-dump soft gate for the auth dylib.
// - Prologue integrity on critical C functions (inline hook / trampoline detect)
// - Suspicious dyld images (Frida, Substrate, …) already covered in TserverSecurity
// - Best-effort mlock of secret buffers + wipe after use
// Not perfect on a fully controlled JB device.

#ifdef __cplusplus
extern "C" {
#endif

/// YES if environment looks free of inline hooks on critical symbols.
BOOL TserverAntiHookLooksClean(void);

/// Soft integrity over a few critical function entrypoints.
BOOL TserverAntiHookCriticalProloguesOK(void);

/// mlock + optional madvise on a secret buffer (best-effort).
void TserverAntiDumpLock(void *p, size_t n);
void TserverAntiDumpUnlockAndWipe(void *p, size_t n);

/// Start periodic re-check (idempotent). On failure, sets global unsafe.
void TserverAntiHookStartWatchdog(void);

#ifdef __cplusplus
}
#endif
