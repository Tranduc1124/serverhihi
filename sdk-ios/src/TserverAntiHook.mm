#import "TserverAntiHook.h"
#import "TserverRuntimeIntegrity.h"
#import "TserverSecureBlob.h"
#import "TserverStringCrypto.h"
#import <Foundation/Foundation.h>
#include <stdint.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#import <sys/mman.h>
#import <sys/sysctl.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>
#import <libkern/OSCacheControl.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>

// Forward decls of symbols we integrity-check (defined in other TUs).
#ifdef __cplusplus
extern "C" {
#endif
int TserverFillClientApiKeyHex(char *out, size_t outCap);
int TserverClientApiKeyEmbedOk(void);
BOOL TserverSecurityAllowSensitiveWork(void);
BOOL TserverAuthorizationLeaseIntegrityCheck(void);
BOOL TserverAuthorizationLeasePerformCapability(NSString *, dispatch_block_t, dispatch_block_t);
BOOL TserverAuthorizationLeaseIsAuthorized(void);
BOOL TserverAuthorizationLeaseAllowsCapability(NSString *);
uint64_t TserverAuthorizationLeaseGeneration(void);
BOOL TserverAuthBootstrapIsValid(void);
void TserverAuthBootstrapStartWithPrepared(void (^)(void), void (^)(NSDictionary *));
void APIClientStartAuthorization(dispatch_block_t, dispatch_block_t);
BOOL APIClientPerformAuthorized(NSString *, dispatch_block_t, dispatch_block_t);
void APIClientOpenPaid(dispatch_block_t);
void APIClientConfirmKey(NSString *, void (^)(NSDictionary *), void (^)(NSDictionary *));
void apiclient_paid(void (^)(void));
void apiclient_on_login(const char *, void (^)(const char *), void (^)(const char *));
#ifdef __cplusplus
}
#endif

static BOOL gWatchdogStarted = NO;
static volatile BOOL gHookClean = YES;

// Snapshot of first N bytes of critical functions after first clean sample.
typedef struct {
  const void *addr;
  uint8_t bytes[16];
  size_t len;
  BOOL armed;
} TserverPrologueSnap;

static TserverPrologueSnap gSnaps[32];
static size_t gSnapCount = 0;

static uint8_t gTextSampleHash[CC_SHA256_DIGEST_LENGTH] = {0};
static BOOL gTextHashArmed = NO;

static BOOL TserverLooksLikeTrampoline(const uint8_t *p, size_t n) {
  if (!p || n < 4) return NO;
  // Common ARM64 hook prologues:
  // LDR X16, #8; BR X16; .quad abs   => 0x50 0x00 0x00 0x58 / variants
  // BR X16: 0x00 0x02 0x1F 0xD6
  // classic: 10 00 00 58  00 02 1F D6
  if (n >= 8) {
    // BR X16 / BR X17 family
    if (p[3] == 0x58 && p[7] == 0xD6) return YES; // LDR literal + BR
    if (p[0] == 0x50 && p[4] == 0x00 && p[5] == 0x02 && p[6] == 0x1F && p[7] == 0xD6) return YES;
    // LDR X17, #8; BR X17
    if (p[0] == 0x51 && p[4] == 0x00 && p[5] == 0x02 && p[6] == 0x1F && p[7] == 0xD6) return YES;
  }
  // B (unconditional) or BL to far
  if (n >= 4) {
    uint32_t w;
    memcpy(&w, p, 4);
    uint32_t op = (w >> 26) & 0x3F;
    // B = 0x05, BL = 0x25 — single instruction jump at entry is suspicious for our leaf helpers
    if (op == 0x05 || op == 0x25) {
      return YES;
    }
  }
  // MOVZ / MOVK sequence (D2 / F2) followed by BR
  if (n >= 8) {
    uint32_t w0, w1;
    memcpy(&w0, p, 4);
    memcpy(&w1, p + 4, 4);
    if ((w0 & 0xFF800000) == 0xD2800000 && (w1 & 0xFF800000) == 0xF2800000) {
      return YES;
    }
  }
  // Inline INT3 / BRK
  if (n >= 4) {
    uint32_t w;
    memcpy(&w, p, 4);
    if ((w & 0xFFE0001F) == 0xD4200000) return YES; // BRK #imm
  }
  return NO;
}

