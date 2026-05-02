#!/usr/bin/env python3
"""
Server-side lookup for dynamic iBeacon tags.

Current model:
  - each operator has its own static iBeacon UUID
  - our tags share one static UUID within the region
  - Major/Minor are derived from AES-128-ECB(KEY, tag_id || slot || 0x00[10])
  - the server determines the operator by UUID
  - for our UUID: resolve TagID locally
  - for foreign UUIDs: route the request to the operator REST endpoint

Legacy support:
  - BNSO "Umka" packets: ID = Major * 65536 + Minor
  - BNSO "Scout" packets: ID = Major + Minor
"""

from __future__ import annotations

import argparse
import datetime
import json
import struct
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

try:
    from Crypto.Cipher import AES
except ImportError:
    try:
        from Cryptodome.Cipher import AES
    except ImportError:
        AES = None


# ---- Pure Python AES-128 fallback ---------------------------------------

def _aes128_sbox(x: int) -> int:
    sbox = [
        0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
        0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
        0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
        0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
        0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
        0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
        0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
        0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
        0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
        0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
        0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
        0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
        0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
        0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
        0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
        0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
    ]
    return sbox[x]


def _xtime(x: int) -> int:
    return ((x << 1) ^ (0x1B if x & 0x80 else 0)) & 0xFF


def _gf_mul(a: int, b: int) -> int:
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        a = _xtime(a)
        b >>= 1
    return p


