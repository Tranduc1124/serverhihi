#!/usr/bin/env bash
# Embed Font Awesome Free Solid into a C++ source for static linking into libAPIClient.a.
# Output: sdk-ios-ui/src/TserverFontAwesomeData.gen.mm
#
# Offline-friendly order:
#   1) gen.mm already has a real embed (skip work)
#   2) existing assets/fa-solid-900.ttf
#   3) Windows host download (powershell / curl.exe) when WSL DNS is broken
#   4) WSL curl/wget
#   5) empty stub (SF Symbols fallback at runtime)
#
# Never fail the caller for network/download issues — always exit 0 with a usable gen.mm.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="$UI_DIR/assets"
OUT_MM="$UI_DIR/src/TserverFontAwesomeData.gen.mm"
FONT_FILE="$ASSETS_DIR/fa-solid-900.ttf"
FA_URL_PRIMARY="https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.5.2/webfonts/fa-solid-900.ttf"
FA_URL_FALLBACK="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/webfonts/fa-solid-900.ttf"

mkdir -p "$ASSETS_DIR" "$(dirname "$OUT_MM")"

write_stub() {
  cat > "$OUT_MM" <<'MM'
// Auto-generated stub — Font Awesome file missing. Do not edit.
// Run: bash sdk-ios-ui/scripts/embed_fa_font.sh
//
// C++ notes:
// - plain `const` at namespace scope = internal linkage (unused warning under -Werror)
// - use `extern const` for external linkage
// - __attribute__((used)) only on DEFINITIONS (not bare extern declarations)
#include <stddef.h>
#include <stdint.h>
extern "C" {
extern const uint8_t kTserverFontAwesomeSolidBytes[];
extern const size_t kTserverFontAwesomeSolidLength;
extern const uint8_t kTserverFontAwesomeSolidBytes[] __attribute__((used)) = {0};
extern const size_t kTserverFontAwesomeSolidLength __attribute__((used)) = 0;
}
MM
}

font_ok() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local n
  n="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
  [[ "${n:-0}" -ge 10000 ]]
}

# Already embedded a real font? Skip re-download/re-write (avoids race with concurrent make hooks).
gen_already_embedded() {
  [[ -f "$OUT_MM" ]] || return 1
  # Real embed has a multi-KB length constant, not "= 0".
  if grep -q 'kTserverFontAwesomeSolidLength __attribute__((used)) = 0;' "$OUT_MM" 2>/dev/null; then
    return 1
  fi
  if grep -Eq 'kTserverFontAwesomeSolidLength __attribute__\(\(used\)\) = [1-9][0-9]{4,};' "$OUT_MM" 2>/dev/null; then
    return 0
  fi
  # Also accept without attribute if present
  if grep -Eq 'kTserverFontAwesomeSolidLength = [1-9][0-9]{4,};' "$OUT_MM" 2>/dev/null; then
    return 0
  fi
  return 1
}

download_one() {
  # $1 = url, writes to FONT_FILE via unique tmp then atomic rename
  local url="$1"
  local tmp
  tmp="$(mktemp "${ASSETS_DIR}/fa-solid-900.XXXXXX.tmp" 2>/dev/null || echo "${ASSETS_DIR}/fa-solid-900.$$.$RANDOM.tmp")"

  cleanup_tmp() { rm -f "$tmp" 2>/dev/null || true; }

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 20 --max-time 120 -o "$tmp" "$url" 2>/dev/null && font_ok "$tmp"; then
      mv -f "$tmp" "$FONT_FILE"
      cleanup_tmp
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -O "$tmp" "$url" 2>/dev/null && font_ok "$tmp"; then
      mv -f "$tmp" "$FONT_FILE"
      cleanup_tmp
      return 0
    fi
  fi
  cleanup_tmp
  return 1
}

