import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  createHash,
  createPublicKey,
  randomBytes,
  randomInt,
  randomUUID,
  verify,
} from 'crypto';
import { PrismaService } from '../../database/prisma/prisma.service';

const VECTOR_DIMENSION = 128;
const SESSION_TTL_MS = 90_000;
const VERIFIED_RESULT_TTL_MS = 3 * 60_000;
const MAX_PUBLIC_KEY_BYTES = 4_096;
type LivenessAction = 'blink' | 'smile' | 'turn';

export type MobileLivenessProof = {
  actions: LivenessAction[];
  completedAt: string;
  frameCount: number;
  blinkPeak: number;
  smilePeak: number;
  turnPeak: number;
  neutralBlinkMax: number;
  neutralSmileMax: number;
  neutralTurnMax: number;
};

export type MobileFaceTicket = {
  protocolVersion: 3;
  sessionId: string;
  nonce: string;
  modelId: string;
  expiresAt: string;
  livenessActions: LivenessAction[];
};

export type MobileFaceEnrollment = {
  identityKey: string;
  embeddings: number[][];
  publicKey: string;
  threshold?: number;
};

/**
 * Android creates the embedding locally. The server only verifies a short
 * ECDSA signature and a 128-element dot product. A new device key is bound
 * only after the captured face matches a template provisioned from the
 * student's 2--5 reference photos. Later requests must use that same key.
 */
@Injectable()
export class MobileFaceAuthService {
  private readonly enabled = process.env.MOBILE_FACE_AUTH_ENABLED === 'true';
  private readonly modelId =
    process.env.MOBILE_FACE_MODEL_ID ?? 'opencv_sface_2021dec_v1';
  private nextCleanupAt = 0;

  constructor(private readonly prisma: PrismaService) {}

