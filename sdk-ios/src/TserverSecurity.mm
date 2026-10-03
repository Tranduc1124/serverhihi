#import "TserverSecurity.h"
#import "TserverAntiHook.h"
#import "TserverAntiPatch.h"
#import "TserverSecurityPolicy.h"
#import "TserverRuntimeIntegrity.h"
#import "TserverFridaGuard.h"
#import "TserverAuthorizationLease.h"
#import "TserverStringCrypto.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/task.h>
#import <mach/thread_act.h>
#import <pthread.h>
#import <string.h>
#import <stdlib.h>
#import <fcntl.h>
#import <errno.h>

#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

typedef int (*TserverPtraceFn)(int request, pid_t pid, caddr_t addr, int data);

// Runtime anti-tamper signals are telemetry/defense-in-depth only. A controlled
// client can patch these checks, while jailbreak/debug tooling is also legitimate
// for supported hosts. Authorization therefore depends only on verified proofs.

static BOOL gWatchdogStarted = NO;
static volatile NSUInteger gRuntimeRiskFlags = TserverRuntimeRiskNone;

void TserverSecurityEnforceAntiDebug(void) {
    void *handle = dlopen(NULL, RTLD_GLOBAL | RTLD_NOW);
    if (handle) {
        TserverPtraceFn ptraceFunc = (TserverPtraceFn)dlsym(handle, TS_OBF_STR("ptrace"));
        if (ptraceFunc) {
            ptraceFunc(PT_DENY_ATTACH, 0, 0, 0);
        }
        dlclose(handle);
    }
}

static BOOL TserverIsDebuggerAttached(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return NO;
    }
    // P_TRACED
    return (info.kp_proc.p_flag & 0x00000800) != 0;
}

static BOOL TserverCheckExceptionPorts(void) {
    mach_port_t task = mach_task_self();
    exception_mask_t masks[EXC_TYPES_COUNT];
    mach_port_t ports[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count = 0;
    kern_return_t kr = task_get_exception_ports(task, EXC_MASK_ALL, masks, &count, ports, behaviors, flavors);
    if (kr == KERN_SUCCESS) {
        for (mach_msg_type_number_t i = 0; i < count; i++) {
            if (MACH_PORT_VALID(ports[i])) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL TserverCheckHardwareBreakpoints(void) {
#if defined(__arm64__) || defined(__aarch64__)
    arm_debug_state64_t dbg;
    mach_msg_type_number_t count = ARM_DEBUG_STATE64_COUNT;
    kern_return_t kr = thread_get_state(mach_thread_self(), ARM_DEBUG_STATE64, (thread_state_t)&dbg, &count);
    if (kr == KERN_SUCCESS) {
        for (int i = 0; i < 16; i++) {
            if (dbg.__bcr[i] != 0 || dbg.__bvr[i] != 0 || dbg.__wcr[i] != 0 || dbg.__wvr[i] != 0) {
                return YES;
            }
        }
    }
#endif
    return NO;
}

static BOOL TserverHasSuspiciousImage(void) {
    static const char *needles[] = {
        "frida",
        "frida-agent",
        "frida-gadget",
        "frida-server",
        "libfrida",
        "gum-js-loop",
        "libcycript",
        "cycript",
        "cynject",
        "ssl-kill",
        "sslkill",
        "sslkillswitch",
        "flex.dylib",
        "libreveal",
        "revelation",
        "substrate",
        "substitute",
        "libhooker",
        "ellekit",
        "cephei",
        "rocketbootstrap",
        "tweakinject",
        "libsparkapplist",
        "objection",
        "hermes-engine-hook",
        "idevicesyslog",
        "libimobiledevice",
        "pcapd",
        "shadowhook",
        "dobby",
        NULL
    };

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        char lower[1024];
        size_t n = strlen(name);
        if (n >= sizeof(lower)) n = sizeof(lower) - 1;
        for (size_t k = 0; k < n; k++) {
            char c = name[k];
            lower[k] = (char)((c >= 'A' && c <= 'Z') ? (c - 'A' + 'a') : c);
        }
        lower[n] = 0;
        for (int j = 0; needles[j]; j++) {
            if (strstr(lower, needles[j]) != NULL) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL TserverHasSuspiciousEnv(void) {
    const char *keys[] = {
        "FRIDA_AGENT",
        "FRIDA_SERVER",
        "FRIDA_OPTIONS",
        "_MSSafeMode",
        "DYLD_INSERT_LIBRARIES",
        NULL
    };
    for (int i = 0; keys[i]; i++) {
        const char *v = getenv(keys[i]);
        if (v && v[0] != '\0') {
            return YES;
        }
    }
    return NO;
}

static BOOL TserverParentLooksLikeDebug(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getppid()};
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return NO;
    char name[MAXCOMLEN + 1] = {0};
    memcpy(name, info.kp_proc.p_comm, MAXCOMLEN);
    for (char *p = name; *p; ++p) {
        if (*p >= 'A' && *p <= 'Z') *p = (char)(*p - 'A' + 'a');
    }
    if (strstr(name, "debugserver") || strstr(name, "lldb") || strstr(name, "frida") ||
        strstr(name, "gdb") || strstr(name, "ida") || strstr(name, "hopper")) {
        return YES;
    }
    return NO;
}

static BOOL TserverHasJailbreakPaths(void) {
    static const char *paths[] = {
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
        "/var/jb",
        "/var/jb/usr",
        "/var/jb/etc",
        "/var/jb/Applications",
        "/basebin",
        "/basebin/jbctl",
        "/var/binpack",
        "/.bootstrapped",
        "/usr/lib/libsubstitute.dylib",
        "/usr/lib/substrate",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], F_OK) == 0) return YES;
    }
    const char *probe = "/private/jailbreak_probe_tserver";
    int fd = open(probe, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        close(fd);
        unlink(probe);
        return YES;
    }
    return NO;
}

static BOOL TserverHasFridaPort(void) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;

    int flags = fcntl(sock, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    }

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(27042);
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);

    int ret = connect(sock, (struct sockaddr *)&sa, sizeof(sa));
    BOOL detected = NO;
    if (ret == 0) {
        detected = YES;
    } else if (errno == EINPROGRESS) {
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 40000; // 40ms
        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(sock, &wfds);
        if (select(sock + 1, NULL, &wfds, NULL, &tv) > 0) {
            int so_error = 0;
            socklen_t len = sizeof(so_error);
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &so_error, &len);
            if (so_error == 0) {
                detected = YES;
            }
        }
    }
    close(sock);
    return detected;
}

