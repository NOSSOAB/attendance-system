import 'dart:convert';

import 'user_role.dart';

class AuthSessionModel {
  final String message;
  final UserRole role;
  final String accessToken;
  final String tokenType;
  final int expiresInSeconds;
  final DateTime? expiresAt;
  final AuthUserProfileModel user;

  const AuthSessionModel({
    required this.message,
    required this.role,
    required this.accessToken,
    required this.tokenType,
    required this.expiresInSeconds,
    this.expiresAt,
    required this.user,
  });

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    final token = json['accessToken'] as String? ?? '';
    final ttl = (json['expiresInSeconds'] as num?)?.toInt() ?? 0;
    return AuthSessionModel(
      message: json['message'] as String? ?? 'Đăng nhập thành công',
      role: userRoleFromValue(json['role'] as String?),
      accessToken: token,
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      expiresInSeconds: ttl,
      expiresAt:
          resolveExpiry(token, json['expiresAt']) ??
          (ttl > 0 ? DateTime.now().toUtc().add(Duration(seconds: ttl)) : null),
      user: AuthUserProfileModel.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'role': role.apiValue,
      'accessToken': accessToken,
      'tokenType': tokenType,
      'expiresInSeconds': expiresInSeconds,
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'user': user.toJson(),
    };
  }

  DateTime? get effectiveExpiresAt =>
      resolveExpiry(accessToken, expiresAt?.toIso8601String());

  bool get isExpired =>
      effectiveExpiresAt == null ||
      !effectiveExpiresAt!.isAfter(DateTime.now().toUtc());

  // JWT decoding is only a local expiry hint; the server verifies the signature.
  // Never renew a restored session from a relative TTL saved at login time.
  static DateTime? resolveExpiry(String token, Object? storedExpiry) {
    final persisted = storedExpiry is String
        ? DateTime.tryParse(storedExpiry)?.toUtc()
        : null;
    DateTime? jwtExpiry;
    try {
      final segments = token.split('.');
      if (segments.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
        );
        final exp = payload is Map<String, dynamic> ? payload['exp'] : null;
        if (exp is num && exp.isFinite && exp > 0) {
          jwtExpiry = DateTime.fromMillisecondsSinceEpoch(
            (exp * 1000).toInt(),
            isUtc: true,
          );
        }
      }
    } catch (_) {
      // Missing or malformed expiry requires login again when no absolute expiry exists.
    }
    if (persisted == null) return jwtExpiry;
    if (jwtExpiry == null) return persisted;
    return persisted.isBefore(jwtExpiry) ? persisted : jwtExpiry;
  }
}

class AuthUserProfileModel {
  final int id;
  final String code;
  final String fullName;
  final String school;
  final String? faculty;
  final String? className;
  final DateTime? dateOfBirth;
  final String? citizenId;
  final String? email;

  const AuthUserProfileModel({
    required this.id,
    required this.code,
    required this.fullName,
    required this.school,
    required this.faculty,
    required this.className,
    required this.dateOfBirth,
    required this.citizenId,
    required this.email,
  });

  factory AuthUserProfileModel.fromJson(Map<String, dynamic> json) {
    final dateOfBirthRaw = json['dateOfBirth'];

    return AuthUserProfileModel(
      id: json['id'] as int,
      code: json['code'] as String,
      fullName: json['fullName'] as String,
      school: json['school'] as String? ?? '',
      faculty: json['faculty'] as String?,
      className: json['class'] as String?,
      dateOfBirth: dateOfBirthRaw is String && dateOfBirthRaw.isNotEmpty
          ? DateTime.tryParse(dateOfBirthRaw)
          : null,
      citizenId: json['citizenId'] as String?,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'fullName': fullName,
      'school': school,
      'faculty': faculty,
      'class': className,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'citizenId': citizenId,
      'email': email,
    };
  }
}
