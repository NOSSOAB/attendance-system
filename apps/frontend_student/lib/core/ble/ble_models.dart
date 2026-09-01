class BleExpectation {
  final String beaconId;
  final String roomId;
  final String deviceName;
  final String serviceUuid;
  final int minRssi;

  const BleExpectation({
    required this.beaconId,
    required this.roomId,
    required this.deviceName,
    required this.serviceUuid,
    required this.minRssi,
  });

  factory BleExpectation.fromJson(Map<String, dynamic> json) {
    return BleExpectation(
      beaconId: json['beaconId'] as String? ?? 'ESP32_TEST_01',
      roomId: json['roomId'] as String? ?? 'ROOM_A101',
      deviceName: json['deviceName'] as String? ?? 'ATTENDANCE_BLE_TEST',
      serviceUuid:
          json['serviceUuid'] as String? ??
          '12345678-1234-1234-1234-123456789abc',
      minRssi: (json['minRssi'] as num?)?.toInt() ?? -80,
    );
  }
}

class BleEvidence {
  final String beaconId;
  final String roomId;
  final String deviceName;
  final String serviceUuid;
  final int rssi;
  final DateTime scannedAt;
  final int scanDurationMs;
  final bool isMock;

  const BleEvidence({
    required this.beaconId,
    required this.roomId,
    required this.deviceName,
    required this.serviceUuid,
    required this.rssi,
    required this.scannedAt,
    required this.scanDurationMs,
    required this.isMock,
  });

  Map<String, dynamic> toJson() {
    return {
      'beaconId': beaconId,
      'roomId': roomId,
      'deviceName': deviceName,
      'serviceUuid': serviceUuid,
      'rssi': rssi,
      'scannedAt': scannedAt.toUtc().toIso8601String(),
      'scanDurationMs': scanDurationMs,
    };
  }
}
