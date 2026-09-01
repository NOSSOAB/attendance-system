import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/schools_api_service.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/models/school_model.dart';
import '../../shared/widgets/animated_graduation_badge.dart';
import '../../shared/widgets/primary_action_button.dart';
import '../role_select/role_select_screen.dart';

class SchoolSelectScreen extends StatefulWidget {
  const SchoolSelectScreen({super.key});

  @override
  State<SchoolSelectScreen> createState() => _SchoolSelectScreenState();
}

class _SchoolSelectScreenState extends State<SchoolSelectScreen> {
  static const String _appLogoAsset = 'assets/images/apps/logo_app_clean.png';
  final TextEditingController _searchController = TextEditingController();
  final SchoolsApiService _schoolsApiService = SchoolsApiService();

  List<SchoolModel> _schools = [];
  bool _isLoading = true;
  String? _errorMessage;
  SchoolModel? _selectedSchool;

  static const Color _bgColor = Color(0xFFF5F7FB);
  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _primary = Color(0xFF165DFF);
  static const Color _primarySoft = Color(0xFFEAF1FF);
  static const Color _border = Color(0xFFE6EAF2);
  static const Color _cardBorder = Color(0xFFE7EBF3);

  @override
  void initState() {
    super.initState();
    _loadSchools();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
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

  Future<void> _loadSchools() async {
    try {
      final schools = await _schoolsApiService.getSchools();

      schools.sort((a, b) {
        const priority = {'HUCE': 0, 'HUST': 1};

        final aPriority = priority[a.code.toUpperCase()] ?? 999;
        final bPriority = priority[b.code.toUpperCase()] ?? 999;

        if (aPriority != bPriority) {
          return aPriority.compareTo(bPriority);
        }

        return a.name.compareTo(b.name);
      });

      if (!mounted) return;

      setState(() {
        _schools = schools;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('LOAD SCHOOLS ERROR: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Kh\u00f4ng t\u1ea3i \u0111\u01b0\u1ee3c danh s\u00e1ch tr\u01b0\u1eddng';
        _isLoading = false;
      });
    }
  }

  List<SchoolModel> get _filteredSchools {
    final keyword = _searchController.text.trim().toLowerCase();

    if (keyword.isEmpty) return _schools;

    return _schools.where((school) {
      return school.name.toLowerCase().contains(keyword) ||
          school.code.toLowerCase().contains(keyword);
    }).toList();
  }

  Future<void> _goToLogin() async {
    final selectedSchool = _selectedSchool;
    if (selectedSchool == null) return;

    final navigator = Navigator.of(context);
    final schoolLogo = _schoolLogoAsset(selectedSchool.code);
    final precacheTasks = <Future<void>>[
      precacheImage(const AssetImage(_appLogoAsset), context),
    ];
    if (schoolLogo != null) {
      precacheTasks.add(precacheImage(AssetImage(schoolLogo), context));
    }
    await Future.wait(precacheTasks);
    if (!mounted) return;

    navigator.push(
      buildAppPageRoute(RoleSelectScreen(selectedSchool: selectedSchool)),
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

  Widget _buildSchoolLogo(SchoolModel school) {
    final assetPath = _schoolLogoAsset(school.code);

    return Container(
      width: 60,
      height: 60,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0A101828),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: assetPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _buildSchoolFallbackLogo(school),
              ),
            )
          : _buildSchoolFallbackLogo(school),
    );
  }

  Widget _buildSchoolFallbackLogo(SchoolModel school) {
    final shortCode = school.code.length >= 2
        ? school.code.substring(0, 2)
        : school.code;

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        shortCode,
        style: _font(size: 18, weight: FontWeight.w800, color: _textSecondary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schools = _filteredSchools;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
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
                            _buildTopHeader(),
                            const SizedBox(height: 24),
                            _buildSearchBox(),
                            const SizedBox(height: 24),
                            _buildSectionHeader(schools.length),
                            const SizedBox(height: 16),
                            _buildContent(schools),
                            const SizedBox(height: 20),
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

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 2, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: _font(
                        size: 26.5,
                        weight: FontWeight.w800,
                        color: const Color(0xFF121826),
                        height: 1.25,
                        letterSpacing: -0.4,
                      ),
                      children: const [
                        TextSpan(text: 'Ch\u1ecdn tr\u01b0\u1eddng\n'),
                        TextSpan(
                          text: '\u0110\u1ea1i h\u1ecdc c\u1ee7a b\u1ea1n',
                          style: TextStyle(color: _primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Vui l\u00f2ng ch\u1ecdn tr\u01b0\u1eddng \u0111\u1ec3 truy c\u1eadp c\u1ed5ng th\u00f4ng tin \u0111\u0103ng nh\u1eadp.',
                    style: _font(
                      size: 15.5,
                      weight: FontWeight.w500,
                      color: _textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 0),
          const AnimatedGraduationBadge(size: 130),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0x09101828),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: _font(
          size: 16,
          weight: FontWeight.w600,
          color: const Color(0xFF1D2939),
        ),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'T\u00ecm tr\u01b0\u1eddng...',
          hintStyle: _font(
            size: 16,
            weight: FontWeight.w500,
            color: _textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search_rounded,
              size: 28,
              color: Color(0xFF475467),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 52,
            minHeight: 52,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(int visibleCount) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Danh s\u00e1ch tr\u01b0\u1eddng',
            style: _font(
              size: 21,
              weight: FontWeight.w800,
              color: const Color(0xFF111827),
              height: 1.1,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFDDE7FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$visibleCount tr\u01b0\u1eddng',
            style: _font(size: 13.5, weight: FontWeight.w700, color: _primary),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButton() {
    final isEnabled = _selectedSchool != null;

    return PrimaryActionButton(
      label: PrimaryActionButton.continueLabel,
      onPressed: isEnabled ? _goToLogin : null,
    );
  }

  Widget _buildContent(List<SchoolModel> schools) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 42),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.8),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 42),
        child: Center(
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: _font(
              size: 15,
              weight: FontWeight.w600,
              color: Colors.red,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    if (schools.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 42),
        child: Center(
          child: Text(
            'Kh\u00f4ng c\u00f3 tr\u01b0\u1eddng n\u00e0o ph\u00f9 h\u1ee3p',
            textAlign: TextAlign.center,
            style: _font(
              size: 15,
              weight: FontWeight.w600,
              color: _textSecondary,
            ),
          ),
        ),
      );
    }

    return Column(
      children: schools
          .map(
            (school) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildSchoolCard(school),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSchoolCard(SchoolModel school) {
    final isSelected = _selectedSchool?.id == school.id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedSchool = school;
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
            _buildSchoolLogo(school),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    school.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 15.5,
                      weight: FontWeight.w700,
                      color: _textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    school.code,
                    style: _font(
                      size: 13,
                      weight: FontWeight.w600,
                      color: _textSecondary,
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
}
