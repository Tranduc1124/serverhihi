#import "TserverAntiPatch.h"
#import "TserverRuntimeIntegrity.h"
#import "TserverSecureBlob.h"
#import "TserverAntiHook.h"
#import "TserverStringCrypto.h"
#import <Foundation/Foundation.h>
#include <stdint.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>

// Critical C functions we call from auth paths — patch-call often replaces these pointers
// or rewrites BL targets to trampolines (prologue check is separate in TserverAntiHook).

#ifdef __cplusplus
extern "C" {
#endif
int TserverFillClientApiKeyHex(char *out, size_t outCap);
int TserverClientApiKeyEmbedOk(void);
int TserverSecureBlobOpen(const void *sealed, size_t sealedSize, void *out, size_t outCap);
BOOL TserverAntiHookLooksClean(void);
BOOL TserverSecurityAllowSensitiveWork(void);
BOOL TserverAuthorizationLeaseIntegrityCheck(void);
BOOL TserverAuthorizationLeasePerformCapability(NSString *, dispatch_block_t, dispatch_block_t);
uint64_t TserverAuthorizationLeaseGeneration(void);
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

typedef struct {
  const void *expected;
  const void * (*resolver)(void);
  const char *tag;
  BOOL armed;
} TserverPatchWatch;

static const void *Resolve_FillKey(void) { return (const void *)&TserverFillClientApiKeyHex; }
static const void *Resolve_EmbedOk(void) { return (const void *)&TserverClientApiKeyEmbedOk; }
static const void *Resolve_BlobOpen(void) { return (const void *)&TserverSecureBlobOpen; }
static const void *Resolve_AntiHookClean(void) { return (const void *)&TserverAntiHookLooksClean; }
static const void *Resolve_SecureWipe(void) { return (const void *)&TserverSecureWipe; }
static const void *Resolve_SecurityGate(void) { return (const void *)&TserverSecurityAllowSensitiveWork; }
static const void *Resolve_LeaseIntegrity(void) { return (const void *)&TserverAuthorizationLeaseIntegrityCheck; }
static const void *Resolve_LeaseCapability(void) { return (const void *)&TserverAuthorizationLeasePerformCapability; }
static const void *Resolve_LeaseGeneration(void) { return (const void *)&TserverAuthorizationLeaseGeneration; }
static const void *Resolve_RuntimeIntegrityContext(void) { return (const void *)&TserverRuntimeIntegrityContext; }
static const void *Resolve_RuntimeIntegrityFlags(void) { return (const void *)&TserverRuntimeIntegrityFlags; }
static const void *Resolve_RuntimeCodeSignature(void) { return (const void *)&TserverRuntimeIntegrityCodeSignatureStatus; }
static const void *Resolve_RuntimeExecutable(void) { return (const void *)&TserverRuntimeIntegrityExecutableStatus; }
static const void *Resolve_BootstrapPrepared(void) { return (const void *)&TserverAuthBootstrapStartWithPrepared; }
static const void *Resolve_APIClientStartAuthorization(void) { return (const void *)&APIClientStartAuthorization; }
static const void *Resolve_APIClientPerformAuthorized(void) { return (const void *)&APIClientPerformAuthorized; }
static const void *Resolve_APIClientOpenPaid(void) { return (const void *)&APIClientOpenPaid; }
static const void *Resolve_APIClientConfirmKey(void) { return (const void *)&APIClientConfirmKey; }
static const void *Resolve_apiclient_paid(void) { return (const void *)&apiclient_paid; }
static const void *Resolve_apiclient_on_login(void) { return (const void *)&apiclient_on_login; }

// Encrypted at rest: packed list of expected relative offsets from a slide base.
// We don't store absolute pointers in the binary; we re-resolve via symbol address each arm
// and keep the baseline only in RAM (harder for static patch of .data expected ptrs).

static TserverPatchWatch gWatches[] = {
  { NULL, Resolve_FillKey, "FillKey", NO },
  { NULL, Resolve_EmbedOk, "EmbedOk", NO },
  { NULL, Resolve_BlobOpen, "BlobOpen", NO },
  { NULL, Resolve_AntiHookClean, "AntiHook", NO },
  { NULL, Resolve_SecureWipe, "Wipe", NO },
  { NULL, Resolve_SecurityGate, "SecurityGate", NO },
  { NULL, Resolve_LeaseIntegrity, "LeaseIntegrity", NO },
  { NULL, Resolve_LeaseCapability, "LeaseCapability", NO },
  { NULL, Resolve_LeaseGeneration, "LeaseGeneration", NO },
  { NULL, Resolve_RuntimeIntegrityContext, "RuntimeIntegrityContext", NO },
  { NULL, Resolve_RuntimeIntegrityFlags, "RuntimeIntegrityFlags", NO },
  { NULL, Resolve_RuntimeCodeSignature, "RuntimeCodeSignature", NO },
  { NULL, Resolve_RuntimeExecutable, "RuntimeExecutable", NO },
  { NULL, Resolve_BootstrapPrepared, "BootstrapPrepared", NO },
  { NULL, Resolve_APIClientStartAuthorization, "APIClientStartAuthorization", NO },
  { NULL, Resolve_APIClientPerformAuthorized, "APIClientPerformAuthorized", NO },
  { NULL, Resolve_APIClientOpenPaid, "APIClientOpenPaid", NO },
  { NULL, Resolve_APIClientConfirmKey, "APIClientConfirmKey", NO },
  { NULL, Resolve_apiclient_paid, "apiclient_paid", NO },
  { NULL, Resolve_apiclient_on_login, "apiclient_on_login", NO },
};
static const size_t gWatchCount = sizeof(gWatches) / sizeof(gWatches[0]);

static BOOL gArmed = NO;
static BOOL gWatchdogStarted = NO;
static volatile BOOL gClean = YES;

// ObjC IMP watches (class name / selector) — detect method_setImplementation patches.
typedef struct {
  char className[64];
  char selectorName[64];
  IMP expected;
  BOOL armed;
} TserverImpWatch;

static TserverImpWatch gImpWatches[16];
static size_t gImpWatchCount = 0;

static void TserverArmImp(const char *cls, const char *selName) {
  if (gImpWatchCount >= sizeof(gImpWatches) / sizeof(gImpWatches[0])) return;
  Class c = objc_getClass(cls);
  if (!c) return;
  SEL sel = sel_registerName(selName);
  Method m = class_getClassMethod(c, sel);
  if (!m) m = class_getInstanceMethod(c, sel);
  if (!m) return;
  IMP imp = method_getImplementation(m);
  if (!imp) return;
  TserverImpWatch *w = &gImpWatches[gImpWatchCount++];
  strncpy(w->className, cls, sizeof(w->className) - 1);
  w->className[sizeof(w->className) - 1] = '\0';
  strncpy(w->selectorName, selName, sizeof(w->selectorName) - 1);
  w->selectorName[sizeof(w->selectorName) - 1] = '\0';
  w->expected = imp;
  w->armed = YES;
}

static BOOL TserverCheckImps(void) {
  for (size_t i = 0; i < gImpWatchCount; i++) {
    TserverImpWatch *w = &gImpWatches[i];
    if (!w->armed) continue;
    Class c = objc_getClass(w->className);
    if (!c) return NO;
    SEL sel = sel_registerName(w->selectorName);
    Method m = class_getClassMethod(c, sel);
    if (!m) m = class_getInstanceMethod(c, sel);
    if (!m) return NO;
    IMP imp = method_getImplementation(m);
    if (imp != w->expected) return NO;
  }
  return YES;
}

// Sealed u32 "token" table — not real file offsets, but rolling fingerprints of
// function addresses mixed with a key so a static patch of gWatches.expected fails
// without also patching this blob consistently (raises cost). The table covers
// the auth gates and runtime-integrity probes.
static uint8_t gSealedFpBlob[sizeof(TserverSecureBlobHeader) + 96];
static BOOL gSealedReady = NO;

static void TserverRebuildSealedFingerprints(void) {
  uint32_t fps[24];
  memset(fps, 0, sizeof(fps));
  size_t n = gWatchCount < 24 ? gWatchCount : 24;
  for (size_t i = 0; i < n; i++) {
    uintptr_t p = (uintptr_t)gWatches[i].expected;
    // Mix high/low to avoid storing raw pointer bits plainly in RAM snapshot blob.
    fps[i] = (uint32_t)(p ^ (p >> 17) ^ (0xA5A5A5A5u * (uint32_t)(i + 1)));
  }
  int sealed = TserverSecureBlobSeal(fps, (size_t)n * 4, gSealedFpBlob, sizeof(gSealedFpBlob));
  gSealedReady = sealed > 0;
}

static BOOL TserverVerifySealedFingerprints(void) {
  if (!gSealedReady) return NO;
  uint32_t fps[24];
  int count = TserverSecureBlobOpenU32Table(gSealedFpBlob, sizeof(gSealedFpBlob), fps, 24);
  if (count <= 0) return NO;
  size_t n = gWatchCount < (size_t)count ? gWatchCount : (size_t)count;
  for (size_t i = 0; i < n; i++) {
    uintptr_t p = (uintptr_t)gWatches[i].resolver();
    uint32_t now = (uint32_t)(p ^ (p >> 17) ^ (0xA5A5A5A5u * (uint32_t)(i + 1)));
    if (now != fps[i]) return NO;
    // Also ensure resolver still returns the armed expected pointer.
    if ((const void *)p != gWatches[i].expected) return NO;
  }
  return YES;
}

void TserverAntiPatchArm(void) {
  for (size_t i = 0; i < gWatchCount; i++) {
    gWatches[i].expected = gWatches[i].resolver();
    gWatches[i].armed = gWatches[i].expected != NULL;
  }
  // Optional ObjC class methods that attackers often swizzle on Unity hosts.
  gImpWatchCount = 0;
  TserverArmImp(TS_OBF_STR("NSJSONSerialization"), TS_OBF_STR("JSONObjectWithData:options:error:"));
  TserverArmImp(TS_OBF_STR("NSJSONSerialization"), TS_OBF_STR("dataWithJSONObject:options:error:"));
  // High-value gate / paid-boundary selectors.
  TserverArmImp(TS_OBF_STR("TserverGateUI"), TS_OBF_STR("completeValidResult:"));
  TserverArmImp(TS_OBF_STR("TserverGateUI"), TS_OBF_STR("dismiss"));
  TserverArmImp(TS_OBF_STR("TserverGateUI"), TS_OBF_STR("isValidStatus:"));
  TserverArmImp(TS_OBF_STR("TserverGateUI"), TS_OBF_STR("setOnValid:"));
  TserverArmImp(TS_OBF_STR("APIClient"), TS_OBF_STR("performAuthorized:work:denied:"));
  TserverArmImp(TS_OBF_STR("APIClient"), TS_OBF_STR("openPaid:"));
  TserverArmImp(TS_OBF_STR("APIClient"), TS_OBF_STR("confirmKey:success:failure:"));
  TserverArmImp(TS_OBF_STR("TserverAuth"), TS_OBF_STR("activateKey:sessionToken:completion:"));
  TserverArmImp(TS_OBF_STR("TserverAuth"), TS_OBF_STR("bootstrapWithCompletion:"));
  TserverRebuildSealedFingerprints();
  gArmed = YES;
  gClean = TserverAntiPatchLooksClean();
}

BOOL TserverAntiPatchLooksClean(void) {
  if (!gArmed) {
    TserverAntiPatchArm();
  }
  for (size_t i = 0; i < gWatchCount; i++) {
    if (!gWatches[i].armed) continue;
    const void *now = gWatches[i].resolver();
    if (now != gWatches[i].expected) {
      gClean = NO;
      return NO;
    }
  }
  if (!TserverCheckImps()) {
    gClean = NO;
    return NO;
  }
  if (!TserverVerifySealedFingerprints()) {
    gClean = NO;
    return NO;
  }
  // Cross-check with prologue anti-hook.
  if (!TserverAntiHookLooksClean()) {
    gClean = NO;
    return NO;
  }
  gClean = YES;
  return YES;
}

void TserverAntiPatchStartWatchdog(void) {
  if (gWatchdogStarted) return;
  gWatchdogStarted = YES;
  TserverAntiPatchArm();
  TserverAntiHookStartWatchdog();
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    while (YES) {
      @autoreleasepool {
        if (!TserverAntiPatchLooksClean()) {
          gClean = NO;
        }
      }
      sleep(2);
    }
  });
}
