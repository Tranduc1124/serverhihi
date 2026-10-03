#pragma once

// Tserver SDK Function & Internal Symbol Obfuscation
// Scrambles critical C functions, secret store resolvers, and security checkpoints.

#define TserverFillClientApiKeyHex                  _0x7a1b9f
#define TserverClientApiKeyEmbedOk                  _0x3e4c8d
#define TserverSecureBlobOpen                       _0x9b2a1f
#define TserverSecureBlobOpenU32Table               _0x6d8e0a
#define TserverSecureWipe                           _0x5c9f2a
#define TserverAntiHookLooksClean                   _0x1f5c3b
#define TserverAntiHookCriticalProloguesOK          _0x4a9d7e
#define TserverAntiHookStartWatchdog                _0x7e2d9a
#define TserverAntiHookLastClean                    _0x2b8c4f
#define TserverAntiDumpLock                         _0x8d3e1a
#define TserverAntiDumpUnlockAndWipe                _0x4f1a7b
#define TserverAntiPatchLooksClean                  _0x8c2e4f
#define TserverAntiPatchStartWatchdog               _0x3a9f2c
#define TserverSecurityAllowSensitiveWork           _0x5b3a9c
#define TserverSecurityRuntimeRiskFlags             _0x6d1e4a
#define TserverSecurityEnforceAntiDebug             _0x9a2f7c
#define TserverSecurityStartWatchdog                _0x4e8b1d
#define TserverAuthorizationLeaseIntegrityCheck     _0x2e8f1a
#define TserverAuthorizationLeaseAllowsCapability   _0x9f5e2d
#define TserverAuthorizationLeaseInvalidate         _0x1d4a8c
#define TserverAuthorizationLeaseLicenseInfo        _0x7c3b9e
#define TserverAuthBootstrapStart                   _0x8e1b3f
#define TserverAuthBootstrapIsValid                 _0x6a4d9b
#define TserverAuthBootstrapConfigure               _0x2c9f4d
#define TserverAuthDrainPendingCallbackURLs         _0x5f1e8a
#define TserverCompiledPrimaryEndpoint              _0x4c7a2e
#define TserverCompiledFallbackEndpoint             _0x9d2b5f
#define TserverRuntimeBaseURL                       _0x1a8d5f
#define TserverRuntimeClientApiKey                  _0x9e2b4c
#define TserverCompiledClientApiKey                 _0x3f6c1a
#define TserverResolvedPackageToken                 _0x8b4c2e
#define TserverPinningValidateLeafSPKI              _0x7f3a1d
#define TserverAuthUiConfigIntegrityAllowsPersist   _0x2a9e6b
#define TserverAuthUiVerifiedCacheEnvelope          _0x4d1b8f
#define TserverDecodedNSString                      _0x6c2f9a
#define TserverDecodedCString                       _0x1e8a4d
#define TserverSecureMemZero                        _0x9f4b2e
