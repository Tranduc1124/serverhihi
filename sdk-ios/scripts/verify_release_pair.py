#!/usr/bin/env python3
"""Validate a public SDK header and every supported arm64/ar slice."""
from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path

AR_MAGIC = b"!<arch>\n"
MACHO64_LE_MAGIC = b"\xcf\xfa\xed\xfe"
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64_ALL = 0
CPU_SUBTYPE_ARM64_V8 = 1
CPU_SUBTYPE_ARM64E = 2
CPU_SUBTYPE_MASK = 0x00FFFFFF
LC_SEGMENT_64 = 0x19
FORBIDDEN_DEBUG_SEGMENTS = {b"__DWARF"}
FORBIDDEN_DEBUG_SECTIONS = {
    b"__debug_abbrev",
    b"__debug_aranges",
    b"__debug_info",
    b"__debug_line",
    b"__debug_line_str",
    b"__debug_loc",
    b"__debug_loclists",
    b"__debug_names",
    b"__debug_pubnames",
    b"__debug_pubtypes",
    b"__debug_ranges",
    b"__debug_rnglists",
    b"__debug_str",
    b"__debug_str_offs",
}
REQUIRED_MEMBERS = (
    "APIClient.mm",
    "TserverActivationAttempt.mm",
    "TserverAuth.mm",
    "TserverAuthBootstrap.mm",
    "TserverStorage.mm",
    "TserverCallbackBridge.mm",
    "TserverCallbackDedup.mm",
    "TserverUUIDCallback.mm",
    "TserverGateUI.mm",
    "TserverGateView.mm",
    "TserverGateWindow.mm",
    "TserverTemplateRegistry.mm",
    "TserverNativeTemplateRenderer.mm",
    "TserverSimpleUiPack.mm",
    "CyberTerminal.mm",
    "TserverAuthorizationLease.mm",
    "TserverAuthorizationKeys.gen.mm",
    "TserverCrypto.mm",
    "TserverHttp.mm",
    "TserverPinning.mm",
    "TserverTransportSession.mm",
    "TserverClientIdentity.mm",
    "TserverClientIdentityData.gen.mm",
    "TserverAntiHook.mm",
    "TserverAntiPatch.mm",
    "TserverLogGuard.mm",
    "TserverSealedConstants.gen.mm",
)
# Screen object basenames must be unique per pack to avoid ar/libtool collisions.
REQUIRED_SCREEN_MEMBERS = (
    "CyberTerminalLoading.mm",
    "CyberTerminalKeyEntry.mm",
    "CyberTerminalDeviceVerify.mm",
    "CyberTerminalResult.mm",
)
REQUIRED_SYMBOLS = {
    "APIClient.mm": (
        b"APIClientStartAuthorization",
        b"APIClientStartAuthorizationWithEvents",
        b"APIClientPerformAuthorized",
        b"APIClientOpenPaid",
        b"APIClientConfirmKey",
        b"apiclient_paid",
        b"apiclient_on_login",
        b"APIClientHandleOpenURL",
    ),
    "TserverAuthBootstrap.mm": (b"TserverAuthBootstrapStartWithPrepared",),
    "TserverActivationAttempt.mm": (
        b"TserverActivationAttemptDidFinishNotification",
        # The terminal status literals are defined once in TserverAuth.mm. This
        # object references their exported symbols, so require the reference
        # rather than a duplicate literal that the linker may coalesce away.
        b"TserverStatusActivationTimeout",
        b"TserverStatusUnsafeEnvironment",
    ),
    "TserverAuthorizationLease.mm": (
        b"TserverAuthorizationLeaseInstall",
        b"TserverAuthorizationLeasePerformCapability",
        b"TserverAuthorizationLeaseGeneration",
    ),
    "TserverCrypto.mm": (b"encryptTransportPayloadV3", b"aes-256-gcm-hkdf"),
    "TserverHttp.mm": (b"TserverPinningConsumeValidatedSession", b"Transport v3"),
    "TserverPinning.mm": (b"TserverPinningConsumeValidatedSession", b"TserverPinningUnionAdvertisedSpkiPins"),
    "TserverTransportSession.mm": (b"transportVersion", b"hs3|"),
    "TserverClientIdentity.mm": (b"TserverClientIdentityKid", b"TserverClientIdentitySignUTF8Payload"),
    "TserverClientIdentityData.gen.mm": (b"TserverFillClientIdentityPrivateKeyDER",),
    "TserverCallbackDedup.mm": (b"TserverCallbackURLShouldProcess",),
}


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def is_required_member(name: str, required: str) -> bool:
    leaf = name.rsplit("/", 1)[-1]
    return leaf.startswith(required + ".") and leaf.endswith(".o")


def fixed_c_string(value: bytes) -> bytes:
    return value.split(b"\0", 1)[0]


