import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/navigation/app_page_route.dart';
import '../../shared/models/school_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/widgets/primary_action_button.dart';
import '../auth/login_screen.dart';
import '../school_select/school_select_screen.dart';

enum _OrbitNodeType { app, school, student, lecturer }

class RoleSelectScreen extends StatefulWidget {
  final SchoolModel selectedSchool;

  const RoleSelectScreen({super.key, required this.selectedSchool});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen>
    with SingleTickerProviderStateMixin {
  static const String _appLogoAsset = 'assets/images/apps/logo_app_clean.png';
  static const Color _bgColor = Color(0xFFF5F7FB);
  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _primary = Color(0xFF165DFF);
  static const Color _primarySoft = Color(0xFFEAF1FF);
  static const Color _cardBorder = Color(0xFFE7EBF3);

  UserRole? _selectedRole;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16000),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage(_appLogoAsset), context);
      final schoolLogo = _schoolLogoAsset(widget.selectedSchool.code);
      if (schoolLogo != null) {
        precacheImage(AssetImage(schoolLogo), context);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextStyle _font({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = _textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.beVietnamPro(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  void _goNext() {
    if (_selectedRole == null) return;

    Navigator.of(context).push(
      buildAppPageRoute(
        LoginScreen(
          selectedSchool: widget.selectedSchool,
          selectedRole: _selectedRole!,
        ),
      ),
    );
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    navigator.pushAndRemoveUntil(
      buildAppPageRoute(const SchoolSelectScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            _buildTopBar(),
                            const SizedBox(height: 8),
                            _buildAnimatedHeader(),
                            const SizedBox(height: 18),
                            _buildTitleBlock(),
                            const SizedBox(height: 24),
                            _buildRoleCard(UserRole.student),
                            const SizedBox(height: 16),
                            _buildRoleCard(UserRole.lecturer),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildBottomButton(),
                    SizedBox(height: bottomPadding > 0 ? 8 : 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _handleBackNavigation,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: Color(0xFF344054),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width - 48;
        final items = [
          _OrbitNodeType.app,
          _OrbitNodeType.school,
          _OrbitNodeType.student,
          _OrbitNodeType.lecturer,
        ];

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final orbitAngle = _controller.value * 2 * math.pi;
            final centerX = width / 2;
            const centerY = 86.0;
            final orbitRadius = math.min(width * 0.23, 62.0);
            const baseNodeSize = 52.0;
            final orbitWidgets = <({double scale, Widget widget})>[];
            var strongestFocus = 0.0;
            final twinkleConfigs =
                <({Offset offset, double size, double phase, Color color})>[
                  (
                    offset: const Offset(-62, -40),
                    size: 13,
                    phase: 0.0,
                    color: const Color(0xFFF3C64F),
                  ),
                  (
                    offset: const Offset(58, -32),
                    size: 11,
                    phase: 1.3,
                    color: const Color(0xFF7CC8FF),
                  ),
                  (
                    offset: const Offset(-52, 44),
                    size: 10,
                    phase: 2.1,
                    color: const Color(0xFF7ED9CC),
                  ),
                  (
                    offset: const Offset(66, 38),
                    size: 12,
                    phase: 2.9,
                    color: const Color(0xFFF3C64F),
                  ),
                ];

            for (var i = 0; i < items.length; i++) {
              final wrappedPhase = _wrapSigned(
                _controller.value - (i / items.length),
              );
              final focusWindow = (1 - (wrappedPhase.abs() / 0.11)).clamp(
                0.0,
                1.0,
              );
              final focus = Curves.easeInOutSine.transform(focusWindow);
              final angle =
                  -math.pi / 2 +
                  orbitAngle +
                  (i * (2 * math.pi / items.length));
              final microAngle = (orbitAngle * 1.15) + (i * 0.75);
              final radius = _lerpDouble(orbitRadius, 10.0, focus);
              final microRadius = focus * 2.2;
              final scale = _lerpDouble(0.98, 1.16, focus);
              strongestFocus = math.max(strongestFocus, focus);

              final nodeSize = baseNodeSize * scale;
              final dx =
                  centerX +
                  (math.cos(angle) * radius) +
                  (math.cos(microAngle) * microRadius) -
                  (nodeSize / 2);
              final dy =
                  centerY +
                  (math.sin(angle) * radius) +
                  (math.sin(microAngle) * microRadius * 0.45) -
                  (focus * 1.6) -
                  (nodeSize / 2);

              orbitWidgets.add((
                scale: scale,
                widget: Positioned(
                  left: dx,
                  top: dy,
                  child: Opacity(
                    opacity: 0.88 + (focus * 0.12),
                    child: _buildOrbitNode(
                      items[i],
                      size: nodeSize,
                      isActive: focus > 0.55,
                    ),
                  ),
                ),
              ));
            }

            orbitWidgets.sort((a, b) => a.scale.compareTo(b.scale));
            final centerGlowScale =
                0.98 +
                (strongestFocus * 0.12) +
                (math.sin(orbitAngle * 1.6) * 0.01 * strongestFocus);

            return SizedBox(
              width: width,
              height: 184,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ...twinkleConfigs.map((sparkle) {
                    final twinkle =
                        0.5 +
                        (math.sin((orbitAngle * 2.2) + sparkle.phase) * 0.5);
                    final shimmer = 0.78 + (twinkle * 0.46);
                    final center = Offset(centerX, centerY) + sparkle.offset;
                    return Positioned(
                      left: center.dx - (sparkle.size / 2),
                      top: center.dy - (sparkle.size / 2),
                      child: Opacity(
                        opacity: 0.18 + (twinkle * 0.50),
                        child: _buildTwinkleStar(
                          size: sparkle.size,
                          color: sparkle.color,
                          scale: shimmer,
                        ),
                      ),
                    );
                  }),
                  Positioned(
                    left: centerX - 46,
                    top: centerY - 46,
                    child: Transform.scale(
                      scale: centerGlowScale,
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x22165DFF),
                              Color(0x12165DFF),
                              Color(0x00165DFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...orbitWidgets.map((entry) => entry.widget),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOrbitNode(
    _OrbitNodeType type, {
    required double size,
    required bool isActive,
  }) {
    switch (type) {
      case _OrbitNodeType.app:
        return _buildAppOrbitNode(size, isActive);
      case _OrbitNodeType.school:
        return _buildSchoolOrbitNode(size, isActive);
      case _OrbitNodeType.student:
        return _buildRoleOrbitNode(UserRole.student, size, isActive);
      case _OrbitNodeType.lecturer:
        return _buildRoleOrbitNode(UserRole.lecturer, size, isActive);
    }
  }

  Widget _buildAppOrbitNode(double size, bool isActive) {
    return _buildOrbitShell(
      size: size,
      isActive: isActive,
      child: Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          _appLogoAsset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5FF),
              borderRadius: BorderRadius.circular(size * 0.24),
            ),
            child: Center(
              child: Icon(
                Icons.verified_user_rounded,
                size: size * 0.36,
                color: _primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolOrbitNode(double size, bool isActive) {
    final assetPath = _schoolLogoAsset(widget.selectedSchool.code);
    final shortCode = widget.selectedSchool.code.length >= 2
        ? widget.selectedSchool.code.substring(0, 2)
        : widget.selectedSchool.code;

    return _buildOrbitShell(
      size: size,
      isActive: isActive,
      child: assetPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.24),
              child: Padding(
                padding: EdgeInsets.all(size * 0.12),
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildOrbitSchoolFallback(shortCode, size),
                ),
              ),
            )
          : _buildOrbitSchoolFallback(shortCode, size),
    );
  }

  Widget _buildOrbitSchoolFallback(String shortCode, double size) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FC),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Center(
        child: Text(
          shortCode,
          style: _font(
            size: size * 0.28,
            weight: FontWeight.w800,
            color: _textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOrbitNode(UserRole role, double size, bool isActive) {
    return _buildOrbitShell(
      size: size,
      isActive: isActive,
      child: Container(
        decoration: BoxDecoration(
          color: role.iconBg,
          borderRadius: BorderRadius.circular(size * 0.26),
        ),
        child: Center(
          child: Icon(role.icon, size: size * 0.42, color: role.iconColor),
        ),
      ),
    );
  }

  Widget _buildOrbitShell({
    required double size,
    required bool isActive,
    required Widget child,
  }) {
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.30),
          border: Border.all(
            color: isActive ? const Color(0xFFBED3FF) : const Color(0xFFE4EBF7),
            width: isActive ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? const Color(0x18165DFF)
                  : const Color(0x12101828),
              blurRadius: isActive ? 20 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildTwinkleStar({
    required double size,
    required Color color,
    required double scale,
  }) {
    final barThickness = math.max(1.8, size * 0.14);
    final shortBar = size * 0.58;

    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: barThickness,
              height: size,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(90),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
            Container(
              width: size,
              height: barThickness,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: barThickness,
                height: shortBar,
                decoration: BoxDecoration(
                  color: color.withAlpha(220),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: shortBar,
                height: barThickness,
                decoration: BoxDecoration(
                  color: color.withAlpha(220),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _schoolLogoAsset(String code) {
    switch (code.toUpperCase()) {
      case 'HUCE':
        return 'assets/images/schools/huce.png';
      case 'HUST':
        return 'assets/images/schools/hust.png';
      default:
        return null;
    }
  }

  double _wrapSigned(double value) {
    var wrapped = (value % 1.0 + 1.0) % 1.0;
    if (wrapped > 0.5) {
      wrapped -= 1.0;
    }
    return wrapped;
  }

  double _lerpDouble(double begin, double end, double t) {
    return begin + ((end - begin) * t);
  }

  Widget _buildTitleBlock() {
    return Column(
      children: [
        Text(
          'Ch\u00e0o m\u1eebng b\u1ea1n \u0111\u1ebfn v\u1edbi',
          textAlign: TextAlign.center,
          style: _font(
            size: 16,
            weight: FontWeight.w500,
            color: _textSecondary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.selectedSchool.name,
          textAlign: TextAlign.center,
          style: _font(
            size: 20,
            weight: FontWeight.w800,
            color: _primary,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ch\u1ecdn vai tr\u00f2 \u0111\u1ec3 ti\u1ebfp t\u1ee5c \u0111\u0103ng nh\u1eadp',
          textAlign: TextAlign.center,
          style: _font(
            size: 12,
            weight: FontWeight.w500,
            color: const Color(0xFF98A2B3),
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard(UserRole role) {
    final isSelected = _selectedRole == role;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? _primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? _primary : _cardBorder,
            width: isSelected ? 1.8 : 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0x0F101828)
                  : const Color(0x09101828),
              blurRadius: isSelected ? 18 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: role.iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(role.icon, size: 23, color: role.iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.title,
                    style: _font(
                      size: 18,
                      weight: FontWeight.w700,
                      color: _textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    role.subtitle,
                    style: _font(
                      size: 12,
                      weight: FontWeight.w500,
                      color: _textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isSelected
                  ? Container(
                      key: const ValueKey('selected'),
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: _primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    )
                  : Container(
                      key: const ValueKey('unselected'),
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: _textSecondary,
                        size: 22,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return PrimaryActionButton(
      label: PrimaryActionButton.continueLabel,
      onPressed: _selectedRole == null ? null : _goNext,
    );
  }
}