def aes128_ecb_encrypt_pure(key: bytes, block: bytes) -> bytes:
    assert len(key) == 16
    assert len(block) == 16

    w = list(key)
    rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]
    for i in range(4, 44):
        t = w[(i - 1) * 4:(i - 1) * 4 + 4]
        if i % 4 == 0:
            t = [
                _aes128_sbox(t[1]) ^ rcon[i // 4 - 1],
                _aes128_sbox(t[2]),
                _aes128_sbox(t[3]),
                _aes128_sbox(t[0]),
            ]
        w += [w[(i - 4) * 4 + j] ^ t[j] for j in range(4)]

    state = [block[i] ^ w[i] for i in range(16)]

    for rnd in range(1, 11):
        state = [_aes128_sbox(x) for x in state]

        state[1], state[5], state[9], state[13] = state[5], state[9], state[13], state[1]
        state[2], state[6], state[10], state[14] = state[10], state[14], state[2], state[6]
        state[3], state[7], state[11], state[15] = state[15], state[3], state[7], state[11]

        if rnd < 10:
            for c in range(4):
                a = state[c * 4:c * 4 + 4]
                state[c * 4 + 0] = _gf_mul(2, a[0]) ^ _gf_mul(3, a[1]) ^ a[2] ^ a[3]
                state[c * 4 + 1] = a[0] ^ _gf_mul(2, a[1]) ^ _gf_mul(3, a[2]) ^ a[3]
                state[c * 4 + 2] = a[0] ^ a[1] ^ _gf_mul(2, a[2]) ^ _gf_mul(3, a[3])
                state[c * 4 + 3] = _gf_mul(3, a[0]) ^ a[1] ^ a[2] ^ _gf_mul(2, a[3])

        round_key = w[rnd * 16:(rnd + 1) * 16]
        state = [state[i] ^ round_key[i] for i in range(16)]

    return bytes(state)


def aes128_ecb_encrypt(key: bytes, block: bytes) -> bytes:
    if AES is not None:
        cipher = AES.new(key, AES.MODE_ECB)
        return cipher.encrypt(block)
    return aes128_ecb_encrypt_pure(key, block)


# ---- Config --------------------------------------------------------------

SLOT_DURATION = 300
DEFAULT_LOCAL_UUID = "FDA50693-A4E2-4FB1-AFCF-C6EB07647825"
DEFAULT_OPERATORS_PATH = Path(__file__).with_name("operators.json")
DEFAULT_OPERATORS_EXAMPLE_PATH = Path(__file__).with_name("operators.example.json")

# Legacy BNSO registry:
#   "serial": "умка" | "скаут"
BNSO_REGISTRY: dict[str, str] = {}


def normalize_uuid(uuid_text: str | None) -> str | None:
    if uuid_text is None:
        return None

    compact = uuid_text.strip().replace("-", "").upper()
    if len(compact) != 32 or any(ch not in "0123456789ABCDEF" for ch in compact):
        raise ValueError(f"Invalid UUID: {uuid_text}")

    return (
        f"{compact[0:8]}-{compact[8:12]}-{compact[12:16]}-"
        f"{compact[16:20]}-{compact[20:32]}"
    )


def format_ts(unix_time: float) -> str:
    return datetime.datetime.fromtimestamp(unix_time, datetime.UTC).strftime("%Y-%m-%d %H:%M:%S UTC")


def load_operator_registry(path: str | None) -> dict[str, Any]:
    registry: dict[str, Any] = {
        "local": {
            "name": "ours",
            "uuid": DEFAULT_LOCAL_UUID,
        },
        "external": [],
    }

    if not path:
        candidate = DEFAULT_OPERATORS_PATH
        if not candidate.exists():
            return registry
        path = str(candidate)

    data = json.loads(Path(path).read_text(encoding="utf-8"))
    local = data.get("local", {})
    external = data.get("external", [])

    if "uuid" in local:
        local["uuid"] = normalize_uuid(local["uuid"])
    for item in external:
        item["uuid"] = normalize_uuid(item["uuid"])

    registry["local"].update(local)
    registry["external"] = external
    return registry


def lookup_external_operator(
    operator: dict[str, Any],
    *,
    major: int,
    minor: int,
    rssi: int | None = None,
    timeout_sec: float = 3.0,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "major": major,
        "minor": minor,
    }
    if rssi is not None:
        payload["rssi"] = rssi

    headers = {"Content-Type": "application/json"}
    headers.update(operator.get("headers", {}))

    method = str(operator.get("method", "POST")).upper()
    body = json.dumps(payload).encode("utf-8") if method != "GET" else None
    url = operator["lookup_url"]
    if method == "GET":
        separator = "&" if "?" in url else "?"
        url = f"{url}{separator}major={major}&minor={minor}"
        if rssi is not None:
            url = f"{url}&rssi={rssi}"

    request = urllib.request.Request(url, data=body, headers=headers, method=method)

    with urllib.request.urlopen(request, timeout=timeout_sec) as response:
        content_type = response.headers.get("Content-Type", "")
        raw = response.read().decode("utf-8")
        if "application/json" in content_type:
            return json.loads(raw)
        return {"raw_response": raw}


# ---- Local algorithm -----------------------------------------------------

def compute_beacon_params(key: bytes, tag_id: int, slot: int) -> tuple[int, int, bytes]:
    block = struct.pack(">HI", tag_id, slot) + (b"\x00" * 10)
    out = aes128_ecb_encrypt(key, block)
    major = (out[0] << 8) | out[1]
    minor = (out[2] << 8) | out[3]
    mac_suffix = bytes([out[4] | 0xC0, out[5], out[6]])
    return major, minor, mac_suffix


def identify_local_tag(
    major: int,
    minor: int,
    *,
    key: bytes,
    num_tags: int,
    unix_time: float | None = None,
) -> dict[str, int] | None:
    if unix_time is None:
        unix_time = time.time()

    slot_now = int(unix_time) // SLOT_DURATION
    for slot in (slot_now - 1, slot_now, slot_now + 1):
        for tag_id in range(0, num_tags + 1):
            calc_major, calc_minor, _ = compute_beacon_params(key, tag_id, slot)
            if calc_major == major and calc_minor == minor:
                return {"tag_id": tag_id, "slot": slot}
    return None


def identify_local_tag_by_sum(
    id_sum: int,
    *,
    key: bytes,
    num_tags: int,
    unix_time: float | None = None,
) -> dict[str, int] | None:
    if unix_time is None:
        unix_time = time.time()

    slot_now = int(unix_time) // SLOT_DURATION
    for slot in (slot_now - 1, slot_now, slot_now + 1):
        for tag_id in range(0, num_tags + 1):
            major, minor, _ = compute_beacon_params(key, tag_id, slot)
            if major + minor == id_sum:
                return {"tag_id": tag_id, "slot": slot}
    return None


def route_ibeacon_packet(
    *,
    uuid: str,
    major: int,
    minor: int,
    key: bytes,
    num_tags: int,
    unix_time: float | None = None,
    operators: dict[str, Any] | None = None,
    rssi: int | None = None,
) -> dict[str, Any]:
    operators = operators or load_operator_registry(None)
    normalized_uuid = normalize_uuid(uuid)
    local_uuid = normalize_uuid(operators["local"]["uuid"])

    if normalized_uuid == local_uuid:
        resolved = identify_local_tag(
            major,
            minor,
            key=key,
            num_tags=num_tags,
            unix_time=unix_time,
        )
        return {
            "route": "local",
            "operator": operators["local"].get("name", "ours"),
            "uuid": normalized_uuid,
            "resolved": resolved,
        }

    for operator in operators.get("external", []):
        if normalized_uuid == normalize_uuid(operator["uuid"]):
            remote = lookup_external_operator(
                operator,
                major=major,
                minor=minor,
                rssi=rssi,
            )
            return {
                "route": "external",
                "operator": operator.get("name", "external"),
                "uuid": normalized_uuid,
                "remote_response": remote,
            }

    return {
        "route": "unknown",
        "uuid": normalized_uuid,
        "resolved": None,
    }


# ---- Legacy BNSO ---------------------------------------------------------

def bnso_decode(serial: str, raw_id: int) -> tuple[str, int | None, int | None, int | None]:
    model = BNSO_REGISTRY.get(serial)
    if model is None:
        raise ValueError(
            f"BNSO serial '{serial}' is not found in BNSO_REGISTRY. "
            "Add it in server/lookup.py before production deployment."
        )

    if model == "умка":
        major = (raw_id >> 16) & 0xFFFF
        minor = raw_id & 0xFFFF
        return model, major, minor, None

    if model == "скаут":
        return model, None, None, raw_id

    raise ValueError(f"Unsupported BNSO model: {model}")


def identify_tag_from_bnso(
    serial: str,
    raw_id: int,
    *,
    key: bytes,
    num_tags: int,
    unix_time: float | None = None,
) -> dict[str, int] | None:
    model, major, minor, id_sum = bnso_decode(serial, raw_id)
    if model == "умка":
        return identify_local_tag(
            major,
            minor,
            key=key,
            num_tags=num_tags,
            unix_time=unix_time,
        )
    return identify_local_tag_by_sum(
        id_sum,
        key=key,
        num_tags=num_tags,
        unix_time=unix_time,
    )


# Backward-compatible aliases for older integrations.
identify_tag = identify_local_tag
identify_tag_by_sum = identify_local_tag_by_sum


# ---- CLI -----------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Lookup BLE tag by operator UUID + Major + Minor or by legacy BNSO ID"
    )
    parser.add_argument("--key", required=True, help="AES-128 key in hex (32 symbols)")
    parser.add_argument("--num-tags", type=int, default=10000, help="Number of tags in the region")
    parser.add_argument("--unix-time", type=float, default=None, help="unix_time for deterministic lookup")
    parser.add_argument("--uuid", type=str, help="Static iBeacon UUID from the packet")
    parser.add_argument("--minor", type=str, help="Minor from the packet (hex)")
    parser.add_argument("--rssi", type=int, default=None, help="RSSI level from scanner/BNSO")
    parser.add_argument("--operators", type=str, default=None, help="Path to operators.json")
    parser.add_argument("--local-uuid", type=str, default=None, help="Override local operator UUID")

    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--simulate", action="store_true", help="Simulate one local tag for the current slot")
    mode.add_argument("--major", type=str, help="Major from the packet (hex)")
    mode.add_argument("--bnso-serial", type=str, metavar="SERIAL", help="Legacy BNSO serial number")

    parser.add_argument("--bnso-id", type=int, metavar="ID", help="Legacy BNSO transport ID")
    parser.add_argument("--tag-id", type=int, help="TagID for --simulate")

    return parser.parse_args()


