import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaTenantService } from '../../database/prisma/prisma-tenant.service';
import type {
  AttendanceDecision,
  AttendanceEvidence,
  AttendanceFailureReason,
  BleEvidence,
} from '../attendance/attendance.domain';
import { decideAttendance } from '../attendance/attendance-decision.engine';
import { BleTestConfig } from '../attendance/ble-test.config';
import {
  isDateWithinScheduleBounds,
  resolveScheduleOccurrenceDates,
} from '../schedules/schedule-recurrence';
import { FaceAuthService } from './face-auth.service';

type StudentQuery = {
  schoolCode?: string;
  mssv?: string;
};

type StudentScheduleQuery = StudentQuery & {
  view?: 'day' | 'week' | 'month';
  date?: string;
};

type StudentHistoryQuery = StudentQuery & {
  courseCode?: string;
  status?: string;
};

type AttendanceScanBody = StudentQuery &
  AttendanceEvidence & {
    sessionId?: number;
    faceSessionId?: string;
    faceSessionToken?: string;
    faceShard?: string;
  };

type StudentRecord = NonNullable<
  Awaited<ReturnType<StudentsService['findStudent']>>
>;

type StudentContext = {
  prisma: PrismaClient;
  student: StudentRecord;
};

type StudentOfferingAccess = {
  hasOfferingData: boolean;
  activeOfferingIds: number[];
  allOfferingIds: number[];
};

type ScheduleEntity = any;
type SessionEntity = any;
type NotificationEntity = any;
type SessionWithRelations = any;

type DerivedAttendanceState = {
  code: 'not_open' | 'open' | 'closed' | 'checked_in';
  label: string;
  canAttend: boolean;
};

type DerivedHistoryStatus = {
  code: 'present' | 'late' | 'needs_review' | 'absent' | 'failed';
  label: string;
};

@Injectable()
export class StudentsService {
  constructor(
    private readonly prismaTenant: PrismaTenantService,
    private readonly faceAuth: FaceAuthService,
  ) {}

  async getStudentHome(query: StudentQuery) {
    const context = await this.getStudentContext(query);
    const today = this.startOfDay(new Date());
    const offeringAccess = await this.getStudentOfferingAccess(context);

    const [schedulePayload, historyPayload, notificationsPayload] =
      await Promise.all([
        this.buildSchedulePayload(
          context,
          {
            view: 'day',
            date: this.formatDateKey(today),
          },
          offeringAccess,
        ),
        this.buildAttendanceHistoryPayload(context, {}, offeringAccess),
        this.getNotifications(query),
      ]);

    return {
      student: this.mapStudentProfile(context.student),
      summary: {
        totalCourses: schedulePayload.scheduleCount,
        openAttendanceCount: schedulePayload.items.filter(
          (item) => item.canAttend,
        ).length,
        attendedCount: historyPayload.items.filter((item) =>
          ['present', 'late', 'needs_review'].includes(item.status.code),
        ).length,
        unreadNotificationCount: notificationsPayload.unreadCount,
      },
      features: [
        {
          key: 'schedule',
          title: 'Lịch học',
          description: 'Theo dõi lịch học và điểm danh theo ngày hoặc tuần',
          icon: 'calendar',
        },
        {
          key: 'history',
          title: 'Lịch sử điểm danh',
          description: 'Xem toàn bộ các lần điểm danh và kết quả',
          icon: 'history',
        },
        {
          key: 'notifications',
          title: 'Thông báo',
          description: 'Cập nhật phiên điểm danh và kết quả mới nhất',
          icon: 'notifications',
        },
        {
          key: 'profile',
          title: 'Thông tin cá nhân',
          description: 'Quản lý thông tin học tập và liên hệ',
          icon: 'profile',
        },
        {
          key: 'logout',
          title: 'Đăng xuất',
          description: 'Quay lại màn hình đăng nhập',
          icon: 'logout',
        },
      ],
      todaySchedules: schedulePayload.items,
      recentHistory: historyPayload.items.slice(0, 3),
      notifications: notificationsPayload.items.slice(0, 3),
    };
  }

  async getSchedule(query: StudentScheduleQuery) {
    const context = await this.getStudentContext(query);
    return this.buildSchedulePayload(context, query);
  }

