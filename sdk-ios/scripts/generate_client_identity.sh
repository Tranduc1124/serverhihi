#!/usr/bin/env bash
# Generate ECDSA P-256 client build identity, scramble private key into
# src/TserverClientIdentityData.gen.mm, and write client-identity.json for
# server registration (public material only).
#
# Private key wire for SecKeyCreateWithData: 97-byte X9.63
#   0x04 || X(32) || Y(32) || d(32)
# kid = cid_ + sha256(SPKI DER)[0:16]
#
# Mirrors embed_client_api_key.sh anti-dump style (dual XOR + shuffle + nibble split).
# Usage: bash scripts/generate_client_identity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_MM="${ROOT}/src/TserverClientIdentityData.gen.mm"
OUT_JSON="${ROOT}/client-identity.json"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ts-cid.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

command -v openssl >/dev/null 2>&1 || {
  echo "[generate_client_identity] ERROR: openssl required" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "[generate_client_identity] ERROR: python3 required" >&2
  exit 1
}

SDK_VERSION="unknown"
VERSION_FILE="$ROOT/scripts/sdk_release_version.txt"
if [[ -r "$VERSION_FILE" ]]; then
  SDK_VERSION="$(tr -d ' \r\n' < "$VERSION_FILE")"
fi

PRIV_PEM="$WORKDIR/priv.pem"
PUB_PEM="$WORKDIR/pub.pem"
openssl ecparam -name prime256v1 -genkey -noout -out "$PRIV_PEM" 2>/dev/null
openssl ec -in "$PRIV_PEM" -pubout -out "$PUB_PEM" 2>/dev/null

PUB_SPKI="$WORKDIR/pub.spki.der"
openssl pkey -pubin -in "$PUB_PEM" -outform DER -out "$PUB_SPKI" 2>/dev/null

MASK1_HEX="$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
MASK2_HEX="$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
PERM_SEED="$(openssl rand -hex 16 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(16))')"

python3 - "$PRIV_PEM" "$PUB_SPKI" "$PUB_PEM" "$OUT_MM" "$OUT_JSON" "$SDK_VERSION" "$MASK1_HEX" "$MASK2_HEX" "$PERM_SEED" <<'PY'
import hashlib
import json
import random
import re
import subprocess
import sys
from pathlib import Path

priv_pem_path, pub_spki_path, pub_pem_path, out_mm, out_json, sdk_version, m1_hex, m2_hex, perm_seed = sys.argv[1:10]
spki = Path(pub_spki_path).read_bytes()
pub_pem = Path(pub_pem_path).read_text(encoding="utf-8").strip() + "\n"
kid = "cid_" + hashlib.sha256(spki).hexdigest()[:16]

# Build 97-byte SecKey private representation: 0x04||X||Y||d
text = subprocess.check_output(
    ["openssl", "ec", "-in", priv_pem_path, "-text", "-noout"],
    stderr=subprocess.DEVNULL,
).decode("utf-8", "replace")

def parse_hex_blob(label: str) -> bytes:
    # openssl ec -text prints "priv:" / "pub:" then indented colon-hex lines
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.strip().startswith(label + ":"):
            start = i + 1
            break
    if start is None:
        raise SystemExit(f"[generate_client_identity] missing {label} in openssl ec -text")
    chunks = []
    for line in lines[start:]:
        if not line.startswith(" ") and not line.startswith("\t"):
            break
        cleaned = re.sub(r"[^0-9a-fA-F]", "", line)
        if cleaned:
            chunks.append(cleaned)
    hex_chars = "".join(chunks)
    if len(hex_chars) % 2:
        hex_chars = "0" + hex_chars
    if not hex_chars:
        raise SystemExit(f"[generate_client_identity] empty {label} blob")
    return bytes.fromhex(hex_chars)

priv_scalar = parse_hex_blob("priv")
pub_point = parse_hex_blob("pub")
# openssl may print leading 00 on priv for high-bit values
if len(priv_scalar) == 33 and priv_scalar[0] == 0:
    priv_scalar = priv_scalar[1:]
if len(priv_scalar) > 32:
    priv_scalar = priv_scalar[-32:]
if len(priv_scalar) < 32:
    priv_scalar = (b"\x00" * (32 - len(priv_scalar))) + priv_scalar
if len(pub_point) != 65 or pub_point[0] != 0x04:
    raise SystemExit(f"[generate_client_identity] unexpected pub point len={len(pub_point)}")
if len(priv_scalar) != 32:
    raise SystemExit(f"[generate_client_identity] unexpected priv scalar len={len(priv_scalar)}")

priv = pub_point + priv_scalar  # 97 bytes for SecKeyCreateWithData
if len(priv) != 97:
    raise SystemExit(f"[generate_client_identity] unexpected raw key len {len(priv)}")

key_len = len(priv)
m1 = bytes.fromhex(m1_hex)
m2 = bytes.fromhex(m2_hex)

def expand(seed: bytes, n: int) -> bytes:
    out = bytearray()
    counter = 0
    while len(out) < n:
        out.extend(hashlib.sha256(seed + counter.to_bytes(4, "big")).digest())
        counter += 1
    return bytes(out[:n])

mask_a = expand(m1, key_len)
mask_b = expand(m2, key_len)
enc = bytes(a ^ b ^ c for a, b, c in zip(priv, mask_a, mask_b))

rng = random.Random(int.from_bytes(bytes.fromhex(perm_seed), "big"))
perm = list(range(key_len))
rng.shuffle(perm)
enc_shuf = bytes(enc[perm[i]] for i in range(key_len))
inv = [0] * key_len
for i, p in enumerate(perm):
    inv[p] = i

