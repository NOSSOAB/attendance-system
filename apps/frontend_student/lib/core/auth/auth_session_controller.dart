import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/models/auth_session_model.dart';
import '../../shared/models/school_model.dart';

class AuthSessionContext {
  const AuthSessionContext({required this.session, required this.school});
  final AuthSessionModel session;
  final SchoolModel school;
}

/// Owns the active login independently of whichever screen initiated a request.
class AuthSessionController extends ChangeNotifier {
  static final instance = AuthSessionController();

  AuthSessionContext? active;
  AuthSessionContext? expired;
  Timer? _expiryTimer;

  void activate(AuthSessionModel session, SchoolModel school) {
    _expiryTimer?.cancel();
    active = AuthSessionContext(session: session, school: school);
    expired = null;
    final expiry = session.effectiveExpiresAt;
    final remaining =
        expiry?.difference(DateTime.now().toUtc()) ?? Duration.zero;
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => expire(session.accessToken),
    );
  }

  void checkExpiry() {
    final current = active;
    if (current != null && current.session.isExpired) {
      expire(current.session.accessToken);
    }
  }

  void expire(String token) {
    // A delayed 401 from an old login must never log out a newer session.
    if (active?.session.accessToken != token) return;
    _expiryTimer?.cancel();
    expired = active;
    active = null;
    notifyListeners();
  }

  void clear() {
    _expiryTimer?.cancel();
    active = null;
    expired = null;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
