import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
// eslint-disable-next-line @typescript-eslint/no-require-imports
import Workbook = require('exceljs/lib/doc/workbook');
import { PrismaTenantService } from '../../database/prisma/prisma-tenant.service';
import { BleTestConfig } from '../attendance/ble-test.config';
import { isScheduleOccurrenceOnDate } from '../schedules/schedule-recurrence';

type LecturerBaseQuery = {
  schoolCode?: string;
  lecturerCode?: string;
};

type LecturerHistoryQuery = LecturerBaseQuery & {
  scheduleId?: string;
  courseKeyword?: string;
  attendanceDate?: string;
};

type LecturerStatisticsQuery = LecturerBaseQuery & {
  scheduleId?: string;
};

type LecturerExportQuery = LecturerBaseQuery & {
  scheduleId?: string;
  scope?: 'today' | 'all';
};

type CreateAttendanceSessionBody = {
  startAt?: string;
  endAt?: string;
  durationMinutes?: number;
};

type SaveAttendanceBody = {
  records?: Array<{
    recordId?: number;
    studentId: number;
    status: 'OK' | 'REVIEW' | 'ABSENT';
    note?: string;
    checkInAt?: string | null;
  }>;
};

type LecturerContext = {
  schoolCode: string;
  lecturerCode: string;
  studentPrisma: PrismaClient;
  lecturerPrisma: PrismaClient;
  lecturerProfile: any;
};

type SessionWindow = {
  startAt: Date;
  endAt: Date;
  durationMinutes: number;
};

type AttendanceSummary = {
  totalStudents: number;
  okCount: number;
  reviewCount: number;
  absentCount: number;
};

type NotificationCreateInput = {
  title: string;
  body: string;
  type: string;
  referenceKey?: string;
};

@Injectable()
export class LecturersService {
  constructor(private readonly prismaTenant: PrismaTenantService) {}

  async getLecturerHome(query: LecturerBaseQuery) {
    const context = await this.getLecturerContext(query);
    const schedules = await this.getOwnedSchedules(context);
    const scheduleIds = schedules.map((schedule) => schedule.id);

    await this.syncExpiredSessions(context, scheduleIds);
    await this.syncScheduleLifecycleNotifications(context, schedules);
    await this.syncEndingSoonNotifications(context, scheduleIds);

    const [classItems, notificationsPayload, totalAttendanceHistory] =
      await Promise.all([
        this.buildClassItems(context, schedules),
        this.fetchLecturerNotifications(context, 3),
        scheduleIds.length
          ? context.studentPrisma.attendanceSession.count({
              where: {
                scheduleId: {
                  in: scheduleIds,
                },
                status: 'closed',
              },
            })
          : Promise.resolve(0),
      ]);

    return {
      lecturer: this.mapLecturerProfile(context.lecturerProfile),
      summary: {
        managedClasses: classItems.length,
        openSessions: classItems.filter(
          (item) => item.currentSessionStatus.code === 'open',
        ).length,
        unreadNotifications: notificationsPayload.unreadCount,
        totalAttendanceHistory,
      },
      classesPreview: classItems.slice(0, 3),
      notificationsPreview: notificationsPayload.items.slice(0, 3),
      features: [
        {
          key: 'classes',
          title: 'Danh sách lớp học phần',
          description: 'Quản lý tất cả lớp học phần đang phụ trách',
          icon: 'class',
        },
        {
          key: 'notifications',
          title: 'Thông báo',
          description: 'Nhận thông báo mới nhất về điểm danh và xuất file',
          icon: 'notifications',
        },
        {
          key: 'history',
          title: 'Lịch sử điểm danh',
          description: 'Xem lại các buổi học đã điểm danh',
          icon: 'history',
        },
        {
          key: 'statistics',
          title: 'Thống kê chuyên cần',
          description: 'Tổng hợp số liệu điểm danh theo lớp và sinh viên',
          icon: 'analytics',
        },
        {
          key: 'profile',
          title: 'Thông tin cá nhân',
          description: 'Xem hồ sơ giảng viên và thông tin liên hệ',
          icon: 'profile',
        },
        {
          key: 'logout',
          title: 'Đăng xuất',
          description: 'Quay lại màn hình đăng nhập',
          icon: 'logout',
        },
      ],
    };
  }

  async getLecturerClasses(query: LecturerBaseQuery) {
    const context = await this.getLecturerContext(query);
    const schedules = await this.getOwnedSchedules(context);
    const scheduleIds = schedules.map((schedule) => schedule.id);

    await this.syncExpiredSessions(context, scheduleIds);

    const classes = await this.buildClassItems(context, schedules);

    return {
      lecturer: this.mapLecturerProfile(context.lecturerProfile),
      summary: {
        totalClasses: classes.length,
        openSessions: classes.filter(
          (item) => item.currentSessionStatus.code === 'open',
        ).length,
      },
      classes,
    };
  }

  async getLecturerClassDetail(scheduleId: number, query: LecturerBaseQuery) {
    const context = await this.getLecturerContext(query);
    const normalizedScheduleId = this.ensurePositiveId(
      scheduleId,
      'scheduleId',
    );
    const schedule = await this.getOwnedSchedule(context, normalizedScheduleId);

    await this.syncExpiredSessions(context, [schedule.id]);

    const [students, sessions] = await Promise.all([
      this.getScheduleStudents(context, schedule),
      context.studentPrisma.attendanceSession.findMany({
        where: {
          scheduleId: schedule.id,
        },
        include: {
          records: true,
        },
        orderBy: [{ attendanceDate: 'desc' }, { id: 'desc' }],
      }),
    ]);

    const currentSession =
      sessions.find((item) => item.status === 'open') ?? sessions[0] ?? null;
    const recordMap = this.getAttendanceRecordMap(
      currentSession?.records ?? [],
    );
    const summary = this.summarizeAttendance(students, recordMap);

    return {
      classInfo: {
        scheduleId: schedule.id,
        courseCode: schedule.course.code,
        courseName: schedule.course.name,
        classCode: this.buildClassCode(schedule),
        studentClassName: schedule.studentClass.name,
        room: this.normalizeRoomName(schedule.room),
        timeLabel: `${this.weekdayLabel(schedule.dayOfWeek)} • ${schedule.startTime} - ${schedule.endTime}`,
        timeRange: `${schedule.startTime} - ${schedule.endTime}`,
        studentCount: students.length,
        totalSessions: sessions.length,
        currentSessionStatus: this.mapSessionStatus(currentSession),
      },
      currentSession: currentSession
        ? {
            sessionId: currentSession.id,
            attendanceDate: currentSession.attendanceDate.toISOString(),
            openedAt: currentSession.openedAt?.toISOString() ?? null,
            closesAt: currentSession.closesAt?.toISOString() ?? null,
            status: this.mapSessionStatus(currentSession),
            summary,
          }
        : null,
      students: students.map((student) =>
        this.mapAttendanceStudent(student, recordMap.get(student.id)),
      ),
      historyPreview: sessions.slice(0, 5).map((session) => ({
        sessionId: session.id,
        attendanceDate: session.attendanceDate.toISOString(),
        dayLabel: this.formatDate(session.attendanceDate),
        status: this.mapSessionStatus(session),
      })),
    };
  }

