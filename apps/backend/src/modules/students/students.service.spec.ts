import { Test, TestingModule } from '@nestjs/testing';
import { createCipheriv } from 'crypto';
import { PrismaTenantService } from '../../database/prisma/prisma-tenant.service';
import { FaceAuthService } from './face-auth.service';
import { MobileFaceAuthService } from './mobile-face-auth.service';
import { StudentsService } from './students.service';

describe('StudentsService', () => {
  let service: StudentsService;
  let prismaTenant: { getClient: jest.Mock };
  let faceAuth: {
    startSession: jest.Mock;
    getSession: jest.Mock;
    deleteSession: jest.Mock;
  };
  let mobileFaceAuth: {
    start: jest.Mock;
    complete: jest.Mock;
    getVerified: jest.Mock;
    enrollTrusted: jest.Mock;
  };

  beforeEach(async () => {
    prismaTenant = {
      getClient: jest.fn(),
    };
    faceAuth = {
      startSession: jest.fn(),
      getSession: jest.fn(),
      deleteSession: jest.fn(),
    };
    mobileFaceAuth = {
      start: jest.fn(),
      complete: jest.fn(),
      getVerified: jest.fn(),
      enrollTrusted: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StudentsService,
        {
          provide: PrismaTenantService,
          useValue: prismaTenant,
        },
        {
          provide: FaceAuthService,
          useValue: faceAuth,
        },
        {
          provide: MobileFaceAuthService,
          useValue: mobileFaceAuth,
        },
      ],
    }).compile();

    service = module.get<StudentsService>(StudentsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('shows an open attendance session before an expired earlier class on home', async () => {
    jest
      .spyOn(service as any, 'getStudentContext')
      .mockResolvedValue({ student: { id: 1 } });
    jest
      .spyOn(service as any, 'getStudentOfferingAccess')
      .mockResolvedValue({ hasOfferingData: false });
    jest.spyOn(service as any, 'buildSchedulePayload').mockResolvedValue({
      scheduleCount: 2,
      items: [
        { courseCode: '020205', sessionId: 17, canAttend: false },
        { courseCode: 'DB202', sessionId: 18, canAttend: true },
      ],
    });
    jest
      .spyOn(service as any, 'buildAttendanceHistoryPayload')
      .mockResolvedValue({ items: [] });
    jest
      .spyOn(service, 'getNotifications')
      .mockResolvedValue({ unreadCount: 0, items: [] } as any);
    jest.spyOn(service as any, 'mapStudentProfile').mockReturnValue({});

    const result = await service.getStudentHome({
      schoolCode: 'HUCE',
      mssv: '1389570',
    });

    expect(result.summary.openAttendanceCount).toBe(1);
    expect(result.todaySchedules.map((item) => item.courseCode)).toEqual([
      'DB202',
      '020205',
    ]);
  });

  it('rejects a new face verification after a successful attendance', async () => {
    const studentPrisma = {
      student: {
        findFirst: jest.fn().mockResolvedValue({
          id: 1,
          mssv: '1389570',
          faceIdentityKey: 'person_A',
        }),
      },
      attendanceSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: 9,
          status: 'open',
          closesAt: new Date(Date.now() + 10 * 60 * 1000),
          records: [{ scanResult: 'success', status: 'present' }],
        }),
      },
    };
    prismaTenant.getClient.mockReturnValue(studentPrisma);
    faceAuth.startSession.mockResolvedValue({
      session_id: 'new-face-session',
      session_token: 'new-face-token',
      shard: 'face-01',
      stage: 'LIVENESS',
    });

    await expect(
      service.startAttendanceFaceSession({
        schoolCode: 'HUCE',
        mssv: '1389570',
        sessionId: 9,
      }),
    ).rejects.toThrow('Sinh viên đã điểm danh trong phiên này');
    expect(faceAuth.startSession).not.toHaveBeenCalled();
  });

  it('rejects face verification before the attendance window opens', async () => {
    const studentPrisma = {
      student: {
        findFirst: jest.fn().mockResolvedValue({
          id: 1,
          mssv: '1389570',
          faceIdentityKey: 'person_A',
        }),
      },
      attendanceSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: 9,
          status: 'open',
          openedAt: new Date(Date.now() + 10 * 60 * 1000),
          closesAt: new Date(Date.now() + 30 * 60 * 1000),
          records: [],
        }),
      },
    };
    prismaTenant.getClient.mockReturnValue(studentPrisma);

    await expect(
      service.startAttendanceFaceSession({
        schoolCode: 'HUCE',
        mssv: '1389570',
        sessionId: 9,
      }),
    ).rejects.toThrow('Buổi học này chưa mở điểm danh');
    expect(faceAuth.startSession).not.toHaveBeenCalled();
  });

  it('disables the attendance action after check-in', () => {
    const state = (service as any).deriveAttendanceState(
      { status: 'open' },
      { status: 'present', scanResult: 'success' },
    );

    expect(state.code).toBe('checked_in');
    expect(state.canAttend).toBe(false);
  });

  it('treats an expired open session as closed in the student UI state', () => {
    const state = (service as any).deriveAttendanceState(
      {
        status: 'open',
        openedAt: new Date(Date.now() - 60_000),
        closesAt: new Date(Date.now() - 1_000),
      },
      null,
    );

    expect(state.code).toBe('closed');
    expect(state.canAttend).toBe(false);
  });

  it('scopes mobile identity by school before completing verification', async () => {
    prismaTenant.getClient.mockReturnValue({
      student: {
        findFirst: jest.fn().mockResolvedValue({
          id: 1,
          mssv: '1389570',
          faceIdentityKey: 'person_A',
          school: { code: 'HUCE' },
          studentClass: { faculty: {} },
        }),
      },
    });
    mobileFaceAuth.complete.mockResolvedValue({ verified: true });

    await service.completeMobileAttendanceFaceSession({
      schoolCode: 'HUCE',
      mssv: '1389570',
      sessionId: 'mobile-session-123456',
      nonce: 'nonce-value-with-enough-length',
      embedding: [1, ...Array<number>(127).fill(0)],
      publicKey: 'public-key-value-with-enough-length',
      signature: 'signature-value',
    });

    expect(mobileFaceAuth.complete).toHaveBeenCalledWith(
      expect.objectContaining({ expectedIdentityKey: 'HUCE:person_A' }),
    );
  });

  it('uses active course-offering registrations instead of the legacy class schedule', async () => {
    const context = {
      student: { id: 11, classId: 7 },
      prisma: {
        courseOfferingEnrollment: {
          findMany: jest.fn().mockResolvedValue([
            {
              offeringId: 41,
              isActive: true,
              offering: { isActive: true },
            },
            {
              offeringId: 42,
              isActive: false,
              offering: { isActive: true },
            },
          ]),
        },
      },
    };

    const access = await (service as any).getStudentOfferingAccess(context);

    expect(access).toEqual({
      hasOfferingData: true,
      activeOfferingIds: [41],
      allOfferingIds: [41, 42],
    });
    expect(
      (service as any).buildStudentScheduleWhere(context, access, true),
    ).toEqual({ isActive: true, offeringId: { in: [41] } });
    expect(
      (service as any).buildStudentScheduleWhere(context, access, false),
    ).toEqual({ offeringId: { in: [41, 42] } });
  });

  it('keeps the class-based schedule fallback when offering data is unavailable', async () => {
    const context = {
      student: { id: 11, classId: 7 },
      prisma: {},
    };

    const access = await (service as any).getStudentOfferingAccess(context);

    expect(access.hasOfferingData).toBe(false);
    expect(
      (service as any).buildStudentScheduleWhere(context, access, true),
    ).toEqual({ isActive: true, classId: 7, offeringId: null });
  });

  it('processes 300 concurrent face, BLE and GPS attendance results', async () => {
    const now = new Date();
    const previousRegistry = process.env.BLE_C6_DEVICES_JSON;
    const key = Buffer.from('0123456789abcdeffedcba9876543210', 'hex');
    process.env.BLE_C6_DEVICES_JSON = JSON.stringify([{
      deviceId: 'a1b2c3d4',
      beaconId: 'ESP32_TEST_01',
      roomId: 'ROOM_A101',
      keyHex: key.toString('hex'),
    }]);
    const nonce = Buffer.from('d4c3b2a10100000001020304', 'hex');
    const cipher = createCipheriv('aes-128-gcm', key, nonce, {
      authTagLength: 8,
    });
    const encrypted = Buffer.concat([
      cipher.update(Buffer.from('d4c3b2a1', 'hex')),
      cipher.final(),
    ]);
    const c6Token = Buffer.concat([
      Buffer.from('ffff', 'hex'),
      nonce,
      encrypted,
      cipher.getAuthTag(),
    ]).toString('base64');
    const studentPrisma = {
      student: {
        findFirst: jest.fn().mockImplementation(({ where }) =>
          Promise.resolve({
            id: Number(String(where.mssv).replace(/\D/g, '')),
            mssv: where.mssv,
            classId: 7,
            faceIdentityKey: `person_${where.mssv}`,
          }),
        ),
      },
      attendanceSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: 9,
          status: 'open',
          attendanceDate: now,
          openedAt: new Date(now.getTime() - 60_000),
          lateAt: new Date(now.getTime() + 5 * 60_000),
          closesAt: new Date(now.getTime() + 10 * 60_000),
          beaconId: 'ESP32_TEST_01',
          roomId: 'ROOM_A101',
          bleServiceUuid: '12345678-1234-1234-1234-123456789abc',
          bleMinRssi: -80,
          records: [],
          schedule: {
            room: 'A101',
            startTime: '07:00',
            endTime: '09:00',
            course: { code: 'LOAD300', name: 'Load test 300' },
            lecturer: { fullName: 'Load Test' },
          },
        }),
      },
      attendanceRecord: {
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        findUnique: jest.fn().mockResolvedValue(null),
        findUniqueOrThrow: jest.fn(),
        create: jest.fn().mockImplementation(({ data }) =>
          Promise.resolve({
            id: data.studentId,
            ...data,
          }),
        ),
      },
      studentNotification: {
        create: jest.fn().mockResolvedValue({ id: 1 }),
      },
    };
    prismaTenant.getClient.mockReturnValue(studentPrisma);
    faceAuth.getSession.mockImplementation(
      (_shard: string, sessionId: string) => {
        const mssv = sessionId.replace('face-session-', '');
        return Promise.resolve({
          stage: 'SUCCESS',
          final: { ok: true },
          recognition: {
            is_recognized: true,
            best_match_name: `person_${mssv}`,
            similarity: 0.95,
          },
        });
      },
    );
    faceAuth.deleteSession.mockResolvedValue(undefined);
    const scannedAt = now.toISOString();

    const results = await Promise.all(
      Array.from({ length: 300 }, (_, index) => {
        const mssv = `SV${index + 1}`;
        return service.scanAttendance({
          schoolCode: 'HUCE',
          mssv,
          sessionId: 9,
          faceSessionId: `face-session-${mssv}`,
          faceSessionToken: `token-${mssv}`,
          faceShard: `face-${String((index % 40) + 1).padStart(2, '0')}`,
          bleEvidence: {
            c6Token,
            isMock: false,
            rssi: -60,
            scannedAt,
            scanDurationMs: 6_500,
          },
          faceEvidence: {
            verified: true,
            score: 0.95,
            verifiedAt: scannedAt,
          },
          gpsEvidence: {
            latitude: 21.0285,
            longitude: 105.8542,
            accuracyMeters: 8,
            capturedAt: scannedAt,
          },
        });
      }),
    );

    expect(results).toHaveLength(300);
    expect(results.every((result) => result.scanState === 'success')).toBe(
      true,
    );
    expect(studentPrisma.attendanceRecord.create).toHaveBeenCalledTimes(300);
    expect(studentPrisma.studentNotification.create).toHaveBeenCalledTimes(300);
    expect(faceAuth.getSession).toHaveBeenCalledTimes(300);
    expect(faceAuth.deleteSession).toHaveBeenCalledTimes(300);
    if (previousRegistry === undefined) delete process.env.BLE_C6_DEVICES_JSON;
    else process.env.BLE_C6_DEVICES_JSON = previousRegistry;
  });
});
