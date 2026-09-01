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
});
