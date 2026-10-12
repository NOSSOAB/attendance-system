import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { AttendanceScanDto, MobileFaceEnrollmentDto } from './students.dto';

describe('MobileFaceEnrollmentDto', () => {
  const validVector = [1, ...Array<number>(127).fill(0)];

  it('accepts the 2-5 embedding matrix sent by the mobile app', async () => {
    const dto = Object.assign(new MobileFaceEnrollmentDto(), {
      faceSessionId: 'face-session-1',
      faceSessionToken: 'trusted-face-session-token',
      faceShard: 'face-01',
      publicKey: 'A'.repeat(32),
      embeddings: [validVector, validVector, validVector],
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('rejects enrollment with fewer than two samples', async () => {
    const dto = Object.assign(new MobileFaceEnrollmentDto(), {
      faceSessionId: 'face-session-1',
      faceSessionToken: 'trusted-face-session-token',
      faceShard: 'face-01',
      publicKey: 'A'.repeat(32),
      embeddings: [validVector],
    });

    const errors = await validate(dto);
    expect(errors.some((error) => error.property === 'embeddings')).toBe(true);
  });
});

describe('AttendanceScanDto', () => {
  const evidence = {
    faceEvidence: {
      verified: true,
      score: 0.8,
      verifiedAt: '2026-09-22T00:00:00.000Z',
    },
    gpsEvidence: {
      latitude: 21.028,
      longitude: 105.834,
      accuracyMeters: 10,
      capturedAt: '2026-09-22T00:00:00.000Z',
    },
  };

  it('accepts a mobile-first result without legacy face or BLE fields', async () => {
    const dto = plainToInstance(AttendanceScanDto, {
      sessionId: 9,
      mobileFaceSessionId: 'mobile-session-123456',
      ...evidence,
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('still requires all legacy face fields when mobile session is absent', async () => {
    const dto = plainToInstance(AttendanceScanDto, {
      sessionId: 9,
      ...evidence,
    });

    const errors = await validate(dto);
    expect(errors.map((error) => error.property)).toEqual(
      expect.arrayContaining([
        'faceSessionId',
        'faceSessionToken',
        'faceShard',
      ]),
    );
  });

  it('accepts authenticated ESP32-C6 evidence without a service UUID', async () => {
    const dto = plainToInstance(AttendanceScanDto, {
      sessionId: 9,
      mobileFaceSessionId: 'mobile-session-123456',
      ...evidence,
      bleEvidence: {
        c6Token: Buffer.alloc(26, 1).toString('base64'),
        isMock: false,
        rssi: -60,
        scannedAt: '2026-09-22T00:00:00.000Z',
        scanDurationMs: 6500,
      },
    });

    await expect(validate(dto, { whitelist: true, forbidNonWhitelisted: true })).resolves.toHaveLength(0);
  });
});
