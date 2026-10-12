import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/auth/auth_session_controller.dart';
import 'features/auth/login_screen.dart';
import 'shared/storage/auth_persistence_service.dart';
import 'features/splash/app_splash_screen.dart';
import 'features/permission_gate/permission_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const StudentAttendanceApp());
}

class StudentAttendanceApp extends StatefulWidget {
  const StudentAttendanceApp({super.key});

  @override
  State<StudentAttendanceApp> createState() => _StudentAttendanceAppState();
}

class _StudentAttendanceAppState extends State<StudentAttendanceApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  AuthSessionContext? _handledExpiry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuthSessionController.instance.addListener(_handleExpiredSession);
  }

  Future<void> _handleExpiredSession() async {
    final expired = AuthSessionController.instance.expired;
    if (expired == null || identical(expired, _handledExpiry)) return;
    _handledExpiry = expired;
    try {
      await AuthPersistenceService().clearSavedSessionKeepingContext(
        school: expired.school,
        role: expired.session.role,
        identifier: expired.session.user.code,
      );
    } catch (_) {
      // Expired credentials cannot be used even if secure storage is unavailable.
    } finally {
      if (mounted &&
          identical(AuthSessionController.instance.expired, expired)) {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => LoginScreen(
              selectedSchool: expired.school,
              selectedRole: expired.session.role,
              initialIdentifier: expired.session.user.code,
            ),
          ),
          (_) => false,
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AuthSessionController.instance.checkExpiry();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthSessionController.instance.removeListener(_handleExpiredSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Student Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: const PermissionGate(
        requireBluetooth: bool.fromEnvironment(
          'BLE_ATTENDANCE_ENABLED',
          defaultValue: true,
        ),
        child: AppSplashScreen(),
      ),
    );
  }
}
