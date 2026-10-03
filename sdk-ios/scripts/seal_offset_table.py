#!/usr/bin/env python3
"""Seal a list of u32 offsets/ids into a TserverSecureBlob for embedding in the dylib.

Usage:
  python3 seal_offset_table.py 0x1000 0x20b0 0x30c4 > sealed_offsets.inc

Output is a C byte array you can paste as:
  static const unsigned char kMySealedOffsets[] = { ... };

Runtime:
  uint32_t table[N];
  TserverSecureBlobOpenU32Table(kMySealedOffsets, sizeof(kMySealedOffsets), table, N);

This is anti-dump / anti-strings only — not strong encryption.
"""
from __future__ import annotations
import secrets
import struct
import sys

MAGIC = 0x31525354  # TSERVER_SECURE_BLOB_MAGIC

def keystream(key: bytes, n: int) -> bytes:
    s0 = int.from_bytes(key[0:4], "little")
    s1 = int.from_bytes(key[4:8], "little")
    s2 = int.from_bytes(key[8:12], "little")
    s3 = int.from_bytes(key[12:16], "little")
    if (s0 | s1 | s2 | s3) == 0:
        s0, s1, s2, s3 = 0xA5A5A5A5, 0x3C6EF372, 0x1F83D9AB, 0x9E3779B9
    out = bytearray(n)
    for i in range(n):
        t = (s0 ^ ((s0 << 11) & 0xFFFFFFFF)) & 0xFFFFFFFF
        s0 = s1
        s1 = s2
        s2 = s3
        s3 = (s3 ^ (s3 >> 19) ^ t ^ (t >> 8)) & 0xFFFFFFFF
        out[i] = s3 & 0xFF
    return bytes(out)

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    vals = []
    for a in sys.argv[1:]:
        vals.append(int(a, 0) & 0xFFFFFFFF)
    plain = b"".join(struct.pack("<I", v) for v in vals)
    key = secrets.token_bytes(16)
    ks = keystream(key, len(plain))
    enc = bytes(a ^ b for a, b in zip(plain, ks))
    blob = struct.pack("<II", MAGIC, len(plain)) + key + enc
    print("// sealed u32 x", len(vals))
    print("static const unsigned char kSealedOffsetTable[] = {")
    for i in range(0, len(blob), 12):
        chunk = blob[i:i+12]
        print("  " + ", ".join(f"0x{b:02x}" for b in chunk) + ",")
    print("};")
    print(f"// sizeof = {len(blob)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
