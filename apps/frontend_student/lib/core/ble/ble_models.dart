import 'dart:convert';

class BleExpectation {
  final String beaconId;
  final String roomId;
  final String deviceName;
  final String serviceUuid;
  final int minRssi;
  final bool proofRequired;
  final List<String> deviceIds;

  const BleExpectation({
    required this.beaconId,
    required this.roomId,
    required this.deviceName,
    required this.serviceUuid,
    required this.minRssi,
    this.proofRequired = true,
    this.deviceIds = const [],
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
      proofRequired: json['proofRequired'] as bool? ?? true,
      deviceIds: (json['deviceIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
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
  final Map<String, dynamic>? proof;
  final String? c6Token;

  String? get c6DeviceId {
    if (c6Token == null) return null;
    try {
      final bytes = base64Decode(c6Token!);
      if (bytes.length != 26 || bytes[0] != 0xff || bytes[1] != 0xff) {
        return null;
      }
      return bytes
          .sublist(2, 6)
          .reversed
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    } on FormatException {
      return null;
    }
  }

  const BleEvidence({
    required this.beaconId,
    required this.roomId,
    required this.deviceName,
    required this.serviceUuid,
    required this.rssi,
    required this.scannedAt,
    required this.scanDurationMs,
    required this.isMock,
    this.proof,
    this.c6Token,
  });

  Map<String, dynamic> toJson() {
    return {
      if (beaconId.isNotEmpty) 'beaconId': beaconId,
      if (roomId.isNotEmpty) 'roomId': roomId,
      if (deviceName.isNotEmpty) 'deviceName': deviceName,
      if (serviceUuid.isNotEmpty) 'serviceUuid': serviceUuid,
      'rssi': rssi,
      'scannedAt': scannedAt.toUtc().toIso8601String(),
      'scanDurationMs': scanDurationMs,
      'isMock': isMock,
      if (proof != null) 'proof': proof,
      if (c6Token != null) 'c6Token': c6Token,
    };
  }
}