  async startAttendanceFaceSession(body: AttendanceScanBody) {
    const context = await this.getStudentContext(body);
    const sessionId = Number(body.sessionId);

    if (!Number.isFinite(sessionId) || sessionId <= 0) {
      throw new BadRequestException('Mã phiên điểm danh không hợp lệ');
    }

    const offeringAccess = await this.getStudentOfferingAccess(context);

    const session = await context.prisma.attendanceSession.findFirst({
      where: {
        id: sessionId,
        schedule: this.buildStudentScheduleWhere(context, offeringAccess, true),
      },
      include: {
        records: {
          where: {
            studentId: context.student.id,
          },
          take: 1,
        },
      },
    });

    if (!session) {
      throw new NotFoundException('Không tìm thấy buổi học điểm danh');
    }

    const now = new Date();
    const openedAt = session.openedAt ? new Date(session.openedAt) : null;
    const closesAt = session.closesAt ? new Date(session.closesAt) : null;
    if (openedAt && openedAt.getTime() > now.getTime()) {
      throw new BadRequestException('Buổi học này chưa mở điểm danh');
    }

    if (
      session.status !== 'open' ||
      (closesAt && closesAt.getTime() < now.getTime())
    ) {
      throw new BadRequestException('Buổi học này không còn mở điểm danh');
    }

    if (session.records[0]?.scanResult === 'success') {
      throw new BadRequestException('Sinh viên đã điểm danh trong phiên này');
    }

    const faceIdentityKey = context.student.faceIdentityKey?.trim();
    if (!faceIdentityKey) {
      throw new BadRequestException(
        'Tài khoản sinh viên chưa được liên kết khuôn mặt',
      );
    }

    const faceSession = await this.faceAuth.startSession(faceIdentityKey);
    return {
      attendanceSessionId: session.id,
      faceSessionId: faceSession.session_id,
      faceSessionToken: faceSession.session_token,
      faceShard: faceSession.shard,
      stage: faceSession.stage,
    };
  }