download_via_windows() {
  # Prefer writing straight to final path (no shared .tmp race).
  if command -v powershell.exe >/dev/null 2>&1; then
    local ps_path="$FONT_FILE"
    if [[ "$FONT_FILE" == /mnt/* ]]; then
      local drive rest
      drive="$(printf '%s' "$FONT_FILE" | cut -d/ -f3 | tr '[:lower:]' '[:upper:]')"
      rest="$(printf '%s' "$FONT_FILE" | cut -d/ -f4- | tr '/' '\\')"
      ps_path="${drive}:\\${rest}"
    fi
    echo "[embed_fa_font] Trying Windows powershell download…"
    if powershell.exe -NoProfile -Command \
      "\$u=@('${FA_URL_PRIMARY}','${FA_URL_FALLBACK}'); \$o='${ps_path}'; New-Item -ItemType Directory -Force -Path (Split-Path \$o) | Out-Null; foreach(\$x in \$u){ try { Invoke-WebRequest -Uri \$x -OutFile \$o -UseBasicParsing; if((Get-Item \$o).Length -gt 10000){ exit 0 } } catch {} }; exit 1" \
      >/dev/null 2>&1; then
      font_ok "$FONT_FILE" && return 0
    fi
  fi

  if command -v curl.exe >/dev/null 2>&1; then
    echo "[embed_fa_font] Trying Windows curl.exe download…"
    local url tmp
    for url in "$FA_URL_PRIMARY" "$FA_URL_FALLBACK"; do
      tmp="$(mktemp "${ASSETS_DIR}/fa-solid-900.XXXXXX.tmp" 2>/dev/null || echo "${ASSETS_DIR}/fa-solid-900.win.$$.$RANDOM.tmp")"
      if curl.exe -fsSL --connect-timeout 20 --max-time 120 -o "$tmp" "$url" 2>/dev/null && font_ok "$tmp"; then
        mv -f "$tmp" "$FONT_FILE"
        rm -f "$tmp" 2>/dev/null || true
        return 0
      fi
      rm -f "$tmp" 2>/dev/null || true
    done
  fi
  return 1
}

download_via_wsl() {
  local url
  for url in "$FA_URL_PRIMARY" "$FA_URL_FALLBACK"; do
    if download_one "$url"; then
      return 0
    fi
  done
  return 1
}

embed_font_file() {
  local font="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[embed_fa_font] ERROR: python3 required to embed font" >&2
    write_stub
    return 0
  fi
  local bytes
  bytes="$(wc -c < "$font" | tr -d ' ')"
  echo "[embed_fa_font] Embedding $font ($bytes bytes) → $OUT_MM"
  if ! python3 - "$font" "$OUT_MM" <<'PY'
import sys
path, out = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
if len(data) < 1000:
    raise SystemExit("font too small")
chunks = []
line = []
for b in data:
    line.append(f"0x{b:02x}")
    if len(line) == 12:
        chunks.append(", ".join(line))
        line = []
if line:
    chunks.append(", ".join(line))
body = ",\n  ".join(chunks)
open(out, "w", encoding="utf-8", newline="\n").write(
    "// Auto-generated by sdk-ios-ui/scripts/embed_fa_font.sh — do not edit.\n"
    "// C++: `extern const` for external linkage; `used` only on definitions.\n"
    "#include <stddef.h>\n#include <stdint.h>\n"
    "extern \"C\" {\n"
    "extern const uint8_t kTserverFontAwesomeSolidBytes[];\n"
    "extern const size_t kTserverFontAwesomeSolidLength;\n"
    f"extern const uint8_t kTserverFontAwesomeSolidBytes[] __attribute__((used)) = {{\n  {body}\n}};\n"
    f"extern const size_t kTserverFontAwesomeSolidLength __attribute__((used)) = {len(data)};\n"
    "}\n"
)
print(f"[embed_fa_font] ok ({len(data)} bytes)")
PY
  then
    echo "[embed_fa_font] WARN: python embed failed — writing stub."
    write_stub
  fi
}

# --- main ---
if gen_already_embedded; then
  echo "[embed_fa_font] gen.mm already embedded — skip."
  exit 0
fi

if ! font_ok "$FONT_FILE"; then
  echo "[embed_fa_font] Font missing/small — downloading Font Awesome Free Solid 6.5.2…"
  if ! download_via_windows && ! download_via_wsl; then
    echo "[embed_fa_font] WARN: download failed — writing empty stub (SF Symbols fallback at runtime)."
    write_stub
    exit 0
  fi
fi

if font_ok "$FONT_FILE"; then
  embed_font_file "$FONT_FILE"
else
  echo "[embed_fa_font] WARN: font still missing after download — stub."
  write_stub
fi

echo "[embed_fa_font] Done."
exit 0
