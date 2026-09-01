import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/core/api/face_auth_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses a face session ticket returned by NestJS', () {
    final ticket = FaceSessionTicket.fromJson({
      'attendanceSessionId': 42,
      'faceSessionId': 'face-session-1',
      'faceSessionToken': 'short-lived-token',
      'faceShard': 'face-01',
      'stage': 'LIVENESS',
    });

    expect(ticket.attendanceSessionId, 42);
    expect(ticket.faceSessionId, 'face-session-1');
    expect(ticket.faceSessionToken, 'short-lived-token');
    expect(ticket.faceShard, 'face-01');
    expect(ticket.stage, 'LIVENESS');
  });

  test('accepts face-40 from the 300-student stack', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'attendanceSessionId': 42,
          'faceSessionId': 'face-session-40',
          'faceSessionToken': 'short-lived-token',
          'faceShard': 'face-40',
          'stage': 'LIVENESS',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = FaceAuthApiService(accessToken: 'token', client: client);

    final ticket = await service.startAttendanceSession(
      schoolCode: 'HUCE',
      mssv: '1389570',
      attendanceSessionId: 42,
    );

    expect(ticket.faceShard, 'face-40');
  });

  test('parses a terminal successful verification response', () {
    const ticket = FaceSessionTicket(
      attendanceSessionId: 42,
      faceSessionId: 'face-session-1',
      faceSessionToken: 'short-lived-token',
      faceShard: 'face-01',
      stage: 'LIVENESS',
    );

    final result = FaceVerificationResult.fromJson({
      'stage': 'SUCCESS',
      'liveness': {
        'current_instruction': 'complete',
        'current_index': 1,
        'time_left_seconds': 0,
        'challenges': [
          {'action_id': 'mouth_open', 'status': 'PASS'},
        ],
      },
      'detection': {
        'face_count': 1,
        'face': {
          'face_size_ratio': 0.48,
          'checks': {'centered': true, 'brightness': true},
        },
      },
      'final': {'ok': true, 'code': 'VERIFIED', 'message': 'SUCCESS'},
      'recognition': {'similarity_percent': 91.25},
      'performance': {'collected_samples': 9},
    }, ticket: ticket);

    expect(result.isTerminal, isTrue);
    expect(result.isSuccess, isTrue);
    expect(result.similarityPercent, 91.25);
    expect(result.collectedSamples, 9);
    expect(result.challengeIndex, 1);
    expect(result.challengeCount, 1);
    expect(result.resultCode, 'VERIFIED');
    expect(result.faceCount, 1);
    expect(result.faceSizeRatio, 0.48);
    expect(result.faceCentered, isTrue);
    expect(result.brightnessOk, isTrue);
  });

  test('parses live face placement and the active action', () {
    const ticket = FaceSessionTicket(
      attendanceSessionId: 42,
      faceSessionId: 'face-session-2',
      faceSessionToken: 'short-lived-token',
      faceShard: 'face-02',
      stage: 'LIVENESS',
    );

    final result = FaceVerificationResult.fromJson({
      'stage': 'LIVENESS',
      'liveness': {
        'current_instruction': 'Vui lòng quay mặt sang trái',
        'current_index': 0,
        'time_left_seconds': 8.5,
        'challenges': [
          {'action_id': 'turn_left', 'baseline_seen': true},
          {'action_id': '', 'baseline_seen': false},
          {'action_id': '', 'baseline_seen': false},
        ],
      },
      'detection': {
        'face_count': 1,
        'face': {
          'face_size_ratio': 0.42,
          'checks': {'centered': true, 'brightness': true},
        },
      },
      'final': {'code': 'IN_PROGRESS'},
      'performance': {'collected_samples': 4},
    }, ticket: ticket);

    expect(result.faceCount, 1);
    expect(result.faceSizeRatio, 0.42);
    expect(result.currentActionId, 'turn_left');
    expect(result.actionBaselineReady, isTrue);
    expect(result.challengeCount, 3);
  });
}
