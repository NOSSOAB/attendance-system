import { Test, TestingModule } from '@nestjs/testing';
import { PrismaTenantService } from '../../database/prisma/prisma-tenant.service';
import { LecturersService } from './lecturers.service';

describe('LecturersService', () => {
  let service: LecturersService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        LecturersService,
        {
          provide: PrismaTenantService,
          useValue: {
            getClient: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<LecturersService>(LecturersService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('builds an exact offering roster while retaining legacy class fallback', async () => {
    const offeringStudent = {
      id: 101,
      mssv: 'SV101',
      classId: 8,
      studentClass: { id: 8, name: 'Lớp nguồn' },
    };
    const legacyStudent = {
      id: 202,
      mssv: 'SV202',
      classId: 7,
      studentClass: { id: 7, name: 'Lớp demo' },
    };
    const context = {
      schoolCode: 'HUCE',
      studentPrisma: {
        courseOfferingEnrollment: {
          findMany: jest
            .fn()
            .mockResolvedValue([{ offeringId: 41, student: offeringStudent }]),
        },
        student: {
          findMany: jest.fn().mockResolvedValue([legacyStudent]),
        },
      },
    };
    const schedules = [
      { id: 1, offeringId: 41, classId: 7 },
      { id: 2, offeringId: null, classId: 7 },
    ];

    const studentsByScheduleId = await (service as any).getStudentsBySchedules(
      context,
      schedules,
    );

    expect(studentsByScheduleId.get(1)).toEqual([offeringStudent]);
    expect(studentsByScheduleId.get(2)).toEqual([legacyStudent]);
    expect(
      context.studentPrisma.courseOfferingEnrollment.findMany,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          offeringId: { in: [41] },
          isActive: true,
        }),
      }),
    );
    expect(context.studentPrisma.student.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ classId: { in: [7] } }),
      }),
    );
  });

  it('does not fall back to the homeroom class for an empty offering roster', async () => {
    const findLegacyStudents = jest.fn();
    const context = {
      schoolCode: 'HUCE',
      studentPrisma: {
        courseOfferingEnrollment: {
          findMany: jest.fn().mockResolvedValue([]),
        },
        student: {
          findMany: findLegacyStudents,
        },
      },
    };

    const studentsByScheduleId = await (service as any).getStudentsBySchedules(
      context,
      [{ id: 1, offeringId: 41, classId: 7 }],
    );

    expect(studentsByScheduleId.get(1)).toEqual([]);
    expect(findLegacyStudents).not.toHaveBeenCalled();
  });

  it('keeps cancelled offering enrollments in historical rosters', async () => {
    const cancelledStudent = {
      id: 303,
      mssv: 'SV303',
      classId: 9,
      isActive: false,
      studentClass: { id: 9, name: 'Lớp lịch sử' },
    };
    const findEnrollments = jest.fn().mockResolvedValue([
      {
        offeringId: 51,
        isActive: false,
        student: cancelledStudent,
      },
    ]);
    const context = {
      schoolCode: 'HUCE',
      studentPrisma: {
        courseOfferingEnrollment: {
          findMany: findEnrollments,
        },
        student: {
          findMany: jest.fn(),
        },
      },
    };

    const studentsByScheduleId = await (service as any).getStudentsBySchedules(
      context,
      [{ id: 5, offeringId: 51, classId: 9 }],
      false,
    );

    expect(studentsByScheduleId.get(5)).toEqual([cancelledStudent]);
    const enrollmentWhere = findEnrollments.mock.calls[0][0].where;
    expect(enrollmentWhere.isActive).toBeUndefined();
    expect(enrollmentWhere.offering).toBeUndefined();
    expect(enrollmentWhere.student.isActive).toBeUndefined();
  });

  it('grants active co-lecturers current ownership and retains historical ownership', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const context = {
      lecturerProfile: { id: 77 },
      studentLecturerId: 77,
      studentPrisma: {
        schedule: { findMany },
      },
    };

    await (service as any).getOwnedSchedules(context);
    const currentWhere = findMany.mock.calls[0][0].where;
    expect(currentWhere.isActive).toBe(true);
    expect(currentWhere.OR).toContainEqual({ lecturerId: 77 });
    expect(currentWhere.OR).toContainEqual({
      lecturerAssignments: {
        some: { lecturerId: 77, isActive: true },
      },
    });

    await (service as any).getOwnedSchedules(context, undefined, true);
    const historicalWhere = findMany.mock.calls[1][0].where;
    expect(historicalWhere.isActive).toBeUndefined();
    expect(historicalWhere.OR).toContainEqual({
      lecturerAssignments: {
        some: { lecturerId: 77 },
      },
    });
  });

  it('rejects source-backed attendance outside the meeting recurrence but keeps legacy flexibility', () => {
    const sourceSchedule = {
      offeringId: 41,
      dayOfWeek: 1,
      startsAt: new Date('2026-08-03T00:00:00.000Z'),
      endsAt: new Date('2026-08-31T23:59:59.000Z'),
      recurrenceKind: 'weekly',
    };

    expect(() =>
      (service as any).assertSessionMatchesSchedule(
        sourceSchedule,
        new Date('2026-08-04T08:00:00.000Z'),
      ),
    ).toThrow('Thời gian mở điểm danh nằm ngoài lịch của lớp học phần');

    expect(() =>
      (service as any).assertSessionMatchesSchedule(
        { ...sourceSchedule, offeringId: null },
        new Date('2026-08-04T08:00:00.000Z'),
      ),
    ).not.toThrow();
  });

  it('resolves ownership using the student tenant ID when lecturer IDs differ', async () => {
    const studentPrisma = {
      lecturer: { findFirst: jest.fn().mockResolvedValue({ id: 101 }) },
    };
    const lecturerPrisma = {
      lecturer: { findFirst: jest.fn().mockResolvedValue({ id: 77 }) },
    };
    const tenant = {
      getClient: jest.fn((_school, role) => role === 'student' ? studentPrisma : lecturerPrisma),
    };
    const target = new LecturersService(tenant as any);
    const context = await (target as any).getLecturerContext({ schoolCode: 'huce', lecturerCode: 'GV01' });
    expect(context.lecturerProfile.id).toBe(77);
    expect(context.studentLecturerId).toBe(101);
    expect(studentPrisma.lecturer.findFirst).toHaveBeenCalledWith({
      where: { lecturerCode: 'GV01', isActive: true, school: { code: 'HUCE' } },
      select: { id: true },
    });
    expect((target as any).buildOwnedScheduleWhere(context, false).OR)
      .toContainEqual({ lecturerId: 101 });
    studentPrisma.lecturer.findFirst.mockResolvedValue(null as any);
    const missing = await (target as any).getLecturerContext({ schoolCode: 'HUCE', lecturerCode: 'GV01' });
    expect((target as any).buildOwnedScheduleWhere(missing, false).OR)
      .toContainEqual({ lecturerId: -1 });
  });

  describe('transactional attendance edits', () => {
    const version = new Date('2026-09-10T00:00:00.000Z');
    function fixture(records: any[] = []) {
      const students = [1, 2].map((id) => ({ id, mssv: `SV${id}`, fullName: `Student ${id}` }));
      const events: string[] = [];
      const session = {
        id: 12, status: 'open', attendanceDate: version, openedAt: version,
        closesAt: new Date('2026-09-10T01:00:00.000Z'),
        schedule: { id: 8, course: { code: 'CS' }, studentClass: { code: 'K1' } },
        records,
      };
      const tx = {
        $queryRaw: jest.fn(async () => { events.push('lock'); }),
        attendanceSession: {
          findFirst: jest.fn(async () => { events.push('read'); return session; }),
          update: jest.fn(async ({ data }) => ({ ...session, ...data })),
        },
        attendanceRecord: {
          upsert: jest.fn().mockResolvedValue({}),
          createMany: jest.fn().mockResolvedValue({ count: 0 }),
          findMany: jest.fn().mockResolvedValue(records),
        },
      };
      const context = {
        schoolCode: 'HUCE', lecturerCode: 'GV01', studentLecturerId: 31,
        lecturerProfile: { id: 71 },
        studentPrisma: { $transaction: jest.fn((callback) => callback(tx)) },
        lecturerPrisma: { lecturerNotification: { upsert: jest.fn().mockResolvedValue({ createdAt: version }) } },
      };
      jest.spyOn(service as any, 'getLecturerContext').mockResolvedValue(context);
      jest.spyOn(service as any, 'getScheduleStudents').mockResolvedValue(students);
      return { tx, context, session, events };
    }

    it('validates the whole batch before writing any valid earlier row', async () => {
      const { tx } = fixture();
      await expect(service.saveAttendanceSession(12, {}, {
        records: [
          { studentId: 1, status: 'OK', expectedUpdatedAt: null },
          { studentId: 999, status: 'ABSENT', expectedUpdatedAt: null },
        ],
      })).rejects.toThrow('Sinh viên 999 không thuộc lớp học phần này');
      expect(tx.attendanceRecord.upsert).not.toHaveBeenCalled();
      expect(tx.attendanceSession.update).not.toHaveBeenCalled();
    });

    it('reads after acquiring the shared lock and keeps an existing late result', async () => {
      const late = { id: 101, studentId: 1, status: 'late', scanResult: 'success', updatedAt: version };
      const { tx, events } = fixture([late]);
      await service.saveAttendanceSession(12, {}, {
        records: [{ studentId: 1, recordId: 101, status: 'OK', expectedUpdatedAt: version.toISOString() }],
      });
      expect(events).toEqual(['lock', 'read']);
      expect(tx.attendanceRecord.upsert).toHaveBeenCalledWith(expect.objectContaining({
        update: expect.objectContaining({ status: 'late', scanResult: 'success' }),
      }));
      expect(tx.attendanceSession.update).toHaveBeenCalledWith(expect.objectContaining({
        data: expect.objectContaining({ status: 'closed' }),
      }));
    });

    it('rejects a stale lecturer edit after a student check-in changed the record', async () => {
      const { tx } = fixture([{ id: 101, studentId: 1, status: 'present', updatedAt: new Date(version.getTime() + 1000) }]);
      await expect(service.saveAttendanceSession(12, {}, {
        records: [{ studentId: 1, recordId: 101, status: 'ABSENT', expectedUpdatedAt: version.toISOString() }],
      })).rejects.toThrow('đã thay đổi');
      expect(tx.attendanceRecord.upsert).not.toHaveBeenCalled();
      expect(tx.attendanceSession.update).not.toHaveBeenCalled();
    });

    it('propagates a database write failure without closing or notifying', async () => {
      const { tx, context } = fixture();
      tx.attendanceRecord.upsert.mockRejectedValue(new Error('database write failed'));
      await expect(service.saveAttendanceSession(12, {}, {
        records: [{ studentId: 1, status: 'OK', expectedUpdatedAt: null }],
      })).rejects.toThrow('database write failed');
      expect(context.studentPrisma.$transaction).toHaveBeenCalledTimes(1);
      expect(tx.attendanceSession.update).not.toHaveBeenCalled();
      expect(context.lecturerPrisma.lecturerNotification.upsert).not.toHaveBeenCalled();
    });

    it('returns a committed close even when the remote notification database fails', async () => {
      const { tx, context } = fixture();
      context.lecturerPrisma.lecturerNotification.upsert.mockRejectedValue(new Error('inbox unavailable'));
      const warn = jest.spyOn((service as any).logger, 'warn').mockImplementation(() => undefined);
      const result = await service.saveAttendanceSession(12, {}, { records: [] });
      expect(result.session.status.code).toBe('closed');
      expect(tx.attendanceSession.update).toHaveBeenCalledTimes(1);
      expect(warn).toHaveBeenCalled();
    });

    it('does not move the close time when an already closed session is saved again', async () => {
      const { tx, session } = fixture();
      session.status = 'closed';
      const result = await service.saveAttendanceSession(12, {}, { records: [] });
      expect(tx.attendanceSession.update).not.toHaveBeenCalled();
      expect(result.session.closesAt).toBe(session.closesAt.toISOString());
    });
  });

  it('recreates missing open and close notifications without changing existing read state', async () => {
    const date = new Date('2026-09-10T00:00:00Z');
    const context = {
      schoolCode: 'HUCE', lecturerCode: 'GV01', studentLecturerId: 1, lecturerProfile: { id: 99 },
      studentPrisma: { attendanceSession: { findMany: jest.fn()
        .mockResolvedValueOnce([{ id: 12, status: 'closed', openedAt: date, closesAt: date,
          schedule: { course: { code: 'CS' }, studentClass: { code: 'K1' } } }])
        .mockResolvedValueOnce([]) } },
      lecturerPrisma: { lecturerNotification: {
        findMany: jest.fn().mockResolvedValue([{ referenceKey: 'HUCE:GV01:attendance_available:12' }]),
        upsert: jest.fn().mockResolvedValue({ createdAt: date }),
      } },
    };
    await (service as any).reconcileSessionNotifications(context);
    expect(context.lecturerPrisma.lecturerNotification.upsert).toHaveBeenCalledTimes(1);
    expect(context.lecturerPrisma.lecturerNotification.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { referenceKey: 'HUCE:GV01:attendance_closed:12' },
      update: {},
      create: expect.objectContaining({ lecturerId: 99 }),
    }));
  });

  it('parses and displays the school timezone even when a timestamp has no offset', () => {
    const date = (service as any).parseDateValue('2026-09-10T07:00:00', 'startAt');
    expect(date.toISOString()).toBe('2026-09-10T00:00:00.000Z');
    expect((service as any).formatDateTime(date)).toBe('10/09/2026 07:00');
    expect((service as any).getDayStart(date).toISOString()).toBe('2026-09-09T17:00:00.000Z');
  });
});