def architecture_name(cpusubtype: int) -> str:
    normalized = cpusubtype & CPU_SUBTYPE_MASK
    if normalized in (CPU_SUBTYPE_ARM64_ALL, CPU_SUBTYPE_ARM64_V8):
        return "arm64"
    if normalized == CPU_SUBTYPE_ARM64E:
        return "arm64e"
    fail(f"unsupported arm64 CPU subtype: 0x{cpusubtype:08x}")
    return ""  # pragma: no cover - fail() raises


def validate_macho_object(name: str, payload: bytes) -> None:
    if len(payload) < 32 or payload[:4] != MACHO64_LE_MAGIC:
        fail(f"archive member is not a 64-bit little-endian Mach-O object: {name}")
    cputype, cpusubtype = struct.unpack_from("<II", payload, 4)
    if cputype != CPU_TYPE_ARM64:
        fail(f"archive member is not arm64/arm64e: {name}")
    architecture_name(cpusubtype)
    command_count, command_bytes = struct.unpack_from("<II", payload, 16)
    if command_count > 4096 or command_bytes > len(payload) - 32:
        fail(f"Mach-O load command table is invalid: {name}")
    offset = 32
    command_end = 32 + command_bytes
    for _ in range(command_count):
        if offset + 8 > command_end:
            fail(f"Mach-O load command is truncated: {name}")
        command, command_size = struct.unpack_from("<II", payload, offset)
        if command_size < 8 or command_size > command_end - offset:
            fail(f"Mach-O load command size is invalid: {name}")
        if command == LC_SEGMENT_64:
            if command_size < 72:
                fail(f"Mach-O segment command is truncated: {name}")
            segment = fixed_c_string(payload[offset + 8 : offset + 24])
            section_count = struct.unpack_from("<I", payload, offset + 64)[0]
            if command_size != 72 + section_count * 80:
                fail(f"Mach-O segment section table is invalid: {name}")
            if segment in FORBIDDEN_DEBUG_SEGMENTS:
                fail(f"archive member contains debug segment {segment.decode('ascii')}: {name}")
            section_offset = offset + 72
            for index in range(section_count):
                entry = section_offset + index * 80
                section = fixed_c_string(payload[entry : entry + 16])
                section_segment = fixed_c_string(payload[entry + 16 : entry + 32])
                if section_segment in FORBIDDEN_DEBUG_SEGMENTS or section in FORBIDDEN_DEBUG_SECTIONS or section.startswith(b"__debug_"):
                    label = section.decode("ascii", errors="replace")
                    fail(f"archive member contains debug section {label}: {name}")
        offset += command_size
    if offset != command_end:
        fail(f"Mach-O load command table length is invalid: {name}")


def parse_ar_members(data: bytes) -> list[tuple[str, bytes]]:
    if not data.startswith(AR_MAGIC):
        fail("archive slice is not ar")
    offset = len(AR_MAGIC)
    members: list[tuple[str, bytes]] = []
    while offset < len(data):
        if offset + 60 > len(data):
            fail("truncated ar header")
        header = data[offset : offset + 60]
        if header[58:60] != b"`\n":
            fail("invalid ar header")
        try:
            size = int(header[48:58].decode("ascii").strip())
        except (UnicodeDecodeError, ValueError):
            fail("invalid ar member size")
        if size < 0 or size > len(data) - offset - 60:
            fail("ar member is out of bounds")
        name = header[:16].decode("ascii", errors="strict").strip().rstrip("/")
        payload_offset = offset + 60
        payload_size = size
        if name.startswith("#1/"):
            try:
                name_length = int(name[3:])
            except ValueError:
                fail("invalid extended ar member name")
            if name_length <= 0 or name_length > size:
                fail("extended ar member name is out of bounds")
            name = data[payload_offset : payload_offset + name_length].decode("utf-8", errors="strict").rstrip("\0")
            payload_offset += name_length
            payload_size -= name_length
        if name and name not in ("/", "//") and not name.startswith("__.SYMDEF"):
            payload = data[payload_offset : payload_offset + payload_size]
            validate_macho_object(name, payload)
            members.append((name, payload))
        offset += 60 + size
        if offset % 2:
            offset += 1
    if offset != len(data) or not members:
        fail("archive contains no valid object members")
    return members


