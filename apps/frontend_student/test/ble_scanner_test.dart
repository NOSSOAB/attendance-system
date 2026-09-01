import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/core/ble/ble_models.dart';
import 'package:frontend_student/core/ble/ble_scanner.dart';

void main() {
  test('selectNearestBle chooses the strongest RSSI', () {
    final now = DateTime.now().toUtc();
    final nearest = selectNearestBle([
      BleEvidence(
        beaconId: 'weak',
        roomId: 'ROOM_1',
        deviceName: 'weak',
        serviceUuid: 'service',
        rssi: -79,
        scannedAt: now,
        scanDurationMs: 6500,
        isMock: true,
      ),
      BleEvidence(
        beaconId: 'strong',
        roomId: 'ROOM_2',
        deviceName: 'strong',
        serviceUuid: 'service',
        rssi: -55,
        scannedAt: now,
        scanDurationMs: 6500,
        isMock: true,
      ),
    ]);

    expect(nearest?.beaconId, 'strong');
  });

  test('maps the configured ESP32 advertisement to beacon and room', () {
    final scannedAt = DateTime.utc(2026, 7, 31, 5, 30);
    final evidence = mapEsp32Advertisement(
      advName: attendanceBleDeviceName,
      advertisedServiceUuids: const ['12345678-1234-1234-1234-123456789ABC'],
      rssi: -61,
      scannedAt: scannedAt,
      scanDuration: attendanceBleScanDuration,
    );

    expect(evidence, isNotNull);
    expect(evidence?.beaconId, attendanceBleBeaconId);
    expect(evidence?.roomId, attendanceBleRoomId);
    expect(evidence?.deviceName, attendanceBleDeviceName);
    expect(evidence?.serviceUuid, attendanceBleServiceUuid);
    expect(evidence?.rssi, -61);
    expect(evidence?.scannedAt, scannedAt);
    expect(evidence?.scanDurationMs, 6500);
    expect(evidence?.isMock, isFalse);
  });

  test('ignores advertisements with another name or service UUID', () {
    final scannedAt = DateTime.utc(2026, 7, 31);

    expect(
      mapEsp32Advertisement(
        advName: 'ANOTHER_DEVICE',
        advertisedServiceUuids: const [attendanceBleServiceUuid],
        rssi: -50,
        scannedAt: scannedAt,
        scanDuration: nearbyRoomScanDuration,
      ),
      isNull,
    );
    expect(
      mapEsp32Advertisement(
        advName: attendanceBleDeviceName,
        advertisedServiceUuids: const ['00000000-0000-0000-0000-000000000000'],
        rssi: -50,
        scannedAt: scannedAt,
        scanDuration: nearbyRoomScanDuration,
      ),
      isNull,
    );
  });

  test('MockBleScanner uses the session expectation', () async {
    final scanner = MockBleScanner();
    const expected = BleExpectation(
      beaconId: 'ESP32_ROOM_B',
      roomId: 'ROOM_B',
      deviceName: 'TEST_B',
      serviceUuid: 'service-b',
      minRssi: -80,
    );

    final results = await scanner.scan(
      duration: const Duration(milliseconds: 1),
      expected: expected,
    );

    expect(results.first.beaconId, expected.beaconId);
    expect(results.first.roomId, expected.roomId);
    await scanner.dispose();
  });

  test('cancel invalidates an active mock scan', () async {
    final scanner = MockBleScanner();
    final scan = scanner.scan(duration: const Duration(milliseconds: 20));
    await scanner.cancel();

    await expectLater(scan, throwsA(isA<BleScanCancelledException>()));
    await scanner.dispose();
  });

  test(
    'attendance scan is a new scanner invocation, not cached evidence',
    () async {
      final scanner = MockBleScanner();
      final nearby = await scanner.scan(
        duration: const Duration(milliseconds: 1),
      );
      final attendance = await scanner.scan(
        duration: const Duration(milliseconds: 2),
      );

      expect(identical(nearby.first, attendance.first), isFalse);
      expect(nearby.first.scanDurationMs, 1);
      expect(attendance.first.scanDurationMs, 2);
      await scanner.dispose();
    },
  );
}
