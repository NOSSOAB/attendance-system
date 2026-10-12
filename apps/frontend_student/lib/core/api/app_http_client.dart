import 'package:http/http.dart' as http;

import '../auth/auth_session_controller.dart';

class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
}

/// One timeout and expired-login policy for every API. Mutations are never
/// retried automatically because a timeout does not prove the server rolled back.
class AppHttpClient extends http.BaseClient {
  static final shared = AppHttpClient();
  final http.Client _inner;
  final AuthSessionController _sessions;
  final Duration timeout;

  AppHttpClient({
    http.Client? inner,
    AuthSessionController? sessions,
    this.timeout = const Duration(seconds: 30),
  }) : _inner = inner ?? http.Client(),
       _sessions = sessions ?? AuthSessionController.instance;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authorization =
        request.headers['Authorization'] ?? request.headers['authorization'];
    final token = authorization != null && authorization.startsWith('Bearer ')
        ? authorization.substring(7)
        : null;
    if (token != null &&
        _sessions.active?.session.accessToken == token &&
        _sessions.active!.session.isExpired) {
      _sessions.expire(token);
      throw const SessionExpiredException();
    }
    final response = await _inner.send(request).timeout(timeout);
    if (response.statusCode == 401 && token != null) {
      _sessions.expire(token);
      await response.stream.listen((_) {}).cancel();
      throw const SessionExpiredException();
    }
    return http.StreamedResponse(
      response.stream.timeout(timeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
