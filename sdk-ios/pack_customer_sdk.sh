#!/usr/bin/env bash
# Package the supported customer SDK (public APIClient header + static archive).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../dist/APIClient"
DIST_ARCHIVE="$ROOT/../dist/APIClient/libAPIClient.a"
OBJ_ARCHIVE="$ROOT/.theos/obj/libAPIClient.a"
DEBUG_ARCHIVE="$ROOT/.theos/obj/debug/libAPIClient.a"
ARCHIVE=""

# Prefer the already stripped/validated Makefile artifact when it is newer than
# the raw Theos object archive; llvm-strip cannot process every raw Mach-O load
# command in the unstripped merged archive.
if [[ -s "$DIST_ARCHIVE" && ( ! -s "$OBJ_ARCHIVE" || "$DIST_ARCHIVE" -nt "$OBJ_ARCHIVE" ) ]]; then
  ARCHIVE="$DIST_ARCHIVE"
else
  for candidate in "$OBJ_ARCHIVE" "$DEBUG_ARCHIVE"; do
    if [[ -s "$candidate" ]]; then
      ARCHIVE="$candidate"
      break
    fi
  done
fi

[[ -n "$ARCHIVE" ]] || {
  echo "ERROR: current libAPIClient.a build output is missing. Run: cd $ROOT && make clean all" >&2
  exit 1
}
[[ -f "$ROOT/scripts/scan_release_artifact.py" && -f "$ROOT/scripts/verify_release_pair.py" ]] || {
  echo "ERROR: release validators are missing" >&2
  exit 1
}
command -v llvm-strip >/dev/null 2>&1 || {
  echo "ERROR: llvm-strip is required for release SDK packaging" >&2
  exit 1
}
# The Ubuntu system strip understands the already validated ar slices; the
# Theos LLVM strip can reject LC_LINKER_OPTION in a merged archive.
STRIP_TOOL="$(command -v llvm-strip)"
if [[ -x /usr/bin/llvm-strip ]]; then
  STRIP_TOOL="/usr/bin/llvm-strip"
fi

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tserver-sdk-package.XXXXXXXX")"
cleanup_validation() { rm -rf -- "$VALIDATION_DIR"; }
trap cleanup_validation EXIT

