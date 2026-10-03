#!/usr/bin/env python3
"""Fail a release when a built archive exposes forbidden secret patterns."""
from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact")
    args = parser.parse_args()
    data = Path(args.artifact).read_bytes()
    rules = {
        "private-key-pem": rb"-----BEGIN (?:EC |RSA )?PRIVATE KEY-----",
        "runtime-package-token": rb"pkg_[A-Za-z0-9_-]{20,}",
    }
    forbidden_client_key = os.environ.get("TSERVER_RELEASE_FORBIDDEN_CLIENT_KEY", "").strip().lower()
    if re.fullmatch(r"[0-9a-f]{64}", forbidden_client_key):
        rules["client-key-hex"] = re.escape(forbidden_client_key.encode("ascii"))
    failures = [name for name, pattern in rules.items() if re.search(pattern, data)]
    # Defense in depth. verify_release_pair parses Mach-O sections precisely; this
    # byte scan also catches common debug payloads in malformed/unexpected archives.
    for marker in (b"__DWARF", b"__debug_info", b"__debug_line", b"__debug_str"):
        if marker in data:
            failures.append(f"debug-section:{marker.decode('ascii')}")
    # Exact release paths/host should be provided by sealed/generated tables. A
    # debug build may opt out explicitly, but production packaging must not.
    for literal in [
        b"/v1/package/license/activate",
        b"/v1/package/license/verify",
        b"proxy.huutien.store",
        b"authorizationLeaseVersion",
    ]:
        if literal in data:
            failures.append(f"plaintext:{literal.decode('ascii')}")
    if failures:
        print("[release_scan] rejected: " + ", ".join(failures))
        return 1
    print("[release_scan] passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
