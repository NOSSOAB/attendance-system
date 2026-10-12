import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_models.dart';

const bool useMockBle = bool.fromEnvironment(
  'USE_MOCK_BLE',
  defaultValue: false,
);
const Duration nearbyRoomScanDuration = Duration(seconds: 2);
const Duration attendanceBleScanDuration = Duration(milliseconds: 6500);
const String attendanceBleServiceUuid = '12345678-1234-1234-1234-123456789abc';
const String attendanceBleProofCharacteristicUuid =
    '12345678-1234-1234-1234-123456789abd';
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
    if (kReleaseMode) {
      throw StateError('BLE giả lập không được dùng trong bản phát hành');
    }
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
  List<int>? proofPayload,
}) {
  final hasAttendanceService = advertisedServiceUuids.any(
    (uuid) => uuid.toLowerCase() == attendanceBleServiceUuid,
  );
  if (!hasAttendanceService ||
      proofPayload == null ||
      proofPayload.length > 1024) {
    return null;
  }

  Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(utf8.decode(proofPayload));
    if (decoded is! Map<String, dynamic>) return null;
    payload = decoded;
  } catch (_) {
    return null;
  }
  final beaconId = payload['beaconId'];
  final roomId = payload['roomId'];
  final issuedAt = payload['issuedAt'];
  final nonce = payload['nonce'];
  final signature = payload['signature'];
  if (payload['version'] != 1 ||
      beaconId is! String ||
      roomId is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(beaconId) ||
      !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(roomId) ||
      issuedAt is! int ||
      issuedAt <= 0 ||
      nonce is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(nonce) ||
      signature is! String ||
      !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(signature)) {
    return null;
  }

  return BleEvidence(
    beaconId: beaconId,
    roomId: roomId,
    deviceName: advName,
    serviceUuid: attendanceBleServiceUuid,
    rssi: rssi,
    scannedAt: scannedAt.toUtc(),
    scanDurationMs: scanDuration.inMilliseconds,
    isMock: false,
    proof: {
      'version': 1,
      'issuedAt': issuedAt,
      'nonce': nonce,
      'signature': signature,
    },
  );
}

/// The ESP32-C6 firmware on GitHub advertises an AES-GCM token in company
/// 0xFFFF manufacturer data. The app forwards the bytes unchanged; only the
/// backend has the key and knows which classroom the device belongs to.
BleEvidence? mapC6Advertisement({
  required Map<int, List<int>> manufacturerData,
  required String advName,
  required int rssi,
  required DateTime scannedAt,
  required Duration scanDuration,
}) {
  final payload = manufacturerData[0xffff];
  if (payload == null) return null;
  final bytes = payload.length == 24
      ? <int>[0xff, 0xff, ...payload]
      : payload;
  if (bytes.length != 26 || bytes[0] != 0xff || bytes[1] != 0xff) {
    return null;
  }
  return BleEvidence(
    beaconId: '',
    roomId: '',
    deviceName: advName,
    serviceUuid: '',
    rssi: rssi,
    scannedAt: scannedAt.toUtc(),
    scanDurationMs: scanDuration.inMilliseconds,
    isMock: false,
    c6Token: base64Encode(bytes),
  );
}

class RealBleScanner implements BleScanner {
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothDevice? _connectedDevice;

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
    final scanStartedAt = DateTime.now().toUtc();
    final evidenceByDevice = <String, BleEvidence>{};
    final candidates = <String, ScanResult>{};
    Object? scanError;

    final subscription = FlutterBluePlus.onScanResults.listen(
      (scanResults) {
        if (_disposed || generation != _generation) {
          return;
        }

        for (final result in scanResults) {
          if (result.timeStamp.toUtc().isBefore(scanStartedAt)) continue;
          final deviceId = result.device.remoteId.str;
          final c6Evidence = mapC6Advertisement(
            manufacturerData: result.advertisementData.manufacturerData,
            advName: result.advertisementData.advName,
            rssi: result.rssi,
            scannedAt: result.timeStamp,
            scanDuration: duration,
          );
          if (c6Evidence != null) {
            final current = evidenceByDevice[deviceId];
            if (current == null || c6Evidence.rssi > current.rssi) {
              evidenceByDevice[deviceId] = c6Evidence;
            }
            continue;
          }
          if (!result.advertisementData.serviceUuids.any(
            (uuid) => uuid.toString().toLowerCase() == attendanceBleServiceUuid,
          )) {
            continue;
          }
          candidates[deviceId] = result;
          final evidence = mapEsp32Advertisement(
            advName: result.advertisementData.advName,
            advertisedServiceUuids: result.advertisementData.serviceUuids.map(
              (uuid) => uuid.toString(),
            ),
            rssi: result.rssi,
            scannedAt: result.timeStamp,
            scanDuration: duration,
            proofPayload: result
                .advertisementData
                .serviceData[Guid(attendanceBleServiceUuid)],
          );
          if (evidence == null) {
            continue;
          }

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

      // Read the signed payload after stopping discovery. IDs come from the
      // device, never from the class the student is trying to attend.
      final ordered = candidates.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      final proofDeadline = DateTime.now().add(const Duration(seconds: 12));
      for (final result in ordered.take(4)) {
        if (DateTime.now().isAfter(proofDeadline)) break;
        if (_disposed || generation != _generation) {
          throw const BleScanCancelledException();
        }
        final deviceId = result.device.remoteId.str;
        var evidence = evidenceByDevice[deviceId];
        evidence ??= await _readProof(result, duration, generation);
        if (evidence != null) evidenceByDevice[deviceId] = evidence;
        if (expected != null &&
            evidence?.beaconId == expected.beaconId &&
            evidence?.roomId == expected.roomId) {
          break;
        }
      }
      if (_disposed || generation != _generation) {
        throw const BleScanCancelledException();
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

  Future<BleEvidence?> _readProof(
    ScanResult result,
    Duration duration,
    int generation,
  ) async {
    final device = result.device;
    _connectedDevice = device;
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 4),
        mtu: null,
      );
      if (_disposed || generation != _generation) return null;
      final services = await device.discoverServices(timeout: 4);
      for (final service in services) {
        if (service.serviceUuid.toString().toLowerCase() !=
            attendanceBleServiceUuid) {
          continue;
        }
        for (final characteristic in service.characteristics) {
          if (characteristic.characteristicUuid.toString().toLowerCase() !=
                  attendanceBleProofCharacteristicUuid ||
              !characteristic.properties.read) {
            continue;
          }
          final payload = await characteristic.read(timeout: 4);
          return mapEsp32Advertisement(
            advName: result.advertisementData.advName,
            advertisedServiceUuids: [attendanceBleServiceUuid],
            rssi: result.rssi,
            scannedAt: DateTime.now().toUtc(),
            scanDuration: duration,
            proofPayload: payload,
          );
        }
      }
    } catch (_) {
      // Unsupported/unsigned devices provide no attendance evidence.
    } finally {
      if (identical(_connectedDevice, device)) _connectedDevice = null;
      try {
        await device.disconnect(timeout: 3);
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<void> cancel() async {
    _generation += 1;
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
    final device = _connectedDevice;
    _connectedDevice = null;
    try {
      await device?.disconnect(timeout: 3, queue: false);
    } catch (_) {}
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
    return useMockBle && !kReleaseMode ? MockBleScanner() : RealBleScanner();
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
