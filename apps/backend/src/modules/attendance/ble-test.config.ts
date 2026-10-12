import type {
  AttendanceFailureReason,
  BleEvidence,
  BleSessionExpectation,
} from './attendance.domain';
import { parseRegistry, verifyBleC6Token } from './ble-c6-verifier';

export const BLE_SCAN_MIN_MS = 5_000;
export const BLE_SCAN_MAX_MS = 8_000;
export const BLE_SCAN_DEFAULT_MS = 6_500;

export class BleTestConfig {
  static readonly beaconId =
    process.env.BLE_TEST_BEACON_ID?.trim() || 'ESP32_TEST_01';
  static readonly deviceName =
    process.env.BLE_TEST_DEVICE_NAME?.trim() || 'ATTENDANCE_BLE_TEST';
  static readonly serviceUuid =
    process.env.BLE_TEST_SERVICE_UUID?.trim().toLowerCase() ||
    '12345678-1234-1234-1234-123456789abc';
  static readonly minRssi = BleTestConfig.readMinRssi();

  static forRoom(room: string): BleSessionExpectation {
    const roomId = BleTestConfig.toRoomId(room);
    return {
      beaconId: BleTestConfig.beaconId,
      roomId,
      deviceName: BleTestConfig.deviceName,
      serviceUuid: BleTestConfig.serviceUuid,
      minRssi: BleTestConfig.minRssi,
      deviceIds: BleTestConfig.deviceIds(BleTestConfig.beaconId, roomId),
    };
  }

  static fromSession(session: {
    beaconId?: string | null;
    roomId?: string | null;
    bleServiceUuid?: string | null;
    bleMinRssi?: number | null;
    schedule: { room: string };
  }): BleSessionExpectation {
    const fallback = BleTestConfig.forRoom(session.schedule.room);
    const beaconId = session.beaconId?.trim() || fallback.beaconId;
    const roomId = session.roomId?.trim() || fallback.roomId;
    return {
      ...fallback,
      beaconId,
      roomId,
      serviceUuid:
        session.bleServiceUuid?.trim().toLowerCase() || fallback.serviceUuid,
      minRssi: session.bleMinRssi ?? fallback.minRssi,
      deviceIds: BleTestConfig.deviceIds(beaconId, roomId),
    };
  }

  static validate(
    evidence: BleEvidence | null | undefined,
    expected: BleSessionExpectation,
    session: {
      openedAt?: Date | string | null;
      closesAt?: Date | string | null;
    },
  ): AttendanceFailureReason | null {
    if (!evidence) {
      return 'BLE_NOT_FOUND';
    }
    if (evidence.isMock) return 'INVALID_EVIDENCE';

    const scannedAt = evidence.scannedAt ? new Date(evidence.scannedAt) : null;
    const scanDurationMs = Number(evidence.scanDurationMs);
    const rssi = Number(evidence.rssi);
    const openedAt = session.openedAt ? new Date(session.openedAt) : null;
    const closesAt = session.closesAt ? new Date(session.closesAt) : null;

    if (
      !scannedAt ||
      Number.isNaN(scannedAt.getTime()) ||
      !Number.isFinite(rssi) ||
      !Number.isFinite(scanDurationMs) ||
      scanDurationMs < BLE_SCAN_MIN_MS ||
      scanDurationMs > BLE_SCAN_MAX_MS ||
      Math.abs(Date.now() - scannedAt.getTime()) > 2 * 60_000 ||
      (openedAt && scannedAt.getTime() < openedAt.getTime()) ||
      (closesAt && scannedAt.getTime() > closesAt.getTime()) ||
      scannedAt.getTime() > Date.now() + 30_000
    ) {
      return 'INVALID_EVIDENCE';
    }

    const authenticated = evidence.c6Token
      ? verifyBleC6Token(evidence.c6Token)
      : null;
    if (!authenticated) return 'INVALID_EVIDENCE';
    if (
      authenticated.beaconId !== expected.beaconId ||
      authenticated.roomId !== expected.roomId
    ) {
      return 'BLE_ROOM_MISMATCH';
    }

    if (rssi < expected.minRssi) {
      return 'BLE_SIGNAL_TOO_WEAK';
    }

    return null;
  }

  static toRoomId(room: string) {
    const normalized = room
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');
    return `ROOM_${normalized || 'TEST'}`;
  }

  private static readMinRssi() {
    const configured = Number(process.env.BLE_TEST_MIN_RSSI ?? -80);
    return Number.isFinite(configured) ? Math.round(configured) : -80;
  }

  private static deviceIds(beaconId: string, roomId: string): string[] {
    return [...parseRegistry(process.env.BLE_C6_DEVICES_JSON ?? '').values()]
      .filter(
        (device) => device.beaconId === beaconId && device.roomId === roomId,
      )
      .map((device) => device.deviceId);
  }
}
