import '../../core/ble/ble_models.dart';

class StudentHomeModel {
  final StudentHomeProfileModel student;
  final StudentHomeSummaryModel summary;
  final List<StudentScheduleItemModel> upcomingSchedules;
  final List<StudentAnnouncementModel> announcements;

  const StudentHomeModel({
    required this.student,
    required this.summary,
    required this.upcomingSchedules,
    required this.announcements,
  });

  factory StudentHomeModel.fromJson(Map<String, dynamic> json) {
    final schedulesRaw =
        json['upcomingSchedules'] ?? json['todaySchedules'] ?? const [];
    final announcementsRaw =
        json['announcements'] ?? json['notifications'] ?? const [];

    return StudentHomeModel(
      student: StudentHomeProfileModel.fromJson(
        json['student'] as Map<String, dynamic>? ?? const {},
      ),
      summary: StudentHomeSummaryModel.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      upcomingSchedules: (schedulesRaw as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(StudentScheduleItemModel.fromJson)
          .toList(),
      announcements: (announcementsRaw as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(StudentAnnouncementModel.fromJson)
          .toList(),
    );
  }
}

class StudentHomeProfileModel {
  final int id;
  final String mssv;
  final String fullName;
  final String schoolCode;
  final String schoolName;
  final String facultyName;
  final String className;
  final String? email;

  const StudentHomeProfileModel({
    required this.id,
    required this.mssv,
    required this.fullName,
    required this.schoolCode,
    required this.schoolName,
    required this.facultyName,
    required this.className,
    required this.email,
  });

  factory StudentHomeProfileModel.fromJson(Map<String, dynamic> json) {
    final schoolCode = json['schoolCode'] as String? ?? '';

    return StudentHomeProfileModel(
      id: json['id'] as int? ?? 0,
      mssv: json['mssv'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      schoolCode: schoolCode,
      schoolName: _normalizeSchoolName(
        code: schoolCode,
        rawName: json['schoolName'] as String? ?? '',
      ),
      facultyName: json['facultyName'] as String? ?? '',
      className: json['className'] as String? ?? '',
      email: json['email'] as String?,
    );
  }

  static String _normalizeSchoolName({
    required String code,
    required String rawName,
  }) {
    switch (code.trim().toUpperCase()) {
      case 'HUCE':
        return 'Đại học Xây dựng Hà Nội';
      case 'HUST':
        return 'Đại học Bách khoa Hà Nội';
      default:
        return rawName;
    }
  }
}

class StudentHomeSummaryModel {
  final int totalSchedules;
  final int currentSchedules;
  final int totalAnnouncements;
  final int unreadAnnouncements;

  const StudentHomeSummaryModel({
    required this.totalSchedules,
    required this.currentSchedules,
    required this.totalAnnouncements,
    required this.unreadAnnouncements,
  });

  factory StudentHomeSummaryModel.fromJson(Map<String, dynamic> json) {
    final unreadAnnouncements =
        json['unreadAnnouncements'] as int? ??
        json['unreadNotificationCount'] as int? ??
        0;

    return StudentHomeSummaryModel(
      totalSchedules:
          json['totalSchedules'] as int? ?? json['totalCourses'] as int? ?? 0,
      currentSchedules:
          json['currentSchedules'] as int? ??
          json['openAttendanceCount'] as int? ??
          0,
      totalAnnouncements:
          json['totalAnnouncements'] as int? ?? unreadAnnouncements,
      unreadAnnouncements: unreadAnnouncements,
    );
  }
}

class StudentScheduleItemModel {
  final int id;
  final int? sessionId;
  final String courseCode;
  final String courseName;
  final int credits;
  final String room;
  final String startTime;
  final String endTime;
  final String lecturerName;
  final String? lecturerCode;
  final String status;
  final bool canAttend;
  final DateTime? occurrenceStart;
  final DateTime? occurrenceEnd;
  final String weekdayLabel;
  final String dayLabel;
  final BleExpectation expectedBle;

  const StudentScheduleItemModel({
    required this.id,
    required this.sessionId,
    required this.courseCode,
    required this.courseName,
    required this.credits,
    required this.room,
    required this.startTime,
    required this.endTime,
    required this.lecturerName,
    required this.lecturerCode,
    required this.status,
    required this.canAttend,
    required this.occurrenceStart,
    required this.occurrenceEnd,
    required this.weekdayLabel,
    required this.dayLabel,
    required this.expectedBle,
  });

  factory StudentScheduleItemModel.fromJson(Map<String, dynamic> json) {
    final occurrenceStartRaw = json['occurrenceStart'] as String?;
    final occurrenceEndRaw = json['occurrenceEnd'] as String?;
    final attendanceState =
        json['attendanceState'] as Map<String, dynamic>? ?? const {};

    return StudentScheduleItemModel(
      id: json['id'] as int? ?? json['scheduleId'] as int? ?? 0,
      sessionId: json['sessionId'] as int?,
      courseCode: json['courseCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      credits: json['credits'] as int? ?? 0,
      room: json['room'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      lecturerName: json['lecturerName'] as String? ?? '',
      lecturerCode: json['lecturerCode'] as String?,
      status:
          json['status'] as String? ??
          attendanceState['code'] as String? ??
          'upcoming',
      canAttend: json['canAttend'] as bool? ?? false,
      occurrenceStart: occurrenceStartRaw == null
          ? null
          : DateTime.tryParse(occurrenceStartRaw),
      occurrenceEnd: occurrenceEndRaw == null
          ? null
          : DateTime.tryParse(occurrenceEndRaw),
      weekdayLabel: json['weekdayLabel'] as String? ?? '',
      dayLabel: json['dayLabel'] as String? ?? '',
      expectedBle: BleExpectation.fromJson(
        json['expectedBle'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class StudentAnnouncementModel {
  final int id;
  final String title;
  final String body;
  final String type;
  final DateTime? createdAt;
  final bool? isRead;

  const StudentAnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
  });

  factory StudentAnnouncementModel.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'] as String?;

    return StudentAnnouncementModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: json['type'] as String? ?? 'general',
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
      isRead: json['isRead'] as bool?,
    );
  }
}
