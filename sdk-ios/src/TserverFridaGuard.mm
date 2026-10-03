#import "TserverFridaGuard.h"
#import "TserverSecurity.h"
#import "TserverRuntimeIntegrity.h"
#import "APIClient.h"

#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <unistd.h>

/// Frida detection and termination.
///
/// Only Frida counts here. The general jailbreak heuristics in TserverSecurity
/// stay telemetry: Cydia, /var/jb, bash, Substrate and friends never terminate
/// the app, because plenty of legitimate users run a jailbroken phone and a valid
/// license should keep working for them.

static BOOL gTserverFridaGuardEnabled = YES;
/// Sticky: once Frida has been seen there is no reason to keep trusting the run.
static BOOL gTserverFridaDetected = NO;
static atomic_bool gTserverFridaEnforcing = ATOMIC_VAR_INIT(false);

static NSString *const TserverFridaGuardLogTag = @"guard.frida";

#pragma mark - Individual signals

/// Frida Gadget and the usual forks ship as a dylib inside the process, so the
/// dyld image list is the most reliable and cheapest signal available.
static BOOL TserverFridaImageListHasFrida(void) {
    static const char *needles[] = {
        "frida",
        "libgum",
        "quickjsp",
        "fridagadget",
        "re.frida.server",
        NULL
    };
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL) continue;
        char lowered[512];
        size_t length = strlen(name);
        if (length >= sizeof(lowered)) length = sizeof(lowered) - 1;
        for (size_t n = 0; n < length; n++) {
            lowered[n] = (char)tolower((unsigned char)name[n]);
        }
        lowered[length] = '\0';
        for (int k = 0; needles[k]; k++) {
            if (strstr(lowered, needles[k]) != NULL) return YES;
        }
    }
    return NO;
}

/// frida-server listens on 27042 by default. Forks often use 27043 or a random
/// port, so the well known ones are probed rather than assumed.
static BOOL TserverFridaPortOpen(uint16_t port) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;
    int flags = fcntl(sock, F_GETFL, 0);
    if (flags >= 0) fcntl(sock, F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    int result = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    BOOL open = NO;
    if (result == 0) {
        open = YES;
    } else if (errno == EINPROGRESS) {
        struct timeval tv = { .tv_sec = 0, .tv_usec = 40000 };
        fd_set writeSet;
        FD_ZERO(&writeSet);
        FD_SET(sock, &writeSet);
        if (select(sock + 1, NULL, &writeSet, NULL, &tv) > 0) {
            int soError = 0;
            socklen_t length = sizeof(soError);
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &length);
            open = (soError == 0);
        }
    }
    close(sock);
    return open;
}

/// The daemon binary on disk. Presence means it can attach at any moment, even
/// when it is not connected right now.
static BOOL TserverFridaServerInstalled(void) {
    static const char *paths[] = {
        "/usr/sbin/frida-server",
        "/usr/bin/frida-server",
        "/usr/bin/fridaserver",
        "/var/jb/usr/sbin/frida-server",
        "/var/jb/usr/bin/fridaserver",
        "/private/var/usr/bin/fridaserver",
        "/var/jb/usr/sbin/frida",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], F_OK) == 0) return YES;
    }
    return NO;
}

#pragma mark - Public surface

@implementation TserverFridaGuard

+ (void)setEnabled:(BOOL)enabled {
    gTserverFridaGuardEnabled = enabled;
    TserverDiagnosticsRecord(TserverFridaGuardLogTag, enabled ? @"guard enabled" : @"guard disabled", @{
        @"enabled": @(enabled)
    });
}

+ (BOOL)isEnabled {
    return gTserverFridaGuardEnabled;
}

+ (BOOL)isPresent {
    if (gTserverFridaDetected) return YES;

    // Cheapest and strongest first: an injected image cannot be un-injected.
    if (TserverFridaImageListHasFrida()) {
        gTserverFridaDetected = YES;
        return YES;
    }
    if (TserverFridaPortOpen(27042) || TserverFridaPortOpen(27043)) {
        gTserverFridaDetected = YES;
        return YES;
    }
    if (TserverFridaServerInstalled()) {
        gTserverFridaDetected = YES;
        return YES;
    }
    return NO;
}

+ (void)terminateForFrida {
    // Record first so a support snapshot taken by the host app just before the
    // process dies still carries the reason. Never blocks.
    TserverDiagnosticsRecord(TserverFridaGuardLogTag, @"terminating: frida detected", @{
        @"image": @(TserverFridaImageListHasFrida()),
        @"port": @(TserverFridaPortOpen(27042) || TserverFridaPortOpen(27043)),
        @"server": @(TserverFridaServerInstalled())
    });
    fflush(stdout);
    fflush(stderr);
    // SIGKILL, not exit()/abort(): those are exactly the calls a hook script
    // replaces, and a hook can swallow them.
    kill(getpid(), SIGKILL);
    // Unreachable in practice; keeps the compiler happy if the signal is blocked.
    _exit(0);
}

+ (BOOL)enforceAndTerminateIfPresent {
    if (!gTserverFridaGuardEnabled) return NO;
    if (![self isPresent]) return NO;
    // Only one thread performs the kill; the rest are already on their way out.
    if (!atomic_exchange(&gTserverFridaEnforcing, true)) {
        [self terminateForFrida];
    }
    return YES;
}

@end

/// Enforce once at startup, before any UI or credential handling happens.
void TserverFridaGuardEnforceAtStartup(void) {
    [TserverFridaGuard enforceAndTerminateIfPresent];
}
