import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../shared/models/student_home_model.dart';
import '../ble/ble_models.dart';
import '../config/api_config.dart';
import '../location/gps_evidence.dart';

class StudentHomeApiService {
  final String accessToken;

  const StudentHomeApiService({required this.accessToken});

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  };

  Future<StudentHomeModel> getHomeOverview({
    required String schoolCode,
    required String mssv,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/students/home');

    final response = await http.get(uri, headers: _headers);
    final payload = _decodePayload(response.body);

    if (response.statusCode != 200) {
      throw Exception(_resolveErrorMessage(payload, response.statusCode));
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception('Dữ liệu trang chủ không hợp lệ');
    }

    return StudentHomeModel.fromJson(payload);
  }

  Future<AttendanceSubmissionResult> scanAttendance({
    required String schoolCode,
    required String mssv,
    required int sessionId,
    required String faceSessionId,
    required String faceSessionToken,
    required String faceShard,
    required BleEvidence bleEvidence,
    required double? faceScore,
    required DateTime faceVerifiedAt,
    required GpsEvidence gpsEvidence,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/students/attendance/scan');
    final payload = await _post(
      uri,
      body: {
        'sessionId': sessionId,
        'faceSessionId': faceSessionId,
        'faceSessionToken': faceSessionToken,
        'faceShard': faceShard,
        'bleEvidence': bleEvidence.toJson(),
        'faceEvidence': {
          'verified': true,
          'score': faceScore,
          'verifiedAt': faceVerifiedAt.toUtc().toIso8601String(),
        },
        'gpsEvidence': gpsEvidence.toJson(),
      },
    );

    return AttendanceSubmissionResult.fromJson(payload);
  }

  Future<List<StudentScheduleItemModel>> getSchedule({
    required String schoolCode,
    required String mssv,
    required String view,
    required String date,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/students/schedule',
    ).replace(queryParameters: {'view': view, 'date': date});

    final response = await http.get(uri, headers: _headers);
    final payload = _decodePayload(response.body);

    if (response.statusCode != 200) {
      throw Exception(_resolveErrorMessage(payload, response.statusCode));
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception('Dữ liệu lịch học không hợp lệ');
    }

    return (payload['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StudentScheduleItemModel.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    required Map<String, Object?> body,
  }) async {
    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode(body),
    );
    final payload = _decodePayload(response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_resolveErrorMessage(payload, response.statusCode));
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception('Phản hồi điểm danh không hợp lệ');
    }

    return payload;
  }

  Object? _decodePayload(String body) {
    if (body.isEmpty) {
      return null;
    }

    return jsonDecode(body) as Object?;
  }

  String _resolveErrorMessage(Object? payload, int statusCode) {
    if (payload is Map<String, dynamic>) {
      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) {
          return first;
        }
      }
    }

    return 'Không xử lý được yêu cầu (mã $statusCode)';
  }
}

class AttendanceSubmissionResult {
  final String status;
  final String message;
  final bool canRetry;

  const AttendanceSubmissionResult({
    required this.status,
    required this.message,
    required this.canRetry,
  });

  bool get isAccepted => status == 'present' || status == 'late';

  factory AttendanceSubmissionResult.fromJson(Map<String, dynamic> json) {
    return AttendanceSubmissionResult(
      status: json['status'] as String? ?? json['scanState'] as String? ?? '',
      message:
          json['message'] as String? ??
          'Máy chủ không trả về kết quả điểm danh hợp lệ',
      canRetry: json['canRetry'] as bool? ?? false,
    );
  }
}
