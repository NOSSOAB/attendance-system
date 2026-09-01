import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/lecturer_api_service.dart';
import '../../shared/models/auth_session_model.dart';
import '../../shared/models/school_model.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/storage/auth_persistence_service.dart';
import '../auth/login_screen.dart';

class LecturerHomeScreen extends StatefulWidget {
  final AuthSessionModel session;
  final SchoolModel selectedSchool;

  const LecturerHomeScreen({
    super.key,
    required this.session,
    required this.selectedSchool,
  });

  @override
  State<LecturerHomeScreen> createState() => _LecturerHomeScreenState();
}

class _LecturerHomeScreenState extends State<LecturerHomeScreen> {
  static const Color _white = Colors.white;
  static const Color _pageBg = Color(0xFFF4F6FA);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _textPrimary = Color(0xFF17212F);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _border = Color(0xFFE4E7EC);
  static const Color _primary = Color(0xFF0057D9);
  static const Color _primarySoft = Color(0xFFEAF2FF);
  static const Color _warning = Color(0xFFF79009);
  static const Color _warningSoft = Color(0xFFFFF4DB);
  static const Color _success = Color(0xFF12B76A);
  static const Color _successSoft = Color(0xFFEAFBF3);
  static const Color _danger = Color(0xFFF04438);
  static const Color _dangerSoft = Color(0xFFFFEEED);

  late final LecturerApiService _lecturerApiService;
  final AuthPersistenceService _authPersistenceService =
      AuthPersistenceService();
  final TextEditingController _historyKeywordController =
      TextEditingController();

  bool _isLoading = true;
  bool _isActionLoading = false;
  String? _errorMessage;
  int _selectedPageIndex = 0;
  int? _selectedScheduleId;
  int? _historyScheduleId;
  int? _statisticsScheduleId;
  DateTime? _historyAttendanceDate;

  Map<String, dynamic>? _homeData;
  Map<String, dynamic>? _classData;
  Map<String, dynamic>? _classDetail;
  Map<String, dynamic>? _historyData;
  Map<String, dynamic>? _statisticsData;
  Map<String, dynamic>? _notificationData;
  Map<String, dynamic>? _profileData;

  final Map<int, _AttendanceDraft> _attendanceDrafts = {};

  String get _lecturerCode => widget.session.user.code;

  @override
  void initState() {
    super.initState();
    _lecturerApiService = LecturerApiService(
      accessToken: widget.session.accessToken,
    );
    _loadDashboard();
  }

