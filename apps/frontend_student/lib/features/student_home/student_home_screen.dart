import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/face_auth_api_service.dart';
import '../../core/api/student_home_api_service.dart';
import '../../core/ble/ble_models.dart';
import '../../core/ble/ble_scanner.dart';
import '../../core/location/gps_evidence_collector.dart';
import '../../shared/models/auth_session_model.dart';
import '../../core/auth/auth_session_controller.dart';
import '../../shared/models/school_model.dart';
import '../../shared/models/student_home_model.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/storage/auth_persistence_service.dart';
import '../auth/login_screen.dart';
import '../face_verification/face_verification_screen.dart';
import '../face_verification/mobile_face_verification_screen.dart';
import 'widgets/student_home_dashboard.dart';

enum _ScheduleViewMode { day, week, month }

class StudentHomeScreen extends StatefulWidget {
  final AuthSessionModel session;
  final SchoolModel selectedSchool;

  const StudentHomeScreen({
    super.key,
    required this.session,
    required this.selectedSchool,
  });

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  static const bool _mobileFaceEnabled = bool.fromEnvironment(
    'MOBILE_FACE_AUTH',
    defaultValue: !kDebugMode,
  );
  // Kept behind a build flag so face-auth can be validated independently
  // without removing the BLE implementation.
  static const bool _bleAttendanceEnabled = bool.fromEnvironment(
    'BLE_ATTENDANCE_ENABLED',
    defaultValue: true,
  );
  static const Color _white = Colors.white;
  static const Color _pageBg = Color(0xFFF5F7FB);
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _primary = Color(0xFF165DFF);
  static const Color _primaryDark = Color(0xFF0B57D0);
  static const Color _primarySoft = Color(0xFFEAF1FF);
  static const Color _border = Color(0xFFE7EBF3);
  static const Color _warning = Color(0xFFF0B323);
  static const Color _success = Color(0xFF22B07D);

  late final StudentHomeApiService _studentHomeApiService;
  final AuthPersistenceService _authPersistenceService =
      AuthPersistenceService();
  final TextEditingController _feedbackController = TextEditingController();
  late final BleScanner _bleScanner;
  final GpsEvidenceCollector _gpsEvidenceCollector =
      const GpsEvidenceCollector();

  StudentHomeModel? _homeData;
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedTabIndex = 0;
  _ScheduleViewMode _scheduleViewMode = _ScheduleViewMode.day;
  late DateTime _scheduleAnchorDate;
  late DateTime _scheduleSelectedDate;
  bool _isScheduleLoading = true;
  String? _scheduleErrorMessage;
  List<StudentScheduleItemModel> _scheduleItems = const [];
  bool _isAttendanceSubmitting = false;
  bool _isNearbyRoomScanning = false;
  BleEvidence? _nearbyRoomEvidence;
  String? _nearbyRoomError;

  @override
  void initState() {
    super.initState();
    AuthSessionController.instance.activate(
      widget.session,
      widget.selectedSchool,
    );
    _scheduleAnchorDate = _normalizeDate(DateTime.now());
    _scheduleSelectedDate = _scheduleAnchorDate;
    _studentHomeApiService = StudentHomeApiService(
      accessToken: widget.session.accessToken,
    );
    _bleScanner = BleScannerFactory.create();
    _loadHomeData();
    _loadScheduleData();
    if (_bleAttendanceEnabled) {
      unawaited(_scanNearbyRoom());
    }
  }

  @override
  void dispose() {
    unawaited(_bleScanner.dispose());
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _scanNearbyRoom() async {
    if (_isNearbyRoomScanning) return;
    setState(() {
      _isNearbyRoomScanning = true;
      _nearbyRoomError = null;
    });

    try {
      final results = await _bleScanner.scan(duration: nearbyRoomScanDuration);
      final nearest = selectNearestBle(results);
      if (!mounted) return;
      setState(() {
        _nearbyRoomEvidence = nearest;
        _nearbyRoomError = nearest == null
            ? 'Không tìm thấy thiết bị điểm danh gần đây'
            : null;
      });
    } on BleScanCancelledException {
      // Expected when the screen is closed or another scan starts.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _nearbyRoomError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isNearbyRoomScanning = false);
      }
    }
  }

  Future<BleEvidence> _scanAttendanceBle(StudentScheduleItemModel item) async {
    final results = await _bleScanner.scan(
      duration: attendanceBleScanDuration,
      expected: item.expectedBle,
    );
    final matching = results
        .where(
          (result) =>
              (result.c6Token != null &&
                  (item.expectedBle.deviceIds.isEmpty ||
                      item.expectedBle.deviceIds.contains(
                        result.c6DeviceId,
                      ))) ||
              (result.beaconId == item.expectedBle.beaconId &&
                  result.roomId == item.expectedBle.roomId),
        )
        .toList();
    final evidence = selectNearestBle(matching);
    if (evidence == null) {
      throw Exception('Không tìm thấy BLE của phòng ${item.room}');
    }
    if (evidence.rssi < item.expectedBle.minRssi) {
      throw Exception('Tín hiệu BLE của phòng học quá yếu');
    }
    return evidence;
  }

  Future<void> _loadHomeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final homeData = await _studentHomeApiService.getHomeOverview(
        schoolCode: widget.selectedSchool.code,
        mssv: widget.session.user.code,
      );

      if (!mounted) return;

      setState(() {
        _homeData = homeData;
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

  Future<void> _loadScheduleData({
    _ScheduleViewMode? viewMode,
    DateTime? anchorDate,
    DateTime? selectedDate,
  }) async {
    final nextViewMode = viewMode ?? _scheduleViewMode;
    final nextAnchorDate = _normalizeDate(anchorDate ?? _scheduleAnchorDate);
    final nextSelectedDate = _resolveScheduleSelectedDate(
      viewMode: nextViewMode,
      anchorDate: nextAnchorDate,
      selectedDate: selectedDate ?? _scheduleSelectedDate,
    );

    setState(() {
      _scheduleViewMode = nextViewMode;
      _scheduleAnchorDate = nextAnchorDate;
      _scheduleSelectedDate = nextSelectedDate;
      _isScheduleLoading = true;
      _scheduleErrorMessage = null;
    });

    try {
      final items = await _studentHomeApiService.getSchedule(
        schoolCode: widget.selectedSchool.code,
        mssv: widget.session.user.code,
        view: _scheduleViewModeParam(nextViewMode),
        date: _formatApiDate(nextAnchorDate),
      );

      if (!mounted) return;

      setState(() {
        _scheduleItems = items;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _scheduleErrorMessage = error.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScheduleLoading = false;
        });
      }
    }
  }

  Future<void> _refreshScheduleTab() async {
    await Future.wait<void>([_loadHomeData(), _loadScheduleData()]);
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

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _twoDigits(int value) => '$value'.padLeft(2, '0');

  String _formatApiDate(DateTime value) {
    return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)}';
  }

  String _scheduleViewModeParam(_ScheduleViewMode value) {
    switch (value) {
      case _ScheduleViewMode.week:
        return 'week';
      case _ScheduleViewMode.month:
        return 'month';
      case _ScheduleViewMode.day:
        return 'day';
    }
  }

  DateTime _startOfWeek(DateTime value) {
    final normalized = _normalizeDate(value);
    final offset = normalized.weekday - DateTime.monday;
    return normalized.subtract(Duration(days: offset));
  }

  DateTime _startOfMonth(DateTime value) {
    return DateTime(value.year, value.month, 1);
  }

  DateTime _moveScheduleAnchor(int offset) {
    switch (_scheduleViewMode) {
      case _ScheduleViewMode.day:
        return _normalizeDate(_scheduleAnchorDate.add(Duration(days: offset)));
      case _ScheduleViewMode.week:
        return _normalizeDate(
          _startOfWeek(_scheduleAnchorDate).add(Duration(days: 7 * offset)),
        );
      case _ScheduleViewMode.month:
        return _startOfMonth(
          DateTime(
            _scheduleAnchorDate.year,
            _scheduleAnchorDate.month + offset,
            1,
          ),
        );
    }
  }

  DateTime _schedulePeriodStart(
    _ScheduleViewMode viewMode,
    DateTime anchorDate,
  ) {
    switch (viewMode) {
      case _ScheduleViewMode.day:
        return _normalizeDate(anchorDate);
      case _ScheduleViewMode.week:
        return _startOfWeek(anchorDate);
      case _ScheduleViewMode.month:
        return _startOfMonth(anchorDate);
    }
  }

  DateTime _schedulePeriodEnd(_ScheduleViewMode viewMode, DateTime anchorDate) {
    switch (viewMode) {
      case _ScheduleViewMode.day:
        return _normalizeDate(anchorDate);
      case _ScheduleViewMode.week:
        return _startOfWeek(anchorDate).add(const Duration(days: 6));
      case _ScheduleViewMode.month:
        final start = _startOfMonth(anchorDate);
        return DateTime(start.year, start.month + 1, 0);
    }
  }

  bool _isDateInSchedulePeriod(
    _ScheduleViewMode viewMode,
    DateTime anchorDate,
    DateTime date,
  ) {
    final normalizedDate = _normalizeDate(date);
    final start = _schedulePeriodStart(viewMode, anchorDate);
    final end = _schedulePeriodEnd(viewMode, anchorDate);
    return !normalizedDate.isBefore(start) && !normalizedDate.isAfter(end);
  }

  DateTime _resolveScheduleSelectedDate({
    required _ScheduleViewMode viewMode,
    required DateTime anchorDate,
    required DateTime selectedDate,
  }) {
    final normalizedSelectedDate = _normalizeDate(selectedDate);
    if (_isDateInSchedulePeriod(viewMode, anchorDate, normalizedSelectedDate)) {
      return normalizedSelectedDate;
    }

    final today = _normalizeDate(DateTime.now());
    if (_isDateInSchedulePeriod(viewMode, anchorDate, today)) {
      return today;
    }

    return _schedulePeriodStart(viewMode, anchorDate);
  }

