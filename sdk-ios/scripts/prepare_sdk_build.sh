#!/usr/bin/env bash
# One-shot prep before compiling libAPIClient.a
# - Font Awesome embed
# - CLIENT_API_KEY dual-XOR embed
# - Seal SDK constant tables (paths / markers / numeric IDs) into generated .mm
# - Never prints secrets
#
# Invoked automatically from Makefile `before-all` and build-lienquan-wsl.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/scripts/sdk_release_version.txt"
[[ -r "$VERSION_FILE" ]] || { echo "[prepare_sdk_build] missing sdk_release_version.txt" >&2; exit 1; }
SDK_RELEASE_VERSION="$(tr -d ' \r\n' < "$VERSION_FILE")"
[[ "$SDK_RELEASE_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "[prepare_sdk_build] invalid SDK release version" >&2; exit 1; }
python3 - "$ROOT/include/APIClient.h" "$ROOT/src/TserverAuth.mm" "$SDK_RELEASE_VERSION" <<'PY'
import re
import sys
from pathlib import Path
header = Path(sys.argv[1]).read_text(encoding="utf-8")
auth = Path(sys.argv[2]).read_text(encoding="utf-8")
expected = sys.argv[3]
header_version = re.search(r'#define\s+TSERVER_SDK_RELEASE_VERSION\s+@"([A-Za-z0-9._-]+)"', header)
# TserverSDKVersion / TserverSDKBuildIdentifier must match the release file exactly.
auth_versions = re.findall(
    r'(?:TserverSDKBuildIdentifier|TserverSDKVersion)\s*=\s*@"([A-Za-z0-9._-]+)"',
    auth,
)
required = ("APIClientStartAuthorizationWithEvents", "APICLIENT_HAS_TERMINAL_EVENTS")
if (
    not header_version
    or header_version.group(1) != expected
    or len(auth_versions) < 2
    or any(value != expected for value in auth_versions)
):
    raise SystemExit("[prepare_sdk_build] SDK release version markers diverge from sdk_release_version.txt")
if any(marker not in header for marker in required):
    raise SystemExit("[prepare_sdk_build] terminal activation API markers are missing")
PY
export SDK_RELEASE_VERSION
UI_ROOT="$(cd "$ROOT/../sdk-ios-ui" && pwd)"
SCRIPTS="$ROOT/scripts"

echo "[prepare_sdk_build] root=$ROOT"

# 1) Generate native UI-pack catalog/registry metadata from canonical manifests.
# Python is required by the existing sealed-constant generator below, so fail closed here too.
python3 "$SCRIPTS/generate_ui_template_catalog.py" \
  --templates "$UI_ROOT/templates" \
  --server-out "$ROOT/../server/src/generated/nativeAuthUiTemplates.ts" \
  --native-out "$UI_ROOT/src/TserverTemplateCatalog.gen.mm" \
  --make-out "$UI_ROOT/src/Templates.mk"

grep -Eq 'TSERVER_NATIVE_UI_TEMPLATE_COUNT [1-9][0-9]*' "$UI_ROOT/src/TserverTemplateCatalog.gen.mm" || {
  echo "[prepare_sdk_build] ERROR: native UI pack manifest output is invalid" >&2
  exit 1
}

# 2) Font Awesome (always exits 0)
if [[ -f "$UI_ROOT/scripts/embed_fa_font.sh" ]]; then
  bash "$UI_ROOT/scripts/embed_fa_font.sh" || true
else
  echo "[prepare_sdk_build] WARN: embed_fa_font.sh missing"
fi

# 3) Client API key embed. An archive without newly generated key material cannot
# authenticate, so never produce one after a failed or skipped embed.
[[ -n "${TSERVER_CLIENT_API_KEY:-}" ]] || {
  echo "[prepare_sdk_build] ERROR: TSERVER_CLIENT_API_KEY is required" >&2
  exit 1
}
[[ -f "$SCRIPTS/embed_client_api_key.sh" ]] || {
  echo "[prepare_sdk_build] ERROR: embed_client_api_key.sh is missing" >&2
  exit 1
}
bash "$SCRIPTS/embed_client_api_key.sh"
grep -q 'int TserverFillClientApiKeyHex' "$ROOT/src/TserverClientApiKeyData.gen.mm" || {
  echo "[prepare_sdk_build] ERROR: client key embed output is invalid" >&2
  exit 1
}

# 3b) Client build identity (ECDSA P-256). Keep CLIENT_API_KEY embed above;
# identity is independent attestation material for package request signing.
# Reuse is explicit so a UI-only rebuild does not silently rotate the key
# material that must already be registered on the production server.
if [[ "${TSERVER_REUSE_CLIENT_IDENTITY:-0}" == "1" ]]; then
  [[ -s "$ROOT/src/TserverClientIdentityData.gen.mm" && -s "$ROOT/client-identity.json" ]] || {
    echo "[prepare_sdk_build] ERROR: reuse requested but generated client identity is missing" >&2
    exit 1
  }
  echo "[prepare_sdk_build] reusing existing client identity"
else
  [[ -f "$SCRIPTS/generate_client_identity.sh" ]] || {
    echo "[prepare_sdk_build] ERROR: generate_client_identity.sh is missing" >&2
    exit 1
  }
  bash "$SCRIPTS/generate_client_identity.sh"
fi
grep -q 'TserverFillClientIdentityPrivateKeyDER' "$ROOT/src/TserverClientIdentityData.gen.mm" || {
  echo "[prepare_sdk_build] ERROR: client identity embed output is invalid" >&2
  exit 1
}

# 4) Seal SDK-internal constants / offset-like IDs. Do not silently retain a
# checked-in placeholder table when generation failed.
command -v python3 >/dev/null 2>&1 || {
  echo "[prepare_sdk_build] ERROR: python3 is required to generate SDK constants" >&2
  exit 1
}
python3 "$SCRIPTS/generate_sealed_sdk_constants.py" \
  --out-mm "$ROOT/src/TserverSealedConstants.gen.mm" \
  --out-h "$ROOT/include/TserverSealedConstants.h"
grep -q 'TserverSealedStringAt' "$ROOT/src/TserverSealedConstants.gen.mm" || {
  echo "[prepare_sdk_build] ERROR: sealed constants output is invalid" >&2
  exit 1
}

# 5) Embed the ES256 public-key keyring. This is public verification material;
# the matching private key must never leave the server.
[[ -n "${TSERVER_AUTHORIZATION_PUBLIC_KEYS:-}" ]] || {
  echo "[prepare_sdk_build] ERROR: TSERVER_AUTHORIZATION_PUBLIC_KEYS is required" >&2
  exit 1
}
command -v openssl >/dev/null 2>&1 || {
  echo "[prepare_sdk_build] ERROR: openssl is required for the lease keyring" >&2
  exit 1
}
python3 "$SCRIPTS/generate_authorization_keyring.py" \
  --keys "$TSERVER_AUTHORIZATION_PUBLIC_KEYS" \
  --out "$ROOT/src/TserverAuthorizationKeys.gen.mm"
grep -q 'TserverAuthorizationPublicKeyringReady' "$ROOT/src/TserverAuthorizationKeys.gen.mm" || {
  echo "[prepare_sdk_build] ERROR: authorization keyring output is invalid" >&2
  exit 1
}

# 6) Generated inputs required by the static archive must exist before compile.
for f in \
  "$ROOT/src/TserverClientApiKeyData.gen.mm" \
  "$ROOT/src/TserverClientIdentityData.gen.mm" \
  "$ROOT/src/TserverSealedConstants.gen.mm" \
  "$ROOT/src/TserverAuthorizationKeys.gen.mm" \
  "$UI_ROOT/src/TserverFontAwesomeData.gen.mm"
do
  [[ -f "$f" ]] || {
    echo "[prepare_sdk_build] ERROR: missing $f" >&2
    exit 1
  }
done

echo "[prepare_sdk_build] done"
