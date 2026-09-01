import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/ble/ble_models.dart';
import '../../../shared/models/student_home_model.dart';

class StudentHomeDashboard extends StatelessWidget {
  const StudentHomeDashboard({
    super.key,
    required this.homeData,
    required this.fullName,
    required this.initials,
    required this.studentCode,
    required this.className,
    required this.schoolName,
    required this.unreadAnnouncementCount,
    required this.isLoading,
    required this.errorMessage,
    required this.isNearbyRoomScanning,
    required this.nearbyRoomEvidence,
    required this.nearbyRoomError,
    required this.isAttendanceSubmitting,
    required this.onRefresh,
    required this.onRescanNearbyRoom,
    required this.onAttend,
    required this.onOpenSchedule,
    required this.onOpenNotifications,
    required this.onOpenProfile,
  });

  static const Color _pageBackground = Color(0xFFF3F6FB);
  static const Color _surface = Colors.white;
  static const Color _ink = Color(0xFF12233F);
  static const Color _muted = Color(0xFF667085);
  static const Color _line = Color(0xFFE4EAF2);
  static const Color _navy = Color(0xFF102A56);
  static const Color _blue = Color(0xFF175CD3);
  static const Color _blueSoft = Color(0xFFEAF2FF);
  static const Color _mint = Color(0xFF12A47A);
  static const Color _mintSoft = Color(0xFFE7F8F2);
  static const Color _amber = Color(0xFFD98C10);
  static const Color _amberSoft = Color(0xFFFFF4DE);

  final StudentHomeModel? homeData;
  final String fullName;
  final String initials;
  final String studentCode;
  final String className;
  final String schoolName;
  final int unreadAnnouncementCount;
  final bool isLoading;
  final String? errorMessage;
  final bool isNearbyRoomScanning;
  final BleEvidence? nearbyRoomEvidence;
  final String? nearbyRoomError;
  final bool isAttendanceSubmitting;
  final Future<void> Function() onRefresh;
  final VoidCallback onRescanNearbyRoom;
  final ValueChanged<StudentScheduleItemModel> onAttend;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;