def print_local_result(result: dict[str, int] | None) -> int:
    if not result:
        print("  Tag not found")
        return 2

    slot_ts = result["slot"] * SLOT_DURATION
    print(f"  Tag ID:    {result['tag_id']}")
    print(f"  Slot:      {result['slot']} ({format_ts(slot_ts)})")
    return 0


def main() -> int:
    args = parse_args()

    key = bytes.fromhex(args.key)
    if len(key) != 16:
        print("Error: KEY must contain exactly 32 hex symbols", file=sys.stderr)
        return 1

    unix_time = args.unix_time or time.time()
    slot = int(unix_time) // SLOT_DURATION

    try:
        operators = load_operator_registry(args.operators)
        if args.local_uuid:
            operators["local"]["uuid"] = normalize_uuid(args.local_uuid)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Error: cannot load operators registry: {exc}", file=sys.stderr)
        return 1

    if args.simulate:
        if args.tag_id is None:
            print("Error: --tag-id is required with --simulate", file=sys.stderr)
            return 1

        major, minor, mac_suffix = compute_beacon_params(key, args.tag_id, slot)
        print(f"  Operator:  {operators['local'].get('name', 'ours')}")
        print(f"  UUID:      {operators['local']['uuid']}")
        print(f"  Tag ID:    {args.tag_id}")
        print(f"  Slot:      {slot}")
        print(f"  Time:      {format_ts(unix_time)}")
        print(f"  Major:     0x{major:04X} ({major})")
        print(f"  Minor:     0x{minor:04X} ({minor})")
        print(f"  MAC sfx:   {mac_suffix[0]:02X}:{mac_suffix[1]:02X}:{mac_suffix[2]:02X}")
        return 0

    if args.major:
        if args.minor is None:
            print("Error: --minor is required with --major", file=sys.stderr)
            return 1
        if args.uuid is None:
            print("Error: --uuid is required with --major/--minor", file=sys.stderr)
            return 1

        major = int(args.major, 16)
        minor = int(args.minor, 16)

        try:
            routed = route_ibeacon_packet(
                uuid=args.uuid,
                major=major,
                minor=minor,
                key=key,
                num_tags=args.num_tags,
                unix_time=unix_time,
                operators=operators,
                rssi=args.rssi,
            )
        except (ValueError, KeyError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        except urllib.error.URLError as exc:
            print(f"Error: external lookup failed: {exc}", file=sys.stderr)
            return 1

        print(f"  UUID:      {routed['uuid']}")
        print(f"  Route:     {routed['route']}")
        if routed.get("operator"):
            print(f"  Operator:  {routed['operator']}")

        if routed["route"] == "local":
            return print_local_result(routed["resolved"])
        if routed["route"] == "external":
            print("  Response:  " + json.dumps(routed["remote_response"], ensure_ascii=False))
            return 0

        print("  Result:    operator is unknown, packet was not resolved")
        return 2

    if args.bnso_id is None:
        print("Error: --bnso-id is required with --bnso-serial", file=sys.stderr)
        return 1

    try:
        model, major, minor, id_sum = bnso_decode(args.bnso_serial, args.bnso_id)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if model == "умка":
        print(f"  BNSO:      {args.bnso_serial} (Umka)")
        print(f"  Decoded:   Major=0x{major:04X} ({major}), Minor=0x{minor:04X} ({minor})")
        result = identify_local_tag(
            major,
            minor,
            key=key,
            num_tags=args.num_tags,
            unix_time=unix_time,
        )
    else:
        print(f"  BNSO:      {args.bnso_serial} (Scout)")
        print(f"  Decoded:   Major+Minor sum = {id_sum}")
        result = identify_local_tag_by_sum(
            id_sum,
            key=key,
            num_tags=args.num_tags,
            unix_time=unix_time,
        )

    return print_local_result(result)


if __name__ == "__main__":
    sys.exit(main())
