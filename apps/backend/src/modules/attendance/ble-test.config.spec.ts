import { createCipheriv } from 'crypto';
import { BleTestConfig } from './ble-test.config';
import { parseRegistry } from './ble-c6-verifier';

describe('BleTestConfig with ESP32-C6', () => {
  const previousRegistry = process.env.BLE_C6_DEVICES_JSON;
  const key = Buffer.from('0123456789abcdeffedcba9876543210', 'hex');
  const now = new Date();
  const session = {
    openedAt: new Date(now.getTime() - 60_000),
    closesAt: new Date(now.getTime() + 60_000),
  };
  const expected = BleTestConfig.forRoom('Phòng A101');

  function token() {
    const nonce = Buffer.from('d4c3b2a10100000001020304', 'hex');
    const cipher = createCipheriv('aes-128-gcm', key, nonce, {
      authTagLength: 8,
    });
    const encrypted = Buffer.concat([
      cipher.update(Buffer.from('d4c3b2a1', 'hex')),
      cipher.final(),
    ]);
    return Buffer.concat([
      Buffer.from('ffff', 'hex'),
      nonce,
      encrypted,
      cipher.getAuthTag(),
    ]).toString('base64');
  }

  const validEvidence = {
    c6Token: token(),
    isMock: false,
    rssi: -62,
    scannedAt: now.toISOString(),
    scanDurationMs: 6_500,
  };

  beforeEach(() => {
    process.env.BLE_C6_DEVICES_JSON = JSON.stringify([
      {
        deviceId: 'a1b2c3d4',
        beaconId: expected.beaconId,
        roomId: expected.roomId,
        keyHex: key.toString('hex'),
      },
    ]);
  });

  afterAll(() => {
    if (previousRegistry === undefined) delete process.env.BLE_C6_DEVICES_JSON;
    else process.env.BLE_C6_DEVICES_JSON = previousRegistry;
  });

  it('authenticates the beacon and accepts a matching classroom', () => {
    expect(BleTestConfig.validate(validEvidence, expected, session)).toBeNull();
    expect(BleTestConfig.forRoom('Phòng A101').deviceIds).toEqual(['a1b2c3d4']);
  });

  it('accepts another registered beacon in the same room', () => {
    process.env.BLE_C6_DEVICES_JSON = JSON.stringify([
      {
        deviceId: 'a1b2c3d4',
        beaconId: expected.beaconId,
        roomId: expected.roomId,
        keyHex: key.toString('hex'),
      },
      {
        deviceId: 'b1b2c3d4',
        beaconId: 'ANOTHER_BEACON',
        roomId: expected.roomId,
        keyHex: '102132435465768798a9bacbdcedfe0f',
      },
    ]);
    expect(BleTestConfig.forRoom('Phòng A101').deviceIds).toEqual([
      'a1b2c3d4',
      'b1b2c3d4',
    ]);
    expect(
      BleTestConfig.validate(
        validEvidence,
        { ...expected, beaconId: 'ANOTHER_BEACON' },
        session,
      ),
    ).toBeNull();
  });

  it('flags a missing BLE scan', () => {
    expect(BleTestConfig.validate(null, expected, session)).toBe(
      'BLE_NOT_FOUND',
    );
  });

  it('rejects a mock or a tampered authentication tag', () => {
    expect(
      BleTestConfig.validate(
        { ...validEvidence, isMock: true },
        expected,
        session,
      ),
    ).toBe('INVALID_EVIDENCE');
    const tampered = Buffer.from(validEvidence.c6Token, 'base64');
    tampered[25] ^= 1;
    expect(
      BleTestConfig.validate(
        { ...validEvidence, c6Token: tampered.toString('base64') },
        expected,
        session,
      ),
    ).toBe('INVALID_EVIDENCE');
  });

  it('flags a weak signal or wrong classroom after authenticating the token', () => {
    expect(
      BleTestConfig.validate(
        { ...validEvidence, rssi: expected.minRssi - 1 },
        expected,
        session,
      ),
    ).toBe('BLE_SIGNAL_TOO_WEAK');
    expect(
      BleTestConfig.validate(
        validEvidence,
        { ...expected, roomId: 'ROOM_OTHER' },
        session,
      ),
    ).toBe('BLE_ROOM_MISMATCH');
  });

  it('rejects unsigned legacy JSON and a stale scan', () => {
    expect(
      BleTestConfig.validate(
        { ...validEvidence, c6Token: undefined },
        expected,
        session,
      ),
    ).toBe('INVALID_EVIDENCE');
    expect(
      BleTestConfig.validate(
        {
          ...validEvidence,
          scannedAt: new Date(now.getTime() - 3 * 60_000).toISOString(),
        },
        expected,
        session,
      ),
    ).toBe('INVALID_EVIDENCE');
  });

  it('rejects a malformed registry without exposing the configured key', () => {
    expect(() => parseRegistry('{"keyHex":"secret-key"')).toThrow(
      'BLE_C6_DEVICES_JSON must be valid JSON',
    );
  });
});
