import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/shared/models/auth_session_model.dart';
import 'package:frontend_student/shared/models/school_model.dart';
import 'package:frontend_student/shared/models/user_role.dart';
import 'package:frontend_student/shared/storage/auth_persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AuthPersistenceService', () {
    test('stores only the session fields needed by the app', () async {
      final secureStore = MemoryAuthStore();
      final legacyStore = MemoryAuthStore();
      final service = AuthPersistenceService(
        secureStore: secureStore,
        legacyStore: legacyStore,
      );

      await service.saveLoginState(
        school: testSchool,
        role: UserRole.student,
        identifier: '  65CS1001  ',
        rememberSession: true,
        session: testSession,
      );

      final restored = await service.readState();
      final secureJson =
          secureStore.values[AuthPersistenceService.secureStateKey];

      expect(restored, isNotNull);
      expect(restored!.identifier, '65CS1001');
      expect(restored.hasSavedSession, isTrue);
      expect(restored.session!.accessToken, 'jwt-access-token');
      expect(restored.session!.user.code, testSession.user.code);
      expect(restored.session!.user.fullName, testSession.user.fullName);
      expect(restored.session!.user.faculty, testSession.user.faculty);
      expect(restored.session!.user.className, testSession.user.className);
      expect(restored.session!.user.dateOfBirth, testSession.user.dateOfBirth);
      expect(restored.session!.user.email, testSession.user.email);
      expect(secureJson, isNotNull);
      expect(secureJson, contains('jwt-access-token'));
      expect(secureJson, isNot(contains('sensitive-citizen-id')));
      expect(secureJson, isNot(contains('server-only-message')));
      expect(secureJson, isNot(contains('refresh-token-type')));
      expect(secureJson, isNot(contains('expiresInSeconds')));
      expect(secureJson, isNot(contains('"id":99')));
      expect(legacyStore.values, isEmpty);
    });

    test(
      'migrates legacy state once and removes every plaintext key',
      () async {
        final secureStore = MemoryAuthStore();
        final legacyStore = MemoryAuthStore(legacyValues(session: testSession));
        final service = AuthPersistenceService(
          secureStore: secureStore,
          legacyStore: legacyStore,
        );

        final migrated = await service.readState();

        expect(migrated, isNotNull);
        expect(migrated!.session!.accessToken, 'jwt-access-token');
        expect(legacyStore.values, isEmpty);
        expect(
          secureStore.values[AuthPersistenceService.secureStateKey],
          isNot(contains('sensitive-citizen-id')),
        );

        final staleSession = sessionWithToken('stale-plaintext-token');
        legacyStore.values.addAll(legacyValues(session: staleSession));

        final secondService = AuthPersistenceService(
          secureStore: secureStore,
          legacyStore: legacyStore,
        );
        final restoredAgain = await secondService.readState();

        expect(restoredAgain!.session!.accessToken, 'jwt-access-token');
        expect(legacyStore.values, isEmpty);
        expect(
          secureStore.values[AuthPersistenceService.secureStateKey],
          isNot(contains('stale-plaintext-token')),
        );
      },
    );

    test('migrates the legacy SharedPreferences boolean value', () async {
      final legacy = legacyValues(session: testSession);
      SharedPreferences.setMockInitialValues({
        ...legacy,
        AuthPersistenceService.legacyRememberSessionKey: true,
      });
      final secureStore = MemoryAuthStore();
      final service = AuthPersistenceService(
        secureStore: secureStore,
        legacyStore: SharedPreferencesAuthStore(),
      );

      final migrated = await service.readState();
      final preferences = await SharedPreferences.getInstance();

      expect(migrated, isNotNull);
      expect(migrated!.rememberSession, isTrue);
      expect(migrated.session!.accessToken, 'jwt-access-token');
      for (final key in legacyAuthKeys) {
        expect(preferences.containsKey(key), isFalse);
      }
    });

    test(
      'keeps legacy state when encrypted write verification fails',
      () async {
        final secureStore = CorruptingAuthStore();
        final legacyStore = MemoryAuthStore(legacyValues(session: testSession));
        final service = AuthPersistenceService(
          secureStore: secureStore,
          legacyStore: legacyStore,
        );

        await expectLater(service.readState(), throwsStateError);

        for (final key in legacyAuthKeys) {
          expect(legacyStore.values, contains(key));
        }
        expect(
          legacyStore.values[AuthPersistenceService.legacySessionKey],
          contains('jwt-access-token'),
        );
      },
    );

    test('logout removes secure token and all legacy auth keys', () async {
      final secureStore = MemoryAuthStore();
      final legacyStore = MemoryAuthStore();
      final service = AuthPersistenceService(
        secureStore: secureStore,
        legacyStore: legacyStore,
      );

      await service.saveLoginState(
        school: testSchool,
        role: UserRole.student,
        identifier: '65CS1001',
        rememberSession: true,
        session: testSession,
      );
      legacyStore.values.addAll(legacyValues(session: testSession));

      await service.clearSavedSessionKeepingContext(
        school: testSchool,
        role: UserRole.student,
        identifier: '65CS1001',
      );

      final afterLogout = await service.readState();
      final secureJson =
          secureStore.values[AuthPersistenceService.secureStateKey];
      expect(
        secureStore.deletedKeys,
        contains(AuthPersistenceService.secureStateKey),
      );
      expect(secureJson, isNotNull);
      expect(secureJson, isNot(contains('jwt-access-token')));
      expect(jsonDecode(secureJson!)['session'], isNull);
      expect(afterLogout, isNotNull);
      expect(afterLogout!.identifier, '65CS1001');
      expect(afterLogout.hasSavedSession, isFalse);
      expect(afterLogout.session, isNull);
      expect(legacyStore.values, isEmpty);
    });

    test('clearAll removes secure and legacy authentication state', () async {
      final secureStore = MemoryAuthStore();
      final legacyStore = MemoryAuthStore();
      final service = AuthPersistenceService(
        secureStore: secureStore,
        legacyStore: legacyStore,
      );

      await service.saveLoginState(
        school: testSchool,
        role: UserRole.lecturer,
        identifier: 'GV001',
        rememberSession: true,
        session: testSession,
      );
      legacyStore.values.addAll(legacyValues(session: testSession));

      await service.clearAll();

      expect(secureStore.values[AuthPersistenceService.secureStateKey], isNull);
      expect(legacyStore.values, isEmpty);
      expect(await service.readState(), isNull);
    });
  });
}

