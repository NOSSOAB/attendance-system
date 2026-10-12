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
      return _validatedUrl(_configuredBaseUrl);
    }

    if (kDebugMode) {
      return kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';
    }
    throw StateError('Thiếu API_BASE_URL cho bản cài trên điện thoại');
  }

  static String get faceBaseUrl {
    if (_configuredFaceBaseUrl.isNotEmpty) {
      return _validatedUrl(_configuredFaceBaseUrl);
    }

    return '${_withoutTrailingSlash(baseUrl)}/face-api';
  }

  static String _withoutTrailingSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static String _validatedUrl(String value) {
    final url = _withoutTrailingSlash(value.trim());
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (!kDebugMode && uri.scheme != 'https') ||
        (kDebugMode && uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('Địa chỉ API không hợp lệ');
    }
    return url;
  }
}