static void TserverArmSnap(const void *fn) {
  if (!fn || gSnapCount >= sizeof(gSnaps) / sizeof(gSnaps[0])) return;
  TserverPrologueSnap *s = &gSnaps[gSnapCount++];
  s->addr = fn;
  s->len = 16;
  s->armed = NO;
  // Best-effort read (function must be executable mapping)
  memcpy(s->bytes, fn, s->len);
  if (TserverLooksLikeTrampoline(s->bytes, s->len)) {
    // Already hooked at arm time — mark dirty, do not trust baseline
    gHookClean = NO;
    return;
  }
  s->armed = YES;
}

static BOOL TserverCheckSnaps(void) {
  for (size_t i = 0; i < gSnapCount; i++) {
    TserverPrologueSnap *s = &gSnaps[i];
    if (!s->armed || !s->addr) continue;
    uint8_t now[16];
    memcpy(now, s->addr, s->len);
    if (memcmp(now, s->bytes, s->len) != 0) return NO;
    if (TserverLooksLikeTrampoline(now, s->len)) return NO;
  }
  return YES;
}

static BOOL TserverCheckTextSegmentIntegrity(void) {
  const struct mach_header *mh = _dyld_get_image_header(0);
  if (!mh) return YES;
  if (mh->magic != MH_MAGIC_64) return YES;

  const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
  const uint8_t *cmdPtr = (const uint8_t *)(mh64 + 1);

  const struct section_64 *textSec = NULL;
  for (uint32_t i = 0; i < mh64->ncmds; i++) {
    const struct load_command *lc = (const struct load_command *)cmdPtr;
    if (lc->cmd == LC_SEGMENT_64) {
      const struct segment_command_64 *seg = (const struct segment_command_64 *)cmdPtr;
      if (strcmp(seg->segname, SEG_TEXT) == 0) {
        const struct section_64 *sec = (const struct section_64 *)(seg + 1);
        for (uint32_t s = 0; s < seg->nsects; s++) {
          if (strcmp(sec[s].sectname, SECT_TEXT) == 0) {
            textSec = &sec[s];
            break;
          }
        }
        break;
      }
    }
    cmdPtr += lc->cmdsize;
  }

  if (!textSec || textSec->size < 128) return YES;

  intptr_t slide = _dyld_get_image_vmaddr_slide(0);
  const uint8_t *textBase = (const uint8_t *)(textSec->addr + slide);
  size_t sampleLen = textSec->size < 4096 ? (size_t)textSec->size : 4096;

  uint8_t currentHash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(textBase, (CC_LONG)sampleLen, currentHash);

  if (!gTextHashArmed) {
    memcpy(gTextSampleHash, currentHash, CC_SHA256_DIGEST_LENGTH);
    gTextHashArmed = YES;
    return YES;
  }

  if (memcmp(currentHash, gTextSampleHash, CC_SHA256_DIGEST_LENGTH) != 0) {
    return NO;
  }
  return YES;
}

static BOOL TserverSuspiciousHookImages(void) {
  static const char *needles[] = {
    "frida", "gum-js", "substrate", "substitute", "libhooker", "ellekit",
    "fishhook", "dobby", "hookzz", "inlinehook", "mshook", "cydia",
    "sslkill", "ssl-kill", "objection", "shadowhook", "whale", "sandhook",
    "bfinject", "cycript", "dumpdecrypted", "clutch", "flex", "charles",
    "mitmproxy", "proxyman", NULL
  };
  uint32_t count = _dyld_image_count();
  for (uint32_t i = 0; i < count; i++) {
    const char *name = _dyld_get_image_name(i);
    if (!name) continue;
    char lower[768];
    size_t n = strlen(name);
    if (n >= sizeof(lower)) n = sizeof(lower) - 1;
    for (size_t k = 0; k < n; k++) {
      char c = name[k];
      lower[k] = (char)((c >= 'A' && c <= 'Z') ? (c - 'A' + 'a') : c);
    }
    lower[n] = 0;
    for (int j = 0; needles[j]; j++) {
      if (strstr(lower, needles[j])) return YES;
    }
  }
  return NO;
}

