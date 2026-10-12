import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../face/mobile_face_ml.dart';
import 'app_http_client.dart';

class MobileFaceSessionTicket {
  final int protocolVersion;
  final int attendanceSessionId;
  final String sessionId;
  final String nonce;
  final String modelId;
  final DateTime expiresAt;
  final List<String> livenessActions;

  const MobileFaceSessionTicket({
    required this.protocolVersion,
    required this.attendanceSessionId,
    required this.sessionId,
    required this.nonce,
    required this.modelId,
    required this.expiresAt,
    required this.livenessActions,
  });

  factory MobileFaceSessionTicket.fromJson(Map<String, dynamic> json) =>
      MobileFaceSessionTicket(
        protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 0,
        attendanceSessionId: json['attendanceSessionId'] as int? ?? 0,
        sessionId: json['sessionId'] as String? ?? '',
        nonce: json['nonce'] as String? ?? '',
        modelId: json['modelId'] as String? ?? '',
        expiresAt:
            DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        livenessActions: (json['livenessActions'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
}

class MobileFaceCompletionResult {
  final bool verified;
  final double similarity;
  const MobileFaceCompletionResult({
    required this.verified,
    required this.similarity,
  });
  factory MobileFaceCompletionResult.fromJson(Map<String, dynamic> json) =>
      MobileFaceCompletionResult(
        verified: json['verified'] == true,
        similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      );
}

class FaceSessionTicket {
  final int attendanceSessionId;
  final String faceSessionId;
  final String faceSessionToken;
  final String faceShard;
  final String stage;

  const FaceSessionTicket({
    required this.attendanceSessionId,
    required this.faceSessionId,
    required this.faceSessionToken,
    required this.faceShard,
    required this.stage,
  });

  factory FaceSessionTicket.fromJson(Map<String, dynamic> json) {
    return FaceSessionTicket(
      attendanceSessionId: json['attendanceSessionId'] as int? ?? 0,
      faceSessionId: json['faceSessionId'] as String? ?? '',
      faceSessionToken: json['faceSessionToken'] as String? ?? '',
      faceShard: json['faceShard'] as String? ?? '',
      stage: json['stage'] as String? ?? 'LIVENESS',
    );
  }
}

class FaceVerificationResult {
  final String faceSessionId;
  final String faceSessionToken;
  final String faceShard;
  final String stage;
  final String instruction;
  final String message;
  final double? similarityPercent;
  final int collectedSamples;
  final int challengeIndex;
  final int challengeCount;
  final double secondsRemaining;
  final String resultCode;
  final int faceCount;
  final double? faceSizeRatio;
  final bool faceCentered;
  final bool brightnessOk;
  final String currentActionId;
  final bool actionBaselineReady;

  const FaceVerificationResult({
    required this.faceSessionId,
    required this.faceSessionToken,
    required this.faceShard,
    required this.stage,
    required this.instruction,
    required this.message,
    required this.similarityPercent,
    required this.collectedSamples,
    required this.challengeIndex,
    required this.challengeCount,
    required this.secondsRemaining,
    required this.resultCode,
    required this.faceCount,
    required this.faceSizeRatio,
    required this.faceCentered,
    required this.brightnessOk,
    required this.currentActionId,
    required this.actionBaselineReady,
  });

  bool get isTerminal => stage == 'SUCCESS' || stage == 'FAILED';
  bool get isSuccess => stage == 'SUCCESS';

  factory FaceVerificationResult.fromJson(
    Map<String, dynamic> json, {
    required FaceSessionTicket ticket,
  }) {
    final liveness =
        json['liveness'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final finalResult =
        json['final'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final recognition =
        json['recognition'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final performance =
        json['performance'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final challenges = liveness['challenges'] as List<dynamic>? ?? const [];
    final detection =
        json['detection'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final face =
        detection['face'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final checks =
        face['checks'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final challengeIndex = (liveness['current_index'] as num?)?.toInt() ?? 0;
    final currentChallenge =
        challengeIndex >= 0 && challengeIndex < challenges.length
        ? challenges[challengeIndex] as Map<String, dynamic>?
        : null;

    return FaceVerificationResult(
      faceSessionId: ticket.faceSessionId,
      faceSessionToken: ticket.faceSessionToken,
      faceShard: ticket.faceShard,
      stage: json['stage'] as String? ?? ticket.stage,
      instruction:
          liveness['current_instruction'] as String? ??
          'Giữ khuôn mặt trong khung hình',
      message:
          finalResult['message'] as String? ??
          liveness['message'] as String? ??
          '',
      similarityPercent: (recognition['similarity_percent'] as num?)
          ?.toDouble(),
      collectedSamples: performance['collected_samples'] as int? ?? 0,
      challengeIndex: challengeIndex,
      challengeCount: challenges.length,
      secondsRemaining:
          (liveness['time_left_seconds'] as num?)?.toDouble() ?? 0,
      resultCode: finalResult['code'] as String? ?? '',
      faceCount: (detection['face_count'] as num?)?.toInt() ?? 0,
      faceSizeRatio: (face['face_size_ratio'] as num?)?.toDouble(),
      faceCentered: checks['centered'] as bool? ?? false,
      brightnessOk: checks['brightness'] as bool? ?? false,
      currentActionId: currentChallenge?['action_id'] as String? ?? '',
      actionBaselineReady: currentChallenge?['baseline_seen'] as bool? ?? false,
    );
  }
}

class FaceAuthApiService {
  final http.Client _client;
  final String accessToken;

  FaceAuthApiService({required this.accessToken, http.Client? client})
    : _client = AppHttpClient(inner: client);

  Future<FaceSessionTicket> startAttendanceSession({
    required String schoolCode,
    required String mssv,
    required int attendanceSessionId,
  }) async {
    final response = await _client
        .post(
          Uri.parse('${ApiConfig.baseUrl}/students/attendance/face-session'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'sessionId': attendanceSessionId}),
        )
        .timeout(const Duration(seconds: 25));
    final payload = _decodeMap(response);
    final ticket = FaceSessionTicket.fromJson(payload);
    if (ticket.faceSessionId.isEmpty ||
        ticket.faceSessionToken.isEmpty ||
        !RegExp(r'^face-(0[1-9]|[1-3][0-9]|40)$').hasMatch(ticket.faceShard)) {
      throw const FaceAuthApiException(
        'Máy chủ trả về phiên xác minh không hợp lệ',
      );
    }
    return ticket;
  }

  Future<MobileFaceSessionTicket> startMobileAttendanceSession({
    required int attendanceSessionId,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '${ApiConfig.baseUrl}/students/attendance/mobile-face-session',
          ),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'sessionId': attendanceSessionId}),
        )
        .timeout(const Duration(seconds: 15));
    final ticket = MobileFaceSessionTicket.fromJson(_decodeMap(response));
    if (ticket.protocolVersion != 3 ||
        ticket.attendanceSessionId != attendanceSessionId ||
        ticket.sessionId.isEmpty ||
        ticket.nonce.isEmpty ||
        ticket.modelId.isEmpty ||
        ticket.expiresAt.difference(DateTime.now().toUtc()) <
            const Duration(seconds: 20) ||
        ticket.livenessActions.length != 3 ||
        ticket.livenessActions.toSet().length != 3 ||
        !ticket.livenessActions.contains('blink') ||
        !ticket.livenessActions.contains('smile') ||
        !ticket.livenessActions.contains('turn')) {
      throw const FaceAuthApiException(
        'Máy chủ trả về phiên mobile không hợp lệ',
      );
    }
    return ticket;
  }

  Future<MobileFaceCompletionResult> completeMobileAttendanceSession({
    required MobileFaceSessionTicket ticket,
    required List<double> embedding,
    required String publicKey,
    required String signature,
    required MobileLivenessProof livenessProof,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '${ApiConfig.baseUrl}/students/attendance/mobile-face-session/complete',
          ),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'protocolVersion': ticket.protocolVersion,
            'sessionId': ticket.sessionId,
            'nonce': ticket.nonce,
            'embedding': embedding,
            'publicKey': publicKey,
            'signature': signature,
            'livenessProof': livenessProof.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    return MobileFaceCompletionResult.fromJson(_decodeMap(response));
  }

  Future<void> enrollMobileFace({
    required FaceSessionTicket trustedTicket,
    required List<List<double>> embeddings,
    required String publicKey,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '${ApiConfig.baseUrl}/students/attendance/mobile-face-enrollment',
          ),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'faceSessionId': trustedTicket.faceSessionId,
            'faceSessionToken': trustedTicket.faceSessionToken,
            'faceShard': trustedTicket.faceShard,
            'embeddings': embeddings,
            'publicKey': publicKey,
          }),
        )
        .timeout(const Duration(seconds: 20));
    _decodeMap(response);
  }

  Future<FaceVerificationResult> sendFrame({
    required FaceSessionTicket ticket,
    required Uint8List jpegBytes,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              '${_faceBaseUrl(ticket)}/api/v1/sessions/'
              '${Uri.encodeComponent(ticket.faceSessionId)}/frames',
            ),
          )
          ..headers['X-Session-Token'] = ticket.faceSessionToken
          ..fields['mirror'] = 'true'
          ..fields['rotation_degrees'] = '-1'
          ..files.add(
            http.MultipartFile.fromBytes(
              'image',
              jpegBytes,
              filename: 'frame.jpg',
            ),
          );

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);
    return FaceVerificationResult.fromJson(
      _decodeMap(response),
      ticket: ticket,
    );
  }

  Future<FaceVerificationResult> getStatus(FaceSessionTicket ticket) async {
    final response = await _client
        .get(
          Uri.parse(
            '${_faceBaseUrl(ticket)}/api/v1/sessions/'
            '${Uri.encodeComponent(ticket.faceSessionId)}',
          ),
          headers: {'X-Session-Token': ticket.faceSessionToken},
        )
        .timeout(const Duration(seconds: 20));
    return FaceVerificationResult.fromJson(
      _decodeMap(response),
      ticket: ticket,
    );
  }

  Future<void> deleteSession(FaceSessionTicket ticket) async {
    try {
      await _client
          .delete(
            Uri.parse(
              '${_faceBaseUrl(ticket)}/api/v1/sessions/'
              '${Uri.encodeComponent(ticket.faceSessionId)}',
            ),
            headers: {'X-Session-Token': ticket.faceSessionToken},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Face Auth expires abandoned sessions automatically.
    }
  }

  void close() {
    _client.close();
  }

  String _faceBaseUrl(FaceSessionTicket ticket) {
    return '${ApiConfig.faceBaseUrl}/${Uri.encodeComponent(ticket.faceShard)}';
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    Object? payload;
    try {
      payload = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      payload = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Không kết nối được dịch vụ xác minh khuôn mặt';
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail'] ?? payload['message'];
        if (detail is String && detail.trim().isNotEmpty) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty) {
          message = detail.first.toString();
        }
      }
      throw FaceAuthApiException(message, statusCode: response.statusCode);
    }

    if (payload is! Map<String, dynamic>) {
      throw const FaceAuthApiException(
        'Phản hồi xác minh khuôn mặt không hợp lệ',
      );
    }
    return payload;
  }
}

class FaceAuthApiException implements Exception {
  final String message;
  final int? statusCode;

  const FaceAuthApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