class MemoryAuthStore implements AuthKeyValueStore {
  MemoryAuthStore([Map<String, String>? initialValues])
    : values = {...?initialValues};

  final Map<String, String> values;
  final List<String> deletedKeys = [];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    values.remove(key);
  }
}

class CorruptingAuthStore extends MemoryAuthStore {
  bool _stateWasWritten = false;

  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    if (key == AuthPersistenceService.secureStateKey &&
        _stateWasWritten &&
        value != null) {
      return '$value-corrupt';
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (key == AuthPersistenceService.secureStateKey) {
      _stateWasWritten = true;
    }
  }
}

const testSchool = SchoolModel(
  id: 7,
  code: 'TEST-SCHOOL',
  name: 'Test University',
);

final testSession = AuthSessionModel(
  message: 'server-only-message',
  role: UserRole.student,
  accessToken: 'jwt-access-token',
  tokenType: 'refresh-token-type',
  expiresInSeconds: 7200,
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
  user: AuthUserProfileModel(
    id: 99,
    code: '65CS1001',
    fullName: 'Nguyen Van A',
    school: 'Server school label',
    faculty: 'Cong nghe thong tin',
    className: '65CS1',
    dateOfBirth: DateTime.utc(2004, 1, 2),
    citizenId: 'sensitive-citizen-id',
    email: 'student@example.edu.vn',
  ),
);

AuthSessionModel sessionWithToken(String token) {
  return AuthSessionModel(
    message: testSession.message,
    role: testSession.role,
    accessToken: token,
    tokenType: testSession.tokenType,
    expiresInSeconds: testSession.expiresInSeconds,
    expiresAt: testSession.expiresAt,
    user: testSession.user,
  );
}

Map<String, String> legacyValues({required AuthSessionModel session}) {
  return {
    AuthPersistenceService.legacySchoolKey: jsonEncode(testSchool.toJson()),
    AuthPersistenceService.legacyRoleKey: UserRole.student.apiValue,
    AuthPersistenceService.legacyIdentifierKey: '65CS1001',
    AuthPersistenceService.legacyRememberSessionKey: 'true',
    AuthPersistenceService.legacySessionKey: jsonEncode(session.toJson()),
  };
}

const legacyAuthKeys = [
  AuthPersistenceService.legacySchoolKey,
  AuthPersistenceService.legacyRoleKey,
  AuthPersistenceService.legacyIdentifierKey,
  AuthPersistenceService.legacyRememberSessionKey,
  AuthPersistenceService.legacySessionKey,
];
