import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_models.dart';

const bool useMockBle = bool.fromEnvironment(
  'USE_MOCK_BLE',
  defaultValue: true,
);
const Duration nearbyRoomScanDuration = Duration(seconds: 2);
const Duration attendanceBleScanDuration = Duration(milliseconds: 6500);
const String attendanceBleServiceUuid = '12345678-1234-1234-1234-123456789abc';
const String attendanceBleDeviceName = 'ATTENDANCE_BLE_TEST';
const String attendanceBleBeaconId = 'ESP32_TEST_01';
const String attendanceBleRoomId = 'ROOM_A101';

abstract class BleScanner {
  Future<List<BleEvidence>> scan({
    required Duration duration,
    BleExpectation? expected,
  });

  Future<void> cancel();

  Future<void> dispose();
}

class BleScanCancelledException implements Exception {
  const BleScanCancelledException();
}

class MockBleScanner implements BleScanner {
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<List<BleEvidence>> scan({
    required Duration duration,
    BleExpectation? expected,
  }) async {
    if (_disposed) {
      throw StateError('BLE scanner đã được đóng');
    }

    final generation = ++_generation;
    await Future<void>.delayed(duration);
    if (_disposed || generation != _generation) {
      throw const BleScanCancelledException();
    }

    final target =
        expected ??
        const BleExpectation(
          beaconId: attendanceBleBeaconId,
          roomId: attendanceBleRoomId,
          deviceName: attendanceBleDeviceName,
          serviceUuid: attendanceBleServiceUuid,
          minRssi: -80,
        );
    final scannedAt = DateTime.now().toUtc();

    return [
      BleEvidence(
        beaconId: target.beaconId,
        roomId: target.roomId,
        deviceName: target.deviceName,
        serviceUuid: target.serviceUuid,
        rssi: -62,
        scannedAt: scannedAt,
        scanDurationMs: duration.inMilliseconds,
        isMock: true,
      ),
      BleEvidence(
        beaconId: 'ESP32_TEST_SECONDARY',
        roomId: 'ROOM_TEST_SECONDARY',
        deviceName: 'ATTENDANCE_BLE_SECONDARY',
        serviceUuid: target.serviceUuid,
        rssi: -76,
        scannedAt: scannedAt,
        scanDurationMs: duration.inMilliseconds,
        isMock: true,
      ),
    ];
  }

  @override
  Future<void> cancel() async {
    _generation += 1;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _generation += 1;
  }
}

BleEvidence? mapEsp32Advertisement({
  required String advName,
  required Iterable<String> advertisedServiceUuids,
  required int rssi,
  required DateTime scannedAt,
  required Duration scanDuration,
}) {
  final hasAttendanceService = advertisedServiceUuids.any(
    (uuid) => uuid.toLowerCase() == attendanceBleServiceUuid,
  );
  if (!hasAttendanceService || advName != attendanceBleDeviceName) {
    return null;
  }

  return BleEvidence(
    beaconId: attendanceBleBeaconId,
    roomId: attendanceBleRoomId,
    deviceName: advName,
    serviceUuid: attendanceBleServiceUuid,
    rssi: rssi,
    scannedAt: scannedAt.toUtc(),
    scanDurationMs: scanDuration.inMilliseconds,
    isMock: false,
  );
}

class RealBleScanner implements BleScanner {
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  Future<List<BleEvidence>> scan({
    required Duration duration,
    BleExpectation? expected,
  }) async {
    if (_disposed) {
      throw StateError('BLE scanner đã được đóng');
    }

    await cancel();
    if (_disposed) {
      throw StateError('BLE scanner đã được đóng');
    }

    final generation = ++_generation;
    final evidenceByDevice = <String, BleEvidence>{};
    Object? scanError;

    final subscription = FlutterBluePlus.onScanResults.listen(
      (scanResults) {
        if (_disposed || generation != _generation) {
          return;
        }

        for (final result in scanResults) {
          final evidence = mapEsp32Advertisement(
            advName: result.advertisementData.advName,
            advertisedServiceUuids: result.advertisementData.serviceUuids.map(
              (uuid) => uuid.toString(),
            ),
            rssi: result.rssi,
            scannedAt: result.timeStamp,
            scanDuration: duration,
          );
          if (evidence == null) {
            continue;
          }

          final deviceId = result.device.remoteId.str;
          final current = evidenceByDevice[deviceId];
          if (current == null || evidence.rssi > current.rssi) {
            evidenceByDevice[deviceId] = evidence;
          }
        }
      },
      onError: (Object error) {
        scanError = error;
      },
    );
    _scanSubscription = subscription;

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(attendanceBleServiceUuid)],
        timeout: duration,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      if (_disposed || generation != _generation) {
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }
        throw const BleScanCancelledException();
      }

      await Future<void>.delayed(duration);
      if (_disposed || generation != _generation) {
        throw const BleScanCancelledException();
      }

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      if (scanError != null) {
        throw Exception('Không thể quét BLE: $scanError');
      }

      return evidenceByDevice.values.toList()
        ..sort((left, right) => right.rssi.compareTo(left.rssi));
    } finally {
      await subscription.cancel();
      if (identical(_scanSubscription, subscription)) {
        _scanSubscription = null;
      }
      if (generation == _generation && FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    }
  }

  @override
  Future<void> cancel() async {
    _generation += 1;
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await cancel();
  }
}

class BleScannerFactory {
  static BleScanner create() {
    return useMockBle ? MockBleScanner() : RealBleScanner();
  }
}

BleEvidence? selectNearestBle(Iterable<BleEvidence> results) {
  if (results.isEmpty) {
    return null;
  }

  final sorted = [...results]
    ..sort((left, right) => right.rssi.compareTo(left.rssi));
  return sorted.first;
}
