import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _configuredFaceBaseUrl = String.fromEnvironment(
    'FACE_API_BASE_URL',
  );

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    return 'http://10.0.2.2:3000';
  }

  static String get faceBaseUrl {
    if (_configuredFaceBaseUrl.isNotEmpty) {
      return _withoutTrailingSlash(_configuredFaceBaseUrl);
    }

    return '${_withoutTrailingSlash(baseUrl)}/face-api';
  }

  static String _withoutTrailingSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }
}