  async start(
    identityKey: string,
    attendanceSessionId: number,
  ): Promise<MobileFaceTicket> {
    this.assertEnabled();
    this.cleanupExpiredSessions();
    const identity = await this.prisma.mobileFaceIdentity.findUnique({
      where: { identityKey_modelId: { identityKey, modelId: this.modelId } },
    });
    if (!identity?.isActive) {
      throw new BadRequestException(
        'Tài khoản chưa có mẫu khuôn mặt mobile từ ảnh hồ sơ',
      );
    }
    if (identity.embeddingDimension !== VECTOR_DIMENSION) {
      throw new ServiceUnavailableException(
        'Mẫu khuôn mặt mobile không hợp lệ',
      );
    }

    const nonce = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + SESSION_TTL_MS);
    const sessionId = randomUUID();
    const livenessActions = this.randomLivenessActions();
    await this.prisma.mobileFaceSession.create({
      data: {
        id: sessionId,
        identityKey,
        attendanceSessionId,
        nonceHash: this.sha256(nonce),
        modelId: this.modelId,
        challenges: {
          issuedAt: new Date().toISOString(),
          attestation: 'android-keystore',
          livenessActions,
        },
        expiresAt,
      },
    });
    return {
      protocolVersion: 3,
      sessionId,
      nonce,
      modelId: this.modelId,
      expiresAt: expiresAt.toISOString(),
      livenessActions,
    };
  }

  /**
   * Called only by the trusted enrollment workflow, after staff has checked
   * the student. It accepts 2--5 locally generated embeddings, never images.
   */
  async enrollTrusted(input: MobileFaceEnrollment) {
    if (
      !Array.isArray(input.embeddings) ||
      input.embeddings.length < 2 ||
      input.embeddings.length > 5
    ) {
      throw new BadRequestException('Cần từ 2 đến 5 mẫu khuôn mặt mobile');
    }
    const samples = input.embeddings.map((sample) =>
      this.normalizeEmbedding(sample),
    );
    const mean = samples[0].map(
      (_, index) =>
        samples.reduce((sum, sample) => sum + sample[index], 0) /
        samples.length,
    );
    const normalizedMean = this.normalizeMean(mean);
    const threshold = input.threshold ?? 0.62;
    if (!Number.isFinite(threshold) || threshold < 0.45 || threshold > 0.9) {
      throw new BadRequestException('Ngưỡng khuôn mặt mobile không hợp lệ');
    }
    const publicKey = this.decodePublicKey(input.publicKey);
    // Validate the key format before inserting it. An enrollment with an
    // unusable public key would otherwise lock the student out.
    if (!this.isSupportedDeviceKey(publicKey)) {
      throw new BadRequestException('Khóa Android Keystore không hợp lệ');
    }
    const keyFingerprint = this.sha256Bytes(publicKey);
    const existingKey = await this.prisma.mobileFaceDeviceKey.findUnique({
      where: { keyFingerprint },
    });
    if (existingKey && existingKey.identityKey !== input.identityKey) {
      throw new BadRequestException(
        'Khóa thiết bị đã thuộc về một sinh viên khác',
      );
    }
    await this.prisma.$transaction([
      this.prisma.mobileFaceIdentity.upsert({
        where: {
          identityKey_modelId: {
            identityKey: input.identityKey,
            modelId: this.modelId,
          },
        },
        create: {
          identityKey: input.identityKey,
          modelId: this.modelId,
          meanEmbedding: normalizedMean,
          embeddingDimension: VECTOR_DIMENSION,
          threshold,
          isActive: true,
        },
        update: {
          meanEmbedding: normalizedMean,
          embeddingDimension: VECTOR_DIMENSION,
          threshold,
          isActive: true,
          enrollmentVersion: { increment: 1 },
          enrolledAt: new Date(),
        },
      }),
      this.prisma.mobileFaceDeviceKey.upsert({
        where: { keyFingerprint },
        create: {
          identityKey: input.identityKey,
          keyFingerprint,
          publicKeyDer: input.publicKey,
          isActive: true,
        },
        update: {
          publicKeyDer: input.publicKey,
          isActive: true,
          revokedAt: null,
        },
      }),
    ]);
    return {
      identityKey: input.identityKey,
      modelId: this.modelId,
      keyFingerprint,
    };
  }

  async complete(input: {
    sessionId: string;
    nonce: string;
    embedding: number[];
    publicKey: string;
    signature: string;
    livenessProof: MobileLivenessProof;
    expectedIdentityKey?: string;
  }) {
    this.assertEnabled();
    const embedding = this.normalizeEmbedding(input.embedding);
    const session = await this.prisma.mobileFaceSession.findUnique({
      where: { id: input.sessionId },
    });
    if (
      !session ||
      session.consumedAt ||
      session.expiresAt.getTime() < Date.now() ||
      session.nonceHash !== this.sha256(input.nonce)
    ) {
      throw new BadRequestException(
        'Phiên xác thực mobile đã hết hạn hoặc đã được dùng',
      );
    }
    if (
      input.expectedIdentityKey &&
      session.identityKey !== input.expectedIdentityKey
    ) {
      throw new BadRequestException(
        'Phiên xác thực không thuộc về sinh viên này',
      );
    }
    this.validateLivenessProof(session.challenges, input.livenessProof);

    const publicKey = this.decodePublicKey(input.publicKey);
    const keyFingerprint = this.sha256Bytes(publicKey);
    let device = await this.prisma.mobileFaceDeviceKey.findUnique({
      where: { keyFingerprint },
    });
    if (device) {
      if (
        !device.isActive ||
        device.identityKey !== session.identityKey ||
        device.publicKeyDer !== input.publicKey
      ) {
        throw new BadRequestException(
          'Khóa thiết bị không thuộc về sinh viên này',
        );
      }
    }
    const payload = this.signaturePayload(
      session.id,
      input.nonce,
      session.modelId,
      embedding,
      input.livenessProof,
    );
    if (!this.verifyDeviceSignature(publicKey, input.signature, payload)) {
      throw new BadRequestException('Chữ ký xác thực thiết bị không hợp lệ');
    }

    const identity = await this.prisma.mobileFaceIdentity.findUnique({
      where: {
        identityKey_modelId: {
          identityKey: session.identityKey,
          modelId: session.modelId,
        },
      },
    });
    if (!identity?.isActive) {
      throw new BadRequestException('Mẫu khuôn mặt mobile không tồn tại');
    }
    const enrolled = this.normalizeEmbedding(
      identity.meanEmbedding as number[],
    );
    const similarity = embedding.reduce(
      (sum, value, index) => sum + value * enrolled[index],
      0,
    );
    const verified = similarity >= identity.threshold;
    if (!device && verified) {
      await this.prisma.mobileFaceDeviceKey.createMany({
        data: [
          {
            identityKey: session.identityKey,
            keyFingerprint,
            publicKeyDer: input.publicKey,
            isActive: true,
          },
        ],
        skipDuplicates: true,
      });
      device = await this.prisma.mobileFaceDeviceKey.findUnique({
        where: { keyFingerprint },
      });
      if (
        !device?.isActive ||
        device.identityKey !== session.identityKey ||
        device.publicKeyDer !== input.publicKey
      ) {
        throw new BadRequestException(
          'Khóa thiết bị đã thuộc về tài khoản khác',
        );
      }
    }
    const consumed = await this.prisma.mobileFaceSession.updateMany({
      where: {
        id: session.id,
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
      data: {
        consumedAt: new Date(),
        deviceKeyFingerprint: keyFingerprint,
        integrityVerdict: {
          attestation: 'android-keystore',
          keyFingerprint,
          liveness: input.livenessProof,
        },
        auditStatus: verified ? 'verified' : 'failed',
      },
    });
    if (consumed.count !== 1) {
      throw new BadRequestException('Phiên xác thực mobile đã được dùng');
    }
    if (verified && device) {
      await this.prisma.mobileFaceDeviceKey.update({
        where: { keyFingerprint },
        data: { lastUsedAt: new Date() },
      });
    }
    return {
      verified,
      similarity,
      attendanceSessionId: session.attendanceSessionId,
      identityKey: session.identityKey,
    };
  }

  async getVerified(
    sessionId: string,
    identityKey: string,
    attendanceSessionId: number,
  ) {
    const session = await this.prisma.mobileFaceSession.findUnique({
      where: { id: sessionId },
    });
    if (
      !session ||
      session.identityKey !== identityKey ||
      session.attendanceSessionId !== attendanceSessionId ||
      !session.consumedAt ||
      Date.now() - session.consumedAt.getTime() > VERIFIED_RESULT_TTL_MS ||
      session.auditStatus !== 'verified'
    ) {
      throw new BadRequestException(
        'Kết quả xác thực khuôn mặt mobile không hợp lệ',
      );
    }
    return session;
  }

  async listDevices(identityKey: string) {
    return this.prisma.mobileFaceDeviceKey.findMany({
      where: { identityKey },
      select: {
        keyFingerprint: true,
        isActive: true,
        enrolledAt: true,
        lastUsedAt: true,
        revokedAt: true,
      },
      orderBy: { enrolledAt: 'desc' },
    });
  }

  async revokeDevice(identityKey: string, keyFingerprint: string) {
    const result = await this.prisma.mobileFaceDeviceKey.updateMany({
      where: { identityKey, keyFingerprint, isActive: true },
      data: { isActive: false, revokedAt: new Date() },
    });
    if (result.count !== 1) {
      throw new BadRequestException('Không tìm thấy thiết bị đang hoạt động');
    }
    return { revoked: true };
  }

  private assertEnabled() {
    if (!this.enabled) {
      throw new ServiceUnavailableException(
        'Xác thực khuôn mặt mobile chưa được cấu hình',
      );
    }
  }

  private cleanupExpiredSessions() {
    const now = Date.now();
    if (now < this.nextCleanupAt) return;
    this.nextCleanupAt = now + 60 * 60 * 1000;
    void this.prisma.mobileFaceSession
      .deleteMany({
        where: { expiresAt: { lt: new Date(now - 24 * 60 * 60 * 1000) } },
      })
      .catch(() => undefined);
  }

  private normalizeEmbedding(value: unknown): number[] {
    if (
      !Array.isArray(value) ||
      value.length !== VECTOR_DIMENSION ||
      value.some((item) => typeof item !== 'number' || !Number.isFinite(item))
    ) {
      throw new BadRequestException('Vector khuôn mặt không hợp lệ');
    }
    const norm = Math.sqrt(
      value.reduce<number>((sum, item) => sum + item * item, 0),
    );
    if (norm < 0.995 || norm > 1.005) {
      throw new BadRequestException('Vector khuôn mặt không được chuẩn hóa');
    }
    // Do not renormalize again. The canonical JSON of these exact values is
    // signed by the app, so changing a float here would invalidate the proof.
    return value;
  }

  private decodePublicKey(value: string): Buffer {
    if (
      !value ||
      value.length > 8_000 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(value)
    ) {
      throw new BadRequestException('Khóa công khai thiết bị không hợp lệ');
    }
    const key = Buffer.from(value, 'base64');
    if (key.length === 0 || key.length > MAX_PUBLIC_KEY_BYTES) {
      throw new BadRequestException('Khóa công khai thiết bị không hợp lệ');
    }
    return key;
  }

  private verifyDeviceSignature(
    publicKey: Buffer,
    encodedSignature: string,
    payload: string,
  ): boolean {
    try {
      const signature = Buffer.from(encodedSignature, 'base64');
      if (signature.length === 0 || signature.length > 512) return false;
      if (!this.isSupportedDeviceKey(publicKey)) return false;
      const key = createPublicKey({
        key: publicKey,
        format: 'der',
        type: 'spki',
      });
      return verify('sha256', Buffer.from(payload, 'utf8'), key, signature);
    } catch {
      return false;
    }
  }

  private isSupportedDeviceKey(publicKey: Buffer): boolean {
    try {
      const key = createPublicKey({
        key: publicKey,
        format: 'der',
        type: 'spki',
      });
      if (key.asymmetricKeyType !== 'ec') return false;
      const details = key.asymmetricKeyDetails as
        | { namedCurve?: string }
        | undefined;
      return !details?.namedCurve || details.namedCurve === 'prime256v1';
    } catch {
      return false;
    }
  }

  private normalizeMean(value: number[]): number[] {
    const norm = Math.sqrt(value.reduce((sum, item) => sum + item * item, 0));
    if (norm < 1e-6)
      throw new BadRequestException('Mẫu khuôn mặt mobile không hợp lệ');
    return value.map((item) => item / norm);
  }

  private signaturePayload(
    sessionId: string,
    nonce: string,
    modelId: string,
    embedding: number[],
    livenessProof: MobileLivenessProof,
  ) {
    return `${sessionId}.${nonce}.${modelId}.${this.sha256(JSON.stringify(embedding))}.${this.sha256(this.canonicalLiveness(livenessProof))}`;
  }

  private validateLivenessProof(
    rawChallenges: unknown,
    proof: MobileLivenessProof,
  ) {
    const challenges = rawChallenges as {
      issuedAt?: unknown;
      livenessActions?: unknown;
    } | null;
    const expected = challenges?.livenessActions;
    if (
      !Array.isArray(expected) ||
      expected.length !== 3 ||
      !Array.isArray(proof?.actions) ||
      proof.actions.length !== 3 ||
      expected.some((action, index) => action !== proof.actions[index]) ||
      new Set(proof.actions).size !== 3 ||
      !proof.actions.includes('blink') ||
      !proof.actions.includes('smile') ||
      !proof.actions.includes('turn')
    ) {
      throw new BadRequestException('Thử thách sống không hợp lệ');
    }
    const completedAt = Date.parse(proof.completedAt);
    if (
      !Number.isFinite(completedAt) ||
      !Number.isInteger(proof.frameCount) ||
      proof.frameCount < 12 ||
      proof.frameCount > 240 ||
      !this.isScore(proof.blinkPeak, 0.35, 1) ||
      !this.isScore(proof.smilePeak, 0.3, 1) ||
      !this.isScore(proof.turnPeak, 0.18, 1) ||
      !this.isScore(proof.neutralBlinkMax, 0, 0.3) ||
      !this.isScore(proof.neutralSmileMax, 0, 0.3) ||
      !this.isScore(proof.neutralTurnMax, 0, 0.14)
    ) {
      throw new BadRequestException('Bằng chứng thử thách sống không hợp lệ');
    }
  }

  private canonicalLiveness(proof: MobileLivenessProof) {
    return [
      proof.actions.join(','),
      proof.completedAt,
      proof.frameCount.toString(),
      proof.blinkPeak.toFixed(6),
      proof.smilePeak.toFixed(6),
      proof.turnPeak.toFixed(6),
      proof.neutralBlinkMax.toFixed(6),
      proof.neutralSmileMax.toFixed(6),
      proof.neutralTurnMax.toFixed(6),
    ].join('|');
  }

  private randomLivenessActions(): LivenessAction[] {
    const actions: LivenessAction[] = ['blink', 'smile', 'turn'];
    for (let index = actions.length - 1; index > 0; index -= 1) {
      const swapWith = randomInt(index + 1);
      [actions[index], actions[swapWith]] = [actions[swapWith], actions[index]];
    }
    return actions;
  }

  private isScore(value: unknown, minimum: number, maximum: number) {
    return (
      typeof value === 'number' &&
      Number.isFinite(value) &&
      value >= minimum &&
      value <= maximum
    );
  }

  private sha256(value: string) {
    return createHash('sha256').update(value).digest('base64url');
  }

  private sha256Bytes(value: Buffer) {
    return createHash('sha256').update(value).digest('base64url');
  }
}