  async scanAttendance(body: AttendanceScanBody) {
    const context = await this.getStudentContext(body);
    const sessionId = Number(body.sessionId);

    if (!Number.isFinite(sessionId) || sessionId <= 0) {
      throw new BadRequestException('Mã phiên điểm danh không hợp lệ');
    }

    const offeringAccess = await this.getStudentOfferingAccess(context);

    const session = await context.prisma.attendanceSession.findFirst({
      where: {
        id: sessionId,
        schedule: this.buildStudentScheduleWhere(context, offeringAccess, true),
      },
      include: {
        schedule: {
          include: {
            course: true,
            lecturer: true,
          },
        },
        records: {
          where: {
            studentId: context.student.id,
          },
          take: 1,
        },
      },
    });

    if (!session) {
      throw new NotFoundException('Không tìm thấy buổi học điểm danh');
    }

    const now = new Date();
    const openedAt = session.openedAt ? new Date(session.openedAt) : null;
    const closesAt = session.closesAt ? new Date(session.closesAt) : null;
    const canScan =
      session.status === 'open' &&
      (!openedAt || openedAt.getTime() <= now.getTime()) &&
      (!closesAt || closesAt.getTime() >= now.getTime());

    if (!canScan) {
      const message =
        openedAt && openedAt.getTime() > now.getTime()
          ? 'Phiên điểm danh chưa mở'
          : 'Phiên điểm danh đã đóng';
      return this.buildAttendanceDecision(
        'rejected_session_closed',
        null,
        now,
        message,
        false,
      );
    }

    const faceSessionId = body.faceSessionId?.trim();
    const faceSessionToken = body.faceSessionToken?.trim();
    const faceShard = body.faceShard?.trim();
    if (!faceSessionId || !faceSessionToken || !faceShard) {
      throw new BadRequestException('Thiếu kết quả xác minh khuôn mặt');
    }

    const currentRecord = session.records[0] ?? null;
    if (
      currentRecord?.scanResult === 'success' &&
      currentRecord.faceSessionId !== faceSessionId
    ) {
      return this.buildAttendanceDecision(
        'rejected_duplicate',
        null,
        now,
        'Sinh viên đã điểm danh trong phiên này',
        false,
      );
    }

    const expectedBle = BleTestConfig.fromSession(session);
    const bleFailure = BleTestConfig.validate(
      body.bleEvidence,
      expectedBle,
      session,
    );
    const evidenceFailure: AttendanceFailureReason | null =
      bleFailure ??
      (body.faceEvidence?.verified === true ? null : 'INVALID_EVIDENCE');
    if (evidenceFailure) {
      const nextAttempts = (currentRecord?.scanAttempts ?? 0) + 1;
      const flaggedData = this.buildFlaggedRecordData(
        body,
        evidenceFailure,
        nextAttempts,
      );
      const saveResult = await this.saveAttendanceAttempt(
        context,
        session.id,
        flaggedData,
      );

      await this.faceAuth.deleteSession(
        faceShard,
        faceSessionId,
        faceSessionToken,
      );

      if (saveResult.duplicate) {
        return this.buildAttendanceDecision(
          'rejected_duplicate',
          null,
          now,
          'Sinh viÃªn Ä‘Ã£ Ä‘iá»ƒm danh trong phiÃªn nÃ y',
          false,
        );
      }

      const savedRecord = saveResult.record;
      return {
        ...this.buildAttendanceDecision(
          'flagged',
          evidenceFailure,
          now,
          this.attendanceFailureMessage(evidenceFailure),
          true,
        ),
        scanState: 'flagged',
        expectedBle,
        historyItem: this.mapHistoryItem(
          session,
          savedRecord,
          this.deriveHistoryStatus(savedRecord),
        ),
      };
    }
    if (
      currentRecord?.faceSessionId === faceSessionId &&
      ['success', 'failed', 'flagged'].includes(currentRecord.scanResult)
    ) {
      const wasSuccessful = currentRecord.scanResult === 'success';
      return {
        message: wasSuccessful
          ? 'Điểm danh thành công'
          : 'Điểm danh thất bại, vui lòng thử lại',
        scanState: currentRecord.scanResult,
        canRetry: !wasSuccessful,
      };
    }
    const expectedIdentity = context.student.faceIdentityKey?.trim();
    if (!expectedIdentity) {
      throw new BadRequestException(
        'Tài khoản sinh viên chưa được liên kết khuôn mặt',
      );
    }

    const faceResult = await this.faceAuth.getSession(
      faceShard,
      faceSessionId,
      faceSessionToken,
    );
    if (!['SUCCESS', 'FAILED'].includes(faceResult.stage)) {
      throw new BadRequestException('Phiên xác minh khuôn mặt chưa hoàn tất');
    }

    const recognizedIdentity =
      faceResult.recognition?.best_match_name?.trim() ?? '';
    const outcome =
      faceResult.stage === 'SUCCESS' &&
      faceResult.final?.ok === true &&
      faceResult.recognition?.is_recognized === true &&
      recognizedIdentity === expectedIdentity
        ? 'success'
        : 'failure';
    const similarity =
      typeof faceResult.recognition?.similarity === 'number'
        ? faceResult.recognition.similarity
        : typeof faceResult.recognition?.similarity_percent === 'number'
          ? faceResult.recognition.similarity_percent / 100
          : null;

    const nextAttempts = (currentRecord?.scanAttempts ?? 0) + 1;
    const sessionStart = new Date(session.attendanceDate);
    const lateThreshold = session.lateAt
      ? new Date(session.lateAt)
      : new Date(sessionStart.getTime() + 10 * 60 * 1000);

    const recordData =
      outcome === 'success'
        ? {
            status:
              now.getTime() > lateThreshold.getTime() ? 'late' : 'present',
            scanResult: 'success',
            faceSessionId,
            faceIdentityKey: recognizedIdentity,
            faceSimilarity: similarity,
            faceVerifiedAt:
              this.parseOptionalDate(body.faceEvidence?.verifiedAt) ?? now,
            ...this.buildBleRecordData(body.bleEvidence!),
            evidence: this.buildEvidenceJson(body),
            decisionReason: null,
            checkInAt: now,
            scanAttempts: nextAttempts,
            lastFailureReason: null,
          }
        : {
            status: 'needs_review',
            scanResult: 'flagged',
            faceSessionId,
            faceIdentityKey: recognizedIdentity || expectedIdentity,
            faceSimilarity: similarity,
            faceVerifiedAt:
              this.parseOptionalDate(body.faceEvidence?.verifiedAt) ?? now,
            ...this.buildBleRecordData(body.bleEvidence!),
            evidence: this.buildEvidenceJson(body),
            decisionReason: 'FACE_VERIFICATION_FAILED',
            checkInAt: null,
            scanAttempts: nextAttempts,
            lastFailureReason: 'FACE_VERIFICATION_FAILED',
          };
    const saveResult = await this.saveAttendanceAttempt(
      context,
      session.id,
      recordData,
    );

    await this.faceAuth.deleteSession(
      faceShard,
      faceSessionId,
      faceSessionToken,
    );

    if (saveResult.duplicate) {
      return this.buildAttendanceDecision(
        'rejected_duplicate',
        null,
        now,
        'Sinh viÃªn Ä‘Ã£ Ä‘iá»ƒm danh trong phiÃªn nÃ y',
        false,
      );
    }

    const savedRecord = saveResult.record;
    await context.prisma.studentNotification.create({
      data: {
        studentId: context.student.id,
        sessionId: session.id,
        title:
          outcome === 'success'
            ? `Điểm danh thành công cho ${session.schedule.course.code}`
            : `Điểm danh thất bại cho ${session.schedule.course.code}`,
        body:
          outcome === 'success'
            ? `Hệ thống đã ghi nhận điểm danh cho môn ${session.schedule.course.name}.`
            : 'Hệ thống chưa nhận diện được khuôn mặt. Bạn có thể thử lại khi phiên điểm danh vẫn mở.',
        type:
          outcome === 'success' ? 'attendance_success' : 'attendance_flagged',
        isRead: false,
      },
    });

    const historyItem = this.mapHistoryItem(
      session,
      savedRecord,
      this.deriveHistoryStatus(savedRecord),
    );
    const finalDecision = decideAttendance({
      sessionIsOpen: true,
      alreadySuccessful: false,
      faceVerified: outcome === 'success',
      recordedAt: now,
      lateAt: lateThreshold,
    });

    return {
      ...this.buildAttendanceDecision(
        finalDecision.status,
        finalDecision.reason,
        now,
        outcome === 'success'
          ? 'Điểm danh thành công'
          : this.attendanceFailureMessage('FACE_VERIFICATION_FAILED'),
        finalDecision.canRetry,
      ),
      message:
        outcome === 'success'
          ? 'Điểm danh thành công'
          : 'Điểm danh thất bại, vui lòng thử lại',
      scanState: outcome === 'success' ? 'success' : 'flagged',
      canRetry: outcome !== 'success',
      schedule: {
        sessionId: session.id,
        courseCode: session.schedule.course.code,
        courseName: session.schedule.course.name,
        room: this.normalizeRoomName(session.schedule.room),
        lecturerName:
          session.schedule.lecturer?.fullName ?? 'Chưa phân công giảng viên',
        startTime: session.schedule.startTime,
        endTime: session.schedule.endTime,
      },
      historyItem,
    };
  }