hi = bytes((b >> 4) & 0x0F for b in enc_shuf)
lo = bytes(b & 0x0F for b in enc_shuf)
decoy1 = expand(bytes.fromhex(perm_seed), key_len)
decoy2 = bytes(b ^ 0xA5 for b in decoy1)
hi_store = bytes(((decoy1[i] & 0xF0) | hi[i]) for i in range(key_len))
lo_store = bytes(((decoy2[i] & 0xF0) | lo[i]) for i in range(key_len))
m1_shuf = bytes(mask_a[perm[i]] for i in range(key_len))
m2_shuf = bytes(mask_b[perm[i]] for i in range(key_len))

def c_array(name, data, width=16):
    lines = []
    for i in range(0, len(data), width):
        chunk = ", ".join(f"0x{b:02x}" for b in data[i:i + width])
        lines.append(f"  {chunk}")
    return f"static const uint8_t {name}[{len(data)}] = {{\n" + ",\n".join(lines) + "\n};\n"

def c_u16_array(name, values):
    lines = []
    for i in range(0, len(values), 16):
        chunk = ", ".join(str(int(v)) for v in values[i:i + 16])
        lines.append(f"  {chunk}")
    return f"static const uint16_t {name}[{len(values)}] = {{\n" + ",\n".join(lines) + "\n};\n"

kid_c = "".join(f"\\x{ord(c):02x}" for c in kid)

content = f"""// AUTO-GENERATED by scripts/generate_client_identity.sh — do not edit.
// Client ECDSA P-256 identity anti-dump embed (97-byte X9.63 private: 04||X||Y||d).
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static const char kTserverClientIdentityKid[] = "{kid_c}";
static const size_t kTserverClientIdentityKeyLen = {key_len};

{c_array("kTserverCidHi", hi_store)}
{c_array("kTserverCidLo", lo_store)}
{c_array("kTserverCidMaskA", m1_shuf)}
{c_array("kTserverCidMaskB", m2_shuf)}
{c_u16_array("kTserverCidInvPerm", inv)}

#ifdef __cplusplus
extern "C" {{
#endif

const char *TserverClientIdentityKidCStr(void) {{
  return kTserverClientIdentityKid;
}}

// Reconstruct X9.63 private key bytes into out[0..*outLen). Returns 0 on success.
int TserverFillClientIdentityPrivateKeyDER(uint8_t *out, size_t outCap, size_t *outLen) {{
  if (!out || !outLen || outCap < kTserverClientIdentityKeyLen) return -1;
  if (kTserverClientIdentityKeyLen != 97) return -1;

  uint8_t enc_shuf[128];
  uint8_t enc[128];
  uint8_t plain[128];

  for (size_t i = 0; i < kTserverClientIdentityKeyLen; i++) {{
    uint8_t h = (uint8_t)(kTserverCidHi[i] & 0x0Fu);
    uint8_t l = (uint8_t)(kTserverCidLo[i] & 0x0Fu);
    enc_shuf[i] = (uint8_t)((h << 4) | l);
  }}
  for (size_t j = 0; j < kTserverClientIdentityKeyLen; j++) {{
    uint16_t idx = kTserverCidInvPerm[j];
    if (idx >= kTserverClientIdentityKeyLen) {{
      return -1;
    }}
    enc[j] = enc_shuf[idx];
  }}
  for (size_t j = 0; j < kTserverClientIdentityKeyLen; j++) {{
    uint16_t idx = kTserverCidInvPerm[j];
    uint8_t ma = kTserverCidMaskA[idx];
    uint8_t mb = kTserverCidMaskB[idx];
    plain[j] = (uint8_t)(enc[j] ^ ma ^ mb);
  }}
  if (plain[0] != 0x04) {{
    volatile uint8_t *w = plain;
    for (size_t i = 0; i < kTserverClientIdentityKeyLen; i++) w[i] = 0;
    return -1;
  }}
  memcpy(out, plain, kTserverClientIdentityKeyLen);
  *outLen = kTserverClientIdentityKeyLen;

  volatile uint8_t *w;
  w = enc_shuf; for (size_t i = 0; i < kTserverClientIdentityKeyLen; i++) w[i] = 0;
  w = enc;      for (size_t i = 0; i < kTserverClientIdentityKeyLen; i++) w[i] = 0;
  w = plain;    for (size_t i = 0; i < kTserverClientIdentityKeyLen; i++) w[i] = 0;
  return 0;
}}

int TserverClientIdentityDataEmbedOk(void) {{
  uint32_t acc = 0;
  for (size_t i = 0; i < kTserverClientIdentityKeyLen; i++) {{
    acc |= kTserverCidHi[i];
    acc |= kTserverCidLo[i];
    acc |= kTserverCidMaskA[i];
    acc |= kTserverCidMaskB[i];
    acc |= (uint8_t)kTserverCidInvPerm[i];
  }}
  acc |= (uint32_t)kTserverClientIdentityKid[0];
  return (acc != 0 && kTserverClientIdentityKeyLen == 97) ? 0 : -1;
}}

#ifdef __cplusplus
}}
#endif
"""
Path(out_mm).write_text(content, encoding="utf-8")

reg = {
    "kid": kid,
    "publicKeyPem": pub_pem,
    "sdkVersion": sdk_version,
    "sdkBuild": 0,
    "status": "ACTIVE",
    "notes": "generated by generate_client_identity.sh",
}
Path(out_json).write_text(json.dumps(reg, indent=2) + "\n", encoding="utf-8")
print(f"[generate_client_identity] wrote {out_mm}")
print(f"[generate_client_identity] wrote {out_json} kid={kid}")
PY
