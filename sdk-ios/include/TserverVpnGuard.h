// Removed: anti-VPN false-positive with DNS apps. Stub kept so old includes don't break.
#pragma once
#import <Foundation/Foundation.h>
static inline BOOL TserverVpnIsActive(void) { return NO; }
static inline void TserverVpnGuardStart(void) {}
static inline BOOL TserverVpnGuardAllowAuth(void) { return YES; }
typedef void (^TserverVpnKillBlock)(void);
static inline void TserverVpnGuardSetKillHandler(TserverVpnKillBlock __unused block) {}