  List<StudentScheduleItemModel> _scheduleItemsForDate(DateTime date) {
    final targetDate = _normalizeDate(date);
    return _scheduleItems.where((item) {
      final occurrence = item.occurrenceStart?.toLocal();
      if (occurrence == null) {
        return false;
      }
      return _isSameDate(occurrence, targetDate);
    }).toList()..sort((left, right) {
      final leftTime =
          left.occurrenceStart?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.occurrenceStart?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return leftTime.compareTo(rightTime);
    });
  }

  bool _hasScheduleOnDate(DateTime date) {
    return _scheduleItemsForDate(date).isNotEmpty;
  }

  List<DateTime> _weekDates() {
    final start = _startOfWeek(_scheduleAnchorDate);
    return List<DateTime>.generate(
      7,
      (index) => _normalizeDate(start.add(Duration(days: index))),
    );
  }

  List<DateTime> _monthDates() {
    final start = _startOfMonth(_scheduleAnchorDate);
    final end = _schedulePeriodEnd(
      _ScheduleViewMode.month,
      _scheduleAnchorDate,
    );
    return List<DateTime>.generate(
      end.day,
      (index) => _normalizeDate(start.add(Duration(days: index))),
    );
  }

  List<DateTime?> _monthCalendarCells() {
    final dates = _monthDates();
    if (dates.isEmpty) {
      return const [];
    }

    final leadingEmptyCount = dates.first.weekday % 7;
    final totalCellCount = ((leadingEmptyCount + dates.length + 6) ~/ 7) * 7;

    return List<DateTime?>.generate(totalCellCount, (index) {
      final dateIndex = index - leadingEmptyCount;
      if (dateIndex < 0 || dateIndex >= dates.length) {
        return null;
      }
      return dates[dateIndex];
    });
  }

  void _selectScheduleDate(DateTime date) {
    setState(() {
      _scheduleSelectedDate = _normalizeDate(date);
    });
  }

  String _formatShortDate(DateTime value) {
    return '${_twoDigits(value.day)}/${_twoDigits(value.month)}';
  }

  String _formatFullDate(DateTime value) {
    return '${_twoDigits(value.day)}/${_twoDigits(value.month)}/${value.year}';
  }

  bool _useNormalizedVietnameseCopy() {
    return true;
  }

