# serverhihi — libAPIClient.a build

Builds the Tserver iOS SDK (`sdk-ios` + `sdk-ios-ui`) into the two-file customer
package and publishes `libAPIClient.a` as an artifact and as a release asset on
the `sdk-latest` tag.

## Why a macOS runner

The archive has to be produced with Apple's toolchain. A `libAPIClient.a` built
on Linux/Theos links with warnings on every object:

```
ld: warning: object file built with an incompatible arm64e ABI:
  vendor/APIClient/libAPIClient.a(TserverCrypto.mm.o)
```

and the host app then dies during `dyld4::APIs::runAllInitializersForMain()`
with `EXC_BAD_ACCESS ... (possible pointer authentication failure)` on arm64e
devices, before `main()` runs.

## Required repository secret

| Name | Meaning |
|---|---|
| `TSERVER_CLIENT_API_KEY` | 64-hex client key, same value as `CLIENT_API_KEY` in the server `.env`. Secret, never committed. |

Everything else is public material and lives in the workflow file: the lease
public keyring (`lease-2026-01`), the TLS SPKI pin, and the committed client
identity.

## Client identity is reused on purpose

`TSERVER_REUSE_CLIENT_IDENTITY=1` keeps `sdk-ios/src/TserverClientIdentityData.gen.mm`
and `sdk-ios/client-identity.json`, so every build ships the same `kid`. A
freshly generated keypair would produce an unregistered `kid` and the package
API would reject every request until the identity is registered server-side.

## Consuming the result

Download `libAPIClient.a` from the `sdk-latest` release and drop it into a host
project's `vendor/APIClient/`. The customer header (`APIClient.h`) is part of
the host project, not this release: it holds the package token.