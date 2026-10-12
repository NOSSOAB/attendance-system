import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session_model.dart';
import '../models/school_model.dart';
import '../models/user_role.dart';

class StoredAuthState {
  final SchoolModel school;
  final UserRole role;
  final String identifier;
  final bool rememberSession;
  final AuthSessionModel? session;

  const StoredAuthState({
    required this.school,
    required this.role,
    required this.identifier,
    required this.rememberSession,
    required this.session,
  });

  bool get hasSavedSession =>
      rememberSession &&
      session != null &&
      session!.accessToken.trim().isNotEmpty &&
      !session!.isExpired;
}

abstract interface class AuthKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureAuthStore implements AuthKeyValueStore {
  final FlutterSecureStorage _storage;

  FlutterSecureAuthStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'smart_attendance_auth_v1',
              resetOnError: true,
              migrateOnAlgorithmChange: true,
              migrateWithBackup: true,
            ),
          );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SharedPreferencesAuthStore implements AuthKeyValueStore {
  Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async {
    final value = (await _preferences()).get(key);
    if (value is String) {
      return value;
    }
    if (value is bool) {
      return value.toString();
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    await (await _preferences()).setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await (await _preferences()).remove(key);
  }
}

class AuthPersistenceService {
  static const String secureStateKey = 'auth.secure_state.v1';
  static const String _migrationMarkerKey = 'auth.secure_migration.v1';
  static const String _migrationVersion = '1';

  static const String legacySchoolKey = 'auth.selected_school';
  static const String legacyRoleKey = 'auth.selected_role';
  static const String legacyIdentifierKey = 'auth.identifier';
  static const String legacyRememberSessionKey = 'auth.remember_session';
  static const String legacySessionKey = 'auth.saved_session';

  static const List<String> _legacyKeys = [
    legacySchoolKey,
    legacyRoleKey,
    legacyIdentifierKey,
    legacyRememberSessionKey,
    legacySessionKey,
  ];

  final AuthKeyValueStore _secureStore;
  final AuthKeyValueStore _legacyStore;

  Future<void>? _migrationFuture;

  AuthPersistenceService({
    AuthKeyValueStore? secureStore,
    AuthKeyValueStore? legacyStore,
  }) : _secureStore = secureStore ?? FlutterSecureAuthStore(),
       _legacyStore = legacyStore ?? SharedPreferencesAuthStore();

  Future<StoredAuthState?> readState() async {
    await _ensureMigrated();
    final payload = await _readSecurePayload();
    if (payload == null) {
      return null;
    }

    final schoolJson = payload['school'];
    final roleRaw = payload['role'];
    final identifierRaw = payload['identifier'];

    if (schoolJson is! Map<String, dynamic> ||
        roleRaw is! String ||
        identifierRaw is! String ||
        identifierRaw.trim().isEmpty) {
      return null;
    }

    try {
      final role = userRoleFromValue(roleRaw);
      final school = SchoolModel.fromJson(schoolJson);
      final rememberSession = payload['rememberSession'] == true;
      final sessionJson = payload['session'];
      var session = sessionJson is Map<String, dynamic>
          ? _sessionFromSecureJson(sessionJson, role: role, school: school)
          : null;

      if (session != null && session.isExpired) {
        session = null;
        await _writeSecurePayload({...payload}..remove('session'));
      }

      return StoredAuthState(
        school: school,
        role: role,
        identifier: identifierRaw.trim(),
        rememberSession: rememberSession,
        session: session,
      );
    } catch (_) {
      await clearAll();
      return null;
    }
  }

  Future<SchoolModel?> readSelectedSchool() async {
    await _ensureMigrated();
    final payload = await _readSecurePayload();
    final schoolJson = payload?['school'];

    if (schoolJson is! Map<String, dynamic>) {
      return null;
    }

    try {
      return SchoolModel.fromJson(schoolJson);
    } catch (_) {
      await clearAll();
      return null;
    }
  }

  Future<void> saveLoginState({
    required SchoolModel school,
    required UserRole role,
    required String identifier,
    required bool rememberSession,
    AuthSessionModel? session,
  }) async {
    await _ensureMigrated();
    final shouldPersistSession = rememberSession && session != null;

    await _writeSecurePayload({
      'version': 1,
      'school': school.toJson(),
      'role': role.apiValue,
      'identifier': identifier.trim(),
      'rememberSession': rememberSession,
      if (shouldPersistSession) 'session': _sessionToSecureJson(session),
    });
    await _deleteLegacyKeys();
  }

  Future<void> clearSavedSessionKeepingContext({
    required SchoolModel school,
    required UserRole role,
    required String identifier,
  }) async {
    await _ensureMigrated();
    final payload = await _readSecurePayload();
    final rememberSession = payload?['rememberSession'] == true;

    await _secureStore.delete(secureStateKey);
    await _writeSecurePayload({
      'version': 1,
      'school': school.toJson(),
      'role': role.apiValue,
      'identifier': identifier.trim(),
      'rememberSession': rememberSession,
    });
    await _deleteLegacyKeys();
  }

  Future<void> saveSelectedSchoolOnly({required SchoolModel school}) async {
    await _ensureMigrated();
    await _writeSecurePayload({'version': 1, 'school': school.toJson()});
    await _deleteLegacyKeys();
  }

  Future<void> clearAll() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _secureStore.delete(secureStateKey);
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    try {
      await _deleteLegacyKeys();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (firstError != null && firstStackTrace != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace);
    }
  }

  Future<void> _ensureMigrated() {
    final activeMigration = _migrationFuture;
    if (activeMigration != null) {
      return activeMigration;
    }

    final migration = _migrateLegacyState();
    _migrationFuture = migration;
    return migration.catchError((Object error, StackTrace stackTrace) {
      if (identical(_migrationFuture, migration)) {
        _migrationFuture = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _migrateLegacyState() async {
    final marker = await _secureStore.read(_migrationMarkerKey);
    if (marker == _migrationVersion) {
      await _deleteLegacyKeys();
      return;
    }

    final legacyValues = <String, String>{};
    for (final key in _legacyKeys) {
      final value = await _legacyStore.read(key);
      if (value != null) {
        legacyValues[key] = value;
      }
    }

    final existingSecurePayload = await _secureStore.read(secureStateKey);
    final hasVerifiedSecurePayload =
        existingSecurePayload != null &&
        _isValidSecurePayload(existingSecurePayload);

    if (legacyValues.isNotEmpty && !hasVerifiedSecurePayload) {
      final migratedPayload = _legacyPayloadToSecureJson(legacyValues);
      final encodedPayload = jsonEncode(migratedPayload);
      await _secureStore.write(secureStateKey, encodedPayload);

      final verifiedPayload = await _secureStore.read(secureStateKey);
      if (verifiedPayload != encodedPayload) {
        throw StateError(
          'Kh\u00f4ng th\u1ec3 x\u00e1c minh d\u1eef li\u1ec7u '
          '\u0111\u0103ng nh\u1eadp \u0111\u00e3 m\u00e3 h\u00f3a',
        );
      }
    }

    await _deleteLegacyKeys();
    await _secureStore.write(_migrationMarkerKey, _migrationVersion);

    if (await _secureStore.read(_migrationMarkerKey) != _migrationVersion) {
      throw StateError(
        'Kh\u00f4ng th\u1ec3 ho\u00e0n t\u1ea5t chuy\u1ec3n \u0111\u1ed5i '
        'l\u01b0u tr\u1eef \u0111\u0103ng nh\u1eadp',
      );
    }
  }

  bool _isValidSecurePayload(String rawPayload) {
    try {
      final payload = jsonDecode(rawPayload);
      return payload is Map<String, dynamic> && payload['version'] == 1;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _legacyPayloadToSecureJson(
    Map<String, String> legacyValues,
  ) {
    final payload = <String, dynamic>{'version': 1};
    final schoolRaw = legacyValues[legacySchoolKey];
    final roleRaw = legacyValues[legacyRoleKey];
    final identifier = legacyValues[legacyIdentifierKey]?.trim();
    final rememberSession =
        legacyValues[legacyRememberSessionKey]?.toLowerCase() == 'true';

    if (schoolRaw != null) {
      try {
        final schoolJson = jsonDecode(schoolRaw);
        if (schoolJson is Map<String, dynamic>) {
          payload['school'] = schoolJson;
        }
      } catch (_) {
        // Invalid legacy context is intentionally not copied into secure storage.
      }
    }

    if (roleRaw != null) {
      payload['role'] = userRoleFromValue(roleRaw).apiValue;
    }
    if (identifier != null && identifier.isNotEmpty) {
      payload['identifier'] = identifier;
    }
    payload['rememberSession'] = rememberSession;

    final sessionRaw = legacyValues[legacySessionKey];
    if (rememberSession && sessionRaw != null) {
      try {
        final sessionJson = jsonDecode(sessionRaw);
        if (sessionJson is Map<String, dynamic>) {
          // Old relative TTLs cannot establish when the user actually logged in.
          final session = AuthSessionModel.fromJson({
            ...sessionJson,
            'expiresInSeconds': 0,
          });
          payload['session'] = _sessionToSecureJson(session);
        }
      } catch (_) {
        // A corrupt legacy session is discarded while valid context is retained.
      }
    }

    return payload;
  }

  Future<Map<String, dynamic>?> _readSecurePayload() async {
    final rawPayload = await _secureStore.read(secureStateKey);
    if (rawPayload == null) {
      return null;
    }

    try {
      final payload = jsonDecode(rawPayload);
      if (payload is Map<String, dynamic> && payload['version'] == 1) {
        return payload;
      }
    } catch (_) {
      // Corrupt encrypted state is removed below by the caller.
    }

    await clearAll();
    return null;
  }

  Future<void> _writeSecurePayload(Map<String, dynamic> payload) async {
    final encodedPayload = jsonEncode(payload);
    await _secureStore.write(secureStateKey, encodedPayload);

    if (await _secureStore.read(secureStateKey) != encodedPayload) {
      throw StateError(
        'Kh\u00f4ng th\u1ec3 x\u00e1c minh d\u1eef li\u1ec7u '
        '\u0111\u0103ng nh\u1eadp \u0111\u00e3 m\u00e3 h\u00f3a',
      );
    }
  }

  Future<void> _deleteLegacyKeys() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    for (final key in _legacyKeys) {
      try {
        await _legacyStore.delete(key);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    for (final key in _legacyKeys) {
      try {
        if (await _legacyStore.read(key) != null) {
          firstError ??= StateError(
            'Kh\u00f4ng th\u1ec3 x\u00f3a d\u1eef li\u1ec7u \u0111\u0103ng nh\u1eadp c\u0169',
          );
          firstStackTrace ??= StackTrace.current;
        }
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstError != null && firstStackTrace != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace);
    }
  }

  Map<String, dynamic> _sessionToSecureJson(AuthSessionModel session) {
    return {
      'accessToken': session.accessToken,
      'expiresAt': session.effectiveExpiresAt?.toUtc().toIso8601String(),
      'user': {
        'code': session.user.code,
        'fullName': session.user.fullName,
        'faculty': session.user.faculty,
        'class': session.user.className,
        'dateOfBirth': session.user.dateOfBirth?.toIso8601String(),
        'email': session.user.email,
      },
    };
  }

  AuthSessionModel _sessionFromSecureJson(
    Map<String, dynamic> json, {
    required UserRole role,
    required SchoolModel school,
  }) {
    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const FormatException('Invalid encrypted user profile');
    }

    final code = userJson['code'];
    final fullName = userJson['fullName'];
    final accessToken = json['accessToken'];
    if (code is! String ||
        fullName is! String ||
        accessToken is! String ||
        accessToken.trim().isEmpty) {
      throw const FormatException('Invalid encrypted auth session');
    }

    final dateOfBirthRaw = userJson['dateOfBirth'];
    return AuthSessionModel(
      message: '\u0110\u0103ng nh\u1eadp th\u00e0nh c\u00f4ng',
      role: role,
      accessToken: accessToken,
      tokenType: 'Bearer',
      expiresInSeconds: 0,
      expiresAt: AuthSessionModel.resolveExpiry(accessToken, json['expiresAt']),
      user: AuthUserProfileModel(
        id: 0,
        code: code,
        fullName: fullName,
        school: school.name,
        faculty: userJson['faculty'] as String?,
        className: userJson['class'] as String?,
        dateOfBirth: dateOfBirthRaw is String && dateOfBirthRaw.isNotEmpty
            ? DateTime.tryParse(dateOfBirthRaw)
            : null,
        citizenId: null,
        email: userJson['email'] as String?,
      ),
    );
  }
}
