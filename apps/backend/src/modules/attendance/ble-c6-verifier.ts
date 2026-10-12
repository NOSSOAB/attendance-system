import { createDecipheriv } from 'crypto';

export type BleC6Device = {
  deviceId: string;
  beaconId: string;
  roomId: string;
  keyHex: string;
};

export type VerifiedBleC6Token = {
  deviceId: string;
  beaconId: string;
  roomId: string;
};

const TOKEN_BYTES = 26;
const COMPANY_ID = 0xffff;

/**
 * The ESP32-C6 firmware advertises company ID, nonce, encrypted device ID and
 * an 8-byte AES-GCM tag. Keys live only in the backend environment. The token
 * authenticates a configured beacon, but this firmware has no wall-clock time;
 * it cannot by itself prove when a received advertisement was emitted.
 */
export function verifyBleC6Token(
  encoded: string,
  registryJson = process.env.BLE_C6_DEVICES_JSON ?? '',
): VerifiedBleC6Token | null {
  if (!/^[A-Za-z0-9+/]{35}=$/.test(encoded)) return null;
  const token = Buffer.from(encoded, 'base64');
  if (token.length !== TOKEN_BYTES || token.readUInt16LE(0) !== COMPANY_ID) {
    return null;
  }
  const devices = parseRegistry(registryJson);
  const nonce = token.subarray(2, 14);
  const deviceId = nonce.readUInt32LE(0).toString(16).padStart(8, '0');
  const configured = devices.get(deviceId);
  if (!configured) return null;
  try {
    const decipher = createDecipheriv(
      'aes-128-gcm',
      Buffer.from(configured.keyHex, 'hex'),
      nonce,
      { authTagLength: 8 },
    );
    decipher.setAuthTag(token.subarray(18, 26));
    const clear = Buffer.concat([
      decipher.update(token.subarray(14, 18)),
      decipher.final(),
    ]);
    if (clear.length !== 4 || clear.readUInt32LE(0) !== nonce.readUInt32LE(0)) {
      return null;
    }
    return {
      deviceId,
      beaconId: configured.beaconId,
      roomId: configured.roomId,
    };
  } catch {
    return null;
  }
}

export function parseRegistry(raw: string): Map<string, BleC6Device> {
  if (!raw.trim()) return new Map();
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('BLE_C6_DEVICES_JSON must be valid JSON');
  }
  if (!Array.isArray(parsed)) {
    throw new Error('BLE_C6_DEVICES_JSON must be an array');
  }
  const devices = new Map<string, BleC6Device>();
  for (const item of parsed) {
    if (!item || typeof item !== 'object') {
      throw new Error('BLE_C6_DEVICES_JSON contains an invalid device');
    }
    const value = item as Record<string, unknown>;
    const deviceId = String(value.deviceId ?? '').toLowerCase();
    const beaconId = value.beaconId;
    const roomId = value.roomId;
    const keyHex = String(value.keyHex ?? '').toLowerCase();
    if (
      !/^[0-9a-f]{8}$/.test(deviceId) ||
      typeof beaconId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,100}$/.test(beaconId) ||
      typeof roomId !== 'string' ||
      !/^ROOM_[A-Z0-9_]{1,95}$/.test(roomId) ||
      !/^[0-9a-f]{32}$/.test(keyHex) ||
      devices.has(deviceId)
    ) {
      throw new Error('BLE_C6_DEVICES_JSON contains an invalid device');
    }
    devices.set(deviceId, { deviceId, beaconId, roomId, keyHex });
  }
  return devices;
}