static BOOL TserverHasFridaThreads(void) {
    thread_act_array_t threads;
    mach_msg_type_number_t threadCount = 0;
    if (task_threads(mach_task_self(), &threads, &threadCount) != KERN_SUCCESS) {
        return NO;
    }

    static const char *fridaThreadNames[] = {
        "gum-js-loop",
        "gmain",
        "gdbus",
        "pool-frida",
        "frida",
        NULL
    };

    BOOL detected = NO;
    for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
        pthread_t pt = pthread_from_mach_thread_np(threads[i]);
        if (pt) {
            char name[128] = {0};
            if (pthread_getname_np(pt, name, sizeof(name)) == 0 && name[0] != '\0') {
                for (int j = 0; fridaThreadNames[j]; j++) {
                    if (strstr(name, fridaThreadNames[j]) != NULL) {
                        detected = YES;
                        break;
                    }
                }
            }
        }
        mach_port_deallocate(mach_task_self(), threads[i]);
        if (detected) break;
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, threadCount * sizeof(thread_act_t));
    return detected;
}

static TserverRuntimeRiskFlags TserverComputeRiskFlags(void) {
    TserverRuntimeRiskFlags flags = TserverRuntimeRiskNone;
    if (TserverIsDebuggerAttached()) flags |= TserverRuntimeRiskDebugger;
    if (TserverCheckExceptionPorts()) flags |= TserverRuntimeRiskExceptionPort;
    if (TserverCheckHardwareBreakpoints()) flags |= TserverRuntimeRiskHardwareDebug;
    if (TserverHasSuspiciousImage()) flags |= TserverRuntimeRiskInjectedImage;
    if (TserverHasSuspiciousEnv()) flags |= TserverRuntimeRiskInjectedEnvironment;
    if (TserverParentLooksLikeDebug()) flags |= TserverRuntimeRiskDebugParent;
    if (TserverHasFridaPort() || TserverHasFridaThreads()) flags |= TserverRuntimeRiskFridaDetected;
    if (!TserverAntiHookLooksClean()) flags |= TserverRuntimeRiskHookDrift;
    if (!TserverAntiPatchLooksClean()) flags |= TserverRuntimeRiskPatchDrift;
    if (TserverHasJailbreakPaths()) flags |= TserverRuntimeRiskJailbreak;
    return flags;
}

BOOL TserverSecurityAllowSensitiveWork(void) {
    // Hosts for this product are jailbroken by design, so a detected
    // jailbreak/hook/integrity drift is telemetry, never a hard failure: gating
    // here would block every legitimate install. Signals stay on the watchdog
    // path and are surfaced through TserverSecurityRuntimeRiskFlags() so a
    // vendor can read them in support diagnostics.
    return YES;
}

TserverRuntimeRiskFlags TserverSecurityRuntimeRiskFlags(void) {
    gRuntimeRiskFlags = TserverComputeRiskFlags();
    return (TserverRuntimeRiskFlags)gRuntimeRiskFlags;
}

void TserverSecurityStartWatchdog(void) {
    if (gWatchdogStarted) return;
    gWatchdogStarted = YES;
    TserverRuntimeIntegrityInitialize();
    TserverSecurityEnforceAntiDebug();
    // Frida terminates the process; every other heuristic stays telemetry.
    TserverFridaGuardEnforceAtStartup();
    TserverAntiHookStartWatchdog();
    TserverAntiPatchStartWatchdog();
    gRuntimeRiskFlags = TserverComputeRiskFlags();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (YES) {
            @autoreleasepool {
                gRuntimeRiskFlags = TserverComputeRiskFlags();
                // Frida can attach long after launch, so keep re-checking on the
                // watchdog cadence instead of trusting a single startup answer.
                [TserverFridaGuard enforceAndTerminateIfPresent];
            }
            sleep(2);
        }
    });
}