  String _weekdayLongLabel(DateTime value) {
    if (_useNormalizedVietnameseCopy()) {
      const labels = [
        'Thứ 2',
        'Thứ 3',
        'Thứ 4',
        'Thứ 5',
        'Thứ 6',
        'Thứ 7',
        'Chủ nhật',
      ];
      return labels[value.weekday - 1];
    }

    const labels = [
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'Chủ nhật',
    ];
    return labels[value.weekday - 1];
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _scheduleRangeLabel() {
    if (_useNormalizedVietnameseCopy()) {
      switch (_scheduleViewMode) {
        case _ScheduleViewMode.day:
          final today = _normalizeDate(DateTime.now());
          if (_isSameDate(_scheduleAnchorDate, today)) {
            return 'Hôm nay, ${_formatFullDate(_scheduleAnchorDate)}';
          }
          return '${_weekdayLongLabel(_scheduleAnchorDate)}, ${_formatFullDate(_scheduleAnchorDate)}';
        case _ScheduleViewMode.week:
          final start = _startOfWeek(_scheduleAnchorDate);
          final end = start.add(const Duration(days: 6));
          return '${_formatShortDate(start)} - ${_formatFullDate(end)}';
        case _ScheduleViewMode.month:
          return 'Tháng ${_scheduleAnchorDate.month}/${_scheduleAnchorDate.year}';
      }
    }

    switch (_scheduleViewMode) {
      case _ScheduleViewMode.day:
        final today = _normalizeDate(DateTime.now());
        if (_isSameDate(_scheduleAnchorDate, today)) {
          return 'Hôm nay, ${_formatFullDate(_scheduleAnchorDate)}';
        }
        return '${_weekdayLongLabel(_scheduleAnchorDate)}, ${_formatFullDate(_scheduleAnchorDate)}';
      case _ScheduleViewMode.week:
        final start = _startOfWeek(_scheduleAnchorDate);
        final end = start.add(const Duration(days: 6));
        return '${_formatShortDate(start)} - ${_formatFullDate(end)}';
      case _ScheduleViewMode.month:
        return 'Tháng ${_scheduleAnchorDate.month}/${_scheduleAnchorDate.year}';
    }
  }

  String _schedulePeriodResetLabel() {
    if (_useNormalizedVietnameseCopy()) {
      switch (_scheduleViewMode) {
        case _ScheduleViewMode.day:
          return 'Hôm nay';
        case _ScheduleViewMode.week:
          return 'Tuần này';
        case _ScheduleViewMode.month:
          return 'Tháng này';
      }
    }

    switch (_scheduleViewMode) {
      case _ScheduleViewMode.day:
        return 'Hôm nay';
      case _ScheduleViewMode.week:
        return 'Tuần này';
      case _ScheduleViewMode.month:
        return 'Tháng này';
    }
  }

  String _scheduleSectionLabel(DateTime value) {
    if (_useNormalizedVietnameseCopy()) {
      final today = _normalizeDate(DateTime.now());
      if (_isSameDate(value, today)) {
        return 'Hôm nay • ${_formatFullDate(value)}';
      }

      final tomorrow = today.add(const Duration(days: 1));
      if (_isSameDate(value, tomorrow)) {
        return 'Ngày mai • ${_formatFullDate(value)}';
      }

      return '${_weekdayLongLabel(value)} • ${_formatFullDate(value)}';
    }

    final today = _normalizeDate(DateTime.now());
    if (_isSameDate(value, today)) {
      return 'Hôm nay • ${_formatFullDate(value)}';
    }

    final tomorrow = today.add(const Duration(days: 1));
    if (_isSameDate(value, tomorrow)) {
      return 'Ngày mai • ${_formatFullDate(value)}';
    }

    return '${_weekdayLongLabel(value)} • ${_formatFullDate(value)}';
  }

  List<_ScheduleGroup> _groupScheduleItemsByDate(
    List<StudentScheduleItemModel> items,
  ) {
    final grouped = <DateTime, List<StudentScheduleItemModel>>{};

    for (final item in items) {
      final source = item.occurrenceStart?.toLocal();
      if (source == null) {
        continue;
      }

      final key = _normalizeDate(source);
      grouped.putIfAbsent(key, () => <StudentScheduleItemModel>[]).add(item);
    }

    final keys = grouped.keys.toList()..sort();
    return keys
        .map(
          (key) => _ScheduleGroup(
            date: key,
            items: [...grouped[key]!]
              ..sort((left, right) {
                final leftTime =
                    left.occurrenceStart?.toLocal() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final rightTime =
                    right.occurrenceStart?.toLocal() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return leftTime.compareTo(rightTime);
              }),
          ),
        )
        .toList();
  }

  String _scheduleStatusLabel(String status) {
    if (_useNormalizedVietnameseCopy()) {
      switch (status) {
        case 'open':
          return 'Đang mở điểm danh';
        case 'checked_in':
          return 'Đã điểm danh';
        case 'closed':
          return 'Đã đóng điểm danh';
        case 'ongoing':
          return 'Đang diễn ra';
        default:
          return 'Chưa mở điểm danh';
      }
    }

    switch (status) {
      case 'open':
        return 'Đang mở điểm danh';
      case 'checked_in':
        return 'Đã điểm danh';
      case 'closed':
        return 'Đã đóng điểm danh';
      case 'ongoing':
        return 'Đang diễn ra';
      default:
        return 'Chưa mở điểm danh';
    }
  }

  Color _scheduleStatusTextColor(String status) {
    switch (status) {
      case 'open':
        return const Color(0xFF0B57D0);
      case 'checked_in':
        return _success;
      case 'closed':
        return const Color(0xFFB54708);
      case 'ongoing':
        return _primaryDark;
      default:
        return _textSecondary;
    }
  }

  Color _scheduleStatusBackgroundColor(String status) {
    switch (status) {
      case 'open':
        return _primarySoft;
      case 'checked_in':
        return const Color(0xFFEAFBF2);
      case 'closed':
        return const Color(0xFFFFF5DB);
      case 'ongoing':
        return const Color(0xFFEAF1FF);
      default:
        return const Color(0xFFF4F7FB);
    }
  }

  String _weekdayShortLabel(DateTime value) {
    switch (value.weekday) {
      case DateTime.monday:
        return 'T2';
      case DateTime.tuesday:
        return 'T3';
      case DateTime.wednesday:
        return 'T4';
      case DateTime.thursday:
        return 'T5';
      case DateTime.friday:
        return 'T6';
      case DateTime.saturday:
        return 'T7';
      default:
        return 'CN';
    }
  }

  Widget _buildScheduleDatePicker() {
    switch (_scheduleViewMode) {
      case _ScheduleViewMode.day:
        return const SizedBox.shrink();
      case _ScheduleViewMode.week:
        return _buildWeekDatePicker();
      case _ScheduleViewMode.month:
        return _buildMonthDatePicker();
    }
  }

  Widget _buildWeekDatePicker() {
    final dates = _weekDates();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: dates.map((date) {
          final isSelected = _isSameDate(date, _scheduleSelectedDate);
          final hasSchedule = _hasScheduleOnDate(date);

          return Expanded(
            child: InkWell(
              onTap: () => _selectScheduleDate(date),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? _primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _weekdayShortLabel(date),
                      style: _font(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: isSelected ? _white : _textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${date.day}',
                      style: _font(
                        size: 15,
                        weight: FontWeight.w800,
                        color: isSelected ? _white : _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: hasSchedule
                            ? (isSelected ? _white : _warning)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMonthDatePicker() {
    const weekdayHeaders = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    final cells = _monthCalendarCells();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: weekdayHeaders
                .map(
                  (label) => Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          label,
                          style: _font(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          ...List<Widget>.generate(cells.length ~/ 7, (rowIndex) {
            final rowCells = cells.skip(rowIndex * 7).take(7).toList();

            return Padding(
              padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 6),
              child: Row(
                children: rowCells.map((date) {
                  if (date == null) {
                    return const Expanded(child: SizedBox(height: 54));
                  }

                  final isSelected = _isSameDate(date, _scheduleSelectedDate);
                  final hasSchedule = _hasScheduleOnDate(date);

                  return Expanded(
                    child: InkWell(
                      onTap: () => _selectScheduleDate(date),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 54,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? _primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${date.day}',
                              style: _font(
                                size: 14,
                                weight: FontWeight.w700,
                                color: isSelected ? _white : _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: hasSchedule
                                    ? (isSelected ? _white : _warning)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  String get _fullName => _homeData?.student.fullName.trim().isNotEmpty == true
      ? _homeData!.student.fullName
      : widget.session.user.fullName;

  String get _studentCode => _homeData?.student.mssv.trim().isNotEmpty == true
      ? _homeData!.student.mssv
      : widget.session.user.code;

  String get _schoolName =>
      _homeData?.student.schoolName.trim().isNotEmpty == true
      ? _homeData!.student.schoolName
      : widget.selectedSchool.name;

  String get _className {
    final className = _homeData?.student.className;
    if (className == null || className.trim().isEmpty) {
      if (_useNormalizedVietnameseCopy()) {
        return widget.session.user.className?.trim().isNotEmpty == true
            ? widget.session.user.className!
            : 'Chưa cập nhật';
      }
      return widget.session.user.className?.trim().isNotEmpty == true
          ? widget.session.user.className!
          : 'Chưa cập nhật';
    }
    return className;
  }

  String get _facultyName {
    final facultyName = _homeData?.student.facultyName;
    if (facultyName == null || facultyName.trim().isEmpty) {
      if (_useNormalizedVietnameseCopy()) {
        return widget.session.user.faculty?.trim().isNotEmpty == true
            ? widget.session.user.faculty!
            : 'Chưa cập nhật';
      }
      return widget.session.user.faculty?.trim().isNotEmpty == true
          ? widget.session.user.faculty!
          : 'Chưa cập nhật';
    }
    return facultyName;
  }

  String get _email {
    final email = _homeData?.student.email;
    if (email != null && email.trim().isNotEmpty) {
      return email;
    }

    final fallback = widget.session.user.email;
    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback;
    }

    return 'Chưa cập nhật';
  }

  int get _unreadAnnouncementCount {
    final summaryUnread = _homeData?.summary.unreadAnnouncements ?? 0;
    if (summaryUnread > 0) {
      return summaryUnread;
    }

    final announcements =
        _homeData?.announcements ?? const <StudentAnnouncementModel>[];
    final explicitUnreadCount = announcements
        .where((item) => item.isRead == false)
        .length;

    if (explicitUnreadCount > 0) {
      return explicitUnreadCount;
    }

    return announcements.where((item) => item.isRead == null).length;
  }

  bool _hasOpenAttendanceSession(StudentScheduleItemModel? item) {
    return item != null && item.canAttend && (item.sessionId ?? 0) > 0;
  }

  void _showSmallMessage(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    final normalizedMessage = _normalizeStudentUiMessage(message);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          normalizedMessage,
          style: _font(size: 13, weight: FontWeight.w600, color: _white),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFB42318) : _textPrimary,
        duration: duration,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String _normalizeStudentUiMessage(String message) {
    return message
        .replaceAll(
          'Buoi hoc nay khong con mo diem danh',
          'Buổi học này không còn mở điểm danh',
        )
        .replaceAll(
          'Hien tai khong co phien diem danh',
          'Hiện tại không có phiên điểm danh',
        )
        .replaceAll(
          'Khong tim thay buoi hoc diem danh',
          'Không tìm thấy buổi học điểm danh',
        )
        .replaceAll(
          'He thong da ghi nhan diem danh cho mon',
          'Hệ thống đã ghi nhận điểm danh cho môn',
        )
        .replaceAll(
          'He thong chua nhan dien duoc khuon mat. Ban co the thu lai khi phien diem danh van mo.',
          'Hệ thống chưa nhận diện được khuôn mặt. Bạn có thể thử lại khi phiên điểm danh vẫn mở.',
        )
        .replaceAll('Diem danh thanh cong', 'Điểm danh thành công')
        .replaceAll(
          'Diem danh that bai, vui long thu lai',
          'Điểm danh thất bại, vui lòng thử lại',
        );
  }

  // ignore: unused_element
  Future<void> _handleAttendanceTap(StudentScheduleItemModel? item) async {
    if (!_hasOpenAttendanceSession(item)) {
      _showSmallMessage('Hiện tại không có phiên điểm danh');
      return;
    }
    final attendanceItem = item!;

    if (_isAttendanceSubmitting) {
      return;
    }

    setState(() {
      _isAttendanceSubmitting = true;
    });

    try {
      final BleEvidence? bleEvidence;
      if (_bleAttendanceEnabled) {
        _showSmallMessage('Đang quét BLE mới trong 5–8 giây...');
        bleEvidence = await _scanAttendanceBle(attendanceItem);
      } else {
        bleEvidence = null;
      }
      if (!mounted) return;

      final Object? verification;
      if (_mobileFaceEnabled) {
        verification = await Navigator.of(context)
            .push<MobileFaceVerificationResult>(
              buildAppPageRoute<MobileFaceVerificationResult>(
                MobileFaceVerificationScreen(
                  accessToken: widget.session.accessToken,
                  attendanceSessionId: attendanceItem.sessionId!,
                  courseCode: attendanceItem.courseCode,
                ),
              ),
            );
      } else {
        verification = await Navigator.of(context).push<FaceVerificationResult>(
          buildAppPageRoute<FaceVerificationResult>(
            FaceVerificationScreen(
              schoolCode: widget.selectedSchool.code,
              mssv: widget.session.user.code,
              accessToken: widget.session.accessToken,
              attendanceSessionId: attendanceItem.sessionId!,
              courseCode: attendanceItem.courseCode,
            ),
          ),
        );
      }

      if (!mounted || verification == null) {
        return;
      }

      _showSmallMessage(
        'Khuôn mặt đã xác minh. Đang kiểm tra vị trí và lưu điểm danh...',
        duration: const Duration(seconds: 20),
      );
      final gpsEvidence = await _gpsEvidenceCollector.captureCurrentPosition();
      if (!mounted) return;

      final result = await _studentHomeApiService.scanAttendance(
        schoolCode: widget.selectedSchool.code,
        mssv: widget.session.user.code,
        sessionId: attendanceItem.sessionId!,
        mobileFaceSessionId: verification is MobileFaceVerificationResult
            ? verification.mobileFaceSessionId
            : null,
        faceSessionId: verification is FaceVerificationResult
            ? verification.faceSessionId
            : null,
        faceSessionToken: verification is FaceVerificationResult
            ? verification.faceSessionToken
            : null,
        faceShard: verification is FaceVerificationResult
            ? verification.faceShard
            : null,
        bleEvidence: bleEvidence,
        faceScore: verification is MobileFaceVerificationResult
            ? verification.similarity
            : verification is FaceVerificationResult &&
                  verification.similarityPercent != null
            ? verification.similarityPercent! / 100
            : null,
        faceVerifiedAt: DateTime.now().toUtc(),
        gpsEvidence: gpsEvidence,
      );

      if (!mounted) return;

      _showSmallMessage(
        result.message,
        isError: !result.isAccepted,
        duration: const Duration(seconds: 5),
      );
      await Future.wait<void>([_loadHomeData(), _loadScheduleData()]);
    } catch (error) {
      if (!mounted) return;

      _showSmallMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAttendanceSubmitting = false;
        });
      }
    }
  }

  String get _initials {
    final parts = _fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'SV';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
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

  String _formatRelativeTime(DateTime? value) {
    if (_useNormalizedVietnameseCopy()) {
      if (value == null) {
        return 'Vừa xong';
      }

      final now = DateTime.now();
      final difference = now.difference(value.toLocal());

      if (difference.inMinutes < 1) {
        return 'Vừa xong';
      }

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} phút trước';
      }

      if (difference.inHours < 24) {
        return '${difference.inHours} giờ trước';
      }

      if (difference.inDays == 1) {
        return 'Hôm qua';
      }

      return '${difference.inDays} ngày trước';
    }

    if (value == null) {
      return 'Vừa xong';
    }

    final now = DateTime.now();
    final difference = now.difference(value.toLocal());

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    }

    if (difference.inDays == 1) {
      return 'Hôm qua';
    }

    return '${difference.inDays} ngày trước';
  }

  String _scheduleBadgeLabel(StudentScheduleItemModel item) {
    if (_useNormalizedVietnameseCopy()) {
      if (item.status == 'ongoing') {
        return 'Đang diễn ra';
      }

      final start = item.occurrenceStart?.toLocal();
      if (start == null) {
        return 'Sắp tới';
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final itemDay = DateTime(start.year, start.month, start.day);
      final difference = itemDay.difference(today).inDays;

      if (difference == 0) {
        return 'Hôm nay';
      }

      if (difference == 1) {
        return 'Ngày mai';
      }

      return 'Sắp tới';
    }

    if (item.status == 'ongoing') {
      return 'Đang diễn ra';
    }

    final start = item.occurrenceStart?.toLocal();
    if (start == null) {
      return 'Sắp tới';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(start.year, start.month, start.day);
    final difference = itemDay.difference(today).inDays;

    if (difference == 0) {
      return 'Hôm nay';
    }

    if (difference == 1) {
      return 'Ngày mai';
    }

    return 'Sắp tới';
  }

  Color _announcementAccent(String type) {
    switch (type) {
      case 'warning':
        return _warning;
      case 'info':
        return _primary;
      default:
        return const Color(0xFFD0D5DD);
    }
  }

  Color _announcementIconBg(String type) {
    switch (type) {
      case 'warning':
        return const Color(0xFFFFF5DB);
      case 'info':
        return const Color(0xFFEAF3FF);
      default:
        return const Color(0xFFF3F5F8);
    }
  }

  IconData _announcementIcon(String type) {
    switch (type) {
      case 'warning':
        return Icons.priority_high_rounded;
      case 'info':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Widget _buildNearbyRoomCard() {
    final evidence = _nearbyRoomEvidence;
    final hasError = _nearbyRoomError != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC9DAFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasError
                  ? Icons.bluetooth_disabled_rounded
                  : Icons.bluetooth_searching_rounded,
              color: hasError ? const Color(0xFFB42318) : _primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isNearbyRoomScanning
                      ? 'Đang tìm phòng gần nhất...'
                      : hasError
                      ? _nearbyRoomError!
                      : evidence == null
                      ? 'Chưa có dữ liệu BLE'
                      : evidence.c6Token != null
                      ? 'Đã tìm thấy thiết bị điểm danh gần đây'
                      : 'Phòng gần nhất: ${evidence.roomId}',
                  style: _font(
                    size: 13,
                    weight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  evidence == null
                      ? 'Chưa có tín hiệu'
                      : 'Tín hiệu BLE • RSSI ${evidence.rssi} dBm',
                  style: _font(
                    size: 11,
                    weight: FontWeight.w600,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quét lại',
            onPressed: _isNearbyRoomScanning ? null : _scanNearbyRoom,
            icon: _isNearbyRoomScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
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
                  Expanded(
                    child: IndexedStack(
                      index: _selectedTabIndex,
                      children: [
                        _buildHomeTab(),
                        _buildScheduleTab(),
                        _buildProfileTab(),
                      ],
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

  Widget _buildHomeTab() {
    if (widget.selectedSchool.code.trim().isNotEmpty) {
      return StudentHomeDashboard(
        homeData: _homeData,
        fullName: _fullName,
        initials: _initials,
        studentCode: _studentCode,
        className: _className,
        schoolName: _schoolName,
        unreadAnnouncementCount: _unreadAnnouncementCount,
        isLoading: _isLoading,
        errorMessage: _errorMessage,
        showRoomSignal: _bleAttendanceEnabled,
        isNearbyRoomScanning: _isNearbyRoomScanning,
        nearbyRoomEvidence: _nearbyRoomEvidence,
        nearbyRoomError: _nearbyRoomError,
        isAttendanceSubmitting: _isAttendanceSubmitting,
        onRefresh: _refreshScheduleTab,
        onRescanNearbyRoom: () {
          unawaited(_scanNearbyRoom());
        },
        onAttend: (item) {
          unawaited(_handleAttendanceTap(item));
        },
        onOpenSchedule: () {
          setState(() {
            _selectedTabIndex = 1;
          });
        },
        onOpenNotifications: _showNotificationsSheet,
        onOpenProfile: () {
          setState(() {
            _selectedTabIndex = 2;
          });
        },
      );
    }

    if (_useNormalizedVietnameseCopy()) {
      final homeData = _homeData;
      final schedules =
          homeData?.upcomingSchedules ?? const <StudentScheduleItemModel>[];
      final firstSchedule = schedules.isNotEmpty ? schedules.first : null;
      final announcementPreview =
          homeData == null
                ? const <StudentAnnouncementModel>[]
                : [...homeData.announcements]
            ..sort((left, right) {
              final leftUnread = left.isRead != true ? 1 : 0;
              final rightUnread = right.isRead != true ? 1 : 0;

              if (leftUnread != rightUnread) {
                return rightUnread.compareTo(leftUnread);
              }

              final leftTime =
                  left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final rightTime =
                  right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return rightTime.compareTo(leftTime);
            });
      final highlightedAnnouncements = announcementPreview.take(2).toList();

      return Column(
        children: [
          _buildTopHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadHomeData,
              child: Container(
                color: _pageBg,
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    if (_isLoading && homeData == null)
                      _buildLoadingCard()
                    else if (_errorMessage != null && homeData == null)
                      _buildErrorCard(_errorMessage!)
                    else ...[
                      _buildNearbyRoomCard(),
                      const SizedBox(height: 14),
                      _buildHomeFocusCard(firstSchedule),
                      const SizedBox(height: 22),
                      _buildSectionTitle('Lối tắt'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDashboardShortcut(
                              title: 'Lịch học',
                              subtitle:
                                  '${homeData?.summary.totalSchedules ?? 0} buổi',
                              icon: Icons.calendar_month_rounded,
                              iconBg: _primarySoft,
                              iconColor: _primary,
                              onTap: () {
                                setState(() {
                                  _selectedTabIndex = 1;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDashboardShortcut(
                              title: 'Thông báo',
                              subtitle: _unreadAnnouncementCount > 0
                                  ? '$_unreadAnnouncementCount chưa đọc'
                                  : 'Đã xem hết',
                              icon: Icons.notifications_active_rounded,
                              iconBg: const Color(0xFFFFF5DB),
                              iconColor: _warning,
                              onTap: _showNotificationsSheet,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDashboardShortcut(
                              title: 'Cá nhân',
                              subtitle: _className,
                              icon: Icons.person_rounded,
                              iconBg: const Color(0xFFEAFBF2),
                              iconColor: _success,
                              onTap: () {
                                setState(() {
                                  _selectedTabIndex = 2;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _buildSectionHeaderWithAction(
                        title: _unreadAnnouncementCount > 0
                            ? 'Thông báo cần đọc'
                            : 'Thông báo mới',
                        actionLabel: 'Xem tất cả',
                        onTap: _showNotificationsSheet,
                      ),
                      const SizedBox(height: 14),
                      if (highlightedAnnouncements.isEmpty)
                        _buildEmptyCard(
                          title: 'Chưa có thông báo mới',
                          body:
                              'Khi nhà trường hoặc giảng viên gửi cập nhật mới, bạn sẽ thấy ở đây.',
                        )
                      else
                        ...highlightedAnnouncements.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildAnnouncementCard(item),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final homeData = _homeData;
    final schedules =
        homeData?.upcomingSchedules ?? const <StudentScheduleItemModel>[];
    final firstSchedule = schedules.isNotEmpty ? schedules.first : null;
    final announcementPreview =
        homeData == null
              ? const <StudentAnnouncementModel>[]
              : [...homeData.announcements]
          ..sort((left, right) {
            final leftUnread = left.isRead != true ? 1 : 0;
            final rightUnread = right.isRead != true ? 1 : 0;

            if (leftUnread != rightUnread) {
              return rightUnread.compareTo(leftUnread);
            }

            final leftTime =
                left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final rightTime =
                right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return rightTime.compareTo(leftTime);
          });
    final highlightedAnnouncements = announcementPreview.take(2).toList();

    return Column(
      children: [
        _buildTopHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadHomeData,
            child: Container(
              color: _pageBg,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  if (_isLoading && homeData == null)
                    _buildLoadingCard()
                  else if (_errorMessage != null && homeData == null)
                    _buildErrorCard(_errorMessage!)
                  else ...[
                    _buildNearbyRoomCard(),
                    const SizedBox(height: 14),
                    _buildHomeFocusCard(firstSchedule),
                    const SizedBox(height: 22),
                    _buildSectionTitle('Lối tắt'),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDashboardShortcut(
                            title: 'Lịch học',
                            subtitle:
                                '${homeData?.summary.totalSchedules ?? 0} buổi',
                            icon: Icons.calendar_month_rounded,
                            iconBg: _primarySoft,
                            iconColor: _primary,
                            onTap: () {
                              setState(() {
                                _selectedTabIndex = 1;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDashboardShortcut(
                            title: 'Thông báo',
                            subtitle: _unreadAnnouncementCount > 0
                                ? '$_unreadAnnouncementCount chưa đọc'
                                : 'Đã xem hết',
                            icon: Icons.notifications_active_rounded,
                            iconBg: const Color(0xFFFFF5DB),
                            iconColor: _warning,
                            onTap: _showNotificationsSheet,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDashboardShortcut(
                            title: 'Cá nhân',
                            subtitle: _className,
                            icon: Icons.person_rounded,
                            iconBg: const Color(0xFFEAFBF2),
                            iconColor: _success,
                            onTap: () {
                              setState(() {
                                _selectedTabIndex = 2;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _buildSectionHeaderWithAction(
                      title: _unreadAnnouncementCount > 0
                          ? 'Thông báo cần đọc'
                          : 'Thông báo mới',
                      actionLabel: 'Xem tất cả',
                      onTap: _showNotificationsSheet,
                    ),
                    const SizedBox(height: 14),
                    if (highlightedAnnouncements.isEmpty)
                      _buildEmptyCard(
                        title: 'Chưa có thông báo mới',
                        body:
                            'Khi nhà trường hoặc giảng viên gửi cập nhật mới, bạn sẽ thấy ở đây.',
                      )
                    else
                      ...highlightedAnnouncements.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildAnnouncementCard(item),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleTab() {
    if (_useNormalizedVietnameseCopy()) {
      final schedules = _scheduleItems;
      final selectedSchedules = _scheduleItemsForDate(_scheduleSelectedDate);
      final groupedSchedules = _groupScheduleItemsByDate(selectedSchedules);
      final openAttendanceCount = schedules
          .where((item) => item.status == 'open')
          .length;
      final checkedInCount = schedules
          .where((item) => item.status == 'checked_in')
          .length;

      return Column(
        children: [
          _buildSimpleHeader(
            title: 'Lịch học',
            subtitle: 'Xem lịch học theo ngày, tuần hoặc tháng',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshScheduleTab,
              child: Container(
                color: _pageBg,
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: '${schedules.length}',
                            subtitle: 'Trong phạm vi xem',
                            icon: Icons.menu_book_rounded,
                            color: const Color(0xFFEAF2FF),
                            iconColor: _primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            title: '$openAttendanceCount',
                            subtitle: 'Đang mở điểm danh',
                            icon: Icons.access_time_filled_rounded,
                            color: const Color(0xFFE8F8F0),
                            iconColor: _success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            title: '$checkedInCount',
                            subtitle: 'Đã điểm danh',
                            icon: Icons.verified_rounded,
                            color: const Color(0xFFEAFBF2),
                            iconColor: _success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildScheduleViewSwitcher(),
                    const SizedBox(height: 12),
                    _buildScheduleNavigator(),
                    if (_scheduleViewMode != _ScheduleViewMode.day) ...[
                      const SizedBox(height: 12),
                      _buildScheduleDatePicker(),
                    ],
                    const SizedBox(height: 18),
                    if (_isScheduleLoading)
                      _buildLoadingCard()
                    else if (_scheduleErrorMessage != null)
                      _buildErrorCard(_scheduleErrorMessage!)
                    else if (schedules.isEmpty)
                      _buildEmptyCard(
                        title: 'Không tìm thấy lịch học',
                        body:
                            'Không có buổi học nào trong phạm vi bạn đang xem. Hãy chuyển sang ngày, tuần hoặc tháng khác.',
                      )
                    else if (selectedSchedules.isEmpty)
                      _buildEmptyCard(
                        title: 'Không có lịch học trong ngày đã chọn',
                        body:
                            'Hãy chọn ngày khác trong tuần hoặc tháng để xem các buổi học đã được xếp lịch.',
                      )
                    else
                      ...groupedSchedules.expand(
                        (group) => [
                          _buildScheduleGroupHeader(group),
                          const SizedBox(height: 12),
                          ...group.items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _buildScheduleListCard(item),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final schedules = _scheduleItems;
    final groupedSchedules = _groupScheduleItemsByDate(schedules);
    final openAttendanceCount = schedules
        .where((item) => item.status == 'open')
        .length;
    final checkedInCount = schedules
        .where((item) => item.status == 'checked_in')
        .length;

    return Column(
      children: [
        _buildSimpleHeader(
          title: 'Lịch học',
          subtitle: 'Xem lịch học theo ngày, tuần hoặc tháng',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshScheduleTab,
            child: Container(
              color: _pageBg,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: '${schedules.length}',
                          subtitle: 'Trong phạm vi xem',
                          icon: Icons.menu_book_rounded,
                          color: const Color(0xFFEAF2FF),
                          iconColor: _primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          title: '$openAttendanceCount',
                          subtitle: 'Đang mở điểm danh',
                          icon: Icons.access_time_filled_rounded,
                          color: const Color(0xFFE8F8F0),
                          iconColor: _success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          title: '$checkedInCount',
                          subtitle: 'Đã điểm danh',
                          icon: Icons.verified_rounded,
                          color: const Color(0xFFEAFBF2),
                          iconColor: _success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildScheduleViewSwitcher(),
                  const SizedBox(height: 12),
                  _buildScheduleNavigator(),
                  const SizedBox(height: 18),
                  if (_isScheduleLoading)
                    _buildLoadingCard()
                  else if (_scheduleErrorMessage != null)
                    _buildErrorCard(_scheduleErrorMessage!)
                  else if (schedules.isEmpty)
                    _buildEmptyCard(
                      title: 'Không tìm thấy lịch học',
                      body:
                          'Không có buổi học nào trong phạm vi bạn đang xem. Hãy chuyển sang ngày, tuần hoặc tháng khác.',
                    )
                  else
                    ...groupedSchedules.expand(
                      (group) => [
                        _buildScheduleGroupHeader(group),
                        const SizedBox(height: 12),
                        ...group.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildScheduleListCard(item),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleViewSwitcher() {
    if (_useNormalizedVietnameseCopy()) {
      const options = [
        (_ScheduleViewMode.day, 'Theo ngày'),
        (_ScheduleViewMode.week, 'Theo tuần'),
        (_ScheduleViewMode.month, 'Theo tháng'),
      ];

      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x07101828),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: options.map((option) {
            final mode = option.$1;
            final label = option.$2;
            final isSelected = mode == _scheduleViewMode;

            return Expanded(
              child: InkWell(
                onTap: isSelected
                    ? null
                    : () => _loadScheduleData(viewMode: mode),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: _font(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: isSelected ? _white : _textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    const options = [
      (_ScheduleViewMode.day, 'Theo ngày'),
      (_ScheduleViewMode.week, 'Theo tuần'),
      (_ScheduleViewMode.month, 'Theo tháng'),
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: options.map((option) {
          final mode = option.$1;
          final label = option.$2;
          final isSelected = mode == _scheduleViewMode;

          return Expanded(
            child: InkWell(
              onTap: isSelected
                  ? null
                  : () => _loadScheduleData(viewMode: mode),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? _primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: _font(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: isSelected ? _white : _textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScheduleNavigator() {
    if (_useNormalizedVietnameseCopy()) {
      final selectedScheduleCount = _scheduleItemsForDate(
        _scheduleSelectedDate,
      ).length;
      final currentReference = _normalizeDate(DateTime.now());
      final isCurrentPeriod = switch (_scheduleViewMode) {
        _ScheduleViewMode.day => _isSameDate(
          _scheduleAnchorDate,
          currentReference,
        ),
        _ScheduleViewMode.week => _isSameDate(
          _startOfWeek(_scheduleAnchorDate),
          _startOfWeek(currentReference),
        ),
        _ScheduleViewMode.month =>
          _scheduleAnchorDate.year == currentReference.year &&
              _scheduleAnchorDate.month == currentReference.month,
      };

      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x07101828),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildScheduleNavigatorButton(
              icon: Icons.chevron_left_rounded,
              onTap: () =>
                  _loadScheduleData(anchorDate: _moveScheduleAnchor(-1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _scheduleRangeLabel(),
                    textAlign: TextAlign.center,
                    style: _font(size: 15, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đang hiển thị $selectedScheduleCount buổi học',
                    textAlign: TextAlign.center,
                    style: _font(
                      size: 12,
                      weight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildScheduleNavigatorButton(
              icon: Icons.chevron_right_rounded,
              onTap: () =>
                  _loadScheduleData(anchorDate: _moveScheduleAnchor(1)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: isCurrentPeriod
                  ? null
                  : () => _loadScheduleData(
                      anchorDate: _normalizeDate(DateTime.now()),
                    ),
              style: TextButton.styleFrom(
                foregroundColor: _primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              child: Text(
                _schedulePeriodResetLabel(),
                style: _font(
                  size: 12,
                  weight: FontWeight.w700,
                  color: isCurrentPeriod ? const Color(0xFF98A2B3) : _primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final currentReference = _normalizeDate(DateTime.now());
    final isCurrentPeriod = switch (_scheduleViewMode) {
      _ScheduleViewMode.day => _isSameDate(
        _scheduleAnchorDate,
        currentReference,
      ),
      _ScheduleViewMode.week => _isSameDate(
        _startOfWeek(_scheduleAnchorDate),
        _startOfWeek(currentReference),
      ),
      _ScheduleViewMode.month =>
        _scheduleAnchorDate.year == currentReference.year &&
            _scheduleAnchorDate.month == currentReference.month,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07101828),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildScheduleNavigatorButton(
            icon: Icons.chevron_left_rounded,
            onTap: () => _loadScheduleData(anchorDate: _moveScheduleAnchor(-1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Text(
                  _scheduleRangeLabel(),
                  textAlign: TextAlign.center,
                  style: _font(size: 15, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Đang hiển thị ${_scheduleItems.length} buổi học',
                  textAlign: TextAlign.center,
                  style: _font(
                    size: 12,
                    weight: FontWeight.w600,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildScheduleNavigatorButton(
            icon: Icons.chevron_right_rounded,
            onTap: () => _loadScheduleData(anchorDate: _moveScheduleAnchor(1)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: isCurrentPeriod
                ? null
                : () => _loadScheduleData(
                    anchorDate: _normalizeDate(DateTime.now()),
                  ),
            style: TextButton.styleFrom(
              foregroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            child: Text(
              _schedulePeriodResetLabel(),
              style: _font(
                size: 12,
                weight: FontWeight.w700,
                color: isCurrentPeriod ? const Color(0xFF98A2B3) : _primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleNavigatorButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: _textPrimary),
      ),
    );
  }

  Widget _buildScheduleGroupHeader(_ScheduleGroup group) {
    if (_useNormalizedVietnameseCopy()) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _scheduleSectionLabel(group.date),
                style: _font(size: 13.5, weight: FontWeight.w800),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _primarySoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${group.items.length} buổi',
                style: _font(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _scheduleSectionLabel(group.date),
              style: _font(size: 13.5, weight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${group.items.length} buổi',
              style: _font(
                size: 11.5,
                weight: FontWeight.w700,
                color: _primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    if (_useNormalizedVietnameseCopy()) {
      return Column(
        children: [
          _buildSimpleHeader(
            title: 'Cá nhân',
            subtitle: 'Chọn chức năng để xem chi tiết',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadHomeData,
              child: Container(
                color: _pageBg,
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  children: [
                    _buildProfileHeroCard(),
                    const SizedBox(height: 18),
                    _buildProfileMenuActionSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildSimpleHeader(
          title: 'Cá nhân',
          subtitle: 'Chọn chức năng để xem chi tiết',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadHomeData,
            child: Container(
              color: _pageBg,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                children: [
                  _buildProfileHeroCard(),
                  const SizedBox(height: 18),
                  _buildProfileMenuActionSection(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileMenuActionSection() {
    if (_useNormalizedVietnameseCopy()) {
      final notificationCount = _homeData?.summary.totalAnnouncements ?? 0;
      final items = [
        _ProfileMenuItemData(
          title: 'Thông tin sinh viên',
          subtitle: 'Xem thông tin cá nhân và dữ liệu học tập',
          icon: Icons.badge_rounded,
          iconBg: _primarySoft,
          iconColor: _primary,
          onTap: _showStudentInfoSheet,
        ),
        _ProfileMenuItemData(
          title: 'Đổi mật khẩu',
          subtitle: 'Hướng dẫn đổi mật khẩu từ màn đăng nhập',
          icon: Icons.lock_reset_rounded,
          iconBg: const Color(0xFFEAFBF2),
          iconColor: _success,
          onTap: _showChangePasswordSheet,
        ),
        _ProfileMenuItemData(
          title: 'Điều khoản và chính sách sử dụng',
          subtitle: 'Xem quy định và cách ứng dụng xử lý dữ liệu',
          icon: Icons.gavel_rounded,
          iconBg: const Color(0xFFFFF5DB),
          iconColor: _warning,
          onTap: _showPolicySheet,
        ),
        _ProfileMenuItemData(
          title: 'Góp ý cho ứng dụng',
          subtitle: 'Gửi nhận xét để cải thiện trải nghiệm',
          icon: Icons.chat_bubble_outline_rounded,
          iconBg: const Color(0xFFF3E8FF),
          iconColor: const Color(0xFF7A5AF8),
          onTap: _showFeedbackSheet,
        ),
        _ProfileMenuItemData(
          title: 'Thông báo',
          subtitle: notificationCount > 0
              ? '$notificationCount thông báo mới từ hệ thống'
              : 'Xem danh sách thông báo hiện có',
          icon: Icons.notifications_active_rounded,
          iconBg: const Color(0xFFFFF5DB),
          iconColor: _warning,
          badgeLabel: notificationCount > 0 ? '$notificationCount' : null,
          onTap: _showNotificationsSheet,
        ),
        _ProfileMenuItemData(
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
          color: _cardBg,
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
                          child: Icon(
                            item.icon,
                            color: item.iconColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: _font(
                                  size: 13.5,
                                  weight: FontWeight.w700,
                                  color: item.isDestructive
                                      ? const Color(0xFFB42318)
                                      : _textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.subtitle,
                                style: _font(
                                  size: 11.5,
                                  weight: FontWeight.w500,
                                  color: item.isDestructive
                                      ? const Color(0xFFB42318)
                                      : _textSecondary,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.badgeLabel != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE4E8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.badgeLabel!,
                              style: _font(
                                size: 10.5,
                                weight: FontWeight.w700,
                                color: const Color(0xFFD92D20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
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
                  const Divider(height: 1, indent: 68, endIndent: 14),
              ],
            );
          }),
        ),
      );
    }

    final notificationCount = _homeData?.summary.totalAnnouncements ?? 0;
    final items = [
      _ProfileMenuItemData(
        title: 'Thông tin sinh viên',
        subtitle: 'Xem thông tin cá nhân và dữ liệu học tập',
        icon: Icons.badge_rounded,
        iconBg: _primarySoft,
        iconColor: _primary,
        onTap: _showStudentInfoSheet,
      ),
      _ProfileMenuItemData(
        title: 'Đổi mật khẩu',
        subtitle: 'Hướng dẫn đổi mật khẩu từ màn đăng nhập',
        icon: Icons.lock_reset_rounded,
        iconBg: const Color(0xFFEAFBF2),
        iconColor: _success,
        onTap: _showChangePasswordSheet,
      ),
      _ProfileMenuItemData(
        title: 'Điều khoản và chính sách sử dụng',
        subtitle: 'Xem quy định và cách ứng dụng xử lý dữ liệu',
        icon: Icons.gavel_rounded,
        iconBg: const Color(0xFFFFF5DB),
        iconColor: _warning,
        onTap: _showPolicySheet,
      ),
      _ProfileMenuItemData(
        title: 'Góp ý cho ứng dụng',
        subtitle: 'Gửi nhận xét để cải thiện trải nghiệm',
        icon: Icons.chat_bubble_outline_rounded,
        iconBg: const Color(0xFFF3E8FF),
        iconColor: const Color(0xFF7A5AF8),
        onTap: _showFeedbackSheet,
      ),
      _ProfileMenuItemData(
        title: 'Thông báo',
        subtitle: notificationCount > 0
            ? '$notificationCount thông báo mới từ hệ thống'
            : 'Xem danh sách thông báo hiện có',
        icon: Icons.notifications_active_rounded,
        iconBg: const Color(0xFFFFF5DB),
        iconColor: _warning,
        badgeLabel: notificationCount > 0 ? '$notificationCount' : null,
        onTap: _showNotificationsSheet,
      ),
      _ProfileMenuItemData(
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
        color: _cardBg,
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
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;

          return Column(
            children: [
              _buildProfileMenuItem(item),
              if (!isLast)
                const Divider(
                  height: 1,
                  indent: 76,
                  endIndent: 18,
                  color: Color(0xFFEFF2F6),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildProfileMenuItem(_ProfileMenuItemData item) {
    final titleColor = item.isDestructive
        ? const Color(0xFFB42318)
        : _textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: item.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: _font(
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: _font(
                        size: 11.5,
                        weight: FontWeight.w500,
                        color: _textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.badgeLabel != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.badgeLabel!,
                    style: _font(
                      size: 10.5,
                      weight: FontWeight.w800,
                      color: _primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
    );
  }

  Future<void> _showStudentInfoSheet() async {
    if (_useNormalizedVietnameseCopy()) {
      await _showProfileBottomSheet(
        title: 'Thông tin sinh viên',
        child: Column(
          children: [
            _buildProfileInfoCard(
              title: 'Hồ sơ tài khoản',
              rows: [
                _ProfileRowData(label: 'MSSV', value: _studentCode),
                _ProfileRowData(label: 'Họ tên', value: _fullName),
                _ProfileRowData(label: 'Trường', value: _schoolName),
                _ProfileRowData(label: 'Lớp', value: _className),
                _ProfileRowData(label: 'Khoa', value: _facultyName),
                _ProfileRowData(
                  label: 'Ngày sinh',
                  value: _formatDate(widget.session.user.dateOfBirth),
                ),
                _ProfileRowData(label: 'Email', value: _email),
              ],
            ),
            const SizedBox(height: 14),
            _buildProfileInfoCard(
              title: 'Dữ liệu học tập',
              rows: [
                _ProfileRowData(
                  label: 'Lịch học',
                  value: '${_homeData?.summary.totalSchedules ?? 0} bản ghi',
                ),
                _ProfileRowData(
                  label: 'Thông báo',
                  value:
                      '${_homeData?.summary.totalAnnouncements ?? 0} bản ghi',
                ),
                _ProfileRowData(
                  label: 'Nguồn',
                  value: 'Tenant DB ${widget.selectedSchool.code}',
                ),
              ],
            ),
          ],
        ),
      );
      return;
    }

    await _showProfileBottomSheet(
      title: 'Thông tin sinh viên',
      child: Column(
        children: [
          _buildProfileInfoCard(
            title: 'Hồ sơ tài khoản',
            rows: [
              _ProfileRowData(label: 'MSSV', value: _studentCode),
              _ProfileRowData(label: 'Họ tên', value: _fullName),
              _ProfileRowData(label: 'Trường', value: _schoolName),
              _ProfileRowData(label: 'Lớp', value: _className),
              _ProfileRowData(label: 'Khoa', value: _facultyName),
              _ProfileRowData(
                label: 'Ngày sinh',
                value: _formatDate(widget.session.user.dateOfBirth),
              ),
              _ProfileRowData(label: 'Email', value: _email),
            ],
          ),
          const SizedBox(height: 14),
          _buildProfileInfoCard(
            title: 'Dữ liệu học tập',
            rows: [
              _ProfileRowData(
                label: 'Lịch học',
                value: '${_homeData?.summary.totalSchedules ?? 0} bản ghi',
              ),
              _ProfileRowData(
                label: 'Thông báo',
                value: '${_homeData?.summary.totalAnnouncements ?? 0} bản ghi',
              ),
              _ProfileRowData(
                label: 'Nguồn',
                value: 'Tenant DB ${widget.selectedSchool.code}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordSheet() async {
    if (_useNormalizedVietnameseCopy()) {
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
                  'Hệ thống hiện chưa có API đổi mật khẩu trực tiếp trong tab Cá nhân. Nếu cần đổi mật khẩu, bạn hãy đăng xuất và chọn Quên mật khẩu ở màn đăng nhập.',
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
                  style: _font(
                    size: 14,
                    weight: FontWeight.w700,
                    color: _white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

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
                'Hệ thống hiện chưa có API đổi mật khẩu trực tiếp trong tab Cá nhân. Nếu cần đổi mật khẩu, bạn hãy đăng xuất và chọn Quên mật khẩu ở màn đăng nhập.',
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

  Future<void> _showPolicySheet() async {
    if (_useNormalizedVietnameseCopy()) {
      await _showProfileBottomSheet(
        title: 'Điều khoản và chính sách sử dụng',
        child: Column(
          children: [
            _buildSheetNoticeCard(
              icon: Icons.verified_user_rounded,
              iconColor: _primary,
              iconBg: _primarySoft,
              title: 'Sử dụng đúng mục đích',
              body:
                  'Ứng dụng chỉ phục vụ tra cứu thông tin học tập và học vụ cho tài khoản được nhà trường cấp.',
            ),
            const SizedBox(height: 12),
            _buildSheetNoticeCard(
              icon: Icons.shield_outlined,
              iconColor: _success,
              iconBg: const Color(0xFFEAFBF2),
              title: 'Bảo mật tài khoản',
              body:
                  'Bạn tự chịu trách nhiệm bảo mật mật khẩu, không chia sẻ tài khoản và nên đăng xuất khi cho mượn thiết bị.',
            ),
            const SizedBox(height: 12),
            _buildSheetNoticeCard(
              icon: Icons.data_usage_rounded,
              iconColor: _warning,
              iconBg: const Color(0xFFFFF5DB),
              title: 'Dữ liệu hiển thị',
              body:
                  'Thông tin hồ sơ, lịch học và thông báo được đồng bộ từ hệ thống backend và tenant database của trường.',
            ),
          ],
        ),
      );
      return;
    }

    await _showProfileBottomSheet(
      title: 'Điều khoản và chính sách sử dụng',
      child: Column(
        children: [
          _buildSheetNoticeCard(
            icon: Icons.verified_user_rounded,
            iconColor: _primary,
            iconBg: _primarySoft,
            title: 'Sử dụng đúng mục đích',
            body:
                'Ứng dụng chỉ phục vụ tra cứu thông tin học tập và học vụ cho tài khoản được nhà trường cấp.',
          ),
          const SizedBox(height: 12),
          _buildSheetNoticeCard(
            icon: Icons.shield_outlined,
            iconColor: _success,
            iconBg: const Color(0xFFEAFBF2),
            title: 'Bảo mật tài khoản',
            body:
                'Bạn tự chịu trách nhiệm bảo mật mật khẩu, không chia sẻ tài khoản và nên đăng xuất khi cho mượn thiết bị.',
          ),
          const SizedBox(height: 12),
          _buildSheetNoticeCard(
            icon: Icons.data_usage_rounded,
            iconColor: _warning,
            iconBg: const Color(0xFFFFF5DB),
            title: 'Dữ liệu hiển thị',
            body:
                'Thông tin hồ sơ, lịch học và thông báo được đồng bộ từ hệ thống backend và tenant database của trường.',
          ),
        ],
      ),
    );
  }

  Future<void> _showFeedbackSheet() async {
    if (_useNormalizedVietnameseCopy()) {
      await _showProfileBottomSheet(
        title: 'Góp ý cho ứng dụng',
        isScrollControlled: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nếu bạn gặp lỗi hoặc muốn đề xuất tính năng mới, hãy nhập nội dung bên dưới.',
              style: _font(
                size: 13,
                weight: FontWeight.w500,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _feedbackController,
                maxLines: 5,
                minLines: 4,
                style: _font(
                  size: 14,
                  weight: FontWeight.w600,
                  color: _textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Nhập góp ý của bạn...',
                  hintStyle: _font(
                    size: 14,
                    weight: FontWeight.w500,
                    color: const Color(0xFF98A2B3),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildSheetNoticeCard(
              icon: Icons.info_outline_rounded,
              iconColor: _warning,
              iconBg: const Color(0xFFFFF5DB),
              title: 'Trạng thái hiện tại',
              body: 'Chức năng gửi góp ý chưa được kết nối với máy chủ.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final feedback = _feedbackController.text.trim();
                  if (feedback.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng nhập nội dung góp ý'),
                      ),
                    );
                    return;
                  }

                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Chưa thể gửi phản hồi. Nội dung của bạn vẫn được giữ lại.',
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Gửi góp ý',
                  style: _font(
                    size: 14,
                    weight: FontWeight.w700,
                    color: _white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    await _showProfileBottomSheet(
      title: 'Góp ý cho ứng dụng',
      isScrollControlled: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nếu bạn gặp lỗi hoặc muốn đề xuất tính năng mới, hãy nhập nội dung bên dưới.',
            style: _font(
              size: 13,
              weight: FontWeight.w500,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              controller: _feedbackController,
              maxLines: 5,
              minLines: 4,
              style: _font(
                size: 14,
                weight: FontWeight.w600,
                color: _textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Nhập góp ý của bạn...',
                hintStyle: _font(
                  size: 14,
                  weight: FontWeight.w500,
                  color: const Color(0xFF98A2B3),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildSheetNoticeCard(
            icon: Icons.info_outline_rounded,
            iconColor: _warning,
            iconBg: const Color(0xFFFFF5DB),
            title: 'Trạng thái hiện tại',
            body: 'Chức năng gửi góp ý chưa được kết nối với máy chủ.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final feedback = _feedbackController.text.trim();
                if (feedback.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập nội dung góp ý'),
                    ),
                  );
                  return;
                }

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Chưa thể gửi phản hồi. Nội dung của bạn vẫn được giữ lại.',
                    ),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Gửi góp ý',
                style: _font(size: 14, weight: FontWeight.w700, color: _white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNotificationsSheet() async {
    final announcements = _homeData?.announcements ?? const [];

    await _showProfileBottomSheet(
      title: 'Thông báo',
      child: announcements.isEmpty
          ? _buildEmptyCard(
              title: 'Chưa có thông báo',
              body:
                  'Khi nhà trường hoặc giảng viên phát thông báo mới, bạn sẽ thấy ở đây.',
            )
          : Column(
              children: announcements
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildAnnouncementCard(item),
                    ),
                  )
                  .toList(),
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
        color: _cardBg,
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

  Widget _buildTopHeader() {
    if (_useNormalizedVietnameseCopy()) {
      final currentSchedules = _homeData?.summary.currentSchedules ?? 0;
      final headerStatus = currentSchedules > 0
          ? '$currentSchedules buổi đang diễn ra'
          : _unreadAnnouncementCount > 0
          ? '$_unreadAnnouncementCount thông báo chưa đọc'
          : 'Hôm nay chưa có việc cần xử lý gấp';

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF165DFF), Color(0xFF4D97FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0x33FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22165DFF),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x3DFFFFFF)),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: _font(size: 18, weight: FontWeight.w800, color: _white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x26FFFFFF)),
                    ),
                    child: Text(
                      'Cổng sinh viên',
                      style: _font(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 19,
                      weight: FontWeight.w800,
                      color: _white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _schoolName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: const Color(0xD9FFFFFF),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headerStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 12,
                      weight: FontWeight.w600,
                      color: const Color(0xF2FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildHeaderMetricChip('MSSV', _studentCode),
                      _buildHeaderMetricChip('Lớp', _className),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildNotificationActionButton(
              iconColor: _white,
              backgroundColor: const Color(0x22FFFFFF),
            ),
          ],
        ),
      );
    }

    if (_useNormalizedVietnameseCopy()) {
      final currentSchedules = _homeData?.summary.currentSchedules ?? 0;
      final headerStatus = currentSchedules > 0
          ? '$currentSchedules buổi đang diễn ra'
          : _unreadAnnouncementCount > 0
          ? '$_unreadAnnouncementCount thông báo chưa đọc'
          : 'Hôm nay chưa có việc cần xử lý gấp';

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A101828),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _primarySoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD9E6FF)),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: _font(
                  size: 18,
                  weight: FontWeight.w800,
                  color: _primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Cổng sinh viên',
                      style: _font(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: _primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(size: 19, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _schoolName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: _textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headerStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 12,
                      weight: FontWeight.w600,
                      color: _primaryDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildHeaderMetricChip('MSSV', _studentCode),
                      _buildHeaderMetricChip('Lớp', _className),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildNotificationActionButton(
              iconColor: _primary,
              backgroundColor: _primarySoft,
            ),
          ],
        ),
      );
    }

    final currentSchedules = _homeData?.summary.currentSchedules ?? 0;
    final headerStatus = currentSchedules > 0
        ? '$currentSchedules buổi đang diễn ra'
        : _unreadAnnouncementCount > 0
        ? '$_unreadAnnouncementCount thông báo chưa đọc'
        : 'Hôm nay chưa có việc cần xử lý gấp';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _primarySoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD9E6FF)),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: _font(size: 18, weight: FontWeight.w800, color: _primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Cổng sinh viên',
                    style: _font(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: _primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _schoolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headerStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 12,
                    weight: FontWeight.w600,
                    color: _primaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHeaderMetricChip('MSSV', _studentCode),
                    _buildHeaderMetricChip('Lớp', _className),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildNotificationActionButton(
            iconColor: _primary,
            backgroundColor: _primarySoft,
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleHeader({required String title, required String subtitle}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09101828),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _font(
                    size: 24,
                    weight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: _font(
                    size: 13.5,
                    weight: FontWeight.w500,
                    color: _textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildNotificationActionButton(
            iconColor: _primary,
            backgroundColor: _primarySoft,
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    AuthSessionController.instance.clear();
    await _authPersistenceService.clearSavedSessionKeepingContext(
      school: widget.selectedSchool,
      role: widget.session.role,
      identifier: widget.session.user.code,
    );
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      buildAppPageRoute(
        LoginScreen(
          selectedSchool: widget.selectedSchool,
          selectedRole: widget.session.role,
          initialIdentifier: widget.session.user.code,
          initialRememberSession: false,
          allowBackNavigation: true,
        ),
      ),
      (route) => false,
    );
  }

  // ignore: unused_element
  void _showNotificationsSheetLegacy() {
    final announcements =
        _homeData?.announcements ?? const <StudentAnnouncementModel>[];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Container(
              decoration: const BoxDecoration(
                color: _pageBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Thông báo',
                            style: _font(size: 18, weight: FontWeight.w800),
                          ),
                        ),
                        if (_unreadAnnouncementCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE4E8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$_unreadAnnouncementCount mới',
                              style: _font(
                                size: 12,
                                weight: FontWeight.w700,
                                color: const Color(0xFFD92D20),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: announcements.isEmpty
                        ? ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            children: [
                              _buildEmptyCard(
                                title: 'Hiện tại không có thông báo',
                                body:
                                    'Khi nhà trường hoặc giảng viên phát thông báo mới, bạn sẽ thấy ở đây.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: announcements.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              return _buildAnnouncementCard(
                                announcements[index],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color iconColor,
    Color backgroundColor = const Color(0xFFF5F7FB),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: iconColor),
      ),
    );
  }

  Widget _buildNotificationActionButton({
    Color iconColor = _white,
    Color backgroundColor = const Color(0x18FFFFFF),
    Color badgeBorderColor = _white,
  }) {
    final hasUnreadAnnouncements = _unreadAnnouncementCount > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildHeaderActionButton(
          icon: Icons.notifications_none_rounded,
          onTap: _showNotificationsSheet,
          iconColor: iconColor,
          backgroundColor: backgroundColor,
        ),
        if (hasUnreadAnnouncements)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 12,
              height: 12,
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

  Widget _buildHomeFocusCard(StudentScheduleItemModel? firstSchedule) {
    final currentSchedules = _homeData?.summary.currentSchedules ?? 0;
    final hasUrgentClass =
        currentSchedules > 0 || firstSchedule?.status == 'open';
    final hasOpenAttendanceSession = _hasOpenAttendanceSession(firstSchedule);
    final toneColor = hasUrgentClass ? _success : _primary;
    final toneBackground = hasUrgentClass
        ? const Color(0xFFEAFBF2)
        : _primarySoft;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
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
                  color: toneBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasUrgentClass ? 'Ưu tiên lúc này' : 'Chuẩn bị tiếp theo',
                  style: _font(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: toneColor,
                  ),
                ),
              ),
              const Spacer(),
              if (_unreadAnnouncementCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_unreadAnnouncementCount mới',
                    style: _font(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: const Color(0xFFD92D20),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (firstSchedule != null) ...[
            Text(
              firstSchedule.courseName,
              style: _font(size: 18, weight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${firstSchedule.startTime} - ${firstSchedule.endTime} | ${firstSchedule.room}',
              style: _font(
                size: 13,
                weight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'GV. ${firstSchedule.lecturerName}',
              style: _font(
                size: 13,
                weight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPill(
                  icon: Icons.calendar_today_rounded,
                  label:
                      '${firstSchedule.weekdayLabel} / ${firstSchedule.dayLabel}',
                ),
                _buildPill(
                  icon: Icons.badge_rounded,
                  label: firstSchedule.courseCode,
                ),
                _buildPill(
                  icon: hasUrgentClass
                      ? Icons.bolt_rounded
                      : Icons.hourglass_top_rounded,
                  label: hasUrgentClass ? 'Đang diễn ra' : 'Sắp tới',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _showNotificationsSheet,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textPrimary,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Thông báo',
                      style: _font(size: 13.5, weight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _handleAttendanceTap(firstSchedule),
                    style: FilledButton.styleFrom(
                      backgroundColor: hasOpenAttendanceSession
                          ? _success
                          : const Color(0xFFD0D5DD),
                      foregroundColor: hasOpenAttendanceSession
                          ? _white
                          : const Color(0xFF667085),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isAttendanceSubmitting && hasOpenAttendanceSession
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(_white),
                            ),
                          )
                        : Text(
                            'Điểm danh',
                            style: _font(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: hasOpenAttendanceSession
                                  ? _white
                                  : const Color(0xFF667085),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Chưa có buổi học nào sắp tới',
              style: _font(size: 18, weight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Bạn có thể kiểm tra thông báo mới hoặc đợi khi có giảng viên mở phiên điểm danh.',
              style: _font(
                size: 13,
                weight: FontWeight.w500,
                color: _textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _showNotificationsSheet,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textPrimary,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Thông báo',
                      style: _font(size: 13.5, weight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _handleAttendanceTap(null),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD0D5DD),
                      foregroundColor: const Color(0xFF667085),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Điểm danh',
                      style: _font(
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: const Color(0xFF667085),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text(
        '$label: $value',
        style: _font(size: 11, weight: FontWeight.w700, color: _white),
      ),
    );
  }

  Widget _buildProfileHeroCard() {
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
              _initials,
              style: _font(size: 22, weight: FontWeight.w800, color: _white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName,
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
                  'MSSV: $_studentCode',
                  style: _font(
                    size: 11,
                    weight: FontWeight.w600,
                    color: const Color(0xD9FFFFFF),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _schoolName,
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

  // ignore: unused_element
  Widget _buildProfileMenuSectionLegacy() {
    return Column(
      children: [
        _buildProfileInfoCard(
          title: 'Thông tin sinh viên',
          rows: [
            _ProfileRowData(label: 'MSSV', value: _studentCode),
            _ProfileRowData(label: 'Lớp', value: _className),
            _ProfileRowData(label: 'Khoa', value: _facultyName),
            _ProfileRowData(
              label: 'Ngày sinh',
              value: _formatDate(widget.session.user.dateOfBirth),
            ),
            _ProfileRowData(label: 'Email', value: _email),
          ],
        ),
        const SizedBox(height: 14),
        _buildProfileInfoCard(
          title: 'Dữ liệu hệ thống',
          rows: [
            _ProfileRowData(
              label: 'Lịch học',
              value: '${_homeData?.summary.totalSchedules ?? 0} bản ghi',
            ),
            _ProfileRowData(
              label: 'Thông báo',
              value: '${_homeData?.summary.totalAnnouncements ?? 0} bản ghi',
            ),
            _ProfileRowData(
              label: 'Chưa đọc',
              value: '$_unreadAnnouncementCount thông báo',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardShortcut({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
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
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: _font(size: 13.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: _font(
                  size: 11,
                  weight: FontWeight.w600,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildHeroScheduleCard(StudentScheduleItemModel item) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF165DFF), Color(0xFF5AA1FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22165DFF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _scheduleBadgeLabel(item),
                      style: _font(
                        size: 11,
                        weight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.courseName,
                    style: _font(
                      size: 24,
                      weight: FontWeight.w800,
                      color: _white,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${item.room} | GV. ${item.lecturerName}',
                    style: _font(
                      size: 14,
                      weight: FontWeight.w500,
                      color: const Color(0xDEFFFFFF),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildHeroPill(
                        Icons.access_time_filled_rounded,
                        '${item.startTime} - ${item.endTime}',
                      ),
                      const SizedBox(width: 10),
                      _buildHeroPill(Icons.badge_rounded, item.courseCode),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0x15FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                children: [
                  Text(
                    item.weekdayLabel,
                    style: _font(
                      size: 11,
                      weight: FontWeight.w700,
                      color: const Color(0xDEFFFFFF),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.dayLabel,
                    style: _font(
                      size: 31,
                      weight: FontWeight.w800,
                      color: _white,
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

  Widget _buildHeroPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1CFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _white),
          const SizedBox(width: 6),
          Text(
            label,
            style: _font(size: 12.5, weight: FontWeight.w700, color: _white),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleListCard(StudentScheduleItemModel item) {
    final statusTextColor = _scheduleStatusTextColor(item.status);
    final statusBackgroundColor = _scheduleStatusBackgroundColor(item.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.menu_book_rounded,
              color: _primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.courseName,
                        style: _font(size: 16, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackgroundColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _scheduleStatusLabel(item.status),
                        style: _font(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: statusTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${item.room} | GV. ${item.lecturerName}',
                  style: _font(
                    size: 13,
                    weight: FontWeight.w500,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPill(
                      icon: Icons.access_time_filled_rounded,
                      label: '${item.startTime} - ${item.endTime}',
                    ),
                    _buildPill(
                      icon: Icons.calendar_today_rounded,
                      label: '${item.weekdayLabel} / ${item.dayLabel}',
                    ),
                    _buildPill(
                      icon: Icons.badge_rounded,
                      label: item.courseCode,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(StudentAnnouncementModel item) {
    final accentColor = _announcementAccent(item.type);

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _announcementIconBg(item.type),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _announcementIcon(item.type),
                        color: accentColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _normalizeStudentUiMessage(item.title),
                            style: _font(size: 14.5, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _normalizeStudentUiMessage(item.body),
                            style: _font(
                              size: 12.5,
                              weight: FontWeight.w500,
                              color: _textSecondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatRelativeTime(item.createdAt),
                            style: _font(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: const Color(0xFF9AA4B2),
                            ),
                          ),
                        ],
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

  Widget _buildStatCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 14),
          Text(title, style: _font(size: 20, weight: FontWeight.w800)),
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

  Widget _buildProfileInfoCard({
    required String title,
    required List<_ProfileRowData> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
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
                    width: 84,
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

  Widget _buildBottomNavigation() {
    if (_useNormalizedVietnameseCopy()) {
      const items = [
        _BottomNavItem(
          label: 'Trang chủ',
          icon: Icons.home_rounded,
          selectedIcon: Icons.home_filled,
        ),
        _BottomNavItem(
          label: 'Lịch học',
          icon: Icons.calendar_today_rounded,
          selectedIcon: Icons.calendar_month_rounded,
        ),
        _BottomNavItem(
          label: 'Cá nhân',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
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
              final isSelected = index == _selectedTabIndex;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? _primarySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          size: 22,
                          color: isSelected
                              ? _primaryDark
                              : const Color(0xFF98A2B3),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.label,
                          style: _font(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: isSelected
                                ? _primaryDark
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

    const items = [
      _BottomNavItem(
        label: 'Trang chủ',
        icon: Icons.home_rounded,
        selectedIcon: Icons.home_filled,
      ),
      _BottomNavItem(
        label: 'Lịch học',
        icon: Icons.calendar_today_rounded,
        selectedIcon: Icons.calendar_month_rounded,
      ),
      _BottomNavItem(
        label: 'Cá nhân',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
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
            final isSelected = index == _selectedTabIndex;

            return Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                },
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? _primarySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        size: 22,
                        color: isSelected
                            ? _primaryDark
                            : const Color(0xFF98A2B3),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.label,
                        style: _font(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: isSelected
                              ? _primaryDark
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

  Widget _buildSectionTitle(String title) {
    return Text(title, style: _font(size: 21, weight: FontWeight.w800));
  }

  Widget _buildSectionHeaderWithAction({
    required String title,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: _font(size: 21, weight: FontWeight.w800)),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              actionLabel,
              style: _font(size: 13, weight: FontWeight.w700, color: _primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF667085)),
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

  Widget _buildLoadingCard() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: _cardBg,
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
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }

  Widget _buildErrorCard(String message) {
    if (_useNormalizedVietnameseCopy()) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEAEA),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFF3C6C3)),
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
            Text(
              'Không tải được dữ liệu',
              style: _font(
                size: 16,
                weight: FontWeight.w800,
                color: const Color(0xFFB42318),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: _font(
                size: 13.5,
                weight: FontWeight.w600,
                color: const Color(0xFFB42318),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _loadHomeData,
              child: Text(
                'Thử lại',
                style: _font(
                  size: 13,
                  weight: FontWeight.w700,
                  color: const Color(0xFFB42318),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEAEA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF3C6C3)),
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
          Text(
            'Không tải được dữ liệu',
            style: _font(
              size: 16,
              weight: FontWeight.w800,
              color: const Color(0xFFB42318),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: _font(
              size: 13.5,
              weight: FontWeight.w600,
              color: const Color(0xFFB42318),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _loadHomeData,
            child: Text(
              'Thử lại',
              style: _font(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFFB42318),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard({required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
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
          const SizedBox(height: 8),
          Text(
            body,
            style: _font(
              size: 13.5,
              weight: FontWeight.w500,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleGroup {
  final DateTime date;
  final List<StudentScheduleItemModel> items;

  const _ScheduleGroup({required this.date, required this.items});
}

class _BottomNavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _ProfileMenuItemData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String? badgeLabel;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ProfileMenuItemData({
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

class _ProfileRowData {
  final String label;
  final String value;

  const _ProfileRowData({required this.label, required this.value});
}