  async getAttendanceHistory(query: StudentHistoryQuery) {
    const context = await this.getStudentContext(query);
    return this.buildAttendanceHistoryPayload(context, query);
  }

  async getAttendanceHistoryDetail(id: number, query: StudentQuery) {
    const context = await this.getStudentContext(query);
    const sessionId = Number(id);

    if (!Number.isFinite(sessionId) || sessionId <= 0) {
      throw new BadRequestException('Mã phiên điểm danh không hợp lệ');
    }

    const offeringAccess = await this.getStudentOfferingAccess(context);

    const session = await context.prisma.attendanceSession.findFirst({
      where: {
        id: sessionId,
        schedule: this.buildStudentScheduleWhere(
          context,
          offeringAccess,
          false,
        ),
      },
      include: {
        schedule: {
          include: {
            course: true,
            lecturer: true,
          },
        },
        records: {
          where: {
            studentId: context.student.id,
          },
          take: 1,
        },
      },
    });

    if (!session) {
      throw new NotFoundException('Không tìm thấy chi tiết điểm danh');
    }

    const record = session.records[0] ?? null;
    const status = this.deriveHistoryStatus(record);

    return {
      sessionId: session.id,
      status,
      courseCode: session.schedule.course.code,
      courseName: session.schedule.course.name,
      room: this.normalizeRoomName(session.schedule.room),
      lecturerName:
        session.schedule.lecturer?.fullName ?? 'Chưa phân công giảng viên',
      lecturerCode: session.schedule.lecturer?.lecturerCode ?? null,
      attendanceDate: session.attendanceDate.toISOString(),
      timeRange: `${session.schedule.startTime} - ${session.schedule.endTime}`,
      openedAt: session.openedAt?.toISOString() ?? null,
      closesAt: session.closesAt?.toISOString() ?? null,
      sessionStatus: session.status,
      scanResult: record?.scanResult ?? 'pending',
      scanAttempts: record?.scanAttempts ?? 0,
      checkInAt: record?.checkInAt?.toISOString() ?? null,
      lastFailureReason: record?.lastFailureReason ?? null,
    };
  }