def archive_slices(data: bytes, require_arm64e: bool = False) -> list[bytes]:
    architectures: set[str] = set()
    if data.startswith(AR_MAGIC):
        members = parse_ar_members(data)
        architectures.update(
            architecture_name(struct.unpack_from("<I", payload, 8)[0])
            for _, payload in members
        )
        slices = [data]
    else:
        if len(data) < 8 or data[:4] not in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
            fail("library is neither ar nor FAT archive")
        endian = ">" if data[:4] == b"\xca\xfe\xba\xbe" else "<"
        count = struct.unpack_from(endian + "I", data, 4)[0]
        table_end = 8 + count * 20
        if count < 1 or count > 8 or len(data) < table_end:
            fail("invalid FAT architecture table")
        intervals: list[tuple[int, int]] = []
        slices = []
        for index in range(count):
            cpu_type, cpu_subtype, offset, size, _ = struct.unpack_from(endian + "IIIII", data, 8 + index * 20)
            if cpu_type != CPU_TYPE_ARM64:
                fail("FAT archive contains a non-arm64/arm64e slice")
            architectures.add(architecture_name(cpu_subtype))
            if size < len(AR_MAGIC) or offset < table_end or offset > len(data) or size > len(data) - offset:
                fail("FAT archive slice is out of bounds")
            right = offset + size
            if any(offset < previous_right and left < right for left, previous_right in intervals):
                fail("FAT archive slices overlap")
            intervals.append((offset, right))
            slices.append(data[offset:right])
        # Lipo alignment gaps are zero-filled. Reject hidden provenance strings outside
        # declared slices rather than letting global substring checks consume them.
        covered = bytearray(len(data))
        covered[:table_end] = b"\x01" * table_end
        for left, right in intervals:
            covered[left:right] = b"\x01" * (right - left)
        if any(byte != 0 for byte, marker in zip(data, covered) if marker == 0):
            fail("FAT archive contains non-zero bytes outside declared slices")
    if require_arm64e and not {"arm64", "arm64e"}.issubset(architectures):
        fail(f"dual-architecture SDK required; found {sorted(architectures)}")
    return slices


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("header")
    parser.add_argument("library")
    parser.add_argument("--expected-client-key-fingerprint")
    parser.add_argument("--expected-lease-kid", action="append", default=[])
    parser.add_argument(
        "--require-arm64e",
        action="store_true",
        help="require both arm64 and arm64e slices in a universal SDK archive",
    )
    args = parser.parse_args()

    header_path = Path(args.header)
    library_path = Path(args.library)
    try:
        header = header_path.read_text(encoding="utf-8")
        library = library_path.read_bytes()
    except (OSError, UnicodeError) as error:
        fail(str(error))
    version_match = re.search(r'#define\s+TSERVER_SDK_RELEASE_VERSION\s+@"([A-Za-z0-9._-]+)"', header)
    if not version_match:
        fail("APIClient.h is missing TSERVER_SDK_RELEASE_VERSION")
    version = version_match.group(1)
    for api in ("APIClientConfigure", "APIClientStartAuthorization", "APIClientStartAuthorizationWithEvents", "APIClientPerformAuthorized", "APIClientHandleOpenURL"):
        if api not in header:
            fail(f"APIClient.h is missing {api}")

    expected_fingerprint = (args.expected_client_key_fingerprint or "").strip().lower()
    if expected_fingerprint and not re.fullmatch(r"[0-9a-f]{64}", expected_fingerprint):
        fail("expected client-key fingerprint is invalid")
    expected_kids: list[str] = []
    for kid in args.expected_lease_kid:
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", kid) or kid in expected_kids:
            fail("expected lease key id is invalid or duplicated")
        expected_kids.append(kid)

    slices = archive_slices(library, require_arm64e=args.require_arm64e)
    for slice_index, data in enumerate(slices):
        members = parse_ar_members(data)
        selected: dict[str, bytes] = {}
        for required in REQUIRED_MEMBERS:
            matches = [payload for name, payload in members if is_required_member(name, required)]
            if len(matches) != 1:
                fail(f"archive slice {slice_index} requires exactly one {required} object")
            selected[required] = matches[0]
        for required in REQUIRED_SCREEN_MEMBERS:
            matches = [payload for name, payload in members if is_required_member(name, required)]
            if len(matches) != 1:
                fail(f"archive slice {slice_index} requires exactly one {required} object")
            selected[required] = matches[0]
        for required, symbols in REQUIRED_SYMBOLS.items():
            for symbol in symbols:
                if symbol not in selected[required]:
                    fail(f"{required} does not define/reference required marker {symbol.decode('ascii')}")
        if version.encode("utf-8") not in selected["TserverAuth.mm"]:
            fail(f"archive slice {slice_index} TserverAuth.mm version differs from APIClient.h")
        if b"trollstore" in selected["TserverLogGuard.mm"] or b"_exit" in selected["TserverLogGuard.mm"]:
            fail("TserverLogGuard still contains installer-kill behavior")
        if expected_fingerprint:
            # This member is not in the minimal module list but must exist in release
            # builds when provenance attestation is requested.
            matches = [payload for name, payload in members if is_required_member(name, "TserverClientApiKeyData.gen.mm")]
            if len(matches) != 1 or expected_fingerprint.encode("ascii") not in matches[0]:
                fail("archive does not contain the expected client-key fingerprint in its generated key object")
        keyring = selected["TserverAuthorizationKeys.gen.mm"]
        for kid in expected_kids:
            if kid.encode("ascii") not in keyring:
                fail(f"authorization keyring does not contain key id {kid}")

    print(f"[release_pair] passed (version={version}, slices={len(slices)}, lease_keys={len(expected_kids)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
