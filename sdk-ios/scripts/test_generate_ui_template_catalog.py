#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("generate_ui_template_catalog.py")


def pack(root: Path, pack_id: str, *, default: bool, fallback: str | None = None) -> None:
    folder = root / pack_id
    (folder / "screens").mkdir(parents=True)
    manifest = {
        "schemaVersion": 2,
        "id": pack_id,
        "name": pack_id,
        "description": pack_id,
        "tags": ["native"],
        "rendererId": pack_id,
        "rendererRevision": 1,
        "minimumSdkUiRevision": 2,
        "isDefault": default,
        "fallbackTemplate": fallback,
        "layout": "floating",
        "supportedOverrides": ["style", "screens"],
    }
    config = {
        "templateName": pack_id,
        "renderer": {"id": pack_id, "revision": 1},
        "layout": "floating",
        "screens": {"loading": {"title": f"loading-{pack_id}"}},
    }
    (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    (folder / "config.json").write_text(json.dumps(config), encoding="utf-8")
    (folder / f"{pack_id}.mm").write_text("// shell\n", encoding="utf-8")


def run(root: Path, expect_ok: bool = True) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
    server = root.parent / "catalog.ts"
    native = root.parent / "catalog.mm"
    make = root.parent / "Templates.mk"
    result = subprocess.run(
        [
            sys.executable, str(SCRIPT), "--templates", str(root),
            "--server-out", str(server), "--native-out", str(native), "--make-out", str(make),
        ],
        text=True,
        capture_output=True,
    )
    if expect_ok and result.returncode != 0:
        raise AssertionError(result.stderr)
    if not expect_ok and result.returncode == 0:
        raise AssertionError("generator unexpectedly succeeded")
    return result, server, native


class CatalogTests(unittest.TestCase):
    def test_multi_pack_default_and_fallback_are_generated_without_pack_hardcode(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "templates"
            pack(root, "pack_a", default=False, fallback="pack_b")
            pack(root, "pack_b", default=True)
            _, server, native = run(root)
            self.assertIn('NATIVE_AUTH_UI_DEFAULT_TEMPLATE_ID = "pack_b"', server.read_text(encoding="utf-8"))
            generated = native.read_text(encoding="utf-8")
            self.assertIn('return @"pack_b";', generated)
            self.assertIn('TserverDescriptor(@"pack_a", @"pack_a", 1, @"pack_b"', generated)
            self.assertIn('TserverDescriptor(@"pack_b", @"pack_b", 1, nil', generated)

    def test_requires_exactly_one_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "templates"
            pack(root, "pack_a", default=False)
            pack(root, "pack_b", default=False)
            result, _, _ = run(root, expect_ok=False)
            self.assertIn("exactly one", result.stderr)

    def test_rejects_missing_fallback_and_cycles(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "templates"
            pack(root, "pack_a", default=True, fallback="missing")
            result, _, _ = run(root, expect_ok=False)
            self.assertIn("does not exist", result.stderr)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "templates"
            pack(root, "pack_a", default=True, fallback="pack_b")
            pack(root, "pack_b", default=False, fallback="pack_a")
            result, _, _ = run(root, expect_ok=False)
            self.assertIn("cycle", result.stderr)


if __name__ == "__main__":
    unittest.main()