  async getNotifications(query: StudentQuery) {
    const context = await this.getStudentContext(query);
    const notifications = await context.prisma.studentNotification.findMany({
      where: {
        studentId: context.student.id,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      unreadCount: notifications.filter((item) => !item.isRead).length,
      items: notifications.map((item) => this.mapNotification(item)),
    };
  }

  async markNotificationRead(id: number, query: StudentQuery) {
    const context = await this.getStudentContext(query);
    const notificationId = Number(id);

    if (!Number.isFinite(notificationId) || notificationId <= 0) {
      throw new BadRequestException('Mã thông báo không hợp lệ');
    }

    const notification = await context.prisma.studentNotification.findFirst({
      where: {
        id: notificationId,
        studentId: context.student.id,
      },
    });

    if (!notification) {
      throw new NotFoundException('Không tìm thấy thông báo');
    }

    const updated = await context.prisma.studentNotification.update({
      where: {
        id: notificationId,
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

  async getProfile(query: StudentQuery) {
    const context = await this.getStudentContext(query);

    return {
      student: this.mapStudentProfile(context.student),
    };
  }

  private async buildSchedulePayload(
    context: StudentContext,
    query: StudentScheduleQuery,
    offeringAccess?: StudentOfferingAccess,
  ) {
    const access =
      offeringAccess ?? (await this.getStudentOfferingAccess(context));
    const anchorDate = this.resolveAnchorDate(query.date);
    const view =
      query.view === 'week' || query.view === 'month' ? query.view : 'day';
    const range = this.resolveScheduleRange(anchorDate, view);

    const schedules = await context.prisma.schedule.findMany({
      where: this.buildStudentScheduleWhere(context, access, true),
      include: {
        course: true,
        lecturer: true,
        offering: true,
      },
      orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }],
    });

    const scheduleIds = schedules.map((item) => item.id);
    const sessions = scheduleIds.length
      ? await context.prisma.attendanceSession.findMany({
          where: {
            scheduleId: {
              in: scheduleIds,
            },
            attendanceDate: {
              gte: range.start,
              lt: range.endExclusive,
            },
          },
          include: {
            records: {
              where: {
                studentId: context.student.id,
              },
            },
          },
          orderBy: [{ attendanceDate: 'asc' }, { id: 'asc' }],
        })
      : [];

    const sessionMap = new Map<string, SessionEntity>();

    for (const session of sessions) {
      sessionMap.set(
        this.buildSessionKey(session.scheduleId, session.attendanceDate),
        session,
      );
    }

    const items = schedules
      .flatMap((schedule) => {
        const scheduledDates = resolveScheduleOccurrenceDates(
          schedule,
          range.start,
          range.endExclusive,
        );
        const sessionDates = sessions
          .filter((session) => session.scheduleId === schedule.id)
          .map((session) => this.startOfDay(session.attendanceDate))
          .filter((date) => isDateWithinScheduleBounds(schedule, date));
        const occurrenceDates = [
          ...new Map(
            [...scheduledDates, ...sessionDates].map((date) => [
              this.formatDateKey(date),
              date,
            ]),
          ).values(),
        ].sort((left, right) => left.getTime() - right.getTime());

        return occurrenceDates.map((occurrenceDate) => {
          const session = sessionMap.get(
            this.buildSessionKey(schedule.id, occurrenceDate),
          );
          const record = session?.records?.[0] ?? null;
          const attendanceState = this.deriveAttendanceState(session, record);
          const occurrenceStart = this.combineDateAndTime(
            occurrenceDate,
            schedule.startTime,
          );
          const occurrenceEnd = this.combineDateAndTime(
            occurrenceDate,
            schedule.endTime,
          );

          return {
            scheduleId: schedule.id,
            sessionId: session?.id ?? null,
            courseCode: schedule.course.code,
            courseName: schedule.course.name,
            classSectionCode: schedule.offering?.code ?? schedule.course.code,
            offeringCode: schedule.offering?.code ?? null,
            termCode: schedule.offering?.termCode ?? null,
            termName: schedule.offering?.termName ?? null,
            recurrenceKind: schedule.recurrenceKind,
            scheduleStartsAt: schedule.startsAt?.toISOString() ?? null,
            scheduleEndsAt: schedule.endsAt?.toISOString() ?? null,
            lecturerName:
              schedule.lecturer?.fullName ?? 'Chưa phân công giảng viên',
            lecturerCode: schedule.lecturer?.lecturerCode ?? null,
            room: this.normalizeRoomName(schedule.room),
            startTime: schedule.startTime,
            endTime: schedule.endTime,
            timeRange: `${schedule.startTime} - ${schedule.endTime}`,
            date: occurrenceDate.toISOString(),
            weekdayLabel: this.formatWeekdayLabel(occurrenceDate),
            dayLabel: this.formatDateKey(occurrenceDate),
            attendanceState,
            canAttend: attendanceState.canAttend,
            expectedBle: BleTestConfig.fromSession({
              beaconId: session?.beaconId,
              roomId: session?.roomId,
              bleServiceUuid: session?.bleServiceUuid,
              bleMinRssi: session?.bleMinRssi,
              schedule: {
                room: schedule.room,
              },
            }),
            openedAt: session?.openedAt?.toISOString() ?? null,
            closesAt: session?.closesAt?.toISOString() ?? null,
            occurrenceStart: occurrenceStart.toISOString(),
            occurrenceEnd: occurrenceEnd.toISOString(),
          };
        });
      })
      .sort((left, right) => {
        const leftTime = new Date(left.occurrenceStart).getTime();
        const rightTime = new Date(right.occurrenceStart).getTime();
        return leftTime - rightTime;
      });

    return {
      view,
      anchorDate: this.formatDateKey(anchorDate),
      range: {
        startDate: this.formatDateKey(range.start),
        endDate: this.formatDateKey(
          new Date(range.endExclusive.getTime() - 24 * 60 * 60 * 1000),
        ),
      },
      scheduleCount: schedules.length,
      items,
    };
  }

  private async buildAttendanceHistoryPayload(
    context: StudentContext,
    query: Pick<StudentHistoryQuery, 'courseCode' | 'status'>,
    offeringAccess?: StudentOfferingAccess,
  ) {
    const access =
      offeringAccess ?? (await this.getStudentOfferingAccess(context));
    const sessions = await context.prisma.attendanceSession.findMany({
      where: {
        schedule: this.buildStudentScheduleWhere(context, access, false),
        attendanceDate: {
          lt: this.endOfDay(new Date()),
        },
      },
      include: {
        schedule: {
          include: {
            course: true,
            lecturer: true,
            offering: true,
          },
        },
        records: {
          where: {
            studentId: context.student.id,
          },
          take: 1,
        },
      },
      orderBy: {
        attendanceDate: 'desc',
      },
    });

    const items = sessions
      .map((session) => {
        const record = session.records[0] ?? null;
        const status = this.deriveHistoryStatus(record);
        return this.mapHistoryItem(session, record, status);
      })
      .filter((item) => {
        if (query.courseCode && item.courseCode !== query.courseCode) {
          return false;
        }

        if (query.status && item.status.code !== query.status) {
          return false;
        }

        return true;
      });

    const courseOptions = [...new Set(items.map((item) => item.courseCode))]
      .sort()
      .map((courseCode) => ({
        courseCode,
        courseName:
          items.find((item) => item.courseCode === courseCode)?.courseName ??
          courseCode,
      }));

    return {
      filters: {
        selectedCourseCode: query.courseCode ?? null,
        selectedStatus: query.status ?? null,
        courseOptions,
        statusOptions: [
          { code: 'present', label: 'Có mặt' },
          { code: 'late', label: 'Muộn' },
          { code: 'needs_review', label: 'Cần kiểm tra' },
          { code: 'absent', label: 'Vắng' },
          { code: 'failed', label: 'Điểm danh thất bại' },
        ],
      },
      items,
    };
  }

  private mapHistoryItem(
    session: SessionWithRelations,
    record: any | null,
    status: DerivedHistoryStatus,
  ) {
    return {
      sessionId: session.id,
      courseCode: session.schedule.course.code,
      courseName: session.schedule.course.name,
      lecturerName:
        session.schedule.lecturer?.fullName ?? 'Chưa phân công giảng viên',
      room: this.normalizeRoomName(session.schedule.room),
      attendanceDate: session.attendanceDate.toISOString(),
      dayLabel: this.formatDateKey(session.attendanceDate),
      timeRange: `${session.schedule.startTime} - ${session.schedule.endTime}`,
      status,
      scanResult: record?.scanResult ?? 'pending',
      scanAttempts: record?.scanAttempts ?? 0,
    };
  }

  private mapStudentProfile(student: NonNullable<StudentContext['student']>) {
    return {
      id: student.id,
      fullName: student.fullName,
      mssv: student.mssv,
      className: student.studentClass.name,
      facultyName: student.studentClass.faculty.name,
      schoolName: student.school.name,
      schoolCode: student.school.code,
      email: student.email,
      phoneNumber: student.phoneNumber,
      citizenId: student.citizenId,
      dateOfBirth: student.dateOfBirth?.toISOString() ?? null,
    };
  }

  private buildAttendanceDecision(
    status: AttendanceDecision['status'],
    reason: AttendanceFailureReason | null,
    recordedAt: Date,
    message: string,
    canRetry: boolean,
  ): AttendanceDecision {
    return {
      status,
      reason,
      recordedAt: recordedAt.toISOString(),
      message,
      canRetry,
    };
  }

  private buildFlaggedRecordData(
    body: AttendanceScanBody,
    reason: AttendanceFailureReason,
    scanAttempts: number,
  ) {
    return {
      status: 'needs_review',
      scanResult: 'flagged',
      faceSessionId: body.faceSessionId?.trim() || null,
      faceSimilarity:
        typeof body.faceEvidence?.score === 'number'
          ? body.faceEvidence.score
          : null,
      faceVerifiedAt: this.parseOptionalDate(body.faceEvidence?.verifiedAt),
      ...this.buildBleRecordData(body.bleEvidence ?? null),
      evidence: this.buildEvidenceJson(body),
      checkInAt: null,
      scanAttempts,
      decisionReason: reason,
      lastFailureReason: reason,
    };
  }

  private buildBleRecordData(evidence: BleEvidence | null) {
    return {
      bleBeaconId: evidence?.beaconId?.trim() || null,
      bleRoomId: evidence?.roomId?.trim() || null,
      bleDeviceName: evidence?.deviceName?.trim() || null,
      bleServiceUuid: evidence?.serviceUuid?.trim().toLowerCase() || null,
      bleRssi:
        typeof evidence?.rssi === 'number' ? Math.round(evidence.rssi) : null,
      bleScannedAt: this.parseOptionalDate(evidence?.scannedAt),
      bleScanDurationMs:
        typeof evidence?.scanDurationMs === 'number'
          ? Math.round(evidence.scanDurationMs)
          : null,
    };
  }

  private buildEvidenceJson(body: AttendanceScanBody) {
    return JSON.parse(
      JSON.stringify({
        bleEvidence: body.bleEvidence ?? null,
        faceEvidence: body.faceEvidence ?? null,
        gpsEvidence: body.gpsEvidence ?? null,
      }),
    );
  }

  private parseOptionalDate(value?: string | null) {
    if (!value) {
      return null;
    }

    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  private attendanceFailureMessage(reason: AttendanceFailureReason) {
    switch (reason) {
      case 'BLE_NOT_FOUND':
        return 'Không tìm thấy BLE của phòng học';
      case 'BLE_SIGNAL_TOO_WEAK':
        return 'Tín hiệu BLE quá yếu';
      case 'BLE_ROOM_MISMATCH':
        return 'BLE không khớp với phòng của phiên điểm danh';
      case 'FACE_VERIFICATION_FAILED':
        return 'Xác thực khuôn mặt không đạt';
      default:
        return 'Bằng chứng điểm danh không hợp lệ';
    }
  }

  private mapNotification(notification: NotificationEntity) {
    return {
      id: notification.id,
      title: notification.title,
      body: notification.body,
      type: notification.type,
      isRead: notification.isRead,
      createdAt: notification.createdAt.toISOString(),
    };
  }

  private deriveAttendanceState(
    session: SessionEntity | undefined,
    record: any | null,
  ): DerivedAttendanceState {
    if (!session || session.status === 'scheduled') {
      return {
        code: 'not_open',
        label: 'Chưa mở điểm danh',
        canAttend: false,
      };
    }

    if (record && ['present', 'late', 'needs_review'].includes(record.status)) {
      return {
        code: 'checked_in',
        label: 'Đã điểm danh',
        canAttend: false,
      };
    }

    if (session.status === 'open') {
      return {
        code: 'open',
        label: 'Đang mở điểm danh',
        canAttend: true,
      };
    }

    return {
      code: 'closed',
      label: 'Đã đóng điểm danh',
      canAttend: false,
    };
  }

  private deriveHistoryStatus(record: any | null): DerivedHistoryStatus {
    switch (record?.status) {
      case 'present':
        return { code: 'present', label: 'Có mặt' };
      case 'late':
        return { code: 'late', label: 'Muộn' };
      case 'needs_review':
        return { code: 'needs_review', label: 'Cần kiểm tra' };
      case 'failed':
        return { code: 'failed', label: 'Điểm danh thất bại' };
      default:
        return { code: 'absent', label: 'Vắng' };
    }
  }

  private async saveAttendanceAttempt(
    context: StudentContext,
    sessionId: number,
    data: Record<string, unknown>,
  ): Promise<{ record: any; duplicate: boolean }> {
    const key = {
      sessionId,
      studentId: context.student.id,
    };

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const updated = await context.prisma.attendanceRecord.updateMany({
        where: {
          ...key,
          scanResult: { not: 'success' },
        },
        data,
      });

      if (updated.count === 1) {
        const record = await context.prisma.attendanceRecord.findUniqueOrThrow({
          where: { sessionId_studentId: key },
        });
        return { record, duplicate: false };
      }

      const existing = await context.prisma.attendanceRecord.findUnique({
        where: { sessionId_studentId: key },
      });
      if (existing?.scanResult === 'success') {
        return { record: existing, duplicate: true };
      }
      if (existing) {
        continue;
      }

      try {
        const record = await context.prisma.attendanceRecord.create({
          data: {
            ...key,
            ...data,
          } as any,
        });
        return { record, duplicate: false };
      } catch (error) {
        if (!this.isUniqueConstraintError(error)) {
          throw error;
        }
      }
    }

    const record = await context.prisma.attendanceRecord.findUniqueOrThrow({
      where: { sessionId_studentId: key },
    });
    return { record, duplicate: record.scanResult === 'success' };
  }

  private isUniqueConstraintError(error: unknown) {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 'P2002'
    );
  }

  private async getStudentOfferingAccess(
    context: StudentContext,
  ): Promise<StudentOfferingAccess> {
    const enrollmentDelegate = (context.prisma as any).courseOfferingEnrollment;

    // Older tenant schemas and existing demo mocks do not expose the additive
    // offering models. In that case the legacy class-based schedule remains the
    // source of truth until the new migration and ETL have both completed.
    if (!enrollmentDelegate?.findMany) {
      return {
        hasOfferingData: false,
        activeOfferingIds: [],
        allOfferingIds: [],
      };
    }

    const enrollments = await enrollmentDelegate.findMany({
      where: {
        studentId: context.student.id,
      },
      select: {
        offeringId: true,
        isActive: true,
        offering: {
          select: {
            isActive: true,
          },
        },
      },
    });
    const allOfferingIds = [
      ...new Set<number>(enrollments.map((item: any) => item.offeringId)),
    ];
    const activeOfferingIds = [
      ...new Set<number>(
        enrollments
          .filter(
            (item: any) => item.isActive && item.offering?.isActive !== false,
          )
          .map((item: any) => item.offeringId),
      ),
    ];

    return {
      hasOfferingData: enrollments.length > 0,
      activeOfferingIds,
      allOfferingIds,
    };
  }

  private buildStudentScheduleWhere(
    context: StudentContext,
    access: StudentOfferingAccess,
    activeOnly: boolean,
  ) {
    if (access.hasOfferingData) {
      return {
        ...(activeOnly ? { isActive: true } : {}),
        offeringId: {
          in: activeOnly ? access.activeOfferingIds : access.allOfferingIds,
        },
      };
    }

    return {
      ...(activeOnly ? { isActive: true } : {}),
      classId: context.student.classId,
      offeringId: null,
    };
  }

  private async getStudentContext(
    query: StudentQuery,
  ): Promise<StudentContext> {
    const schoolCode = query.schoolCode?.trim().toUpperCase();
    const mssv = query.mssv?.trim();

    if (!schoolCode) {
      throw new BadRequestException('Thiếu schoolCode');
    }

    if (!mssv) {
      throw new BadRequestException('Thiếu mssv');
    }

    const prisma = this.prismaTenant.getClient(schoolCode, 'student');
    const student = await this.findStudent(prisma, schoolCode, mssv);

    if (!student) {
      throw new NotFoundException('Không tìm thấy sinh viên');
    }

    return {
      prisma,
      student,
    };
  }

  private findStudent(prisma: PrismaClient, schoolCode: string, mssv: string) {
    return prisma.student.findFirst({
      where: {
        mssv,
        isActive: true,
        school: {
          code: schoolCode,
        },
      },
      include: {
        school: true,
        studentClass: {
          include: {
            faculty: true,
          },
        },
      },
    });
  }

  private resolveAnchorDate(dateValue?: string) {
    if (!dateValue) {
      return this.startOfDay(new Date());
    }

    const parsed = new Date(dateValue);
    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException('Ngày không hợp lệ');
    }

    return this.startOfDay(parsed);
  }

  private resolveScheduleRange(
    anchorDate: Date,
    view: 'day' | 'week' | 'month',
  ) {
    if (view === 'day') {
      return {
        start: anchorDate,
        endExclusive: new Date(anchorDate.getTime() + 24 * 60 * 60 * 1000),
      };
    }

    if (view === 'week') {
      const isoDay = this.getIsoDay(anchorDate);
      const weekStart = new Date(anchorDate);
      weekStart.setDate(weekStart.getDate() - (isoDay - 1));
      weekStart.setHours(0, 0, 0, 0);

      return {
        start: weekStart,
        endExclusive: new Date(weekStart.getTime() + 7 * 24 * 60 * 60 * 1000),
      };
    }

    const monthStart = new Date(
      anchorDate.getFullYear(),
      anchorDate.getMonth(),
      1,
    );
    monthStart.setHours(0, 0, 0, 0);

    return {
      start: monthStart,
      endExclusive: new Date(
        monthStart.getFullYear(),
        monthStart.getMonth() + 1,
        1,
      ),
    };
  }

  private combineDateAndTime(source: Date, timeValue: string) {
    const [hours, minutes] = timeValue.split(':').map((value) => Number(value));
    const result = new Date(source);
    result.setHours(hours || 0, minutes || 0, 0, 0);
    return result;
  }

  private buildSessionKey(scheduleId: number, dateValue: Date) {
    return `${scheduleId}:${this.formatDateKey(dateValue)}`;
  }

  private formatDateKey(value: Date) {
    const year = `${value.getFullYear()}`;
    const month = `${value.getMonth() + 1}`.padStart(2, '0');
    const day = `${value.getDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private normalizeRoomName(room: string) {
    return room
      .replace(/^Phong\b/, 'Phòng')
      .replace(/^Giang duong\b/, 'Giảng đường');
  }

  private formatWeekdayLabel(value: Date) {
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return labels[this.getIsoDay(value) - 1] ?? 'N/A';
  }

  private getIsoDay(value: Date) {
    const day = value.getDay();
    return day === 0 ? 7 : day;
  }

  private startOfDay(value: Date) {
    const result = new Date(value);
    result.setHours(0, 0, 0, 0);
    return result;
  }

  private endOfDay(value: Date) {
    const result = this.startOfDay(value);
    result.setDate(result.getDate() + 1);
    return result;
  }
}
