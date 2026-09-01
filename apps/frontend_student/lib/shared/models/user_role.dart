import 'package:flutter/material.dart';

enum UserRole { student, lecturer }

UserRole userRoleFromValue(String? value) {
  switch (value) {
    case 'lecturer':
      return UserRole.lecturer;
    case 'student':
    default:
      return UserRole.student;
  }
}

extension UserRoleX on UserRole {
  String get apiValue {
    switch (this) {
      case UserRole.student:
        return 'student';
      case UserRole.lecturer:
        return 'lecturer';
    }
  }

  String get title {
    switch (this) {
      case UserRole.student:
        return 'Sinh vi\u00ean';
      case UserRole.lecturer:
        return 'Gi\u1ea3ng vi\u00ean';
    }
  }

  String get subtitle {
    switch (this) {
      case UserRole.student:
        return 'Truy c\u1eadp c\u1ed5ng th\u00f4ng tin \u0111\u00e0o t\u1ea1o';
      case UserRole.lecturer:
        return 'Qu\u1ea3n l\u00fd l\u1edbp h\u1ecdc v\u00e0 \u0111\u00e0o t\u1ea1o';
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.student:
        return Icons.school_rounded;
      case UserRole.lecturer:
        return Icons.cast_for_education_rounded;
    }
  }

  Color get iconBg {
    switch (this) {
      case UserRole.student:
        return const Color(0xFFEAF2FF);
      case UserRole.lecturer:
        return const Color(0xFFFFF2D6);
    }
  }

  Color get iconColor {
    switch (this) {
      case UserRole.student:
        return const Color(0xFF1D63EA);
      case UserRole.lecturer:
        return const Color(0xFFC88908);
    }
  }

  String get identifierLabel {
    switch (this) {
      case UserRole.student:
        return 'M\u00e3 sinh vi\u00ean';
      case UserRole.lecturer:
        return 'M\u00e3 gi\u1ea3ng vi\u00ean';
    }
  }

  String get identifierPlaceholder {
    switch (this) {
      case UserRole.student:
        return 'Nh\u1eadp m\u00e3 sinh vi\u00ean';
      case UserRole.lecturer:
        return 'Nh\u1eadp m\u00e3 gi\u1ea3ng vi\u00ean';
    }
  }

  String get loginHeading {
    switch (this) {
      case UserRole.student:
        return '\u0110\u0103ng nh\u1eadp Sinh vi\u00ean';
      case UserRole.lecturer:
        return '\u0110\u0103ng nh\u1eadp Gi\u1ea3ng vi\u00ean';
    }
  }

  String get loginDescription {
    switch (this) {
      case UserRole.student:
        return 'Nh\u1eadp th\u00f4ng tin t\u00e0i kho\u1ea3n \u0111\u1ec3 truy c\u1eadp c\u1ed5ng th\u00f4ng tin sinh vi\u00ean.';
      case UserRole.lecturer:
        return 'Nh\u1eadp th\u00f4ng tin t\u00e0i kho\u1ea3n \u0111\u1ec3 truy c\u1eadp c\u1ed5ng th\u00f4ng tin gi\u1ea3ng vi\u00ean.';
    }
  }

  String get profileCodeLabel {
    switch (this) {
      case UserRole.student:
        return 'MSSV';
      case UserRole.lecturer:
        return 'M\u00e3 GV';
    }
  }

  String get resetPrompt {
    switch (this) {
      case UserRole.student:
        return 'Vui l\u00f2ng nh\u1eadp m\u00e3 sinh vi\u00ean tr\u01b0\u1edbc khi \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u';
      case UserRole.lecturer:
        return 'Vui l\u00f2ng nh\u1eadp m\u00e3 gi\u1ea3ng vi\u00ean tr\u01b0\u1edbc khi \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u';
    }
  }
}
