#import <Foundation/Foundation.h>

// Anti realtime-log tooling (3uTools log stream, idevicesyslog, Console, etc.)
// - Silence stdout/stderr for this process
// - Watchdog signals are telemetry only and never invalidate signed authorization.

typedef void (^TserverLogKillBlock)(void);

FOUNDATION_EXPORT BOOL TserverLogToolIsActive(void);
FOUNDATION_EXPORT void TserverLogGuardStart(void);
FOUNDATION_EXPORT void TserverLogGuardSilenceConsole(void);
FOUNDATION_EXPORT void TserverLogGuardSetKillHandler(TserverLogKillBlock block);
FOUNDATION_EXPORT BOOL TserverLogGuardAllowAuth(void);