  @override
  void dispose() {
    _historyKeywordController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait<Map<String, dynamic>>([
        _lecturerApiService.getHome(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
        ),
        _lecturerApiService.getClasses(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
        ),
        _lecturerApiService.getHistory(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
          scheduleId: _historyScheduleId,
          courseKeyword: _historyKeywordController.text.trim(),
          attendanceDate: _historyAttendanceDate,
        ),
        _lecturerApiService.getStatistics(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
          scheduleId: _statisticsScheduleId,
        ),
        _lecturerApiService.getNotifications(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
        ),
        _lecturerApiService.getProfile(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
        ),
      ]);

      final classData = results[1];
      final classes = _listMap(classData['classes']);
      final nextScheduleId =
          classes.any(
            (item) => _intValue(item['scheduleId']) == _selectedScheduleId,
          )
          ? _selectedScheduleId
          : (classes.isEmpty ? null : _intValue(classes.first['scheduleId']));

      Map<String, dynamic>? classDetail;
      if (nextScheduleId != null && nextScheduleId > 0) {
        classDetail = await _lecturerApiService.getClassDetail(
          schoolCode: widget.selectedSchool.code,
          lecturerCode: _lecturerCode,
          scheduleId: nextScheduleId,
        );
      }

      if (!mounted) return;

      setState(() {
        _homeData = results[0];
        _classData = classData;
        _historyData = results[2];
        _statisticsData = results[3];
        _notificationData = results[4];
        _profileData = results[5];
        _selectedScheduleId = nextScheduleId;
        _classDetail = classDetail;
        _attendanceDrafts.clear();
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadClassDetail(int scheduleId) async {
    setState(() {
      _isActionLoading = true;
      _selectedScheduleId = scheduleId;
    });

    try {
      final payload = await _lecturerApiService.getClassDetail(
        schoolCode: widget.selectedSchool.code,
        lecturerCode: _lecturerCode,
        scheduleId: scheduleId,
      );

      if (!mounted) return;

      setState(() {
        _classDetail = payload;
        _attendanceDrafts.clear();
      });
    } catch (error) {
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await _authPersistenceService.clearSavedSessionKeepingContext(
      school: widget.selectedSchool,
      role: widget.session.role,
      identifier: _lecturerCode,
    );

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      buildAppPageRoute(
        LoginScreen(
          selectedSchool: widget.selectedSchool,
          selectedRole: widget.session.role,
          initialIdentifier: _lecturerCode,
          initialRememberSession: false,
          allowBackNavigation: true,
        ),
      ),
      (route) => false,
    );
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

  void _selectPage(int index) {
    if (_selectedPageIndex == index) {
      return;
    }

    setState(() {
      _selectedPageIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  _buildTopHeader(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _loadDashboard(showLoader: false),
                      child: Container(
                        color: _pageBg,
                        child: ListView(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                          children: [
                            if (_errorMessage != null && !_isLoading)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildErrorBanner(_errorMessage!),
                              ),
                            if (_isLoading && _homeData == null)
                              _buildLoadingCard()
                            else
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: KeyedSubtree(
                                  key: ValueKey(_selectedPageIndex),
                                  child: _buildCurrentPage(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildBottomNavigation(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _pageTitle {
    switch (_selectedPageIndex) {
      case 1:
        return 'Lớp học phần';
      case 2:
        return 'Lịch sử điểm danh';
      case 3:
        return 'Thống kê chuyên cần';
      case 4:
        return 'Thông báo';
      case 5:
        return 'Thông tin cá nhân';
      default:
        return 'Trang chủ Giảng viên';
    }
  }

  String get _pageSubtitle {
    final homeSummary = _mapValue(_homeData, 'summary');
    final classSummary = _mapValue(_classData, 'summary');
    final statisticSummary = _mapValue(_statisticsData, 'summary');
    final lecturer = _mapValue(_profileData, 'lecturer');
    final unreadCount = _unreadNotificationCount;

    switch (_selectedPageIndex) {
      case 1:
        final totalClasses = _intValue(classSummary['totalClasses']);
        final openSessions = _intValue(classSummary['openSessions']);
        return totalClasses > 0
            ? '$totalClasses lớp phụ trách • $openSessions phiên đang mở'
            : 'Quản lý các lớp học phần đang được phân công';
      case 2:
        final totalHistory = _intValue(homeSummary['totalAttendanceHistory']);
        return totalHistory > 0
            ? '$totalHistory buổi đã lưu điểm danh'
            : 'Xem lại các buổi điểm danh đã hoàn tất';
      case 3:
        final totalSessions = _intValue(statisticSummary['totalSessions']);
        return totalSessions > 0
            ? '$totalSessions buổi đã được tổng hợp chuyên cần'
            : 'Theo dõi chuyên cần theo lớp và sinh viên';
      case 4:
        return unreadCount > 0
            ? '$unreadCount thông báo chưa đọc'
            : 'Cập nhật mới nhất dành cho giảng viên';
      case 5:
        return '${_stringValue(lecturer['lecturerCode'], fallback: _lecturerCode)} • ${widget.selectedSchool.name}';
      default:
        final openSessions = _intValue(homeSummary['openSessions']);
        if (openSessions > 0) {
          return '$openSessions phiên điểm danh đang mở';
        }
        if (unreadCount > 0) {
          return '$unreadCount thông báo cần xem';
        }
        return 'Hôm nay chưa có việc cần xử lý gấp';
    }
  }

  int get _unreadNotificationCount {
    final homeSummary = _mapValue(_homeData, 'summary');
    final homeUnread = _intValue(homeSummary['unreadNotifications']);
    final notificationUnread = _intValue(_notificationData?['unreadCount']);
    return notificationUnread > 0 ? notificationUnread : homeUnread;
  }

  IconData get _pageHeaderIcon {
    switch (_selectedPageIndex) {
      case 1:
        return Icons.class_rounded;
      case 2:
        return Icons.history_rounded;
      case 3:
        return Icons.bar_chart_rounded;
      case 4:
        return Icons.notifications_active_rounded;
      case 5:
        return Icons.person_rounded;
      default:
        return Icons.space_dashboard_rounded;
    }
  }

  Widget _buildTopHeader() {
    if (_selectedPageIndex == 0) {
      final lecturer = _mapValue(_homeData, 'lecturer');
      final summary = _mapValue(_homeData, 'summary');
      final fullName = _stringValue(
        lecturer['fullName'],
        fallback: widget.session.user.fullName,
      );

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _buildHomeOverviewCard(
          fullName: fullName,
          lecturerCode: _stringValue(
            lecturer['lecturerCode'],
            fallback: _lecturerCode,
          ),
          schoolName: widget.selectedSchool.name,
          managedClasses: _intValue(summary['managedClasses']),
          openSessions: _intValue(summary['openSessions']),
          unreadNotifications: _unreadNotificationCount,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _buildCompactPageHeader(
        title: _pageTitle,
        subtitle: _pageSubtitle,
        icon: _pageHeaderIcon,
      ),
    );
  }

  Widget _buildCompactPageHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _primarySoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: _primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _font(size: 18, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: _font(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: _textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNotificationActionButton(
                iconColor: _textPrimary,
                backgroundColor: _primarySoft,
                badgeBorderColor: _surface,
              ),
              const SizedBox(width: 8),
              _buildHeaderActionButton(
                icon: _isLoading || _isActionLoading
                    ? Icons.hourglass_top_rounded
                    : Icons.refresh_rounded,
                onTap: _isLoading || _isActionLoading
                    ? null
                    : () => _loadDashboard(showLoader: false),
                iconColor: _textPrimary,
                backgroundColor: const Color(0xFFF4F7FB),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color iconColor = _white,
    Color backgroundColor = const Color(0x18FFFFFF),
    double buttonSize = 42,
    double iconSize = 20,
  }) {
    final radius = buttonSize <= 38 ? 14.0 : 16.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: buttonSize,
        height: buttonSize,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }

  Widget _buildNotificationActionButton({
    Color iconColor = _white,
    Color backgroundColor = const Color(0x18FFFFFF),
    Color badgeBorderColor = _white,
    double buttonSize = 42,
    double iconSize = 20,
    double badgeSize = 12,
  }) {
    final hasUnreadNotifications = _unreadNotificationCount > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildHeaderActionButton(
          icon: Icons.notifications_none_rounded,
          onTap: () => _selectPage(4),
          iconColor: iconColor,
          backgroundColor: backgroundColor,
          buttonSize: buttonSize,
          iconSize: iconSize,
        ),
        if (hasUnreadNotifications)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D4F),
                shape: BoxShape.circle,
                border: Border.all(color: badgeBorderColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentPage() {
    switch (_selectedPageIndex) {
      case 1:
        return _buildClassesPage();
      case 2:
        return _buildHistoryPage();
      case 3:
        return _buildStatisticsPage();
      case 4:
        return _buildNotificationsPage();
      case 5:
        return _buildProfilePage();
      default:
        return _buildHomePage();
    }
  }

  Widget _buildHomePage() {
    final summary = _mapValue(_homeData, 'summary');
    final classesPreview = _listMap(_homeData?['classesPreview']);
    final notificationsPreview = _listMap(_homeData?['notificationsPreview']);
    final openSessions = _intValue(summary['openSessions']);
    Map<String, dynamic>? openClass;

    for (final item in classesPreview) {
      final status = _mapValue(item['currentSessionStatus']);
      if (_stringValue(status['code']) == 'open') {
        openClass = item;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHomeFeaturedClassCard(openClass, openSessionCount: openSessions),
        const SizedBox(height: 22),
        _buildSectionHeader('Tổng quan'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildHomeShortcutCard(
                title: '${_intValue(summary['managedClasses'])}',
                subtitle: 'Lớp phụ trách',
                icon: Icons.class_rounded,
                color: _primarySoft,
                iconColor: _primary,
                onTap: () => _selectPage(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildHomeShortcutCard(
                title: '$openSessions',
                subtitle: 'Phiên đang mở',
                icon: Icons.fact_check_rounded,
                color: _warningSoft,
                iconColor: _warning,
                onTap: () => _selectPage(1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildHomeShortcutCard(
                title: '${_intValue(summary['totalAttendanceHistory'])}',
                subtitle: 'Buổi đã lưu',
                icon: Icons.history_rounded,
                color: _successSoft,
                iconColor: _success,
                onTap: () => _selectPage(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildHomeShortcutCard(
                title: '$_unreadNotificationCount',
                subtitle: 'Thông báo chưa đọc',
                icon: Icons.notifications_active_rounded,
                color: _dangerSoft,
                iconColor: _danger,
                onTap: () => _selectPage(4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _buildSectionHeaderWithAction(
          title: 'Lớp học phần gần đây',
          subtitle: 'Chạm vào lớp để mở điểm danh và danh sách sinh viên',
          actionLabel: 'Xem tất cả',
          onTap: () => _selectPage(1),
        ),
        const SizedBox(height: 12),
        if (classesPreview.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có lớp học phần',
            body:
                'Giảng viên này chưa được phân công lớp học phần trong cơ sở dữ liệu.',
          )
        else
          ...classesPreview.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildHomeRecentClassCard(item),
            ),
          ),
        const SizedBox(height: 22),
        _buildSectionHeaderWithAction(
          title: _unreadNotificationCount > 0
              ? 'Thông báo cần xem'
              : 'Thông báo mới',
          subtitle: _unreadNotificationCount > 0
              ? '$_unreadNotificationCount nội dung chưa đọc'
              : 'Bạn đã xem hết các cập nhật gần đây',
          actionLabel: 'Xem tất cả',
          onTap: () => _selectPage(4),
        ),
        const SizedBox(height: 12),
        if (notificationsPreview.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có thông báo',
            body:
                'Thông báo dành cho giảng viên sẽ hiển thị tại đây khi có sự kiện mới.',
          )
        else
          ...notificationsPreview
              .take(2)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildNotificationCard(
                    item,
                    onTap: () => _openNotification(item),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildClassesPage() {
    final summary = _mapValue(_classData, 'summary');
    final classes = _listMap(_classData?['classes']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildSummaryCard(
              title: '${_intValue(summary['totalClasses'])}',
              subtitle: 'Tổng lớp học phần',
              color: _primarySoft,
              iconColor: _primary,
              icon: Icons.class_rounded,
            ),
            _buildSummaryCard(
              title: '${_intValue(summary['openSessions'])}',
              subtitle: 'Phiên đang mở',
              color: _warningSoft,
              iconColor: _warning,
              icon: Icons.lock_open_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('Danh sách lớp học phần'),
        const SizedBox(height: 12),
        if (classes.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có lớp học phần',
            body:
                'Hệ thống chưa tìm thấy lớp học phần nào do giảng viên này phụ trách.',
          )
        else
          ...classes.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildClassCard(
                item,
                isSelected:
                    _selectedScheduleId == _intValue(item['scheduleId']),
                onTap: () => _loadClassDetail(_intValue(item['scheduleId'])),
              ),
            ),
          ),
        const SizedBox(height: 22),
        if (_classDetail != null) _buildClassDetailPanel(),
      ],
    );
  }

  Widget _buildHistoryPage() {
    final filters = _mapValue(_historyData, 'filters');
    final items = _listMap(_historyData?['history']);
    final classOptions = _listMap(filters['classOptions']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterCard(
          title: 'Bộ lọc lịch sử',
          child: Column(
            children: [
              DropdownButtonFormField<int?>(
                initialValue: _historyScheduleId,
                decoration: const InputDecoration(labelText: 'Lớp học phần'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tất cả lớp học phần'),
                  ),
                  ...classOptions.map(
                    (item) => DropdownMenuItem<int?>(
                      value: _intValue(item['scheduleId']),
                      child: Text(_stringValue(item['classCode'])),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _historyScheduleId = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _historyKeywordController,
                decoration: const InputDecoration(
                  labelText: 'Tên môn học / mã môn',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _historyAttendanceDate ?? DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2035),
                        );
                        if (picked == null) return;
                        setState(() {
                          _historyAttendanceDate = picked;
                        });
                      },
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text(
                        _historyAttendanceDate == null
                            ? 'Chọn ngày'
                            : _formatDate(_historyAttendanceDate),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _historyScheduleId = null;
                          _historyAttendanceDate = null;
                          _historyKeywordController.clear();
                        });
                        _loadDashboard(showLoader: false);
                      },
                      child: const Text('Xóa lọc'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _loadDashboard(showLoader: false),
                  child: const Text('Áp dụng bộ lọc'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có lịch sử điểm danh',
            body:
                'Sau khi giảng viên lưu điểm danh, các buổi học sẽ hiển thị tại đây.',
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildHistoryCard(item),
            ),
          ),
      ],
    );
  }

  Widget _buildStatisticsPage() {
    final filters = _mapValue(_statisticsData, 'filters');
    final summary = _mapValue(_statisticsData, 'summary');
    final classStatistics = _listMap(_statisticsData?['classStatistics']);
    final studentStatistics = _listMap(_statisticsData?['studentStatistics']);
    final classOptions = _listMap(filters['classOptions']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterCard(
          title: 'Bộ lọc thống kê',
          child: Column(
            children: [
              DropdownButtonFormField<int?>(
                initialValue: _statisticsScheduleId,
                decoration: const InputDecoration(labelText: 'Lớp học phần'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tất cả lớp học phần'),
                  ),
                  ...classOptions.map(
                    (item) => DropdownMenuItem<int?>(
                      value: _intValue(item['scheduleId']),
                      child: Text(_stringValue(item['classCode'])),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _statisticsScheduleId = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _loadDashboard(showLoader: false),
                  child: const Text('Cập nhật thống kê'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildSummaryCard(
              title: '${_intValue(summary['totalClasses'])}',
              subtitle: 'Tổng lớp',
              color: _primarySoft,
              iconColor: _primary,
              icon: Icons.class_rounded,
            ),
            _buildSummaryCard(
              title: '${_intValue(summary['totalSessions'])}',
              subtitle: 'Tổng buổi',
              color: _warningSoft,
              iconColor: _warning,
              icon: Icons.event_note_rounded,
            ),
            _buildSummaryCard(
              title: '${_intValue(summary['totalOk'])}',
              subtitle: 'Lượt OK',
              color: _successSoft,
              iconColor: _success,
              icon: Icons.verified_rounded,
            ),
            _buildSummaryCard(
              title: '${_intValue(summary['totalAbsent'])}',
              subtitle: 'Lượt vắng',
              color: _dangerSoft,
              iconColor: _danger,
              icon: Icons.person_off_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('Thống kê theo lớp học phần'),
        const SizedBox(height: 12),
        if (classStatistics.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có thống kê lớp',
            body:
                'Cần có ít nhất một buổi đã lưu điểm danh để hiển thị thống kê.',
          )
        else
          ...classStatistics.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildStatisticsCard(item),
            ),
          ),
        const SizedBox(height: 20),
        _buildSectionHeader('Thống kê theo sinh viên'),
        const SizedBox(height: 12),
        if (studentStatistics.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có thống kê sinh viên',
            body:
                'Thống kê theo sinh viên sẽ hiển thị sau khi có dữ liệu điểm danh.',
          )
        else
          ...studentStatistics.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildStudentStatisticsCard(item),
            ),
          ),
      ],
    );
  }

  Widget _buildNotificationsPage() {
    final notifications = _listMap(_notificationData?['items']);

    if (notifications.isEmpty) {
      return _buildEmptyCard(
        title: 'Không có thông báo',
        body:
            'Khi có phiên mới, phiên sắp kết thúc hay xuất file, thông báo sẽ hiển thị ở đây.',
      );
    }

    return Column(
      children: notifications
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildNotificationCard(
                item,
                onTap: () => _openNotification(item),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildProfilePage() {
    final lecturer = _mapValue(_profileData, 'lecturer');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHeroCard(lecturer),
        const SizedBox(height: 18),
        _buildProfileMenuActionSection(lecturer),
      ],
    );
  }

  Widget _buildProfileHeroCard(Map<String, dynamic> lecturer) {
    final fullName = _stringValue(
      lecturer['fullName'],
      fallback: widget.session.user.fullName,
    );
    final lecturerCode = _stringValue(
      lecturer['lecturerCode'],
      fallback: _lecturerCode,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF165DFF), Color(0xFF4D97FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22165DFF),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(fullName),
              style: _font(size: 22, weight: FontWeight.w800, color: _white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 14.5,
                    weight: FontWeight.w800,
                    color: _white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Mã GV: $lecturerCode',
                  style: _font(
                    size: 11,
                    weight: FontWeight.w600,
                    color: const Color(0xD9FFFFFF),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _stringValue(
                    lecturer['school'],
                    fallback: widget.selectedSchool.name,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: const Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuActionSection(Map<String, dynamic> lecturer) {
    final summary = _mapValue(_homeData, 'summary');
    final unreadCount = _unreadNotificationCount;
    final items = [
      _LecturerProfileMenuItemData(
        title: 'Thông tin giảng viên',
        subtitle: 'Xem hồ sơ cá nhân và thông tin liên hệ',
        icon: Icons.badge_rounded,
        iconBg: _primarySoft,
        iconColor: _primary,
        onTap: () => _showLecturerInfoSheet(lecturer),
      ),
      _LecturerProfileMenuItemData(
        title: 'Dữ liệu hệ thống',
        subtitle:
            '${_intValue(summary['managedClasses'])} lớp phụ trách • ${_intValue(summary['totalAttendanceHistory'])} buổi đã lưu',
        icon: Icons.storage_rounded,
        iconBg: const Color(0xFFEAFBF2),
        iconColor: _success,
        onTap: () => _showLecturerSystemSheet(lecturer),
      ),
      _LecturerProfileMenuItemData(
        title: 'Đổi mật khẩu',
        subtitle: 'Thực hiện từ màn đăng nhập khi cần',
        icon: Icons.lock_reset_rounded,
        iconBg: const Color(0xFFFFF5DB),
        iconColor: _warning,
        onTap: _showLecturerChangePasswordSheet,
      ),
      _LecturerProfileMenuItemData(
        title: 'Thông báo',
        subtitle: unreadCount > 0
            ? '$unreadCount thông báo chưa đọc'
            : 'Xem danh sách thông báo hiện có',
        icon: Icons.notifications_active_rounded,
        iconBg: const Color(0xFFFFF5DB),
        iconColor: _warning,
        badgeLabel: unreadCount > 0 ? '$unreadCount' : null,
        onTap: () => _selectPage(4),
      ),
      _LecturerProfileMenuItemData(
        title: 'Đăng xuất',
        subtitle: 'Thoát khỏi tài khoản hiện tại',
        icon: Icons.logout_rounded,
        iconBg: const Color(0xFFFFEAEA),
        iconColor: const Color(0xFFB42318),
        isDestructive: true,
        onTap: _logout,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final showDivider = index != items.length - 1;

          return Column(
            children: [
              InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: item.iconBg,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: Icon(item.icon, color: item.iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: _font(
                                size: 14,
                                weight: FontWeight.w800,
                                color: item.isDestructive
                                    ? const Color(0xFFB42318)
                                    : _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle,
                              style: _font(
                                size: 12,
                                weight: FontWeight.w500,
                                color: _textSecondary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.badgeLabel != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primarySoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.badgeLabel!,
                            style: _font(
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: _primary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: item.isDestructive
                            ? const Color(0xFFB42318)
                            : const Color(0xFF98A2B3),
                      ),
                    ],
                  ),
                ),
              ),
              if (showDivider)
                const Divider(height: 1, indent: 66, endIndent: 14),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _showLecturerInfoSheet(Map<String, dynamic> lecturer) async {
    await _showProfileBottomSheet(
      title: 'Thông tin giảng viên',
      child: Column(
        children: [
          _buildProfileInfoCard(
            title: 'Hồ sơ tài khoản',
            rows: [
              _InfoRow(
                'Mã giảng viên',
                _stringValue(lecturer['lecturerCode'], fallback: _lecturerCode),
              ),
              _InfoRow(
                'Họ tên',
                _stringValue(
                  lecturer['fullName'],
                  fallback: widget.session.user.fullName,
                ),
              ),
              _InfoRow(
                'Khoa',
                _stringValue(lecturer['faculty'], fallback: 'Chưa cập nhật'),
              ),
              _InfoRow(
                'Email',
                _stringValue(lecturer['email'], fallback: 'Chưa cập nhật'),
              ),
              _InfoRow(
                'Số điện thoại',
                _stringValue(
                  lecturer['phoneNumber'],
                  fallback: 'Chưa cập nhật',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildProfileInfoCard(
            title: 'Đơn vị công tác',
            rows: [
              _InfoRow(
                'Trường',
                _stringValue(
                  lecturer['school'],
                  fallback: widget.selectedSchool.name,
                ),
              ),
              _InfoRow('Mã trường', widget.selectedSchool.code),
              _InfoRow('Phân hệ', 'Điểm danh Giảng viên'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLecturerSystemSheet(Map<String, dynamic> lecturer) async {
    final summary = _mapValue(_homeData, 'summary');
    final notificationCount = _listMap(
      _notificationData?['notifications'],
    ).length;

    await _showProfileBottomSheet(
      title: 'Dữ liệu hệ thống',
      child: Column(
        children: [
          _buildProfileInfoCard(
            title: 'Dữ liệu giảng dạy',
            rows: [
              _InfoRow(
                'Lớp phụ trách',
                '${_intValue(summary['managedClasses'])} lớp học phần',
              ),
              _InfoRow(
                'Phiên đang mở',
                '${_intValue(summary['openSessions'])} phiên điểm danh',
              ),
              _InfoRow(
                'Buổi đã lưu',
                '${_intValue(summary['totalAttendanceHistory'])} bản ghi',
              ),
              _InfoRow('Thông báo', '$notificationCount bản ghi'),
            ],
          ),
          const SizedBox(height: 14),
          _buildProfileInfoCard(
            title: 'Nguồn dữ liệu',
            rows: [
              _InfoRow('Tenant', widget.selectedSchool.code),
              _InfoRow('Vai trò DB', 'LECTURER'),
              _InfoRow(
                'Tài khoản',
                _stringValue(lecturer['lecturerCode'], fallback: _lecturerCode),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLecturerChangePasswordSheet() async {
    await _showProfileBottomSheet(
      title: 'Đổi mật khẩu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSheetNoticeCard(
            icon: Icons.lock_reset_rounded,
            iconColor: _primary,
            iconBg: _primarySoft,
            title: 'Đổi mật khẩu từ màn đăng nhập',
            body:
                'Hiện tại tab Cá nhân chưa có API đổi mật khẩu trực tiếp. Nếu cần đổi mật khẩu, hãy đăng xuất và chọn Quên mật khẩu ở màn đăng nhập.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                'Đăng xuất để đổi mật khẩu',
                style: _font(size: 14, weight: FontWeight.w700, color: _white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    if (_intValue(item['id']) <= 0 || item['isRead'] == true) {
      return;
    }

    try {
      await _lecturerApiService.markNotificationAsRead(
        schoolCode: widget.selectedSchool.code,
        lecturerCode: _lecturerCode,
        notificationId: _intValue(item['id']),
      );
      await _loadDashboard(showLoader: false);
    } catch (error) {
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Widget _buildClassDetailPanel() {
    final classInfo = _mapValue(_classDetail, 'classInfo');
    final currentSession = _mapValue(_classDetail, 'currentSession');
    final sessionSummary = _mapValue(currentSession, 'summary');
    final students = _listMap(_classDetail?['students']);
    final historyPreview = _listMap(_classDetail?['historyPreview']);
    final currentSessionStatus = _stringValue(
      _mapValue(currentSession['status'])['code'],
      fallback: 'scheduled',
    );
    final isSessionOpen = currentSessionStatus == 'open';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Chi tiết lớp học phần'),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: _stringValue(classInfo['courseName']),
          rows: [
            _InfoRow('Mã lớp học phần', _stringValue(classInfo['classCode'])),
            _InfoRow('Phòng học', _stringValue(classInfo['room'])),
            _InfoRow('Thời gian học', _stringValue(classInfo['timeLabel'])),
            _InfoRow(
              'Trạng thái phiên',
              _stringValue(
                _mapValue(classInfo['currentSessionStatus'])['label'],
                fallback: 'Chưa tạo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildActionTile(
              title: 'Mở phiên',
              icon: Icons.add_alarm_rounded,
              color: _primarySoft,
              iconColor: _primary,
              onTap: _isActionLoading || isSessionOpen
                  ? null
                  : _openCreateSessionDialog,
            ),
            _buildActionTile(
              title: 'Đóng phiên',
              icon: Icons.stop_circle_outlined,
              color: _successSoft,
              iconColor: _success,
              onTap:
                  _isActionLoading ||
                      !isSessionOpen ||
                      _intValue(currentSession['sessionId']) <= 0
                  ? null
                  : _closeAttendanceSession,
            ),
            _buildActionTile(
              title: 'Xuất hôm nay',
              icon: Icons.file_download_rounded,
              color: _warningSoft,
              iconColor: _warning,
              onTap: _isActionLoading ? null : () => _exportAttendance('today'),
            ),
            _buildActionTile(
              title: 'Xuất tất cả',
              icon: Icons.table_view_rounded,
              color: _dangerSoft,
              iconColor: _danger,
              onTap: _isActionLoading ? null : () => _exportAttendance('all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: 'Phiên điểm danh hiện tại',
          rows: [
            _InfoRow(
              'Ngày điểm danh',
              _formatDateTime(_dateValue(currentSession['attendanceDate'])),
            ),
            _InfoRow(
              'Mở lúc',
              _formatDateTime(_dateValue(currentSession['openedAt'])),
            ),
            _InfoRow(
              'Đóng lúc',
              _formatDateTime(_dateValue(currentSession['closesAt'])),
            ),
            _InfoRow(
              'Tổng sinh viên',
              '${_intValue(sessionSummary['totalStudents'])}',
            ),
            _InfoRow('OK', '${_intValue(sessionSummary['okCount'])}'),
            _InfoRow(
              'Cần kiểm tra',
              '${_intValue(sessionSummary['reviewCount'])}',
            ),
            _InfoRow('Vắng', '${_intValue(sessionSummary['absentCount'])}'),
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionHeader('Danh sách sinh viên'),
        const SizedBox(height: 12),
        if (students.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có sinh viên',
            body: 'Không có dữ liệu sinh viên thuộc lớp học phần này.',
          )
        else
          ...students.map(
            (student) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildAttendanceStudentCard(student),
            ),
          ),
        const SizedBox(height: 14),
        _buildSectionHeader('Buổi gần đây'),
        const SizedBox(height: 12),
        if (historyPreview.isEmpty)
          _buildEmptyCard(
            title: 'Chưa có lịch sử gần đây',
            body: 'Sau khi lưu điểm danh, các buổi học sẽ hiển thị tại đây.',
          )
        else
          ...historyPreview.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCompactSessionCard(item),
            ),
          ),
      ],
    );
  }

  Widget _buildAttendanceStudentCard(Map<String, dynamic> student) {
    final draft = _attendanceViewFor(student);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stringValue(student['fullName']),
                      style: _font(size: 15.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'MSSV: ${_stringValue(student['mssv'])}',
                      style: _font(color: _textSecondary),
                    ),
                  ],
                ),
              ),
              _buildStatusPill(draft.statusCode),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Thời gian điểm danh: ${_formatDateTime(draft.checkInAt)}',
            style: _font(size: 12.5, color: _textSecondary),
          ),
          if (draft.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ghi chú: ${draft.note}',
              style: _font(size: 12.5, color: _textSecondary, height: 1.45),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isActionLoading
                  ? null
                  : () => _editAttendanceStudent(student),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(
                'Chỉnh sửa',
                style: _font(weight: FontWeight.w700, color: _textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSessionCard(Map<String, dynamic> item) {
    final status = _mapValue(item['status']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stringValue(item['dayLabel']),
                  style: _font(size: 14.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(_dateValue(item['attendanceDate'])),
                  style: _font(size: 12.5, color: _textSecondary),
                ),
              ],
            ),
          ),
          _buildStatusPill(_stringValue(status['code'], fallback: 'scheduled')),
        ],
      ),
    );
  }

  _AttendanceDraft _attendanceViewFor(Map<String, dynamic> student) {
    final studentId = _intValue(student['studentId']);
    final draft = _attendanceDrafts[studentId];
    if (draft != null) {
      return draft;
    }

    final status = _mapValue(student['status']);
    return _AttendanceDraft(
      statusCode: _stringValue(status['code'], fallback: 'ABSENT'),
      note: _stringValue(student['note']),
      checkInAt: _dateValue(student['checkInAt']),
    );
  }

  Future<void> _openCreateSessionDialog() async {
    if (_selectedScheduleId == null || _selectedScheduleId! <= 0) {
      _showSnack('Vui lòng chọn lớp học phần trước', isError: true);
      return;
    }

    var startAt = DateTime.now();
    DateTime? endAt;
    var useEndTime = false;
    final durationController = TextEditingController(text: '20');

    final didSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Mở phiên điểm danh'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bắt đầu: ${_formatDateTime(startAt)}',
                      style: _font(weight: FontWeight.w700),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await _pickDateTime(startAt);
                        if (picked == null) return;
                        setLocalState(() {
                          startAt = picked;
                          if (endAt != null && !endAt!.isAfter(startAt)) {
                            endAt = startAt.add(const Duration(minutes: 20));
                          }
                        });
                      },
                      child: const Text('Chọn thời gian bắt đầu'),
                    ),
                    SwitchListTile(
                      value: useEndTime,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Nhập thời gian kết thúc'),
                      subtitle: const Text('Tắt nếu muốn dùng thời lượng'),
                      onChanged: (value) {
                        setLocalState(() {
                          useEndTime = value;
                          endAt ??= startAt.add(const Duration(minutes: 20));
                        });
                      },
                    ),
                    if (useEndTime) ...[
                      Text(
                        'Kết thúc: ${_formatDateTime(endAt)}',
                        style: _font(weight: FontWeight.w700),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await _pickDateTime(
                            endAt ?? startAt.add(const Duration(minutes: 20)),
                          );
                          if (picked == null) return;
                          setLocalState(() {
                            endAt = picked;
                          });
                        },
                        child: const Text('Chọn thời gian kết thúc'),
                      ),
                    ] else ...[
                      TextField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Thời lượng (phút)',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Mở phiên'),
                ),
              ],
            );
          },
        );
      },
    );

    if (didSubmit != true) {
      durationController.dispose();
      return;
    }

    try {
      setState(() {
        _isActionLoading = true;
      });

      await _lecturerApiService.createAttendanceSession(
        schoolCode: widget.selectedSchool.code,
        lecturerCode: _lecturerCode,
        scheduleId: _selectedScheduleId!,
        startAt: startAt,
        endAt: useEndTime ? endAt : null,
        durationMinutes: useEndTime
            ? null
            : int.tryParse(durationController.text.trim()),
      );

      durationController.dispose();
      await _loadDashboard(showLoader: false);
      _showSnack('Đã mở phiên điểm danh mới');
    } catch (error) {
      durationController.dispose();
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  Future<void> _editAttendanceStudent(Map<String, dynamic> student) async {
    final currentDraft = _attendanceViewFor(student);
    var statusCode = currentDraft.statusCode;
    final noteController = TextEditingController(text: currentDraft.note);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(_stringValue(student['fullName'])),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: statusCode,
                    decoration: const InputDecoration(labelText: 'Trạng thái'),
                    items: const [
                      DropdownMenuItem(value: 'OK', child: Text('OK')),
                      DropdownMenuItem(
                        value: 'REVIEW',
                        child: Text('Cần kiểm tra'),
                      ),
                      DropdownMenuItem(value: 'ABSENT', child: Text('Vắng')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() {
                        statusCode = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú',
                      hintText: 'Nhập ghi chú nếu cần',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Đóng'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cập nhật'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave == true) {
      setState(() {
        _attendanceDrafts[_intValue(student['studentId'])] = _AttendanceDraft(
          statusCode: statusCode,
          note: noteController.text.trim(),
          checkInAt: _dateValue(student['checkInAt']),
        );
      });
    }

    noteController.dispose();
  }

  Future<void> _saveAttendance() async {
    final currentSession = _mapValue(_classDetail, 'currentSession');
    final sessionId = _intValue(currentSession['sessionId']);

    if (sessionId <= 0) {
      _showSnack('Chưa có phiên điểm danh để lưu', isError: true);
      return;
    }

    final students = _listMap(_classDetail?['students']);
    final records = students.map((student) {
      final draft = _attendanceViewFor(student);
      final payload = <String, dynamic>{
        'recordId': student['recordId'],
        'studentId': _intValue(student['studentId']),
        'status': draft.statusCode,
        'note': draft.note,
      };

      if (draft.checkInAt != null) {
        payload['checkInAt'] = draft.checkInAt!.toIso8601String();
      }

      return payload;
    }).toList();

    try {
      setState(() {
        _isActionLoading = true;
      });

      await _lecturerApiService.saveAttendanceSession(
        schoolCode: widget.selectedSchool.code,
        lecturerCode: _lecturerCode,
        sessionId: sessionId,
        records: records,
      );

      await _loadDashboard(showLoader: false);
      _showSnack('Đã đóng phiên và lưu kết quả điểm danh');
    } catch (error) {
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  Future<void> _closeAttendanceSession() async {
    final currentSession = _mapValue(_classDetail, 'currentSession');
    final sessionId = _intValue(currentSession['sessionId']);
    final sessionStatus = _stringValue(
      _mapValue(currentSession['status'])['code'],
    );

    if (sessionId <= 0 || sessionStatus != 'open') {
      _showSnack('Không có phiên điểm danh đang mở', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Đóng phiên điểm danh?'),
          content: const Text(
            'Phiên hiện tại sẽ kết thúc. Kết quả đã điểm danh được giữ lại, sinh viên chưa hoàn tất sẽ được ghi nhận vắng.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Đóng phiên'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _saveAttendance();
    }
  }

  Future<void> _exportAttendance(String scope) async {
    if (_selectedScheduleId == null || _selectedScheduleId! <= 0) {
      _showSnack('Vui lòng chọn lớp học phần để xuất file', isError: true);
      return;
    }

    try {
      setState(() {
        _isActionLoading = true;
      });

      final result = await _lecturerApiService.exportAttendance(
        schoolCode: widget.selectedSchool.code,
        lecturerCode: _lecturerCode,
        scheduleId: _selectedScheduleId!,
        scope: scope,
      );
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${result.fileName}');
      await file.writeAsBytes(result.bytes, flush: true);

      await _loadDashboard(showLoader: false);
      _showSnack('Đã lưu file Excel tại ${file.path}');
    } catch (error) {
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initialValue) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialValue,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );

    if (pickedDate == null || !mounted) {
      return null;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialValue),
    );

    if (pickedTime == null) {
      return null;
    }

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Widget _buildHomeOverviewCard({
    required String fullName,
    required String lecturerCode,
    required String schoolName,
    required int managedClasses,
    required int openSessions,
    required int unreadNotifications,
  }) {
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? 'Chào buổi sáng'
        : hour < 18
        ? 'Chào buổi chiều'
        : 'Chào buổi tối';
    final statusLabel = openSessions > 0
        ? '$openSessions phiên điểm danh đang mở'
        : 'Không có phiên điểm danh đang mở';

    return Semantics(
      container: true,
      label:
          '$greeting, $fullName. $managedClasses lớp phụ trách. '
          '$statusLabel. $unreadNotifications thông báo chưa đọc.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0C2E59), Color(0xFF0B63CE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x260B63CE),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0x24FFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x38FFFFFF)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(fullName),
                    style: _font(
                      size: 16,
                      weight: FontWeight.w800,
                      color: _white,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: _font(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: const Color(0xCFFFFFFF),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _font(
                          size: 17.5,
                          weight: FontWeight.w800,
                          color: _white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$lecturerCode • $schoolName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _font(
                          size: 11,
                          weight: FontWeight.w500,
                          color: const Color(0xCFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: unreadNotifications > 0
                      ? 'Mở $unreadNotifications thông báo chưa đọc'
                      : 'Mở thông báo',
                  child: ExcludeSemantics(
                    child: _buildNotificationActionButton(
                      buttonSize: 44,
                      iconSize: 20,
                      badgeSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: 'Làm mới dữ liệu',
                  child: ExcludeSemantics(
                    child: _buildHeaderActionButton(
                      icon: _isLoading || _isActionLoading
                          ? Icons.hourglass_top_rounded
                          : Icons.refresh_rounded,
                      onTap: _isLoading || _isActionLoading
                          ? null
                          : () => _loadDashboard(showLoader: false),
                      buttonSize: 44,
                      iconSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label: '$statusLabel. Mở danh sách lớp học phần.',
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectPage(1),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1FFFFFFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x2EFFFFFF)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          openSessions > 0
                              ? Icons.radio_button_checked_rounded
                              : Icons.check_circle_rounded,
                          size: 19,
                          color: openSessions > 0
                              ? const Color(0xFFFFCC66)
                              : const Color(0xFF7EE2B8),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            openSessions > 0
                                ? '$statusLabel • Chạm để xử lý'
                                : '$managedClasses lớp phụ trách • Xem lịch lớp',
                            style: _font(
                              size: 12,
                              weight: FontWeight.w700,
                              color: _white,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: _white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeOverviewPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1CFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _white),
          const SizedBox(width: 5),
          Text(
            label,
            style: _font(size: 11.5, weight: FontWeight.w700, color: _white),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeShortcutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$subtitle: $title',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x07101828),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: _font(size: 19, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _font(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: _textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String subtitle,
    required Color color,
    required Color iconColor,
    required IconData icon,
  }) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(title, style: _font(size: 22, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: _font(
              size: 12.5,
              weight: FontWeight.w600,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: _font(size: 20, weight: FontWeight.w800));
  }

  Widget _buildSectionHeaderWithAction({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: _font(size: 18, weight: FontWeight.w800),
              ),
            ),
            Semantics(
              button: true,
              label: '$actionLabel $title',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel,
                          style: _font(
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: _primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          subtitle,
          style: _font(
            size: 11.5,
            weight: FontWeight.w500,
            color: _textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildHomeFeaturedClassCard(
    Map<String, dynamic>? item, {
    required int openSessionCount,
  }) {
    final hasOpenSession = item != null;
    final courseName = hasOpenSession
        ? _stringValue(item['courseName'], fallback: 'Lớp học phần')
        : 'Mọi phiên điểm danh đã được xử lý';
    final classContext = hasOpenSession
        ? '${_stringValue(item['classCode'])} • ${_stringValue(item['room'])}'
        : 'Bạn có thể xem lịch hoặc chuẩn bị phiên điểm danh tiếp theo.';

    void openClass() {
      _selectPage(1);
      if (item != null) {
        _loadClassDetail(_intValue(item['scheduleId']));
      }
    }

    return Semantics(
      button: true,
      label: hasOpenSession
          ? 'Ưu tiên hôm nay. $courseName. $classContext. Mở lớp điểm danh.'
          : '$courseName. $classContext. Mở danh sách lớp.',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: openClass,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              gradient: hasOpenSession
                  ? const LinearGradient(
                      colors: [Color(0xFF0A3B72), Color(0xFF0B63CE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFF0FBF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasOpenSession
                    ? const Color(0x00000000)
                    : const Color(0xFFB7E8D0),
              ),
              boxShadow: [
                BoxShadow(
                  color: hasOpenSession
                      ? const Color(0x260B63CE)
                      : const Color(0x0F12B76A),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: hasOpenSession
                            ? const Color(0xFFFFE4A3)
                            : _successSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasOpenSession
                                ? Icons.bolt_rounded
                                : Icons.check_circle_rounded,
                            size: 15,
                            color: hasOpenSession
                                ? const Color(0xFF805600)
                                : _success,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            hasOpenSession ? 'ƯU TIÊN HÔM NAY' : 'ĐÃ HOÀN TẤT',
                            style: _font(
                              size: 10.5,
                              weight: FontWeight.w800,
                              color: hasOpenSession
                                  ? const Color(0xFF684600)
                                  : _success,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (hasOpenSession && openSessionCount > 1)
                      Text(
                        '$openSessionCount phiên đang mở',
                        style: _font(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: const Color(0xD9FFFFFF),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  hasOpenSession ? 'Phiên điểm danh đang mở' : courseName,
                  style: _font(
                    size: 15,
                    weight: FontWeight.w700,
                    color: hasOpenSession ? const Color(0xD9FFFFFF) : _success,
                  ),
                ),
                if (hasOpenSession) ...[
                  const SizedBox(height: 5),
                  Text(
                    courseName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 20,
                      weight: FontWeight.w800,
                      color: _white,
                      height: 1.25,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Text(
                  classContext,
                  style: _font(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: hasOpenSession
                        ? const Color(0xD9FFFFFF)
                        : _textSecondary,
                    height: 1.45,
                  ),
                ),
                if (hasOpenSession) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _buildHomeOverviewPill(
                        icon: Icons.access_time_filled_rounded,
                        label: _stringValue(item['timeRange']),
                      ),
                      _buildHomeOverviewPill(
                        icon: Icons.groups_rounded,
                        label: '${_intValue(item['studentCount'])} sinh viên',
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 15),
                Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: hasOpenSession ? _white : _primary,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasOpenSession
                            ? Icons.fact_check_rounded
                            : Icons.calendar_month_rounded,
                        size: 19,
                        color: hasOpenSession ? _primary : _white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasOpenSession
                            ? 'Mở lớp điểm danh'
                            : 'Xem danh sách lớp',
                        style: _font(
                          size: 13,
                          weight: FontWeight.w800,
                          color: hasOpenSession ? _primary : _white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                        color: hasOpenSession ? _primary : _white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeRecentClassCard(Map<String, dynamic> item) {
    final sessionStatus = _mapValue(item['currentSessionStatus']);
    final statusCode = _stringValue(
      sessionStatus['code'],
      fallback: 'not_created',
    );
    final isOpen = statusCode == 'open';
    final courseName = _stringValue(item['courseName']);
    final classCode = _stringValue(item['classCode']);
    final timeRange = _stringValue(item['timeRange']);

    void openClass() {
      _selectPage(1);
      _loadClassDetail(_intValue(item['scheduleId']));
    }

    return Semantics(
      button: true,
      label:
          '$courseName. $classCode. $timeRange. '
          '${_statusStyle(statusCode).label}.',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: openClass,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: isOpen ? _success : _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x07101828),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isOpen ? _successSoft : _primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isOpen ? Icons.fact_check_rounded : Icons.menu_book_rounded,
                    color: isOpen ? _success : _primary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        courseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _font(size: 13.5, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$classCode • $timeRange',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _font(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildStatusPill(statusCode),
                    const SizedBox(height: 5),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: Color(0xFF98A2B3),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassCard(
    Map<String, dynamic> item, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final sessionStatus = _mapValue(item['currentSessionStatus']);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? _primary : _border,
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x07101828),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stringValue(item['courseName']),
                        style: _font(size: 16, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _stringValue(item['classCode']),
                        style: _font(
                          size: 13,
                          weight: FontWeight.w600,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusPill(
                  _stringValue(sessionStatus['code'], fallback: 'not_created'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSmallPill(
                  icon: Icons.groups_rounded,
                  label: '${_intValue(item['studentCount'])} SV',
                ),
                _buildSmallPill(
                  icon: Icons.access_time_filled_rounded,
                  label: _stringValue(item['timeRange']),
                ),
                _buildSmallPill(
                  icon: Icons.meeting_room_rounded,
                  label: _stringValue(item['room']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    Map<String, dynamic> item, {
    required VoidCallback onTap,
  }) {
    final isRead = item['isRead'] == true;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRead ? _border : _primary),
          boxShadow: const [
            BoxShadow(
              color: Color(0x07101828),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isRead ? const Color(0xFFF4F6F8) : _primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _notificationIcon(_stringValue(item['type'])),
                color: _primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _stringValue(item['title']),
                          style: _font(size: 14.5, weight: FontWeight.w800),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: _primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stringValue(item['body']),
                    style: _font(
                      size: 12.5,
                      color: _textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _relativeTime(_dateValue(item['createdAt'])),
                    style: _font(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _notificationIcon(String type) {
    switch (type) {
      case 'schedule_upcoming':
        return Icons.schedule_rounded;
      case 'schedule_started':
        return Icons.play_circle_fill_rounded;
      case 'attendance_available':
        return Icons.fact_check_rounded;
      case 'attendance_export_failed':
        return Icons.error_outline_rounded;
      case 'attendance_export_success':
        return Icons.download_done_rounded;
      case 'attendance_closing':
        return Icons.alarm_on_rounded;
      case 'attendance_closed':
        return Icons.event_busy_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Widget _buildInfoCard({required String title, required List<_InfoRow> rows}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _font(size: 16, weight: FontWeight.w800)),
          const SizedBox(height: 16),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(
                      row.label,
                      style: _font(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: _font(
                        size: 13,
                        weight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: _font(size: 13.5, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String statusCode) {
    final style = _statusStyle(statusCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: _font(
          size: 12,
          weight: FontWeight.w800,
          color: style.foreground,
        ),
      ),
    );
  }

  _StatusStyle _statusStyle(String statusCode) {
    switch (statusCode) {
      case 'open':
      case 'OK':
        return const _StatusStyle('Đang mở', _successSoft, _success);
      case 'closed':
        return const _StatusStyle('Đã đóng', _primarySoft, _primary);
      case 'REVIEW':
        return const _StatusStyle('Cần kiểm tra', _warningSoft, _warning);
      case 'ABSENT':
        return const _StatusStyle('Vắng', _dangerSoft, _danger);
      case 'scheduled':
        return const _StatusStyle('Đã lên lịch', _warningSoft, _warning);
      default:
        return const _StatusStyle(
          'Chưa tạo',
          Color(0xFFF2F4F7),
          Color(0xFF475467),
        );
    }
  }

  Widget _buildEmptyCard({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _font(size: 15.5, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            body,
            style: _font(size: 13, color: _textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _font(size: 16, weight: FontWeight.w800)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final students = _listMap(item['students']);
    final summary = _mapValue(item['summary']);

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          _stringValue(item['courseName']),
          style: _font(size: 15, weight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${_stringValue(item['classCode'])} • ${_formatDate(_dateValue(item['attendanceDate']))} • ${_stringValue(item['timeRange'])}',
            style: _font(size: 12.5, color: _textSecondary),
          ),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSmallPill(
                icon: Icons.verified_rounded,
                label: 'OK ${_intValue(summary['okCount'])}',
              ),
              _buildSmallPill(
                icon: Icons.fact_check_rounded,
                label: 'Cần kiểm tra ${_intValue(summary['reviewCount'])}',
              ),
              _buildSmallPill(
                icon: Icons.person_off_rounded,
                label: 'Vắng ${_intValue(summary['absentCount'])}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...students.map(
            (student) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_stringValue(student['mssv'])} • ${_stringValue(student['fullName'])}',
                      style: _font(size: 12.8, weight: FontWeight.w600),
                    ),
                  ),
                  _buildStatusPill(
                    _stringValue(
                      _mapValue(student['status'])['code'],
                      fallback: 'ABSENT',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stringValue(item['courseName']),
            style: _font(size: 15.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _stringValue(item['classCode']),
            style: _font(size: 12.5, color: _textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSmallPill(
                icon: Icons.event_note_rounded,
                label: '${_intValue(item['totalSessions'])} buổi',
              ),
              _buildSmallPill(
                icon: Icons.groups_rounded,
                label: '${_intValue(item['studentCount'])} SV',
              ),
              _buildSmallPill(
                icon: Icons.verified_rounded,
                label: 'OK ${_intValue(item['okCount'])}',
              ),
              _buildSmallPill(
                icon: Icons.fact_check_rounded,
                label: 'Cần kiểm tra ${_intValue(item['reviewCount'])}',
              ),
              _buildSmallPill(
                icon: Icons.person_off_rounded,
                label: 'Vắng ${_intValue(item['absentCount'])}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentStatisticsCard(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stringValue(item['fullName']),
                  style: _font(size: 14.5, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_stringValue(item['mssv'])} • ${_stringValue(item['className'])}',
                  style: _font(size: 12.5, color: _textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'OK ${_intValue(item['totalOk'])}',
                style: _font(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: _success,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Cần kiểm tra ${_intValue(item['totalReview'])}',
                style: _font(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: _warning,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Vắng ${_intValue(item['totalAbsent'])}',
                style: _font(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: _danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475467)),
          const SizedBox(width: 6),
          Text(
            label,
            style: _font(
              size: 12,
              weight: FontWeight.w700,
              color: const Color(0xFF475467),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    const items = [
      _LecturerBottomNavItem(
        label: 'Trang chủ',
        icon: Icons.home_rounded,
        selectedIcon: Icons.home_filled,
        pageIndex: 0,
      ),
      _LecturerBottomNavItem(
        label: 'Lớp học',
        icon: Icons.class_outlined,
        selectedIcon: Icons.class_rounded,
        pageIndex: 1,
      ),
      _LecturerBottomNavItem(
        label: 'Theo dõi',
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        pageIndex: 2,
      ),
      _LecturerBottomNavItem(
        label: 'Thông báo',
        icon: Icons.notifications_none_rounded,
        selectedIcon: Icons.notifications_active_rounded,
        pageIndex: 4,
      ),
      _LecturerBottomNavItem(
        label: 'Cá nhân',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        pageIndex: 5,
      ),
    ];

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C101828),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = item.pageIndex == 2
                ? _selectedPageIndex == 2 || _selectedPageIndex == 3
                : _selectedPageIndex == item.pageIndex;

            return Expanded(
              child: InkWell(
                onTap: () => _selectPage(item.pageIndex),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: isSelected ? _primarySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        size: 21,
                        color: isSelected ? _primary : const Color(0xFF98A2B3),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _font(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: isSelected
                              ? _primary
                              : const Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dangerSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: _font(
                size: 13,
                weight: FontWeight.w600,
                color: _danger,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _danger : _textPrimary,
      ),
    );
  }

  Future<void> _showProfileBottomSheet({
    required String title,
    required Widget child,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(12, 80, 12, bottomInset),
          child: Container(
            decoration: BoxDecoration(
              color: _white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
                bottom: Radius.circular(24),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A101828),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: _font(
                              size: 19,
                              weight: FontWeight.w800,
                              color: _textPrimary,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(sheetContext).pop(),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F4F7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: Color(0xFF344054),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    child,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetNoticeCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _font(
                    size: 14,
                    weight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: _font(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: _textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoCard({
    required String title,
    required List<_InfoRow> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _font(size: 16, weight: FontWeight.w800)),
          const SizedBox(height: 16),
          ...rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(
                      row.label,
                      style: _font(
                        size: 13,
                        weight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: _font(
                        size: 13.5,
                        weight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _listMap(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> _mapValue(Object? value, [String key = '']) {
    if (key.isNotEmpty && value is Map<String, dynamic>) {
      final nested = value[key];
      if (nested is Map<String, dynamic>) {
        return nested;
      }
      return const {};
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    return const {};
  }

  String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return fallback;
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  DateTime? _dateValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '--';
    }

    final local = value.toLocal();
    final day = '${local.day}'.padLeft(2, '0');
    final month = '${local.month}'.padLeft(2, '0');
    final year = '${local.year}';
    final hour = '${local.hour}'.padLeft(2, '0');
    final minute = '${local.minute}'.padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '--/--/----';
    }

    final local = value.toLocal();
    final day = '${local.day}'.padLeft(2, '0');
    final month = '${local.month}'.padLeft(2, '0');
    final year = '${local.year}';
    return '$day/$month/$year';
  }

  String _relativeTime(DateTime? value) {
    if (value == null) {
      return 'Vừa xong';
    }

    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    }
    return '${difference.inDays} ngày trước';
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'GV';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _AttendanceDraft {
  final String statusCode;
  final String note;
  final DateTime? checkInAt;

  const _AttendanceDraft({
    required this.statusCode,
    required this.note,
    required this.checkInAt,
  });
}

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);
}

class _LecturerBottomNavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int pageIndex;

  const _LecturerBottomNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.pageIndex,
  });
}

class _LecturerProfileMenuItemData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String? badgeLabel;
  final bool isDestructive;
  final VoidCallback onTap;

  const _LecturerProfileMenuItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.onTap,
    this.badgeLabel,
    this.isDestructive = false,
  });
}

class _StatusStyle {
  final String label;
  final Color background;
  final Color foreground;

  const _StatusStyle(this.label, this.background, this.foreground);
}