# Never ship compiler debug data or local symbols even if a caller supplied a
# nonstandard Theos configuration. Validate and package this stripped copy only.
cp -f "$ARCHIVE" "$VALIDATION_DIR/libAPIClient.release.a"
RELEASE_ARCHIVE="$VALIDATION_DIR/libAPIClient.release.a"
if file "$RELEASE_ARCHIVE" | grep -q "Mach-O universal binary"; then
  command -v llvm-lipo >/dev/null 2>&1 || {
    echo "ERROR: llvm-lipo is required to strip a universal SDK archive" >&2
    exit 1
  }
  SLICE_DIR="$VALIDATION_DIR/slices"
  mkdir -p "$SLICE_DIR"
  SLICES=()
  for arch in $(llvm-lipo -archs "$RELEASE_ARCHIVE"); do
    slice="$SLICE_DIR/$arch.a"
    llvm-lipo -thin "$arch" "$RELEASE_ARCHIVE" -o "$slice"
    "$STRIP_TOOL" --strip-debug "$slice"
    SLICES+=("$slice")
  done
  (( ${#SLICES[@]} > 0 )) || {
    echo "ERROR: universal SDK archive has no architecture slices" >&2
    exit 1
  }
  llvm-lipo -create "${SLICES[@]}" -o "$RELEASE_ARCHIVE"
else
  "$STRIP_TOOL" --strip-debug "$RELEASE_ARCHIVE"
fi
ARCHIVE="$RELEASE_ARCHIVE"

# Extract every ar slice from the exact selected artifact. The Theos merged output
# is usually a FAT Mach-O wrapper even for one arm64 architecture.
mapfile -t MEMBER_ARCHIVES < <(
  python3 - "$ARCHIVE" "$VALIDATION_DIR" <<'PY'
import struct
import sys
from pathlib import Path

source = Path(sys.argv[1])
out = Path(sys.argv[2])
data = source.read_bytes()
AR_MAGIC = b"!<arch>\n"
if data.startswith(AR_MAGIC):
    print(source)
    raise SystemExit(0)
if len(data) < 8 or data[:4] not in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
    raise SystemExit("ERROR: SDK archive is neither ar nor FAT Mach-O")
endian = ">" if data[:4] == b"\xca\xfe\xba\xbe" else "<"
count = struct.unpack_from(endian + "I", data, 4)[0]
if count < 1 or count > 8 or len(data) < 8 + count * 20:
    raise SystemExit("ERROR: invalid FAT architecture table")
seen = []
for index in range(count):
    _, _, offset, size, _ = struct.unpack_from(endian + "IIIII", data, 8 + index * 20)
    if size < len(AR_MAGIC) or offset > len(data) or size > len(data) - offset:
        raise SystemExit("ERROR: FAT archive slice is out of bounds")
    interval = (offset, offset + size)
    if any(interval[0] < right and left < interval[1] for left, right in seen):
        raise SystemExit("ERROR: FAT archive slices overlap")
    seen.append(interval)
    payload = data[offset : offset + size]
    if not payload.startswith(AR_MAGIC):
        raise SystemExit("ERROR: FAT slice is not an ar archive")
    target = out / f"slice-{index}.a"
    target.write_bytes(payload)
    print(target)
PY
)
(( ${#MEMBER_ARCHIVES[@]} > 0 )) || {
  echo "ERROR: no architecture slice was extracted" >&2
  exit 1
}

for member_archive in "${MEMBER_ARCHIVES[@]}"; do
  members="$(ar t "$member_archive")" || {
    echo "ERROR: cannot inspect archive slice" >&2
    exit 1
  }
  for required_member in \
    APIClient.mm \
    TserverAuth.mm \
    TserverAuthBootstrap.mm \
    TserverStorage.mm \
    TserverCallbackBridge.mm \
    TserverCallbackDedup.mm \
    TserverUUIDCallback.mm \
    TserverGateUI.mm \
    TserverGateView.mm \
    TserverGateWindow.mm \
    TserverAuthorizationLease.mm \
    TserverAuthorizationKeys.gen.mm \
    TserverCrypto.mm \
    TserverHttp.mm \
    TserverPinning.mm \
    TserverTransportSession.mm \
    TserverAntiHook.mm \
    TserverAntiPatch.mm \
    TserverSealedConstants.gen.mm
  do
    grep -Fq "$required_member" <<<"$members" || {
      echo "ERROR: archive is stale or incomplete (missing $required_member)" >&2
      exit 1
    }
  done
done

SDK_VERSION="$(python3 - "$ROOT/include/APIClient.h" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'#define\s+TSERVER_SDK_RELEASE_VERSION\s+@"([A-Za-z0-9._-]+)"', text)
if not match:
    raise SystemExit("ERROR: APIClient.h is missing TSERVER_SDK_RELEASE_VERSION")
print(match.group(1))
PY
)"
grep -aFq "$SDK_VERSION" "$ARCHIVE" || {
  echo "ERROR: header/archive SDK version mismatch ($SDK_VERSION)" >&2
  exit 1
}

python3 "$ROOT/scripts/verify_release_pair.py" --require-arm64e "$ROOT/include/APIClient.h" "$ARCHIVE"
TSERVER_RELEASE_FORBIDDEN_CLIENT_KEY="${TSERVER_CLIENT_API_KEY:-}" python3 "$ROOT/scripts/scan_release_artifact.py" "$ARCHIVE"
source_sha="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -f "$ROOT/include/APIClient.h" "$OUT/APIClient.h"
cp -f "$ARCHIVE" "$OUT/libAPIClient.a"
cp -f "$ROOT/../docs/CUSTOMER_INTEGRATION.md" "$OUT/INTEGRATE.md"
output_sha="$(sha256sum "$OUT/libAPIClient.a" | cut -d' ' -f1)"
[[ "$output_sha" == "$source_sha" ]] || {
  echo "ERROR: packaged SDK archive hash mismatch" >&2
  exit 1
}
python3 "$ROOT/scripts/scan_release_artifact.py" "$OUT/libAPIClient.a"

printf 'Customer SDK package: %s\n' "$OUT"
printf 'Archive: %s\n' "$OUT/libAPIClient.a"
printf 'Header: %s\n' "$OUT/APIClient.h"