BOOL TserverAntiHookCriticalProloguesOK(void) {
  if (gSnapCount == 0) {
    // Arm on first call (baseline after load, before hooks ideally).
    TserverArmSnap((const void *)&TserverFillClientApiKeyHex);
    TserverArmSnap((const void *)&TserverClientApiKeyEmbedOk);
    TserverArmSnap((const void *)&TserverSecureBlobOpen);
    TserverArmSnap((const void *)&TserverAntiHookLooksClean);
    TserverArmSnap((const void *)&TserverSecurityAllowSensitiveWork);
    TserverArmSnap((const void *)&TserverAuthorizationLeaseIntegrityCheck);
    TserverArmSnap((const void *)&TserverAuthorizationLeasePerformCapability);
    TserverArmSnap((const void *)&SecKeyVerifySignature);
    TserverArmSnap((const void *)&TserverAuthorizationLeaseIsAuthorized);
    TserverArmSnap((const void *)&TserverAuthorizationLeaseAllowsCapability);
     TserverArmSnap((const void *)&TserverAuthorizationLeaseGeneration);
    TserverArmSnap((const void *)&TserverAuthBootstrapIsValid);
     TserverArmSnap((const void *)&TserverAuthBootstrapStartWithPrepared);
     TserverArmSnap((const void *)&APIClientStartAuthorization);
     TserverArmSnap((const void *)&APIClientPerformAuthorized);
     TserverArmSnap((const void *)&APIClientOpenPaid);
     TserverArmSnap((const void *)&APIClientConfirmKey);
     TserverArmSnap((const void *)&apiclient_paid);
     TserverArmSnap((const void *)&apiclient_on_login);
    TserverArmSnap((const void *)&TserverRuntimeIntegrityContext);
    TserverArmSnap((const void *)&TserverRuntimeIntegrityFlags);
    TserverArmSnap((const void *)&TserverRuntimeIntegrityCodeSignatureStatus);
    TserverArmSnap((const void *)&TserverRuntimeIntegrityExecutableStatus);
    // Arm sensitive system functions
    TserverArmSnap((const void *)&dlsym);
    TserverArmSnap((const void *)&dlopen);
    TserverArmSnap((const void *)&sysctl);
    TserverArmSnap((const void *)&exit);
    TserverArmSnap((const void *)&abort);
    TserverArmSnap((const void *)&objc_msgSend);
    (void)TserverCheckTextSegmentIntegrity();
  }
  return TserverCheckSnaps();
}

BOOL TserverAntiHookLooksClean(void) {
  if (TserverSuspiciousHookImages()) {
    gHookClean = NO;
    return NO;
  }
  if (!TserverAntiHookCriticalProloguesOK()) {
    gHookClean = NO;
    return NO;
  }
  if (!TserverCheckTextSegmentIntegrity()) {
    gHookClean = NO;
    return NO;
  }
  gHookClean = YES;
  return YES;
}

void TserverAntiDumpLock(void *p, size_t n) {
  if (!p || n == 0) return;
  (void)mlock(p, n);
#if defined(MADV_DONTDUMP)
  (void)madvise(p, n, MADV_DONTDUMP);
#endif
}

void TserverAntiDumpUnlockAndWipe(void *p, size_t n) {
  if (!p || n == 0) return;
  TserverSecureWipe(p, n);
  (void)munlock(p, n);
}

void TserverAntiHookStartWatchdog(void) {
  if (gWatchdogStarted) return;
  gWatchdogStarted = YES;
  (void)TserverAntiHookLooksClean();
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    while (YES) {
      @autoreleasepool {
        if (!TserverAntiHookLooksClean()) {
          gHookClean = NO;
        }
      }
      sleep(2);
    }
  });
}

BOOL TserverAntiHookLastClean(void) {
  return gHookClean;
}
