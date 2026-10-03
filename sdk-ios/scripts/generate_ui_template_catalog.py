#!/usr/bin/env python3
"""Discover and validate native UI packs.

Simple layout:
  sdk-ios-ui/templates/<pack>/manifest.json
  sdk-ios-ui/templates/<pack>/config.json
  sdk-ios-ui/templates/<pack>/<Pack>.mm          # pack shell
  sdk-ios-ui/templates/<pack>/screens/*.mm       # optional per-screen files

Every discovered .mm is included in the SDK build automatically.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ID_RE = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
REQUIRED = {
    "schemaVersion", "id", "name", "description", "tags", "rendererId",
    "rendererRevision", "minimumSdkUiRevision", "isDefault", "fallbackTemplate", "layout",
    "supportedOverrides",
}


def load_packs(root: Path) -> list[dict]:
    packs: list[dict] = []
    seen: set[str] = set()
    for manifest_path in sorted(root.glob("*/manifest.json")):
        folder = manifest_path.parent
        if folder.name == "starter_simple_ui":
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        missing = REQUIRED - manifest.keys()
        if missing:
            raise ValueError(f"{manifest_path}: missing {', '.join(sorted(missing))}")
        pack_id = manifest["id"]
        if not isinstance(pack_id, str) or not ID_RE.fullmatch(pack_id) or pack_id in seen:
            raise ValueError(f"{manifest_path}: invalid or duplicate id")
        seen.add(pack_id)
        if manifest["schemaVersion"] != 2 or not isinstance(manifest["rendererRevision"], int):
            raise ValueError(f"{manifest_path}: unsupported schema/revision")
        if not isinstance(manifest["isDefault"], bool):
            raise ValueError(f"{manifest_path}: isDefault must be boolean")
        fallback = manifest["fallbackTemplate"]
        if fallback is not None and (not isinstance(fallback, str) or not ID_RE.fullmatch(fallback)):
            raise ValueError(f"{manifest_path}: fallbackTemplate must be null or a valid pack id")
        if not isinstance(manifest["rendererId"], str) or not ID_RE.fullmatch(manifest["rendererId"]):
            raise ValueError(f"{manifest_path}: invalid rendererId")
        config_path = folder / "config.json"
        if not config_path.is_file():
            raise ValueError(f"{manifest_path}: missing config.json")
        config = json.loads(config_path.read_text(encoding="utf-8"))
        renderer = config.get("renderer", {})
        if config.get("templateName") != pack_id or renderer.get("id") != manifest["rendererId"] or renderer.get("revision") != manifest["rendererRevision"]:
            raise ValueError(f"{config_path}: id/renderer does not match manifest")
        shell_files = sorted(folder.glob("*.mm"))
        if len(shell_files) != 1:
            raise ValueError(f"{folder}: exactly one pack shell .mm file is required")
        source_files = [shell_files[0], *sorted((folder / "screens").glob("*.mm"))]
        manifest["config"] = config
        manifest["sourceFiles"] = [source.relative_to(root.parent).as_posix() for source in source_files]
        manifest["folder"] = folder.name
        packs.append(manifest)
    if not packs:
        raise ValueError("no UI pack folders found")

    pack_ids = {pack["id"] for pack in packs}
    defaults = [pack for pack in packs if pack["isDefault"]]
    if len(defaults) != 1:
        raise ValueError(f"exactly one native UI pack must declare isDefault=true (found {len(defaults)})")
    for pack in packs:
        fallback = pack["fallbackTemplate"]
        if fallback is not None and fallback not in pack_ids:
            raise ValueError(f"{pack['id']}: fallbackTemplate target does not exist: {fallback}")

    for pack in packs:
        visited: set[str] = set()
        current = pack
        while current["fallbackTemplate"] is not None:
            current_id = current["id"]
            if current_id in visited:
                raise ValueError(f"fallback cycle detected from {pack['id']}")
            visited.add(current_id)
            next_id = current["fallbackTemplate"]
            current = next(candidate for candidate in packs if candidate["id"] == next_id)
    return packs


def write(path: Path, content: str, check: bool) -> None:
    if check:
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            raise ValueError(f"generated file drift: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--templates", type=Path, required=True)
    parser.add_argument("--server-out", type=Path, required=True)
    parser.add_argument("--native-out", type=Path, required=True)
    parser.add_argument("--make-out", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    packs = load_packs(args.templates)
    canonical = json.dumps(packs, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(canonical.encode()).hexdigest()
    default_id = next(pack["id"] for pack in packs if pack["isDefault"])
    server = (
        "// Generated by generate_ui_template_catalog.py. Do not edit.\n"
        + f"export const NATIVE_AUTH_UI_TEMPLATE_MANIFEST_SHA256 = \"{digest}\";\n"
        + f"export const NATIVE_AUTH_UI_DEFAULT_TEMPLATE_ID = \"{default_id}\";\n"
        + "export const NATIVE_AUTH_UI_TEMPLATE_CATALOG = "
        + json.dumps(packs, ensure_ascii=False, indent=2)
        + " as const;\n"
    )

    # Generate forward declarations and force-load anchors for all discovered packs
    class_decls = "\n".join([f"@interface TserverPack_{p['rendererId']} : TserverSimpleUiPackBase\n@end" for p in packs])
    known_classes = "\n".join([f"        [TserverPack_{p['rendererId']} class]," for p in packs])
    name_lookups = "\n".join([f"    if ([rendererId isEqualToString:@\"{p['rendererId']}\"]) return [TserverPack_{p['rendererId']} class];" for p in packs])
    force_classes = "\n".join([f"        (void)[TserverPack_{p['rendererId']} class];" for p in packs])

    def objc_literal(value):
        if value is None:
            return "[NSNull null]"
        if value is True:
            return "@YES"
        if value is False:
            return "@NO"
        if isinstance(value, (int, float)):
            return f"@{value}"
        if isinstance(value, str):
            escaped = value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
            return f'@"{escaped}"'
        if isinstance(value, list):
            return "@[" + ", ".join(objc_literal(item) for item in value) + "]"
        if isinstance(value, dict):
            pairs = [f"@\"{key}\": {objc_literal(item)}" for key, item in value.items()]
            return "@{" + ", ".join(pairs) + "}"
        raise ValueError(f"unsupported config value type: {type(value).__name__}")

    # Generate full immutable descriptor config for every pack. No global palette is allowed.
    descriptors_list = []
    for p in packs:
        descriptor_config = {
            "schemaVersion": p["schemaVersion"],
            **p["config"],
            "templateName": p["id"],
            "renderer": {"id": p["rendererId"], "revision": p["rendererRevision"]},
        }
        overrides_literal = objc_literal(p.get("supportedOverrides", ["style", "screens", "assets", "animation", "typography", "popup", "geometry"]))
        fallback_literal = "nil" if p.get("fallbackTemplate") is None else objc_literal(p["fallbackTemplate"])
        descriptors_list.append(
            f"            TserverDescriptor({objc_literal(p['id'])}, {objc_literal(p['rendererId'])}, {p['rendererRevision']}, "
            f"{fallback_literal}, {objc_literal(descriptor_config)}, {overrides_literal})"
        )
    descriptors_code = ",\n".join(descriptors_list)

    native = (
        "// Generated native UI manifest marker and auto-registration.\n"
        f"#define TSERVER_NATIVE_UI_TEMPLATE_MANIFEST_SHA256 @\"{digest}\"\n"
        f"#define TSERVER_NATIVE_UI_TEMPLATE_COUNT {len(packs)}\n\n"
        "#import \"TserverSimpleUiPack.h\"\n"
        "#import \"TserverTemplateRegistry.h\"\n\n"
        f"{class_decls}\n\n"
        "static inline Class _TserverResolvedClassForRendererId(NSString *rendererId) {\n"
        f"{name_lookups}\n"
        "    return nil;\n"
        "}\n\n"
        "static inline void _TserverKeepPackClassesLive(void) {\n"
        "    Class knownPacks[] = {\n"
        f"{known_classes}\n"
        "    };\n"
        "    (void)knownPacks;\n"
        "}\n\n"
        "static inline void _TserverForceLoadAllPacksOnce(void) {\n"
        f"{force_classes}\n"
        "}\n\n"
        "static inline NSString *_TserverGeneratedDefaultTemplateId(void) {\n"
        f"    return {objc_literal(default_id)};\n"
        "}\n\n"
        "static inline NSArray<TserverTemplateDescriptor *> *_TserverGeneratedDescriptors(void) {\n"
        "    return @[\n"
        f"{descriptors_code}\n"
        "    ];\n"
        "}\n"
    )

    pack_sources = [source for pack in packs for source in pack["sourceFiles"]]
    sdk_sources = [
        "../sdk-ios-ui/src/TserverTemplateRegistry.mm",
        "../sdk-ios-ui/src/TserverNativeTemplateRenderer.mm",
        "../sdk-ios-ui/src/TserverSimpleUiPack.mm",
        *[f"../sdk-ios-ui/{source}" for source in pack_sources],
    ]
    make = "# Generated by generate_ui_template_catalog.py\nTSERVER_UI_TEMPLATE_FILES = \\\n" + " \\\n".join(f"\t{source}" for source in sdk_sources) + "\n"
    write(args.server_out, server, args.check)
    write(args.native_out, native, args.check)
    write(args.make_out, make, args.check)
    print(f"[ui-template-catalog] {len(packs)} pack(s) · {len(pack_sources)} UI source file(s) · {digest[:12]}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"[ui-template-catalog] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
