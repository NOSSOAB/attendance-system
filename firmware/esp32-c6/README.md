# ESP32-C6 BLE beacon

This sketch is based on the repository's `add-esp32-c6-firmware` branch (latest
commit 10 September 2026). It broadcasts a 26-byte AES-128-GCM token in
manufacturer data (company ID `0xffff`) every 30 seconds. The Flutter app
forwards that token to NestJS; only NestJS holds the per-device AES key and maps
the device ID to a classroom.

For each physical board, run:

```bash
python create_device_secrets.py \
  --device-id A1B2C3D4 \
  --beacon-id ESP32_TEST_01 \
  --room-id ROOM_A101
```

The command creates `ble_device_secrets.h` for the Arduino sketch and
`ble_device_registry.local.json` for the server. Both files are ignored by Git.
Use a different device ID and key for every board. Add the JSON entries from
the registry file to `BLE_C6_DEVICES_JSON` in the server's private `infra/.env`,
then flash the sketch. Do not put the AES key in the APK or commit it to Git.

The token format from this firmware has no absolute timestamp. NestJS checks
the AES-GCM tag, configured room, scan time and RSSI, but a previously observed
valid advertisement could be relayed. A future firmware protocol needs a
server-verifiable time or challenge to close that gap.