  TextStyle _font({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
    double? height,
  }) {
    return GoogleFonts.beVietnamPro(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedules =
        homeData?.upcomingSchedules ?? const <StudentScheduleItemModel>[];
    final focusSchedule = schedules.isEmpty ? null : schedules.first;
    final announcements = _sortedAnnouncements(
      homeData?.announcements ?? const [],
    );

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: _blue,
            child: ColoredBox(
              color: _pageBackground,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  if (errorMessage != null && homeData != null) ...[
                    _buildInlineError(errorMessage!),
                    const SizedBox(height: 14),
                  ],
                  if (isLoading && homeData == null)
                    _buildLoadingState()
                  else if (errorMessage != null && homeData == null)
                    _buildEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Chưa tải được dữ liệu',
                      body: errorMessage!,
                      actionLabel: 'Thử lại',
                      onAction: () => onRefresh(),
                    )
                  else ...[
                    _buildFocusCard(focusSchedule),
                    const SizedBox(height: 12),
                    _buildRoomSignal(),
                    const SizedBox(height: 18),
                    _buildSnapshot(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      title: 'Truy cập nhanh',
                      subtitle: 'Những việc bạn dùng thường xuyên',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickAction(
                            icon: Icons.calendar_month_rounded,
                            iconColor: _blue,
                            iconBackground: _blueSoft,
                            title: 'Lịch học',
                            subtitle:
                                '${homeData?.summary.totalSchedules ?? 0} buổi sắp tới',
                            onTap: onOpenSchedule,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildQuickAction(
                            icon: Icons.notifications_active_rounded,
                            iconColor: _amber,
                            iconBackground: _amberSoft,
                            title: 'Thông báo',
                            subtitle: unreadAnnouncementCount > 0
                                ? '$unreadAnnouncementCount tin chưa đọc'
                                : 'Bạn đã xem hết',
                            onTap: onOpenNotifications,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      title: unreadAnnouncementCount > 0
                          ? 'Cần bạn xem'
                          : 'Cập nhật mới',
                      subtitle: unreadAnnouncementCount > 0
                          ? '$unreadAnnouncementCount thông báo chưa đọc'
                          : 'Thông tin gần đây từ nhà trường',
                      actionLabel: 'Xem tất cả',
                      onAction: onOpenNotifications,
                    ),
                    const SizedBox(height: 12),
                    if (announcements.isEmpty)
                      _buildEmptyState(
                        icon: Icons.mark_email_read_rounded,
                        title: 'Chưa có thông báo mới',
                        body:
                            'Thông tin từ nhà trường và giảng viên sẽ xuất hiện tại đây.',
                      )
                    else
                      ...announcements
                          .take(2)
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildAnnouncement(item),
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

  Widget _buildHeader() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 15),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Mở hồ sơ sinh viên',
            child: Material(
              color: _blueSoft,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                onTap: onOpenProfile,
                borderRadius: BorderRadius.circular(17),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Center(
                    child: Text(
                      initials,
                      style: _font(
                        size: 17,
                        weight: FontWeight.w800,
                        color: _blue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()}, ${_displayName()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(size: 17, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  schoolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$studentCode · $className',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: _blue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: unreadAnnouncementCount > 0
                ? 'Mở $unreadAnnouncementCount thông báo chưa đọc'
                : 'Mở thông báo',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: const Color(0xFFF1F4F9),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: onOpenNotifications,
                    borderRadius: BorderRadius.circular(16),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.notifications_none_rounded,
                        color: _ink,
                        size: 23,
                      ),
                    ),
                  ),
                ),
                if (unreadAnnouncementCount > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD92D20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _surface, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadAnnouncementCount > 99
                            ? '99+'
                            : '$unreadAnnouncementCount',
                        style: _font(
                          size: 9,
                          weight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCard(StudentScheduleItemModel? schedule) {
    final canAttend =
        schedule != null && schedule.canAttend && (schedule.sessionId ?? 0) > 0;

    return Semantics(
      container: true,
      label: schedule == null
          ? 'Không có buổi học sắp tới'
          : 'Buổi học ưu tiên ${schedule.courseName}',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_navy, Color(0xFF194C99)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24102A56),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: schedule == null
            ? _buildNoScheduleFocus()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildFocusBadge(
                        canAttend ? 'ĐANG MỞ ĐIỂM DANH' : 'BUỔI HỌC TIẾP THEO',
                        canAttend ? _mintSoft : const Color(0x24FFFFFF),
                        canAttend ? _mint : Colors.white,
                      ),
                      const Spacer(),
                      Text(
                        schedule.courseCode,
                        style: _font(
                          size: 11,
                          weight: FontWeight.w700,
                          color: const Color(0xCCFFFFFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    schedule.courseName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 22,
                      weight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 9,
                    children: [
                      _buildFocusMeta(
                        Icons.schedule_rounded,
                        '${schedule.startTime} - ${schedule.endTime}',
                      ),
                      _buildFocusMeta(
                        Icons.location_on_outlined,
                        schedule.room.isEmpty
                            ? 'Chưa xếp phòng'
                            : schedule.room,
                      ),
                      _buildFocusMeta(
                        Icons.calendar_today_rounded,
                        '${schedule.weekdayLabel} · ${schedule.dayLabel}',
                      ),
                    ],
                  ),
                  if (schedule.lecturerName.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'GV. ${schedule.lecturerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _font(
                        size: 12,
                        weight: FontWeight.w600,
                        color: const Color(0xD9FFFFFF),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: isAttendanceSubmitting
                          ? null
                          : canAttend
                          ? () => onAttend(schedule)
                          : onOpenSchedule,
                      style: FilledButton.styleFrom(
                        backgroundColor: canAttend ? _mint : Colors.white,
                        foregroundColor: canAttend ? Colors.white : _navy,
                        disabledBackgroundColor: const Color(0x99FFFFFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: isAttendanceSubmitting && canAttend
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              canAttend
                                  ? Icons.verified_user_rounded
                                  : Icons.calendar_month_rounded,
                              size: 20,
                            ),
                      label: Text(
                        canAttend ? 'Điểm danh ngay' : 'Xem lịch học',
                        style: _font(
                          size: 13.5,
                          weight: FontWeight.w800,
                          color: canAttend ? Colors.white : _navy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNoScheduleFocus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFocusBadge(
          'KẾ HOẠCH HỌC TẬP',
          const Color(0x24FFFFFF),
          Colors.white,
        ),
        const SizedBox(height: 16),
        Text(
          'Chưa có buổi học sắp tới',
          style: _font(size: 21, weight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Kéo xuống để làm mới hoặc mở lịch học để xem kế hoạch của bạn.',
          style: _font(
            size: 12.5,
            weight: FontWeight.w500,
            color: const Color(0xD9FFFFFF),
            height: 1.55,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: onOpenSchedule,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _navy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.calendar_month_rounded, size: 19),
            label: Text(
              'Mở lịch học',
              style: _font(size: 13, weight: FontWeight.w800, color: _navy),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFocusBadge(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: _font(size: 9.5, weight: FontWeight.w800, color: foreground),
      ),
    );
  }

  Widget _buildFocusMeta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xCCFFFFFF), size: 17),
        const SizedBox(width: 6),
        Text(
          label,
          style: _font(
            size: 11.5,
            weight: FontWeight.w600,
            color: const Color(0xE6FFFFFF),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomSignal() {
    final evidence = nearbyRoomEvidence;
    final hasRoom = evidence != null;
    final title = isNearbyRoomScanning
        ? 'Đang tìm tín hiệu phòng học...'
        : hasRoom
        ? 'Bạn đang gần phòng ${evidence.roomId}'
        : 'Chưa phát hiện phòng học gần bạn';
    final detail = isNearbyRoomScanning
        ? 'Quá trình quét thường mất vài giây'
        : hasRoom
        ? 'Cường độ tín hiệu ${evidence.rssi} dBm'
        : nearbyRoomError ?? 'Bạn có thể quét lại trước khi điểm danh';

    return Semantics(
      container: true,
      label: '$title. $detail',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: hasRoom ? _mintSoft : _blueSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: isNearbyRoomScanning
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: _blue,
                      ),
                    )
                  : Icon(
                      hasRoom
                          ? Icons.sensors_rounded
                          : Icons.location_searching_rounded,
                      color: hasRoom ? _mint : _blue,
                      size: 21,
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(size: 12.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(
                      size: 10.5,
                      weight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Quét lại tín hiệu phòng học',
              child: IconButton(
                onPressed: isNearbyRoomScanning ? null : onRescanNearbyRoom,
                tooltip: 'Quét lại',
                icon: const Icon(Icons.refresh_rounded),
                color: _blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshot() {
    final summary = homeData?.summary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          _buildMetric(
            value: '${summary?.totalSchedules ?? 0}',
            label: 'Lịch học',
            color: _blue,
          ),
          _buildMetricDivider(),
          _buildMetric(
            value: '${summary?.currentSchedules ?? 0}',
            label: 'Đang diễn ra',
            color: _mint,
          ),
          _buildMetricDivider(),
          _buildMetric(
            value: '$unreadAnnouncementCount',
            label: 'Chưa đọc',
            color: _amber,
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Semantics(
        label: '$label: $value',
        child: Column(
          children: [
            Text(
              value,
              style: _font(size: 20, weight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: _font(size: 10.5, weight: FontWeight.w600, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricDivider() {
    return const SizedBox(
      height: 34,
      child: VerticalDivider(width: 1, thickness: 1, color: _line),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: _font(size: 17, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: _font(
                  size: 10.5,
                  weight: FontWeight.w500,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _blue,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              actionLabel,
              style: _font(size: 11.5, weight: FontWeight.w700, color: _blue),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: iconColor, size: 21),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      color: Color(0xFF98A2B3),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(title, style: _font(size: 13.5, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _font(
                    size: 10.5,
                    weight: FontWeight.w500,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncement(StudentAnnouncementModel item) {
    final unread = item.isRead != true;
    final tone = _announcementTone(item.type);
    return Semantics(
      button: true,
      label: '${unread ? 'Chưa đọc. ' : ''}${item.title}. ${item.body}',
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onOpenNotifications,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: unread ? tone.$1 : _line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tone.$2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(tone.$3, color: tone.$1, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _font(
                                size: 13,
                                weight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                color: tone.$1,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _font(
                          size: 10.5,
                          weight: FontWeight.w500,
                          color: _muted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _timeAgo(item.createdAt),
                        style: _font(
                          size: 9.5,
                          weight: FontWeight.w600,
                          color: tone.$1,
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

  Widget _buildLoadingState() {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _blue, strokeWidth: 2.5),
            const SizedBox(height: 14),
            Text(
              'Đang chuẩn bị trang chủ của bạn...',
              style: _font(size: 12, weight: FontWeight.w600, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineError(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD4D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _font(
                size: 10.5,
                weight: FontWeight.w600,
                color: const Color(0xFFB42318),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String body,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _blueSoft,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: _blue, size: 22),
          ),
          const SizedBox(height: 11),
          Text(
            title,
            textAlign: TextAlign.center,
            style: _font(size: 13.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: _font(
              size: 10.5,
              weight: FontWeight.w500,
              color: _muted,
              height: 1.5,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }

  List<StudentAnnouncementModel> _sortedAnnouncements(
    List<StudentAnnouncementModel> items,
  ) {
    final result = [...items];
    result.sort((left, right) {
      final unreadCompare = (right.isRead != true ? 1 : 0).compareTo(
        left.isRead != true ? 1 : 0,
      );
      if (unreadCompare != 0) return unreadCompare;
      final leftTime = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });
    return result;
  }

  (Color, Color, IconData) _announcementTone(String type) {
    switch (type.toLowerCase()) {
      case 'warning':
      case 'attendance_closing':
        return (_amber, _amberSoft, Icons.schedule_rounded);
      case 'attendance_open':
      case 'attendance_success':
        return (_mint, _mintSoft, Icons.verified_rounded);
      case 'attendance_failed':
      case 'attendance_review':
        return (
          const Color(0xFFD92D20),
          const Color(0xFFFFEDEC),
          Icons.report_gmailerrorred_rounded,
        );
      default:
        return (_blue, _blueSoft, Icons.campaign_rounded);
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Chào buổi sáng';
    if (hour < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  String _displayName() {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty || RegExp(r'^\d+$').hasMatch(parts.last)) {
      return 'bạn';
    }
    return parts.last;
  }

  String _timeAgo(DateTime? value) {
    if (value == null) return 'Vừa cập nhật';
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) return 'Vừa xong';
    if (difference.inMinutes < 60) return '${difference.inMinutes} phút trước';
    if (difference.inHours < 24) return '${difference.inHours} giờ trước';
    if (difference.inDays < 7) return '${difference.inDays} ngày trước';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }
}
