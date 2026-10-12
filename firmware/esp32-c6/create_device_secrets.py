#!/usr/bin/env python3
"""Create a per-beacon AES key without putting it in Git or the APK."""

import argparse
import json
from pathlib import Path
import re
import secrets


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-id", required=True, help="8 hex digits, unique per ESP32-C6")
    parser.add_argument("--beacon-id", required=True)
    parser.add_argument("--room-id", required=True)
    args = parser.parse_args()
    device_id = args.device_id.lower()
    if not re.fullmatch(r"[0-9a-f]{8}", device_id) or device_id == "00000000":
        parser.error("--device-id must be 8 nonzero hex digits")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", args.beacon_id):
        parser.error("--beacon-id must contain only letters, digits, _ or -")
    if not re.fullmatch(r"ROOM_[A-Z0-9_]{1,95}", args.room_id):
        parser.error("--room-id must look like ROOM_A101")

    directory = Path(__file__).resolve().parent
    header = directory / "ble_device_secrets.h"
    registry = directory / "ble_device_registry.local.json"
    if header.exists() or registry.exists():
        parser.error("local secrets already exist; move them safely before creating another device")

    key = secrets.token_bytes(16)
    byte_literals = ", ".join(f"0x{byte:02x}" for byte in key)
    header.write_text(
        "#pragma once\n"
        f"const uint32_t DEVICE_ID = 0x{device_id.upper()};\n"
        f"const uint8_t AES_KEY[16] = {{{byte_literals}}};\n",
        encoding="utf-8",
    )
    registry.write_text(
        json.dumps(
            [{
                "deviceId": device_id,
                "beaconId": args.beacon_id,
                "roomId": args.room_id,
                "keyHex": key.hex(),
            }],
            separators=(",", ":"),
        ) + "\n",
        encoding="utf-8",
    )
    header.chmod(0o600)
    registry.chmod(0o600)
    print(f"Created {header.name} and {registry.name} (both ignored by Git)")


if __name__ == "__main__":
    main()
