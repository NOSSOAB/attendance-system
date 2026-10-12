import { createHash, generateKeyPairSync, sign } from 'crypto';
import { MobileFaceAuthService } from './mobile-face-auth.service';

describe('MobileFaceAuthService', () => {
  const originalEnabled = process.env.MOBILE_FACE_AUTH_ENABLED;
  const createLivenessProof = () => ({
    actions: ['blink', 'smile', 'turn'] as Array<'blink' | 'smile' | 'turn'>,
    completedAt: new Date().toISOString(),
    frameCount: 14,
    blinkPeak: 0.7,
    smilePeak: 0.65,
    turnPeak: 0.4,
    neutralBlinkMax: 0.1,
    neutralSmileMax: 0.1,
    neutralTurnMax: 0.08,
  });

  beforeEach(() => {
    process.env.MOBILE_FACE_AUTH_ENABLED = 'true';
  });

  afterAll(() => {
    process.env.MOBILE_FACE_AUTH_ENABLED = originalEnabled;
  });

  it('creates a three-action permutation and stores the exact order', async () => {
    const prisma = {
      mobileFaceIdentity: {
        findUnique: jest.fn().mockResolvedValue({
          isActive: true,
          embeddingDimension: 128,
        }),
      },
      mobileFaceSession: {
        create: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    const service = new MobileFaceAuthService(prisma as any);

    const ticket = await service.start('HUCE:person_A', 9);

    expect(ticket.livenessActions).toHaveLength(3);
    expect(new Set(ticket.livenessActions)).toEqual(
      new Set(['blink', 'smile', 'turn']),
    );
    expect(prisma.mobileFaceSession.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        challenges: expect.objectContaining({
          livenessActions: ticket.livenessActions,
        }),
      }),
    });
  });

  it.each([
    {
      name: 'the actions are submitted in a different order',
      mutate: (proof: ReturnType<typeof createLivenessProof>) => ({
        ...proof,
        actions: ['smile', 'blink', 'turn'] as Array<
          'blink' | 'smile' | 'turn'
        >,
      }),
    },
    {
      name: 'one action is repeated',
      mutate: (proof: ReturnType<typeof createLivenessProof>) => ({
        ...proof,
        actions: ['blink', 'smile', 'smile'] as Array<
          'blink' | 'smile' | 'turn'
        >,
      }),
    },
    {
      name: 'the head turn is below the acceptance threshold',
      mutate: (proof: ReturnType<typeof createLivenessProof>) => ({
        ...proof,
        turnPeak: 0.17,
      }),
    },
  ])('rejects liveness when $name', ({ mutate }) => {
    const service = new MobileFaceAuthService({} as any);
    const proof = createLivenessProof();

    expect(() =>
      (service as any).validateLivenessProof(
        { livenessActions: proof.actions },
        mutate(proof),
      ),
    ).toThrow();
  });

  it('accepts a registered P-256 key only when it signs this one-use ticket', async () => {
    const { publicKey, privateKey } = generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const publicKeyDer = publicKey.export({ format: 'der', type: 'spki' });
    const publicKeyBase64 = publicKeyDer.toString('base64');
    const fingerprint = createHash('sha256')
      .update(publicKeyDer)
      .digest('base64url');
    const embedding = [1, ...Array<number>(127).fill(0)];
    const livenessProof = createLivenessProof();
    const session = {
      id: 'c1f1b6b2-ea09-4f10-9000-000000000001',
      identityKey: 'person_A',
      attendanceSessionId: 9,
      nonceHash: createHash('sha256').update('nonce-value').digest('base64url'),
      modelId: 'opencv_sface_2021dec_v1',
      expiresAt: new Date(Date.now() + 60_000),
      consumedAt: null,
      challenges: {
        issuedAt: new Date(Date.now() - 5_000).toISOString(),
        livenessActions: livenessProof.actions,
      },
    };
    const prisma = {
      mobileFaceSession: {
        findUnique: jest.fn().mockResolvedValue(session),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      mobileFaceDeviceKey: {
        findUnique: jest.fn().mockResolvedValue({
          identityKey: 'person_A',
          isActive: true,
          publicKeyDer: publicKeyBase64,
        }),
        update: jest.fn(),
      },
      mobileFaceIdentity: {
        findUnique: jest.fn().mockResolvedValue({
          isActive: true,
          meanEmbedding: embedding,
          threshold: 0.62,
        }),
      },
    };
    const service = new MobileFaceAuthService(prisma as any);
    const payload = (service as any).signaturePayload(
      session.id,
      'nonce-value',
      session.modelId,
      embedding,
      livenessProof,
    );
    const signature = sign('sha256', Buffer.from(payload), privateKey).toString(
      'base64',
    );

    await expect(
      service.complete({
        sessionId: session.id,
        nonce: 'nonce-value',
        embedding,
        publicKey: publicKeyBase64,
        signature,
        livenessProof,
        expectedIdentityKey: 'person_A',
      }),
    ).resolves.toMatchObject({ verified: true, similarity: 1 });

    expect(prisma.mobileFaceSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ deviceKeyFingerprint: fingerprint }),
      }),
    );
  });

  it('binds a new device only after its face matches a provisioned template', async () => {
    const { publicKey, privateKey } = generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const publicKeyDer = publicKey.export({ format: 'der', type: 'spki' });
    const publicKeyBase64 = publicKeyDer.toString('base64');
    const embedding = [1, ...Array<number>(127).fill(0)];
    const livenessProof = createLivenessProof();
    const session = {
      id: 'c1f1b6b2-ea09-4f10-9000-000000000002',
      identityKey: 'HUCE:person_A',
      attendanceSessionId: 9,
      nonceHash: createHash('sha256')
        .update('first-device')
        .digest('base64url'),
      modelId: 'opencv_sface_2021dec_v1',
      expiresAt: new Date(Date.now() + 60_000),
      consumedAt: null,
      challenges: {
        issuedAt: new Date(Date.now() - 5_000).toISOString(),
        livenessActions: livenessProof.actions,
      },
    };
    const createdDevice = {
      identityKey: session.identityKey,
      isActive: true,
      publicKeyDer: publicKeyBase64,
    };
    const prisma = {
      mobileFaceSession: {
        findUnique: jest.fn().mockResolvedValue(session),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      mobileFaceDeviceKey: {
        findUnique: jest
          .fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce(createdDevice),
        createMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn(),
      },
      mobileFaceIdentity: {
        findUnique: jest.fn().mockResolvedValue({
          isActive: true,
          meanEmbedding: embedding,
          threshold: 0.45,
        }),
      },
    };
    const service = new MobileFaceAuthService(prisma as any);
    const payload = (service as any).signaturePayload(
      session.id,
      'first-device',
      session.modelId,
      embedding,
      livenessProof,
    );
    const signature = sign('sha256', Buffer.from(payload), privateKey).toString(
      'base64',
    );

    await expect(
      service.complete({
        sessionId: session.id,
        nonce: 'first-device',
        embedding,
        publicKey: publicKeyBase64,
        signature,
        livenessProof,
        expectedIdentityKey: session.identityKey,
      }),
    ).resolves.toMatchObject({ verified: true });
    expect(prisma.mobileFaceDeviceKey.createMany).toHaveBeenCalledWith({
      data: [expect.objectContaining({ identityKey: 'HUCE:person_A' })],
      skipDuplicates: true,
    });
  });

  it('does not reuse a verified face result after the attendance window', async () => {
    const prisma = {
      mobileFaceSession: {
        findUnique: jest.fn().mockResolvedValue({
          identityKey: 'HUCE:person_A',
          attendanceSessionId: 9,
          consumedAt: new Date(Date.now() - 4 * 60_000),
          auditStatus: 'verified',
        }),
      },
    };
    const service = new MobileFaceAuthService(prisma as any);

    await expect(
      service.getVerified('face-ticket', 'HUCE:person_A', 9),
    ).rejects.toThrow('Kết quả xác thực khuôn mặt mobile không hợp lệ');
  });
});
