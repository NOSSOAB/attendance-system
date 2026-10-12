import 'dart:convert';

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

  test('maps actual signed device IDs across rooms and forwards proof', () {
    final scannedAt = DateTime.utc(2026, 7, 31, 5, 30);
    final evidence = mapEsp32Advertisement(
      advName: attendanceBleDeviceName,
      advertisedServiceUuids: const ['12345678-1234-1234-1234-123456789ABC'],
      rssi: -61,
      scannedAt: scannedAt,
      scanDuration: attendanceBleScanDuration,
      proofPayload: utf8.encode(
        jsonEncode({
          'version': 1,
          'beaconId': 'ESP32_B202',
          'roomId': 'ROOM_B202',
          'issuedAt': scannedAt.millisecondsSinceEpoch ~/ 1000,
          'nonce': '0123456789abcdef',
          'signature': 'a' * 64,
        }),
      ),
    );

    expect(evidence, isNotNull);
    expect(evidence?.beaconId, 'ESP32_B202');
    expect(evidence?.roomId, 'ROOM_B202');
    expect(evidence?.toJson()['proof'], containsPair('signature', 'a' * 64));
    expect(evidence?.toJson()['isMock'], false);
    expect(evidence?.deviceName, attendanceBleDeviceName);
    expect(evidence?.serviceUuid, attendanceBleServiceUuid);
    expect(evidence?.rssi, -61);
    expect(evidence?.scannedAt, scannedAt);
    expect(evidence?.scanDurationMs, 6500);
    expect(evidence?.isMock, isFalse);
  });

  test('ignores unsigned advertisements and unrelated service UUIDs', () {
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

  test('forwards the ESP32-C6 manufacturer token without putting a key in the app', () {
    final bytes = List<int>.generate(24, (index) => index);
    final evidence = mapC6Advertisement(
      manufacturerData: {0xffff: bytes},
      advName: 'SecureAttendance_C6',
      rssi: -60,
      scannedAt: DateTime.utc(2026, 10, 13),
      scanDuration: attendanceBleScanDuration,
    );

    expect(evidence, isNotNull);
    expect(evidence!.c6Token, base64Encode([0xff, 0xff, ...bytes]));
    expect(evidence.c6DeviceId, '03020100');
    expect(evidence.toJson()['c6Token'], evidence.c6Token);
    expect(evidence.toJson(), isNot(contains('serviceUuid')));
    expect(evidence.toJson(), isNot(contains('beaconId')));
    expect(evidence.toJson(), isNot(contains('roomId')));
    expect(evidence.isMock, isFalse);
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