  async createAttendanceSession(
    scheduleId: number,
    query: LecturerBaseQuery,
    body: CreateAttendanceSessionBody,
  ) {
    const context = await this.getLecturerContext(query);
    const normalizedScheduleId = this.ensurePositiveId(
      scheduleId,
      'scheduleId',
    );
    const schedule = await this.getOwnedSchedule(context, normalizedScheduleId);
    const students = await this.getScheduleStudents(context, schedule);

    if (students.length === 0) {
      throw new BadRequestException('Lớp học phần này chưa có sinh viên');
    }

    await this.syncExpiredSessions(context, [schedule.id]);

    const window = this.resolveSessionWindow(body);
    this.assertSessionMatchesSchedule(schedule, window.startAt);
    const bleExpectation = BleTestConfig.forRoom(schedule.room);

    const openSession = await context.studentPrisma.attendanceSession.findFirst(
      {
        where: {
          scheduleId: schedule.id,
          status: 'open',
        },
        orderBy: [{ attendanceDate: 'desc' }, { id: 'desc' }],
      },
    );

    if (openSession) {
      throw new BadRequestException(
        'Lớp học phần này đang có phiên điểm danh mở',
      );
    }

    let session;
    try {
      session = await context.studentPrisma.attendanceSession.create({
        data: {
          scheduleId: schedule.id,
          attendanceDate: window.startAt,
          openedAt: window.startAt,
          lateAt: new Date(window.startAt.getTime() + 10 * 60 * 1000),
          closesAt: window.endAt,
          beaconId: bleExpectation.beaconId,
          roomId: bleExpectation.roomId,
          bleServiceUuid: bleExpectation.serviceUuid,
          bleMinRssi: bleExpectation.minRssi,
          status: 'open',
        },
      });
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new BadRequestException(
          'Lá»›p há»c pháº§n nÃ y Ä‘ang cÃ³ phiÃªn Ä‘iá»ƒm danh má»Ÿ',
        );
      }
      throw error;
    }

    await this.ensureSessionRecords(context, session.id, students);

    await context.studentPrisma.announcement.create({
      data: {
        schoolId: schedule.course.schoolId,
        classId: schedule.classId,
        title: 'Đã có phiên điểm danh',
        body: `Môn ${schedule.course.name} đã mở phiên điểm danh từ ${this.formatDateTime(window.startAt)} đến ${this.formatDateTime(window.endAt)}.`,
        type: 'attendance_available',
      },
    });

    await context.studentPrisma.studentNotification.deleteMany({
      where: {
        sessionId: session.id,
        type: 'attendance_available',
      },
    });

    await context.studentPrisma.studentNotification.createMany({
      data: students.map((student) => ({
        studentId: student.id,
        sessionId: session.id,
        title: 'Đã có phiên điểm danh',
        body: `Môn ${schedule.course.name} đã có phiên điểm danh và sẽ kết thúc lúc ${this.formatTime(window.endAt)}.`,
        type: 'attendance_available',
        isRead: false,
      })),
    });

    await this.createLecturerNotification(context, {
      type: 'attendance_available',
      referenceKey: `attendance_available:${session.id}`,
      title: 'Đã có phiên điểm danh',
      body: `Lớp ${this.buildClassCode(schedule)} đã mở phiên điểm danh từ ${this.formatDateTime(window.startAt)} đến ${this.formatDateTime(window.endAt)}.`,
    });

    await this.syncEndingSoonNotifications(context, [schedule.id]);

