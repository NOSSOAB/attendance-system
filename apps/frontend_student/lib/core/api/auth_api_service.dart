import 'dart:convert';

import '../../shared/models/auth_session_model.dart';
import '../../shared/models/user_role.dart';
import '../config/api_config.dart';
import 'app_http_client.dart';

class AuthApiService {
  Future<AuthSessionModel> login({
    required UserRole role,
    required String schoolCode,
    required String identifier,
    required String password,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/login');
    final payload = await _post(
      uri,
      body: {
        'schoolCode': schoolCode,
        'role': role.apiValue,
        'identifier': identifier,
        'password': password,
      },
    );

    return AuthSessionModel.fromJson(payload);
  }

  Future<String> forgotPassword({
    required UserRole role,
    required String schoolCode,
    required String identifier,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/forgot-password');
    final payload = await _post(
      uri,
      body: {
        'schoolCode': schoolCode,
        'role': role.apiValue,
        'identifier': identifier,
      },
    );

    final message = payload['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    throw Exception(
      'Kh\u00f4ng nh\u1eadn \u0111\u01b0\u1ee3c th\u00f4ng b\u00e1o \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u',
    );
  }

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    required Map<String, Object> body,
  }) async {
    final response = await AppHttpClient.shared.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final payload = response.body.isEmpty
        ? null
        : jsonDecode(response.body) as Object?;

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_resolveErrorMessage(payload, response.statusCode));
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception(
        'Ph\u1ea3n h\u1ed3i t\u1eeb m\u00e1y ch\u1ee7 kh\u00f4ng h\u1ee3p l\u1ec7',
      );
    }

    return payload;
  }

  String _resolveErrorMessage(Object? payload, int statusCode) {
    if (payload is Map<String, dynamic>) {
      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) {
          return first;
        }
      }
    }

    return 'Y\u00eau c\u1ea7u th\u1ea5t b\u1ea1i (m\u00e3 $statusCode)';
  }
}
