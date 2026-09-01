import { BleTestConfig } from './ble-test.config';

describe('BleTestConfig', () => {
  const now = new Date();
  const session = {
    openedAt: new Date(now.getTime() - 60_000),
    closesAt: new Date(now.getTime() + 60_000),
  };
  const expected = BleTestConfig.forRoom('Phòng A101');
  const validEvidence = {
    beaconId: expected.beaconId,
    roomId: expected.roomId,
    deviceName: expected.deviceName,
    serviceUuid: expected.serviceUuid,
    rssi: -62,
    scannedAt: now.toISOString(),
    scanDurationMs: 6_500,
  };

  it('accepts matching test BLE evidence', () => {
    expect(BleTestConfig.validate(validEvidence, expected, session)).toBeNull();
  });

  it('flags a missing BLE scan', () => {
    expect(BleTestConfig.validate(null, expected, session)).toBe(
      'BLE_NOT_FOUND',
    );
  });

  it('flags a weak signal', () => {
    expect(
      BleTestConfig.validate(
        { ...validEvidence, rssi: expected.minRssi - 1 },
        expected,
        session,
      ),
    ).toBe('BLE_SIGNAL_TOO_WEAK');
  });

  it('flags a room mismatch', () => {
    expect(
      BleTestConfig.validate(
        { ...validEvidence, roomId: 'ROOM_OTHER' },
        expected,
        session,
      ),
    ).toBe('BLE_ROOM_MISMATCH');
  });

  it('rejects a scan duration outside 5-8 seconds', () => {
    expect(
      BleTestConfig.validate(
        { ...validEvidence, scanDurationMs: 4_999 },
        expected,
        session,
      ),
    ).toBe('INVALID_EVIDENCE');
  });
});
