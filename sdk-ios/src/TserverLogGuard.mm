#import "TserverLogGuard.h"
#import "TserverSecurityPolicy.h"
#import "TserverActivationAttempt.h"
#import "TserverAuthorizationLease.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>
#import <dlfcn.h>
#import <fcntl.h>

// Anti realtime-log / USB tooling (3uTools, iTools, idevicesyslog, Console.app attach, etc.)
// Strategy:
// 1) Soften console noise: redirect stdout/stderr to /dev/null once auth starts (SDK has no NSLog).
// 2) Poll for best-effort telemetry only. Tool presence never revokes a valid
//    cryptographic authorization proof or blocks supported jailbreak hosts.

static BOOL gWatchdogStarted = NO;
static BOOL gWasClean = YES;
static BOOL gStdoutSilenced = NO;
static BOOL gLogToolActiveMidSession = NO;
static BOOL gLogToolPresentAtBoot = NO;
static TserverLogKillBlock gKillBlock = nil;

static void TserverLowercase(char *s) {
    if (!s) return;
    for (; *s; ++s) {
        if (*s >= 'A' && *s <= 'Z') *s = (char)(*s - 'A' + 'a');
    }
}

static BOOL TserverNameLooksLikeLogTool(const char *name) {
    if (!name || !name[0]) return NO;
    char buf[MAXCOMLEN + 1];
    memset(buf, 0, sizeof(buf));
    strncpy(buf, name, MAXCOMLEN);
    TserverLowercase(buf);

    // On-device / paired agents commonly visible when 3uTools / iTools / Xcode Console stream logs.
    static const char *needles[] = {
        "3utools",
        "3uairplayer",
        "i4tools",
        "itools",
        "itunnel",
        "idevicesyslog",
        "ideviceinstaller",
        "libimobiledevice",
        "usbmuxd",
        "lockdownd", // too broad alone — checked with combo below
        "syslogd",   // always present — never alone
        "logd",
        "diagnosticd",
        "osanalyticshelper",
        "sysdiagnose",
        "pcapd",
        "tcpdump",
        "frida",
        "debugserver",
        "lldb",
        "console",
        "cfgutil",
        "cfgutilagent",
        "appleconfiguratord",
        "iosappinstaller",
        "anytrans",
        "ifunbox",
        "syncios",
        "imazing",
        "waltr",
        "sideloadly",
        "altserver",
        "altdaemon",
        NULL
    };

    // Always-on system daemons we should NOT kill on alone:
    if (strcmp(buf, "syslogd") == 0 || strcmp(buf, "logd") == 0 ||
        strcmp(buf, "lockdownd") == 0 || strcmp(buf, "usbmuxd") == 0) {
        return NO;
    }

    for (int i = 0; needles[i]; i++) {
        if (strstr(buf, needles[i]) != NULL) return YES;
    }
    return NO;
}

static BOOL TserverHasLogToolProcess(void) {
    // Enumerate processes via sysctl KERN_PROC_ALL
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0 || size == 0) return NO;
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return NO;
    if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
        free(procs);
        return NO;
    }
    int n = (int)(size / sizeof(struct kinfo_proc));
    BOOL hit = NO;
    pid_t selfPid = getpid();
    for (int i = 0; i < n; i++) {
        if (procs[i].kp_proc.p_pid == selfPid) continue;
        char name[MAXCOMLEN + 1] = {0};
        memcpy(name, procs[i].kp_proc.p_comm, MAXCOMLEN);
        if (TserverNameLooksLikeLogTool(name)) {
            hit = YES;
            break;
        }
    }
    free(procs);
    return hit;
}

static BOOL TserverHasUsbMuxOrDiagSpike(void) {
    // Soft signal: multiple diagnostic helpers at once while our process is foregrounded.
    // We only use this as secondary — process name match is primary.
    return NO;
}

BOOL TserverLogToolIsActive(void) {
    if (TserverHasLogToolProcess()) return YES;
    if (TserverHasUsbMuxOrDiagSpike()) return YES;
    return NO;
}

void TserverLogGuardSilenceConsole(void) {
    if (gStdoutSilenced) return;
    gStdoutSilenced = YES;
    // Drop accidental stdout/stderr so USB syslog tools see nothing from this process fd.
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) {
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        if (devnull > STDERR_FILENO) close(devnull);
    } else {
        freopen("/dev/null", "w", stdout);
        freopen("/dev/null", "w", stderr);
    }
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
}

void TserverLogGuardSetKillHandler(TserverLogKillBlock block) {
    gKillBlock = [block copy];
}

void TserverLogGuardStart(void) {
    if (gWatchdogStarted) return;
    gWatchdogStarted = YES;
    TserverLogGuardSilenceConsole();
    gLogToolPresentAtBoot = TserverLogToolIsActive();
    gWasClean = !gLogToolPresentAtBoot;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (YES) {
            @autoreleasepool {
                BOOL active = TserverLogToolIsActive();
                if (!active) {
                    gWasClean = YES;
                    gLogToolPresentAtBoot = NO;
                } else if (gWasClean) {
                    // Record a transition without changing authorization state. The
                    // server-issued lease remains the only paid-capability authority.
                    gWasClean = NO;
                }
                if (active && !gLogToolActiveMidSession) {
                    gLogToolActiveMidSession = YES;
                }
            }
            sleep(2);
        }
    });
}

BOOL TserverLogGuardAllowAuth(void) {
    // Never blocks auth: users legitimately have sideload/log tooling installed,
    // and a denied check would look like a license failure to the integrator.
    // Presence is reported through TserverLogToolIsActive() only.
    return YES;
}
