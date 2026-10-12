import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend_student/core/api/app_http_client.dart';
import 'package:frontend_student/core/api/attendance_changes.dart';
import 'package:frontend_student/core/api/lecturer_api_service.dart';
import 'package:frontend_student/core/auth/auth_session_controller.dart';
import 'package:frontend_student/shared/models/auth_session_model.dart';
import 'package:frontend_student/shared/storage/auth_persistence_service.dart';

import 'auth_persistence_service_test.dart' as fixture;

void main() {
  test('closing an unchanged roster cannot overwrite concurrent check-ins', () {
    final students = <Map<String, dynamic>>[
      {
        'studentId': 1,
        'recordId': 10,
        'status': {'code': 'OK'},
        'note': '',
        'updatedAt': '2026-09-10T01:00:00.000Z',
      },
      {
        'studentId': 2,
        'recordId': null,
        'status': {'code': 'ABSENT'},
        'note': '',
      },
    ];
    expect(buildAttendanceChanges(students: students, edits: {}), isEmpty);
    expect(
      buildAttendanceChanges(
        students: students,
        edits: {
          1: {'status': 'OK', 'note': ''},
        },
      ),
      isEmpty,
    );
    expect(
      buildAttendanceChanges(
        students: students,
        edits: {
          1: {'status': 'OK', 'note': 'Reviewed'},
        },
      ),
      [
        {
          'studentId': 1,
          'recordId': 10,
          'expectedUpdatedAt': '2026-09-10T01:00:00.000Z',
          'status': 'OK',
          'note': 'Reviewed',
        },
      ],
    );
  });

  test(
    'lecturer timestamps carry UTC while history date stays a calendar date',
    () async {
      final requests = <http.Request>[];
      final api = LecturerApiService(
        accessToken: 'test',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      final start = DateTime.parse('2026-09-10T07:00:00+07:00');
      await api.createAttendanceSession(
        schoolCode: 'S',
        lecturerCode: 'L',
        scheduleId: 1,
        startAt: start,
        endAt: start.add(const Duration(minutes: 20)),
      );
      final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(body['startAt'], '2026-09-10T00:00:00.000Z');
      expect(body['endAt'], '2026-09-10T00:20:00.000Z');
      await api.getHistory(
        schoolCode: 'S',
        lecturerCode: 'L',
        attendanceDate: DateTime(2026, 9, 10),
      );
      expect(requests.last.url.queryParameters['attendanceDate'], '2026-09-10');
    },
  );

  test(
    '401 expires current login once and ignores a previous login response',
    () async {
      final sessions = AuthSessionController();
      addTearDown(sessions.dispose);
      var notifications = 0;
      sessions.addListener(() => notifications++);
      sessions.activate(fixture.testSession, fixture.testSchool);
      final client = AppHttpClient(
        sessions: sessions,
        inner: MockClient((_) async => http.Response('{}', 401)),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(
          Uri.parse('https://api.test/students/home'),
          headers: {'Authorization': 'Bearer old-token'},
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(sessions.active, isNotNull);
      expect(notifications, 0);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          client.get(
            Uri.parse('https://api.test/students/home'),
            headers: {
              'Authorization': 'Bearer ${fixture.testSession.accessToken}',
            },
          ),
          throwsA(isA<SessionExpiredException>()),
        );
      }
      expect(sessions.active, isNull);
      expect(notifications, 1);
    },
  );

  test('Face session token 401 does not log out application login', () async {
    final sessions = AuthSessionController();
    addTearDown(sessions.dispose);
    sessions.activate(fixture.testSession, fixture.testSchool);
    final client = AppHttpClient(
      sessions: sessions,
      inner: MockClient((_) async => http.Response('{}', 401)),
    );
    addTearDown(client.close);
    final response = await client.get(
      Uri.parse('https://api.test/face-01/session'),
      headers: {'X-Session-Token': 'face-token'},
    );
    expect(response.statusCode, 401);
    expect(sessions.active, isNotNull);
  });

  test(
    'expired persisted session is removed while school and identifier remain',
    () async {
      final secure = fixture.MemoryAuthStore();
      final service = AuthPersistenceService(
        secureStore: secure,
        legacyStore: fixture.MemoryAuthStore(),
      );
      final session = AuthSessionModel.fromJson({
        ...fixture.testSession.toJson(),
        'expiresAt': '2020-01-01T00:00:00Z',
        'expiresInSeconds': 28800,
      });
      await service.saveLoginState(
        school: fixture.testSchool,
        role: session.role,
        identifier: session.user.code,
        rememberSession: true,
        session: session,
      );
      final restored = await service.readState();
      expect(restored!.hasSavedSession, false);
      expect(restored.identifier, session.user.code);
      expect(restored.session, isNull);
      expect(
        secure.values[AuthPersistenceService.secureStateKey],
        isNot(contains(session.accessToken)),
      );
    },
  );

  test('legacy relative TTL never renews an unknown token', () async {
    final legacy = fixture.legacyValues(session: fixture.testSession);
    final data =
        jsonDecode(legacy[AuthPersistenceService.legacySessionKey]!)
            as Map<String, dynamic>;
    data.remove('expiresAt');
    legacy[AuthPersistenceService.legacySessionKey] = jsonEncode(data);
    final service = AuthPersistenceService(
      secureStore: fixture.MemoryAuthStore(),
      legacyStore: fixture.MemoryAuthStore(legacy),
    );
    expect((await service.readState())!.hasSavedSession, false);
  });

  test('JWT expiry bounds saved expiry and supports legacy migration', () {
    final exp = DateTime.now().toUtc().add(const Duration(hours: 1));
    final token =
        'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'exp': exp.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.signature';
    expect(
      AuthSessionModel.resolveExpiry(
            token,
            '2099-01-01T00:00:00Z',
          )!.millisecondsSinceEpoch ~/
          1000,
      exp.millisecondsSinceEpoch ~/ 1000,
    );
    expect(AuthSessionModel.resolveExpiry(token, null), isNotNull);
  });
}