    return {
      message: 'Đã tạo phiên điểm danh',
      classInfo: {
        scheduleId: schedule.id,
        classCode: this.buildClassCode(schedule),
        courseCode: schedule.course.code,
        courseName: schedule.course.name,
      },
      session: {
        sessionId: session.id,
        attendanceDate: session.attendanceDate.toISOString(),
        openedAt: session.openedAt?.toISOString() ?? null,
        closesAt: session.closesAt?.toISOString() ?? null,
        lateAt: session.lateAt?.toISOString() ?? null,
        durationMinutes: window.durationMinutes,
        expectedBle: bleExpectation,
        status: this.mapSessionStatus(session),
      },
    };
  }

  async saveAttendanceSession(
    sessionId: number,
    query: LecturerBaseQuery,
    body: SaveAttendanceBody,
  ) {
    const context = await this.getLecturerContext(query);
    const normalizedSessionId = this.ensurePositiveId(sessionId, 'sessionId');
    const session = await context.studentPrisma.attendanceSession.findFirst({
      where: {
        id: normalizedSessionId,
        schedule: this.buildOwnedScheduleWhere(context, false),
      },
      include: {
        schedule: {
          include: {
            course: true,
            offering: true,
            studentClass: true,
          },
        },
        records: true,
      },
    });

    if (!session) {
      throw new NotFoundException('Không tìm thấy phiên điểm danh');
    }

    const students = await this.getScheduleStudents(context, session.schedule);
    const studentMap = new Map(
      students.map((student) => [student.id, student]),
    );
    const existingRecordMap = this.getAttendanceRecordMap(session.records);
    const seenStudentIds = new Set<number>();

    for (const item of body.records ?? []) {
      const student = studentMap.get(item.studentId);

      if (!student) {
        throw new BadRequestException(
          `Sinh viên ${item.studentId} không thuộc lớp học phần này`,
        );
      }

      if (seenStudentIds.has(item.studentId)) {
        throw new BadRequestException(
          `Sinh viên ${item.studentId} bị lặp dữ liệu`,
        );
      }

      seenStudentIds.add(item.studentId);
      const existingRecord = existingRecordMap.get(item.studentId);
      const updatePayload = this.buildRecordPayload(item, existingRecord);

      await context.studentPrisma.attendanceRecord.upsert({
        where: {
          sessionId_studentId: {
            sessionId: session.id,
            studentId: item.studentId,
          },
        },
        update: updatePayload,
        create: {
          sessionId: session.id,
          studentId: item.studentId,
          scanAttempts: existingRecord?.scanAttempts ?? 0,
          ...updatePayload,
        },
      });
    }

    const missingStudents = students.filter(
      (student) =>
        !existingRecordMap.has(student.id) && !seenStudentIds.has(student.id),
    );

    if (missingStudents.length > 0) {
      await context.studentPrisma.attendanceRecord.createMany({
        data: missingStudents.map((student) => ({
          sessionId: session.id,
          studentId: student.id,
          status: 'absent',
          scanResult: 'manual_absent',
          scanAttempts: 0,
          note: null,
          lastFailureReason: 'Chưa điểm danh',
          checkInAt: null,
        })),
      });
    }

    const closedSession = await context.studentPrisma.attendanceSession.update({
      where: {
        id: session.id,
      },
      data: {
        status: 'closed',
        closesAt: new Date(),
      },
    });

    const savedRecords = await context.studentPrisma.attendanceRecord.findMany({
      where: {
        sessionId: session.id,
      },
    });
    const savedRecordMap = this.getAttendanceRecordMap(savedRecords);
    const summary = this.summarizeAttendance(students, savedRecordMap);

    await this.createLecturerNotification(context, {
      type: 'attendance_closed',
      referenceKey: `attendance_closed:${session.id}`,
      title: 'Phiên điểm danh đã kết thúc',
      body: `Phiên điểm danh lớp ${this.buildClassCode(session.schedule)} đã kết thúc với ${summary.okCount} OK, ${summary.reviewCount} cần kiểm tra, ${summary.absentCount} vắng.`,
    });

    return {
      message: 'Đã lưu điểm danh thành công',
      session: {
        sessionId: closedSession.id,
        attendanceDate: closedSession.attendanceDate.toISOString(),
        openedAt: closedSession.openedAt?.toISOString() ?? null,
        closesAt: closedSession.closesAt?.toISOString() ?? null,
        status: this.mapSessionStatus(closedSession),
      },
      summary,
      records: students.map((student) =>
        this.mapAttendanceStudent(student, savedRecordMap.get(student.id)),
      ),
    };
  }

  async getAttendanceHistory(query: LecturerHistoryQuery) {
    const context = await this.getLecturerContext(query);
    const schedules = await this.getOwnedSchedules(
      context,
      query.scheduleId
        ? this.ensurePositiveId(query.scheduleId, 'scheduleId')
        : undefined,
      true,
    );
    const scheduleIds = schedules.map((schedule) => schedule.id);

    await this.syncExpiredSessions(context, scheduleIds);

    const where: Record<string, unknown> = {
      scheduleId: {
        in: scheduleIds,
      },
      status: {
        not: 'scheduled',
      },
    };

    const courseKeyword = query.courseKeyword?.trim();
    if (courseKeyword) {
      where.schedule = {
        course: {
          OR: [
            {
              code: {
                contains: courseKeyword,
                mode: 'insensitive',
              },
            },
            {
              name: {
                contains: courseKeyword,
                mode: 'insensitive',
              },
            },
          ],
        },
      };
    }

    if (query.attendanceDate?.trim()) {
      const attendanceDate = this.parseDateValue(
        query.attendanceDate,
        'attendanceDate',
      );
      where.attendanceDate = {
        gte: this.getDayStart(attendanceDate),
        lt: this.getDayEnd(attendanceDate),
      };
    }

    const studentsByScheduleId = await this.getStudentsBySchedules(
      context,
      schedules,
      false,
    );

    const history = scheduleIds.length
      ? await context.studentPrisma.attendanceSession.findMany({
          where,
          include: {
            schedule: {
              include: {
                course: true,
                offering: true,
                studentClass: true,
              },
            },
            records: true,
          },
          orderBy: [{ attendanceDate: 'desc' }, { id: 'desc' }],
        })
      : [];

    return {
      filters: {
        selectedScheduleId: query.scheduleId ? Number(query.scheduleId) : null,
        selectedCourseKeyword: courseKeyword ?? null,
        selectedAttendanceDate: query.attendanceDate ?? null,
        classOptions: schedules.map((schedule) => ({
          scheduleId: schedule.id,
          classCode: this.buildClassCode(schedule),
          courseName: schedule.course.name,
        })),
      },
      history: history.map((session) => {
        const students = studentsByScheduleId.get(session.schedule.id) ?? [];
        const recordMap = this.getAttendanceRecordMap(session.records);
        const summary = this.summarizeAttendance(students, recordMap);

        return {
          sessionId: session.id,
          courseName: session.schedule.course.name,
          courseCode: session.schedule.course.code,
          classCode: this.buildClassCode(session.schedule),
          attendanceDate: session.attendanceDate.toISOString(),
          dayLabel: this.formatDate(session.attendanceDate),
          timeRange: `${session.schedule.startTime} - ${session.schedule.endTime}`,
          sessionStatus: this.mapSessionStatus(session),
          summary,
          students: students.map((student) =>
            this.mapAttendanceStudent(student, recordMap.get(student.id)),
          ),
        };
      }),
    };
  }

  async getAttendanceStatistics(query: LecturerStatisticsQuery) {
    const context = await this.getLecturerContext(query);
    const schedules = await this.getOwnedSchedules(
      context,
      query.scheduleId
        ? this.ensurePositiveId(query.scheduleId, 'scheduleId')
        : undefined,
      true,
    );
    const scheduleIds = schedules.map((schedule) => schedule.id);

    await this.syncExpiredSessions(context, scheduleIds);

    const sessions = scheduleIds.length
      ? await context.studentPrisma.attendanceSession.findMany({
          where: {
            scheduleId: {
              in: scheduleIds,
            },
            status: 'closed',
          },
          include: {
            schedule: {
              include: {
                course: true,
                offering: true,
                studentClass: true,
              },
            },
            records: true,
          },
          orderBy: [{ attendanceDate: 'asc' }, { id: 'asc' }],
        })
      : [];

    const studentsByScheduleId = await this.getStudentsBySchedules(
      context,
      schedules,
      false,
    );
    const studentStatisticsMap = new Map<number, any>();

    for (const students of studentsByScheduleId.values()) {
      for (const student of students) {
        if (!studentStatisticsMap.has(student.id)) {
          studentStatisticsMap.set(student.id, {
            studentId: student.id,
            mssv: student.mssv,
            fullName: student.fullName,
            className: student.studentClass.name,
            totalOk: 0,
            totalReview: 0,
            totalAbsent: 0,
          });
        }
      }
    }

    const classStatistics = schedules.map((schedule) => {
      const classStudents = studentsByScheduleId.get(schedule.id) ?? [];
      const scheduleSessions = sessions.filter(
        (session) => session.scheduleId === schedule.id,
      );
      let okCount = 0;
      let reviewCount = 0;
      let absentCount = 0;

      for (const session of scheduleSessions) {
        const recordMap = this.getAttendanceRecordMap(session.records);
        const summary = this.summarizeAttendance(classStudents, recordMap);

        okCount += summary.okCount;
        reviewCount += summary.reviewCount;
        absentCount += summary.absentCount;

        for (const student of classStudents) {
          const stats = studentStatisticsMap.get(student.id);
          const statusCode = this.getAttendanceStatusCode(
            recordMap.get(student.id),
          );

          if (statusCode === 'OK') {
            stats.totalOk += 1;
          } else if (statusCode === 'REVIEW') {
            stats.totalReview += 1;
          } else {
            stats.totalAbsent += 1;
          }
        }
      }

      return {
        scheduleId: schedule.id,
        courseCode: schedule.course.code,
        courseName: schedule.course.name,
        classCode: this.buildClassCode(schedule),
        studentCount: classStudents.length,
        totalSessions: scheduleSessions.length,
        okCount,
        reviewCount,
        absentCount,
      };
    });

    return {
      filters: {
        selectedScheduleId: query.scheduleId ? Number(query.scheduleId) : null,
        classOptions: schedules.map((schedule) => ({
          scheduleId: schedule.id,
          classCode: this.buildClassCode(schedule),
          courseName: schedule.course.name,
        })),
      },
      summary: {
        totalClasses: classStatistics.length,
        totalSessions: classStatistics.reduce(
          (total, item) => total + item.totalSessions,
          0,
        ),
        totalOk: classStatistics.reduce(
          (total, item) => total + item.okCount,
          0,
        ),
        totalReview: classStatistics.reduce(
          (total, item) => total + item.reviewCount,
          0,
        ),
        totalAbsent: classStatistics.reduce(
          (total, item) => total + item.absentCount,
          0,
        ),
      },
      classStatistics,
      studentStatistics: [...studentStatisticsMap.values()].sort(
        (left, right) => left.mssv.localeCompare(right.mssv),
      ),
    };
  }

  async getLecturerNotifications(query: LecturerBaseQuery) {
    const context = await this.getLecturerContext(query);
    const schedules = await this.getOwnedSchedules(context);
    const scheduleIds = schedules.map((item) => item.id);

    await this.syncExpiredSessions(context, scheduleIds);
    await this.syncScheduleLifecycleNotifications(context, schedules);
    await this.syncEndingSoonNotifications(context, scheduleIds);

    return this.fetchLecturerNotifications(context);
  }

  async markNotificationAsRead(
    notificationId: number,
    query: LecturerBaseQuery,
  ) {
    const context = await this.getLecturerContext(query);
    const normalizedNotificationId = this.ensurePositiveId(
      notificationId,
      'notificationId',
    );
    const notification =
      await context.lecturerPrisma.lecturerNotification.findFirst({
        where: {
          id: normalizedNotificationId,
          lecturerId: context.lecturerProfile.id,
        },
      });

    if (!notification) {
      throw new NotFoundException('Không tìm thấy thông báo');
    }

    const updated = await context.lecturerPrisma.lecturerNotification.update({
      where: {
        id: normalizedNotificationId,
      },
      data: {
        isRead: true,
      },
    });

    return {
      message: 'Đã đánh dấu thông báo đã đọc',
      notification: this.mapNotification(updated),
    };
  }

  async getLecturerProfile(query: LecturerBaseQuery) {
    const context = await this.getLecturerContext(query);

    return {
      lecturer: this.mapLecturerProfile(context.lecturerProfile),
    };
  }

  async exportAttendanceReport(query: LecturerExportQuery) {
    const context = await this.getLecturerContext(query);
    const scheduleId = this.ensurePositiveId(query.scheduleId, 'scheduleId');
    const schedule = await this.getOwnedSchedule(context, scheduleId, true);
    const scope = query.scope === 'today' ? 'today' : 'all';

    try {
      await this.syncExpiredSessions(context, [schedule.id]);

      const where: Record<string, unknown> = {
        scheduleId: schedule.id,
        status: {
          not: 'scheduled',
        },
      };

      if (scope === 'today') {
        const today = new Date();
        where.attendanceDate = {
          gte: this.getDayStart(today),
          lt: this.getDayEnd(today),
        };
      }

      const [students, sessions] = await Promise.all([
        this.getScheduleStudents(context, schedule, false),
        context.studentPrisma.attendanceSession.findMany({
          where,
          include: {
            records: true,
          },
          orderBy: [{ attendanceDate: 'asc' }, { id: 'asc' }],
        }),
      ]);

      if (sessions.length === 0) {
        throw new NotFoundException('Không có dữ liệu điểm danh để xuất file');
      }

      const workbook = new Workbook();
      const worksheet = workbook.addWorksheet('Attendance');

      worksheet.columns = [
        { header: 'Ten mon hoc', key: 'courseName', width: 28 },
        { header: 'Ma lop hoc phan', key: 'classCode', width: 24 },
        { header: 'Ngày điểm danh', key: 'attendanceDate', width: 18 },
        { header: 'Mã sinh viên', key: 'mssv', width: 16 },
        { header: 'Ho ten', key: 'fullName', width: 28 },
        { header: 'Trang thai', key: 'status', width: 16 },
        { header: 'Thời gian điểm danh', key: 'checkInAt', width: 22 },
        { header: 'Ghi chu', key: 'note', width: 36 },
      ];
      worksheet.getRow(1).font = { bold: true };
      worksheet.views = [{ state: 'frozen', ySplit: 1 }];
      worksheet.autoFilter = {
        from: 'A1',
        to: 'H1',
      };

      for (const session of sessions) {
        const recordMap = this.getAttendanceRecordMap(session.records);

        for (const student of students) {
          const record = recordMap.get(student.id);
          const status = this.getAttendanceDisplay(record);

          worksheet.addRow({
            courseName: schedule.course.name,
            classCode: this.buildClassCode(schedule),
            attendanceDate: this.formatDate(session.attendanceDate),
            mssv: student.mssv,
            fullName: student.fullName,
            status: status.label,
            checkInAt: record?.checkInAt
              ? this.formatDateTime(record.checkInAt)
              : '',
            note: this.getRecordNote(record),
          });
        }
      }

      const fileName = `attendance-${context.schoolCode.toLowerCase()}-${schedule.course.code.toLowerCase()}-${scope}-${this.formatDateKey(new Date())}.xlsx`;
      const buffer = await workbook.xlsx.writeBuffer();

      await this.createLecturerNotification(context, {
        type: 'attendance_export_success',
        title: 'Xuất file Excel thành công',
        body: `Đã xuất file ${fileName} cho lớp ${this.buildClassCode(schedule)}.`,
      });

      return {
        fileName,
        buffer,
      };
    } catch (error) {
      await this.createLecturerNotification(context, {
        type: 'attendance_export_failed',
        title: 'Xuất file Excel thất bại',
        body: `Không thể xuất file cho lớp ${this.buildClassCode(schedule)}. ${(error as Error).message}`,
      });
      throw error;
    }
  }

  private isUniqueConstraintError(error: unknown) {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 'P2002'
    );
  }

  private async getLecturerContext(
    query: LecturerBaseQuery,
  ): Promise<LecturerContext> {
    const schoolCode = query.schoolCode?.trim().toUpperCase();
    const lecturerCode = query.lecturerCode?.trim();

    if (!schoolCode) {
      throw new BadRequestException('Thiếu mã trường');
    }

    if (!lecturerCode) {
      throw new BadRequestException('Thiếu mã giảng viên');
    }

    const studentPrisma = this.prismaTenant.getClient(schoolCode, 'student');
    const lecturerPrisma = this.prismaTenant.getClient(schoolCode, 'lecturer');
    const lecturerProfile = await lecturerPrisma.lecturer.findFirst({
      where: {
        lecturerCode,
        isActive: true,
        school: {
          code: schoolCode,
        },
      },
      include: {
        faculty: true,
        school: true,
      },
    });

    if (!lecturerProfile) {
      throw new NotFoundException('Không tìm thấy giảng viên');
    }

    return {
      schoolCode,
      lecturerCode,
      studentPrisma,
      lecturerPrisma,
      lecturerProfile,
    };
  }

  private async getOwnedSchedules(
    context: LecturerContext,
    scheduleId?: number,
    historical = false,
  ) {
    return context.studentPrisma.schedule.findMany({
      where: {
        ...this.buildOwnedScheduleWhere(context, historical),
        ...(scheduleId ? { id: scheduleId } : {}),
      },
      include: {
        course: true,
        offering: true,
        studentClass: {
          include: {
            faculty: true,
          },
        },
      },
      orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }],
    });
  }

  private async getOwnedSchedule(
    context: LecturerContext,
    scheduleId: number,
    historical = false,
  ) {
    const schedule = await context.studentPrisma.schedule.findFirst({
      where: {
        id: scheduleId,
        ...this.buildOwnedScheduleWhere(context, historical),
      },
      include: {
        course: true,
        offering: true,
        studentClass: {
          include: {
            faculty: true,
          },
        },
      },
    });

    if (!schedule) {
      throw new NotFoundException('Không tìm thấy lớp học phần');
    }

    return schedule;
  }

  private buildOwnedScheduleWhere(
    context: LecturerContext,
    historical: boolean,
  ) {
    return {
      ...(historical ? {} : { isActive: true }),
      OR: [
        {
          lecturerId: context.lecturerProfile.id,
        },
        {
          lecturerAssignments: {
            some: {
              lecturerId: context.lecturerProfile.id,
              ...(historical ? {} : { isActive: true }),
            },
          },
        },
      ],
    };
  }

  private assertSessionMatchesSchedule(schedule: any, startAt: Date) {
    if (schedule.offeringId == null) {
      return;
    }

    if (!isScheduleOccurrenceOnDate(schedule, startAt)) {
      throw new BadRequestException(
        'Thời gian mở điểm danh nằm ngoài lịch của lớp học phần',
      );
    }
  }

  private async getOwnedScheduleIds(
    context: LecturerContext,
    scheduleId?: number,
  ) {
    const schedules = await this.getOwnedSchedules(context, scheduleId);
    return schedules.map((item) => item.id);
  }

  private async buildClassItems(context: LecturerContext, schedules: any[]) {
    if (schedules.length === 0) {
      return [];
    }

    const scheduleIds = schedules.map((schedule) => schedule.id);
    const studentsByScheduleId = await this.getStudentsBySchedules(
      context,
      schedules,
    );
    const sessions = await context.studentPrisma.attendanceSession.findMany({
      where: {
        scheduleId: {
          in: scheduleIds,
        },
      },
      orderBy: [{ attendanceDate: 'desc' }, { id: 'desc' }],
    });

    const latestSessionByScheduleId = new Map<number, any>();
    const openSessionByScheduleId = new Map<number, any>();
    const totalSessionsByScheduleId = new Map<number, number>();

    for (const session of sessions) {
      totalSessionsByScheduleId.set(
        session.scheduleId,
        (totalSessionsByScheduleId.get(session.scheduleId) ?? 0) + 1,
      );

      if (!latestSessionByScheduleId.has(session.scheduleId)) {
        latestSessionByScheduleId.set(session.scheduleId, session);
      }

      if (
        session.status === 'open' &&
        !openSessionByScheduleId.has(session.scheduleId)
      ) {
        openSessionByScheduleId.set(session.scheduleId, session);
      }
    }

    return schedules
      .map((schedule) => {
        const students = studentsByScheduleId.get(schedule.id) ?? [];
        const currentSession =
          openSessionByScheduleId.get(schedule.id) ??
          latestSessionByScheduleId.get(schedule.id) ??
          null;

        return {
          scheduleId: schedule.id,
          courseCode: schedule.course.code,
          courseName: schedule.course.name,
          classCode: this.buildClassCode(schedule),
          studentCount: students.length,
          room: this.normalizeRoomName(schedule.room),
          timeLabel: `${this.weekdayLabel(schedule.dayOfWeek)} • ${schedule.startTime} - ${schedule.endTime}`,
          timeRange: `${schedule.startTime} - ${schedule.endTime}`,
          currentSessionStatus: this.mapSessionStatus(currentSession),
          totalSessions: totalSessionsByScheduleId.get(schedule.id) ?? 0,
          lastAttendanceDate:
            currentSession?.attendanceDate?.toISOString() ?? null,
        };
      })
      .sort((left, right) => {
        const leftPriority = this.sessionPriority(
          left.currentSessionStatus.code,
        );
        const rightPriority = this.sessionPriority(
          right.currentSessionStatus.code,
        );

        if (leftPriority !== rightPriority) {
          return leftPriority - rightPriority;
        }

        return left.classCode.localeCompare(right.classCode);
      });
  }

  private async getStudentsByClassIds(
    context: LecturerContext,
    classIds: number[],
    activeOnly = true,
  ) {
    const uniqueClassIds = [...new Set(classIds)].filter((value) => value > 0);
    const students = uniqueClassIds.length
      ? await context.studentPrisma.student.findMany({
          where: {
            classId: {
              in: uniqueClassIds,
            },
            ...(activeOnly ? { isActive: true } : {}),
            school: {
              code: context.schoolCode,
            },
          },
          include: {
            studentClass: true,
          },
          orderBy: [{ mssv: 'asc' }],
        })
      : [];

    const result = new Map<number, any[]>();

    for (const student of students) {
      const existing = result.get(student.classId) ?? [];
      existing.push(student);
      result.set(student.classId, existing);
    }

    return result;
  }

  private async getStudentsBySchedules(
    context: LecturerContext,
    schedules: any[],
    activeOnly = true,
  ) {
    const result = new Map<number, any[]>();
    const offeringIds = [
      ...new Set<number>(
        schedules
          .map((schedule) => schedule.offeringId)
          .filter((value): value is number => Number.isInteger(value)),
      ),
    ];
    const enrollmentDelegate = (context.studentPrisma as any)
      .courseOfferingEnrollment;
    const enrollments =
      offeringIds.length > 0 && enrollmentDelegate?.findMany
        ? await enrollmentDelegate.findMany({
            where: {
              offeringId: {
                in: offeringIds,
              },
              ...(activeOnly
                ? {
                    isActive: true,
                    offering: {
                      isActive: true,
                    },
                  }
                : {}),
              student: {
                ...(activeOnly ? { isActive: true } : {}),
                school: {
                  code: context.schoolCode,
                },
              },
            },
            include: {
              student: {
                include: {
                  studentClass: true,
                },
              },
            },
            orderBy: {
              student: {
                mssv: 'asc',
              },
            },
          })
        : [];
    const studentsByOfferingId = new Map<number, any[]>();

    for (const enrollment of enrollments) {
      const existing = studentsByOfferingId.get(enrollment.offeringId) ?? [];
      existing.push(enrollment.student);
      studentsByOfferingId.set(enrollment.offeringId, existing);
    }

    const legacySchedules = schedules.filter(
      (schedule) => schedule.offeringId == null,
    );
    const studentsByClassId = await this.getStudentsByClassIds(
      context,
      legacySchedules.map((schedule) => schedule.classId),
      activeOnly,
    );

    for (const schedule of schedules) {
      const students =
        schedule.offeringId == null
          ? (studentsByClassId.get(schedule.classId) ?? [])
          : (studentsByOfferingId.get(schedule.offeringId) ?? []);
      result.set(schedule.id, students);
    }

    return result;
  }

  private async getScheduleStudents(
    context: LecturerContext,
    schedule: any,
    activeOnly = true,
  ) {
    const studentsByScheduleId = await this.getStudentsBySchedules(
      context,
      [schedule],
      activeOnly,
    );
    return studentsByScheduleId.get(schedule.id) ?? [];
  }

  private async ensureSessionRecords(
    context: LecturerContext,
    sessionId: number,
    students: any[],
  ) {
    const existingRecords =
      await context.studentPrisma.attendanceRecord.findMany({
        where: {
          sessionId,
        },
        select: {
          studentId: true,
        },
      });
    const existingStudentIds = new Set(
      existingRecords.map((record) => record.studentId),
    );
    const missingStudents = students.filter(
      (student) => !existingStudentIds.has(student.id),
    );

    if (missingStudents.length === 0) {
      return;
    }

    await context.studentPrisma.attendanceRecord.createMany({
      data: missingStudents.map((student) => ({
        sessionId,
        studentId: student.id,
        status: 'absent',
        scanResult: 'pending',
        scanAttempts: 0,
        note: null,
        lastFailureReason: 'Chưa điểm danh',
        checkInAt: null,
      })),
    });
  }

  private async syncExpiredSessions(
    context: LecturerContext,
    scheduleIds: number[],
  ) {
    if (scheduleIds.length === 0) {
      return;
    }

    const expiredSessions =
      await context.studentPrisma.attendanceSession.findMany({
        where: {
          scheduleId: {
            in: scheduleIds,
          },
          status: 'open',
          closesAt: {
            lt: new Date(),
          },
        },
        include: {
          schedule: {
            include: {
              course: true,
              offering: true,
              studentClass: true,
            },
          },
        },
      });

    await context.studentPrisma.attendanceSession.updateMany({
      where: {
        scheduleId: {
          in: scheduleIds,
        },
        status: 'open',
        closesAt: {
          lt: new Date(),
        },
      },
      data: {
        status: 'closed',
      },
    });

    for (const session of expiredSessions) {
      await this.createLecturerNotification(context, {
        type: 'attendance_closed',
        referenceKey: `attendance_closed:${session.id}`,
        title: 'Phiên điểm danh đã kết thúc',
        body: `Phiên điểm danh lớp ${this.buildClassCode(session.schedule)} đã kết thúc lúc ${this.formatDateTime(session.closesAt ?? new Date())}.`,
      });
    }
  }

  private async syncScheduleLifecycleNotifications(
    context: LecturerContext,
    schedules: any[],
  ) {
    if (schedules.length === 0) {
      return;
    }

    const now = new Date();
    const upcomingThreshold = new Date(now.getTime() + 30 * 60 * 1000);
    const today = this.getDayStart(now);

    for (const schedule of schedules) {
      if (!isScheduleOccurrenceOnDate(schedule, today)) {
        continue;
      }

      const startsAt = this.combineDateAndTime(today, schedule.startTime);
      const startedUntil = new Date(startsAt.getTime() + 10 * 60 * 1000);
      const dateKey = this.formatDateKey(today);

      if (startsAt > now && startsAt <= upcomingThreshold) {
        await this.createLecturerNotification(context, {
          type: 'schedule_upcoming',
          referenceKey: `schedule_upcoming:${schedule.id}:${dateKey}`,
          title: 'Sắp đến giờ học',
          body: `Lớp ${this.buildClassCode(schedule)} sẽ bắt đầu lúc ${this.formatTime(startsAt)} tại ${schedule.room}.`,
        });
      }

      if (startsAt <= now && now <= startedUntil) {
        await this.createLecturerNotification(context, {
          type: 'schedule_started',
          referenceKey: `schedule_started:${schedule.id}:${dateKey}`,
          title: 'Đã đến giờ học',
          body: `Lớp ${this.buildClassCode(schedule)} đã bắt đầu lúc ${this.formatTime(startsAt)}.`,
        });
      }
    }
  }

  private async syncEndingSoonNotifications(
    context: LecturerContext,
    scheduleIds: number[],
  ) {
    if (scheduleIds.length === 0) {
      return;
    }

    const now = new Date();
    const endingSoon = new Date(now.getTime() + 10 * 60 * 1000);
    const sessions = await context.studentPrisma.attendanceSession.findMany({
      where: {
        scheduleId: {
          in: scheduleIds,
        },
        status: 'open',
        closesAt: {
          gte: now,
          lte: endingSoon,
        },
      },
      include: {
        schedule: {
          include: {
            course: true,
            offering: true,
            studentClass: true,
          },
        },
      },
    });

    for (const session of sessions) {
      await this.createLecturerNotification(context, {
        type: 'attendance_closing',
        referenceKey: `attendance_closing:${session.id}`,
        title: 'Phiên điểm danh sắp kết thúc',
        body: `Phiên điểm danh lớp ${this.buildClassCode(session.schedule)} sẽ kết thúc lúc ${this.formatDateTime(session.closesAt ?? endingSoon)}.`,
      });
    }
  }

  private async fetchLecturerNotifications(
    context: LecturerContext,
    take?: number,
  ) {
    const notifications =
      await context.lecturerPrisma.lecturerNotification.findMany({
        where: {
          lecturerId: context.lecturerProfile.id,
        },
        orderBy: {
          createdAt: 'desc',
        },
        ...(take ? { take } : {}),
      });

    return {
      unreadCount: notifications.filter((item) => !item.isRead).length,
      items: notifications.map((item) => this.mapNotification(item)),
    };
  }

  private async createLecturerNotification(
    context: LecturerContext,
    input: NotificationCreateInput,
  ) {
    if (input.referenceKey) {
      const notification =
        await context.lecturerPrisma.lecturerNotification.upsert({
          where: {
            referenceKey: input.referenceKey,
          },
          update: {
            title: input.title,
            body: input.body,
            type: input.type,
            lecturerId: context.lecturerProfile.id,
          },
          create: {
            lecturerId: context.lecturerProfile.id,
            title: input.title,
            body: input.body,
            type: input.type,
            isRead: false,
            referenceKey: input.referenceKey,
          },
        });

      return this.mapNotification(notification);
    }

    const notification =
      await context.lecturerPrisma.lecturerNotification.create({
        data: {
          lecturerId: context.lecturerProfile.id,
          title: input.title,
          body: input.body,
          type: input.type,
          isRead: false,
        },
      });

    return this.mapNotification(notification);
  }

  private buildRecordPayload(
    item: NonNullable<SaveAttendanceBody['records']>[number],
    existing: any,
  ) {
    const note = item.note?.trim() ? item.note.trim() : null;
    const checkInAt =
      item.status === 'ABSENT'
        ? null
        : item.checkInAt
          ? this.parseDateValue(item.checkInAt, 'checkInAt')
          : (existing?.checkInAt ?? null);

    if (item.status === 'OK') {
      return {
        status: 'present',
        scanResult:
          existing?.scanResult === 'success' ? existing.scanResult : 'manual',
        checkInAt,
        note,
        lastFailureReason: null,
      };
    }

    if (item.status === 'REVIEW') {
      return {
        status: 'needs_review',
        scanResult:
          existing?.scanResult === 'success'
            ? existing.scanResult
            : 'manual_review',
        checkInAt,
        note,
        lastFailureReason:
          note ?? existing?.lastFailureReason ?? 'Cần kiểm tra thêm',
      };
    }

    return {
      status: 'absent',
      scanResult: 'manual_absent',
      checkInAt: null,
      note,
      lastFailureReason:
        note ??
        existing?.lastFailureReason ??
        'Chưa điểm danh hoặc không hợp lệ',
    };
  }

  private getAttendanceRecordMap(records: any[]) {
    return new Map<number, any>(
      records.map((record) => [record.studentId, record]),
    );
  }

  private summarizeAttendance(
    students: any[],
    recordMap: Map<number, any>,
  ): AttendanceSummary {
    let okCount = 0;
    let reviewCount = 0;
    let absentCount = 0;

    for (const student of students) {
      const status = this.getAttendanceStatusCode(recordMap.get(student.id));

      if (status === 'OK') {
        okCount += 1;
      } else if (status === 'REVIEW') {
        reviewCount += 1;
      } else {
        absentCount += 1;
      }
    }

    return {
      totalStudents: students.length,
      okCount,
      reviewCount,
      absentCount,
    };
  }

  private getAttendanceStatusCode(record: any): 'OK' | 'REVIEW' | 'ABSENT' {
    if (!record) {
      return 'ABSENT';
    }

    if (record.status === 'present' || record.status === 'late') {
      return 'OK';
    }

    if (record.status === 'needs_review') {
      return 'REVIEW';
    }

    return 'ABSENT';
  }

  private getAttendanceDisplay(record: any) {
    const code = this.getAttendanceStatusCode(record);

    if (code === 'OK') {
      return {
        code,
        label: 'OK',
      };
    }

    if (code === 'REVIEW') {
      return {
        code,
        label: 'Cần kiểm tra',
      };
    }

    return {
      code,
      label: 'Vắng',
    };
  }

  private mapAttendanceStudent(student: any, record: any) {
    const status = this.getAttendanceDisplay(record);

    return {
      recordId: record?.id ?? null,
      studentId: student.id,
      mssv: student.mssv,
      fullName: student.fullName,
      status,
      checkInAt: record?.checkInAt?.toISOString() ?? null,
      note: this.getRecordNote(record),
    };
  }

  private getRecordNote(record: any) {
    return record?.note ?? record?.lastFailureReason ?? null;
  }

  private mapSessionStatus(session: any) {
    if (!session) {
      return {
        code: 'not_created',
        label: 'Chưa tạo phiên điểm danh',
      };
    }

    switch (session.status) {
      case 'open':
        return {
          code: 'open',
          label: 'Đang mở',
        };
      case 'closed':
        return {
          code: 'closed',
          label: 'Đã đóng',
        };
      default:
        return {
          code: 'scheduled',
          label: 'Đã lên lịch',
        };
    }
  }

  private mapNotification(notification: any) {
    return {
      id: notification.id,
      title: notification.title,
      body: notification.body,
      type: notification.type,
      isRead: notification.isRead,
      createdAt: notification.createdAt.toISOString(),
    };
  }

  private mapLecturerProfile(lecturer: any) {
    return {
      id: lecturer.id,
      fullName: lecturer.fullName,
      lecturerCode: lecturer.lecturerCode,
      faculty: lecturer.faculty?.name ?? null,
      email: lecturer.email ?? null,
      phoneNumber: lecturer.phoneNumber ?? null,
      school: lecturer.school?.name ?? null,
      schoolCode: lecturer.school?.code ?? null,
    };
  }

  private resolveSessionWindow(
    body: CreateAttendanceSessionBody,
  ): SessionWindow {
    const startAt = body.startAt
      ? this.parseDateValue(body.startAt, 'startAt')
      : new Date();
    let endAt: Date;

    if (body.endAt) {
      endAt = this.parseDateValue(body.endAt, 'endAt');
    } else {
      const durationMinutes =
        Number.isFinite(body.durationMinutes) &&
        Number(body.durationMinutes) > 0
          ? Number(body.durationMinutes)
          : 20;
      endAt = new Date(startAt.getTime() + durationMinutes * 60 * 1000);
    }

    if (endAt.getTime() <= startAt.getTime()) {
      throw new BadRequestException(
        'Thời gian kết thúc phải sau thời gian bắt đầu',
      );
    }

    const durationMinutes = Math.ceil(
      (endAt.getTime() - startAt.getTime()) / 60_000,
    );
    if (durationMinutes > 240) {
      throw new BadRequestException(
        'Phiên điểm danh không được kéo dài quá 240 phút',
      );
    }

    if (endAt.getTime() <= Date.now()) {
      throw new BadRequestException(
        'Thời gian kết thúc phiên điểm danh phải ở tương lai',
      );
    }

    return {
      startAt,
      endAt,
      durationMinutes,
    };
  }

  private parseDateValue(value: string, fieldName: string) {
    const parsed = new Date(value);

    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException(`${fieldName} không hợp lệ`);
    }

    return parsed;
  }

  private ensurePositiveId(
    value: string | number | undefined,
    fieldName: string,
  ) {
    const parsed = Number(value);

    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new BadRequestException(`${fieldName} không hợp lệ`);
    }

    return parsed;
  }

  private combineDateAndTime(source: Date, timeValue: string) {
    const [hours, minutes] = timeValue.split(':').map((value) => Number(value));
    const result = new Date(source);
    result.setHours(hours || 0, minutes || 0, 0, 0);
    return result;
  }

  private getIsoDay(value: Date) {
    const day = value.getDay();
    return day === 0 ? 7 : day;
  }

  private buildClassCode(schedule: any) {
    return (
      schedule.offering?.code ??
      `${schedule.course.code}-${schedule.studentClass.code}`
    );
  }

  private normalizeRoomName(room: string) {
    return room
      .replace(/^Phong\b/, 'Phòng')
      .replace(/^Giang duong\b/, 'Giảng đường');
  }

  private formatDate(value: Date) {
    const day = `${value.getDate()}`.padStart(2, '0');
    const month = `${value.getMonth() + 1}`.padStart(2, '0');
    const year = `${value.getFullYear()}`;
    return `${day}/${month}/${year}`;
  }

  private formatTime(value: Date) {
    const hours = `${value.getHours()}`.padStart(2, '0');
    const minutes = `${value.getMinutes()}`.padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  private formatDateTime(value: Date) {
    return `${this.formatDate(value)} ${this.formatTime(value)}`;
  }

  private formatDateKey(value: Date) {
    const year = `${value.getFullYear()}`;
    const month = `${value.getMonth() + 1}`.padStart(2, '0');
    const day = `${value.getDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private weekdayLabel(dayOfWeek: number) {
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return labels[Math.max(0, Math.min(dayOfWeek - 1, labels.length - 1))];
  }

  private getDayStart(value: Date) {
    const result = new Date(value);
    result.setHours(0, 0, 0, 0);
    return result;
  }

  private getDayEnd(value: Date) {
    const result = this.getDayStart(value);
    result.setDate(result.getDate() + 1);
    return result;
  }

  private sessionPriority(statusCode: string) {
    switch (statusCode) {
      case 'open':
        return 0;
      case 'closed':
        return 1;
      case 'scheduled':
        return 2;
      default:
        return 3;
    }
  }
}
