import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class LecturerExportResult {
  final String fileName;
  final Uint8List bytes;

  const LecturerExportResult({required this.fileName, required this.bytes});
}

class LecturerApiService {
  final String accessToken;

  const LecturerApiService({required this.accessToken});

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> getHome({
    required String schoolCode,
    required String lecturerCode,
  }) {
    return _get(
      '/lecturers/home',
      queryParameters: const {},
    );
  }

  Future<Map<String, dynamic>> getClasses({
    required String schoolCode,
    required String lecturerCode,
  }) {
    return _get(
      '/lecturers/classes',
      queryParameters: const {},
    );
  }

  Future<Map<String, dynamic>> getClassDetail({
    required String schoolCode,
    required String lecturerCode,
    required int scheduleId,
  }) {
    return _get(
      '/lecturers/classes/$scheduleId',
      queryParameters: const {},
    );
  }

  Future<Map<String, dynamic>> createAttendanceSession({
    required String schoolCode,
    required String lecturerCode,
    required int scheduleId,
    required DateTime startAt,
    DateTime? endAt,
    int? durationMinutes,
  }) {
    return _post(
      '/lecturers/classes/$scheduleId/attendance-sessions',
      queryParameters: const {},
      body: {
        'startAt': startAt.toIso8601String(),
        if (endAt != null) 'endAt': endAt.toIso8601String(),
        'durationMinutes': ?durationMinutes,
      },
    );
  }

  Future<Map<String, dynamic>> saveAttendanceSession({
    required String schoolCode,
    required String lecturerCode,
    required int sessionId,
    required List<Map<String, dynamic>> records,
  }) {
    return _post(
      '/lecturers/attendance-sessions/$sessionId/save',
      queryParameters: const {},
      body: {'records': records},
    );
  }

  Future<Map<String, dynamic>> getHistory({
    required String schoolCode,
    required String lecturerCode,
    int? scheduleId,
    String? courseKeyword,
    DateTime? attendanceDate,
  }) {
    return _get(
      '/lecturers/history',
      queryParameters: {
        if (scheduleId != null) 'scheduleId': '$scheduleId',
        if (courseKeyword != null && courseKeyword.trim().isNotEmpty)
          'courseKeyword': courseKeyword.trim(),
        if (attendanceDate != null)
          'attendanceDate': attendanceDate.toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> getStatistics({
    required String schoolCode,
    required String lecturerCode,
    int? scheduleId,
  }) {
    return _get(
      '/lecturers/statistics',
      queryParameters: {
        if (scheduleId != null) 'scheduleId': '$scheduleId',
      },
    );
  }

  Future<Map<String, dynamic>> getNotifications({
    required String schoolCode,
    required String lecturerCode,
  }) {
    return _get(
      '/lecturers/notifications',
      queryParameters: const {},
    );
  }

  Future<Map<String, dynamic>> markNotificationAsRead({
    required String schoolCode,
    required String lecturerCode,
    required int notificationId,
  }) {
    return _patch(
      '/lecturers/notifications/$notificationId/read',
      queryParameters: const {},
    );
  }

  Future<Map<String, dynamic>> getProfile({
    required String schoolCode,
    required String lecturerCode,
  }) {
    return _get(
      '/lecturers/profile',
      queryParameters: const {},
    );
  }

  Future<LecturerExportResult> exportAttendance({
    required String schoolCode,
    required String lecturerCode,
    required int scheduleId,
    required String scope,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/lecturers/export').replace(
      queryParameters: {
        'scheduleId': '$scheduleId',
        'scope': scope,
      },
    );
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode != 200) {
      final payload = response.body.isEmpty
          ? null
          : jsonDecode(response.body) as Object?;
      throw Exception(_resolveErrorMessage(payload, response.statusCode));
    }

    final disposition = response.headers['content-disposition'] ?? '';
    final fileName = _extractFileName(disposition) ?? 'attendance.xlsx';

    return LecturerExportResult(fileName: fileName, bytes: response.bodyBytes);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$path',
    ).replace(queryParameters: queryParameters);
    final response = await http.get(uri, headers: _headers);
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$path',
    ).replace(queryParameters: queryParameters);
    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode(body ?? const {}),
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$path',
    ).replace(queryParameters: queryParameters);
    final response = await http.patch(uri, headers: _headers);
    return _decodeJsonResponse(response);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final payload = response.body.isEmpty
        ? null
        : jsonDecode(response.body) as Object?;

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_resolveErrorMessage(payload, response.statusCode));
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception('Phản hồi từ máy chủ không hợp lệ');
    }

    return payload;
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

    return 'Yêu cầu thất bại (mã $statusCode)';
  }

  String? _extractFileName(String contentDisposition) {
    final match = RegExp(
      r'filename=\"?([^\";]+)\"?',
    ).firstMatch(contentDisposition);
    return match?.group(1);
  }
}
