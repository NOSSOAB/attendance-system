import 'user_role.dart';

class AuthSessionModel {
  final String message;
  final UserRole role;
  final String accessToken;
  final String tokenType;
  final int expiresInSeconds;
  final AuthUserProfileModel user;

  const AuthSessionModel({
    required this.message,
    required this.role,
    required this.accessToken,
    required this.tokenType,
    required this.expiresInSeconds,
    required this.user,
  });

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    return AuthSessionModel(
      message: json['message'] as String? ?? 'Đăng nhập thành công',
      role: userRoleFromValue(json['role'] as String?),
      accessToken: json['accessToken'] as String? ?? '',
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 0,
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
      'user': user.toJson(),
    };
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
