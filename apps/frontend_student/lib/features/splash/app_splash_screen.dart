import 'package:flutter/material.dart';

import '../../shared/models/user_role.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/storage/auth_persistence_service.dart';
import '../auth/login_screen.dart';
import '../lecturer_home/lecturer_home_screen.dart';
import '../school_select/school_select_screen.dart';
import '../student_home/student_home_screen.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = 'assets/images/apps/logo_app_clean.png';
  static const _schoolAssets = [
    'assets/images/schools/huce.png',
    'assets/images/schools/hust.png',
  ];

  final AuthPersistenceService _authPersistenceService =
      AuthPersistenceService();
  late final AnimationController _controller;
  bool _didNavigate = false;
  bool _isResolvingLaunchTarget = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 980),
          )
          ..addListener(_handleTimeline)
          ..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage(_logoAsset), context);
      for (final asset in _schoolAssets) {
        precacheImage(AssetImage(asset), context);
      }
    });
  }

  void _handleTimeline() {
    if (_didNavigate || _isResolvingLaunchTarget || !mounted) return;
    if (_controller.value < 0.58) return;

    _isResolvingLaunchTarget = true;
    _openInitialScreen();
  }

  Future<void> _openInitialScreen() async {
    final destination = await _resolveInitialScreen();
    if (!mounted || _didNavigate) return;

    _didNavigate = true;
    Navigator.of(context).pushReplacement(buildAppPageRoute(destination));
  }

  Future<Widget> _resolveInitialScreen() async {
    final state = await _authPersistenceService.readState();
    if (state == null) {
      return const SchoolSelectScreen();
    }

    if (state.hasSavedSession) {
      if (state.role == UserRole.student) {
        return StudentHomeScreen(
          session: state.session!,
          selectedSchool: state.school,
        );
      }

      return LecturerHomeScreen(
        session: state.session!,
        selectedSchool: state.school,
      );
    }

    return LoginScreen(
      selectedSchool: state.school,
      selectedRole: state.role,
      initialIdentifier: state.identifier,
      initialRememberSession: state.rememberSession,
      allowBackNavigation: true,
      initialSession: state.hasSavedSession ? state.session : null,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.92,
          end: 1.02,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 62,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.02,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 38,
      ),
    ]).animate(_controller);
    final opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.46,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 56,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 44,
      ),
    ]).animate(_controller);
    final glow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.94,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 58,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1.16,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 42,
      ),
    ]).animate(_controller);
    final lift = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 52),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -18,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 48,
      ),
    ]).animate(_controller);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: opacity.value,
              child: Transform.translate(
                offset: Offset(0, lift.value),
                child: Transform.scale(
                  scale: scale.value,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: glow.value,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Color(0x1A21D4C7),
                                Color(0x122B95F2),
                                Color(0x00165DFF),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        height: 170,
                        child: Image.asset(_logoAsset, fit: BoxFit.contain),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
