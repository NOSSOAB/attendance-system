import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/auth_api_service.dart';
import '../../shared/models/auth_session_model.dart';
import '../../shared/models/school_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/storage/auth_persistence_service.dart';
import '../../shared/widgets/primary_action_button.dart';
import '../role_select/role_select_screen.dart';
import '../lecturer_home/lecturer_home_screen.dart';
import '../student_home/student_home_screen.dart';

class LoginScreen extends StatefulWidget {
  final SchoolModel selectedSchool;
  final UserRole selectedRole;
  final String? initialIdentifier;
  final bool initialRememberSession;
  final bool allowBackNavigation;
  final AuthSessionModel? initialSession;

  const LoginScreen({
    super.key,
    required this.selectedSchool,
    required this.selectedRole,
    this.initialIdentifier,
    this.initialRememberSession = false,
    this.allowBackNavigation = true,
    this.initialSession,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color _bgColor = Color(0xFFF5F7FB);
  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _primary = Color(0xFF165DFF);
  static const Color _cardBorder = Color(0xFFE7EBF3);
  static const Color _infoBg = Color(0xFFEAF1FF);
  static const Color _infoText = Color(0xFF194185);
  static const Color _successBg = Color(0xFFEAFBF2);
  static const Color _successText = Color(0xFF067647);
  static const Color _errorBg = Color(0xFFFFEAEA);
  static const Color _errorText = Color(0xFFB42318);

  final AuthApiService _authApiService = AuthApiService();
  final AuthPersistenceService _authPersistenceService =
      AuthPersistenceService();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isResettingPassword = false;
  bool _obscurePassword = true;
  bool _rememberSession = false;
  String? _errorMessage;
  String? _infoMessage;
  AuthSessionModel? _session;

  UserRole get _role => widget.selectedRole;
  bool get _isStudent => _role == UserRole.student;

  @override
  void initState() {
    super.initState();
    _identifierController.text = widget.initialIdentifier?.trim() ?? '';
    _rememberSession = widget.initialRememberSession;
    _session = widget.initialSession;
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
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

  bool _useNormalizedLoginCopy() {
    return true;
  }

  Future<void> _submit() async {
    if (_useNormalizedLoginCopy()) {
      FocusScope.of(context).unfocus();

      final identifier = _identifierController.text.trim();
      final password = _passwordController.text.replaceAll(RegExp(r'\D'), '');

      if (identifier.isEmpty) {
        setState(() {
          _errorMessage =
              'Vui l\u00f2ng nh\u1eadp ${_role.identifierLabel.toLowerCase()}';
          _infoMessage = null;
        });
        return;
      }

      if (password.length != 8) {
        setState(() {
          _errorMessage =
              'Vui l\u00f2ng nh\u1eadp \u0111\u1ee7 8 s\u1ed1 m\u1eadt kh\u1ea9u';
          _infoMessage = null;
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _infoMessage = null;
      });

      var didNavigateAway = false;

      try {
        final session = await _authApiService.login(
          role: _role,
          schoolCode: widget.selectedSchool.code,
          identifier: identifier,
          password: password,
        );

        await _authPersistenceService.saveLoginState(
          school: widget.selectedSchool,
          role: _role,
          identifier: identifier,
          rememberSession: _rememberSession,
          session: session,
        );

        if (!mounted) return;

        didNavigateAway = true;
        if (_isStudent) {
          _openStudentHome(session);
        } else {
          _openLecturerHome(session);
        }
        return;
      } catch (error) {
        if (!mounted) return;

        setState(() {
          _session = null;
          _errorMessage = _normalizeError(error);
        });
      } finally {
        if (mounted && !didNavigateAway) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }

    FocusScope.of(context).unfocus();

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.replaceAll(RegExp(r'\D'), '');

    if (identifier.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập ${_role.identifierLabel.toLowerCase()}';
        _infoMessage = null;
      });
      return;
    }

    if (password.length != 8) {
      setState(() {
        _errorMessage = 'Vui lòng nhập đủ 8 chữ số của mật khẩu';
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    var didNavigateAway = false;

    try {
      final session = await _authApiService.login(
        role: _role,
        schoolCode: widget.selectedSchool.code,
        identifier: identifier,
        password: password,
      );

      await _authPersistenceService.saveLoginState(
        school: widget.selectedSchool,
        role: _role,
        identifier: identifier,
        rememberSession: _rememberSession,
        session: session,
      );

      if (!mounted) return;

      didNavigateAway = true;
      if (_isStudent) {
        _openStudentHome(session);
      } else {
        _openLecturerHome(session);
      }
      return;
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _session = null;
        _errorMessage = _normalizeError(error);
      });
    } finally {
      if (mounted && !didNavigateAway) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    FocusScope.of(context).unfocus();

    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() {
        _errorMessage = _role.resetPrompt;
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _isResettingPassword = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final message = await _authApiService.forgotPassword(
        role: _role,
        schoolCode: widget.selectedSchool.code,
        identifier: identifier,
      );

      if (!mounted) return;

      setState(() {
        _session = null;
        _passwordController.clear();
        _infoMessage = message;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _normalizeError(error);
        _infoMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResettingPassword = false;
        });
      }
    }
  }

  String _normalizeError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
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

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '--/--/----';
    }

    final localValue = value.toLocal();
    final day = '${localValue.day}'.padLeft(2, '0');
    final month = '${localValue.month}'.padLeft(2, '0');
    final year = '${localValue.year}';
    return '$day/$month/$year';
  }

  void _openStudentHome(AuthSessionModel session) {
    Navigator.of(context).pushAndRemoveUntil(
      buildAppPageRoute(
        StudentHomeScreen(
          session: session,
          selectedSchool: widget.selectedSchool,
        ),
      ),
      (route) => false,
    );
  }

  void _openLecturerHome(AuthSessionModel session) {
    Navigator.of(context).pushAndRemoveUntil(
      buildAppPageRoute(
        LecturerHomeScreen(
          session: session,
          selectedSchool: widget.selectedSchool,
        ),
      ),
      (route) => false,
    );
  }

  void _handleBackNavigation() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      buildAppPageRoute(
        RoleSelectScreen(selectedSchool: widget.selectedSchool),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || !widget.allowBackNavigation) {
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTopBar(),
                              const SizedBox(height: 14),
                              _buildHeader(),
                              const SizedBox(height: 22),
                              _buildSchoolCard(),
                              const SizedBox(height: 18),
                              _buildLoginForm(),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 14),
                                _buildMessageCard(
                                  message: _errorMessage!,
                                  backgroundColor: _errorBg,
                                  iconColor: _errorText,
                                  textColor: _errorText,
                                  icon: Icons.error_outline_rounded,
                                ),
                              ],
                              if (_infoMessage != null) ...[
                                const SizedBox(height: 14),
                                _buildMessageCard(
                                  message: _infoMessage!,
                                  backgroundColor: _infoBg,
                                  iconColor: _primary,
                                  textColor: _infoText,
                                  icon: Icons.lock_reset_rounded,
                                ),
                              ],
                              if (_session != null) ...[
                                const SizedBox(height: 14),
                                _buildSuccessCard(),
                              ],
                              const SizedBox(height: 24),
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
      ),
    );
  }

  Widget _buildTopBar() {
    if (!widget.allowBackNavigation) {
      return const SizedBox(height: 40);
    }

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

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _role.iconBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_role.icon, size: 16, color: _role.iconColor),
              const SizedBox(width: 8),
              Text(
                _role.title,
                style: _font(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: _role.iconColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _role.loginHeading,
          style: _font(
            size: 28,
            weight: FontWeight.w800,
            color: _primary,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _role.loginDescription,
          style: _font(
            size: 15,
            weight: FontWeight.w500,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolCard() {
    final logoAsset = _schoolLogoAsset(widget.selectedSchool.code);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09101828),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _cardBorder),
            ),
            child: logoAsset == null
                ? Center(
                    child: Text(
                      widget.selectedSchool.code,
                      textAlign: TextAlign.center,
                      style: _font(
                        size: 15,
                        weight: FontWeight.w800,
                        color: _textSecondary,
                      ),
                    ),
                  )
                : Image.asset(logoAsset, fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.selectedSchool.name,
                  style: _font(
                    size: 16,
                    weight: FontWeight.w700,
                    color: _textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.selectedSchool.code,
                  style: _font(
                    size: 13,
                    weight: FontWeight.w600,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    if (_useNormalizedLoginCopy()) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _cardBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x09101828),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel(_role.identifierLabel),
            const SizedBox(height: 10),
            _buildInput(
              controller: _identifierController,
              hintText: _role.identifierPlaceholder,
              prefixIcon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
              keyboardType: _isStudent
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: _isStudent
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
            ),
            const SizedBox(height: 18),
            _buildFieldLabel('M\u1eadt kh\u1ea9u'),
            const SizedBox(height: 10),
            _buildInput(
              controller: _passwordController,
              hintText: 'Nh\u1eadp m\u1eadt kh\u1ea9u',
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                splashRadius: 20,
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _textSecondary,
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            _buildCompactRememberSessionTile(),
            if (_isStudent) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_isLoading || _isResettingPassword)
                      ? null
                      : _forgotPassword,
                  style: TextButton.styleFrom(
                    foregroundColor: _primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Qu\u00ean m\u1eadt kh\u1ea9u?',
                    style: _font(
                      size: 13,
                      weight: FontWeight.w700,
                      color: _primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09101828),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(_role.identifierLabel),
          const SizedBox(height: 10),
          _buildInput(
            controller: _identifierController,
            hintText: _role.identifierPlaceholder,
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            keyboardType: _isStudent
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: _isStudent
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
          ),
          const SizedBox(height: 18),
          _buildFieldLabel('Mật khẩu'),
          const SizedBox(height: 10),
          _buildInput(
            controller: _passwordController,
            hintText: 'Nhập mật khẩu',
            prefixIcon: Icons.lock_outline_rounded,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.number,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
              splashRadius: 20,
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _textSecondary,
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          _buildCompactRememberSessionTile(),
          if (_isStudent) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (_isLoading || _isResettingPassword)
                    ? null
                    : _forgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: _primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Quên mật khẩu?',
                  style: _font(
                    size: 13,
                    weight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildRememberSessionTile() {
    if (_useNormalizedLoginCopy()) {
      final isDisabled = _isLoading || _isResettingPassword;

      return InkWell(
        onTap: isDisabled
            ? null
            : () {
                setState(() {
                  _rememberSession = !_rememberSession;
                });
              },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _rememberSession ? _primary : Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: _rememberSession
                        ? _primary
                        : const Color(0xFFCBD5E1),
                    width: 1.4,
                  ),
                ),
                child: _rememberSession
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'L\u01b0u phi\u00ean \u0111\u0103ng nh\u1eadp',
                        style: _font(
                          size: 14,
                          weight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDisabled = _isLoading || _isResettingPassword;

    return InkWell(
      onTap: isDisabled
          ? null
          : () {
              setState(() {
                _rememberSession = !_rememberSession;
              });
            },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _rememberSession ? _primary : Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _rememberSession ? _primary : const Color(0xFFCBD5E1),
                  width: 1.4,
                ),
              ),
              child: _rememberSession
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lưu phiên đăng nhập',
                      style: _font(
                        size: 14,
                        weight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactRememberSessionTile() {
    if (_useNormalizedLoginCopy()) {
      final isDisabled = _isLoading || _isResettingPassword;

      return InkWell(
        onTap: isDisabled
            ? null
            : () {
                setState(() {
                  _rememberSession = !_rememberSession;
                });
              },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _rememberSession ? _primary : Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: _rememberSession
                        ? _primary
                        : const Color(0xFFCBD5E1),
                    width: 1.4,
                  ),
                ),
                child: _rememberSession
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'L\u01b0u phi\u00ean \u0111\u0103ng nh\u1eadp',
                  style: _font(
                    size: 14,
                    weight: FontWeight.w700,
                    color: isDisabled ? _textSecondary : _textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDisabled = _isLoading || _isResettingPassword;

    return InkWell(
      onTap: isDisabled
          ? null
          : () {
              setState(() {
                _rememberSession = !_rememberSession;
              });
            },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _rememberSession ? _primary : Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _rememberSession ? _primary : const Color(0xFFCBD5E1),
                  width: 1.4,
                ),
              ),
              child: _rememberSession
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Lưu phiên đăng nhập',
                style: _font(
                  size: 14,
                  weight: FontWeight.w700,
                  color: isDisabled ? _textSecondary : _textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: _font(size: 14, weight: FontWeight.w700, color: _textPrimary),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    required TextInputAction textInputAction,
    required TextInputType keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    bool obscureText = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        enableSuggestions: !obscureText,
        autocorrect: !obscureText,
        textInputAction: textInputAction,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: _font(size: 15.5, weight: FontWeight.w600, color: _textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: _font(
            size: 15,
            weight: FontWeight.w500,
            color: const Color(0xFF98A2B3),
          ),
          border: InputBorder.none,
          prefixIcon: Icon(prefixIcon, color: _textSecondary),
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }

  Widget _buildMessageCard({
    required String message,
    required Color backgroundColor,
    required Color iconColor,
    required Color textColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: _font(
                size: 13,
                weight: FontWeight.w600,
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    if (_useNormalizedLoginCopy()) {
      final user = _session!.user;

      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _successBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFA6F4C5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: _successText,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _session!.message,
                        style: _font(
                          size: 16,
                          weight: FontWeight.w800,
                          color: _successText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.fullName,
                        style: _font(
                          size: 14,
                          weight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProfileRow(_role.profileCodeLabel, user.code),
            if (user.faculty != null && user.faculty!.trim().isNotEmpty)
              _buildProfileRow('Khoa', user.faculty!),
            if (user.className != null && user.className!.trim().isNotEmpty)
              _buildProfileRow('L\u1edbp', user.className!),
            _buildProfileRow('Ng\u00e0y sinh', _formatDate(user.dateOfBirth)),
            if (user.email != null && user.email!.trim().isNotEmpty)
              _buildProfileRow('Email', user.email!),
          ],
        ),
      );
    }

    final user = _session!.user;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _successBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFA6F4C5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: _successText,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _session!.message,
                      style: _font(
                        size: 16,
                        weight: FontWeight.w800,
                        color: _successText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.fullName,
                      style: _font(
                        size: 14,
                        weight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProfileRow(_role.profileCodeLabel, user.code),
          if (user.faculty != null && user.faculty!.trim().isNotEmpty)
            _buildProfileRow('Khoa', user.faculty!),
          if (user.className != null && user.className!.trim().isNotEmpty)
            _buildProfileRow('Lớp', user.className!),
          _buildProfileRow('Ngày sinh', _formatDate(user.dateOfBirth)),
          if (user.email != null && user.email!.trim().isNotEmpty)
            _buildProfileRow('Email', user.email!),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: _font(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFF344054),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: _font(
                size: 13,
                weight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    if (_useNormalizedLoginCopy()) {
      return PrimaryActionButton(
        label: (_isLoading || _isResettingPassword)
            ? (_isResettingPassword
                  ? '\u0110ang \u0111\u1eb7t l\u1ea1i...'
                  : '\u0110ang x\u00e1c th\u1ef1c...')
            : (_session == null
                  ? '\u0110\u0103ng nh\u1eadp'
                  : '\u0110\u0103ng nh\u1eadp l\u1ea1i'),
        onPressed: (_isLoading || _isResettingPassword) ? null : _submit,
      );
    }

    return PrimaryActionButton(
      label: (_isLoading || _isResettingPassword)
          ? (_isResettingPassword ? 'Đang đặt lại...' : 'Đang xác thực...')
          : (_session == null ? 'Đăng nhập' : 'Đăng nhập lại'),
      onPressed: (_isLoading || _isResettingPassword) ? null : _submit,
    );
  }
}
