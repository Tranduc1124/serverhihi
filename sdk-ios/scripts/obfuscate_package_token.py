#!/usr/bin/env python3
"""Obfuscate a pkg_ token for TserverAuthConfig.h (optional).

Usage:
  python3 obfuscate_package_token.py 'pkg_xxxxx'

Paste the printed kTserverPackageTokenEnc / Mask lines into TserverAuthConfig.h
and set kTserverPackageTokenUseObfuscated = 1.

This is NOT strong crypto — only stops casual `strings` dumps of the full token.
"""
from __future__ import annotations
import secrets
import sys

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    token = sys.argv[1].strip()
    if not token.startswith("pkg_") or len(token) < 24:
        print("ERROR: expected pkg_... token", file=sys.stderr)
        return 2
    raw = token.encode("utf-8")
    mask = secrets.token_bytes(len(raw))
    enc = bytes(a ^ b for a, b in zip(raw, mask))

    def c_bytes(data: bytes) -> str:
        return ", ".join(f"0x{b:02x}" for b in data)

    print("// Paste into TserverAuthConfig.h (keep both arrays same length)")
    print(f"static const unsigned char kTserverPackageTokenEnc[] = {{ {c_bytes(enc)} }};")
    print(f"static const unsigned char kTserverPackageTokenMask[] = {{ {c_bytes(mask)} }};")
    print(f"static const unsigned kTserverPackageTokenEncLen = {len(raw)};")
    print("static const int kTserverPackageTokenUseObfuscated = 1;")
    print('// static NSString * const kTserverPackageToken = @""; // unused when obfuscated')
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
