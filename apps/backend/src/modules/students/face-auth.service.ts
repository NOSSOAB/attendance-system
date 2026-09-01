import {
  BadGatewayException,
  HttpException,
  HttpStatus,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';

type FaceAuthShard = {
  id: string;
  baseUrl: string;
};

export type FaceSessionPayload = {
  session_id: string;
  session_token: string;
  stage: string;
  shard: string;
};

export type FaceVerificationPayload = {
  session_id: string;
  stage: string;
  recognition?: {
    best_match_name?: string;
    similarity?: number;
    similarity_percent?: number;
    is_recognized?: boolean;
  } | null;
  final?: {
    ok?: boolean;
    code?: string;
    message?: string;
  } | null;
};

@Injectable()
export class FaceAuthService {
  private readonly shards = this.loadShards();
  private nextShardIndex = this.loadShardOffset();

  async startSession(targetName: string): Promise<FaceSessionPayload> {
    const apiKey = process.env.FACE_CLIENT_API_KEY?.trim();
    if (!apiKey) {
      throw new ServiceUnavailableException(
        'Dịch vụ xác thực khuôn mặt chưa được cấu hình trên máy chủ',
      );
    }

    const startIndex = this.nextShardIndex++ % this.shards.length;
    let lastError: unknown;

    for (let offset = 0; offset < this.shards.length; offset += 1) {
      const shard = this.shards[(startIndex + offset) % this.shards.length];
      try {
        const payload = await this.requestJson<FaceSessionPayload>(
          shard.baseUrl,
          '/api/v1/sessions',
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey,
            },
            body: JSON.stringify({
              target_name: targetName,
              skip_liveness: false,
            }),
          },
        );

        if (
          typeof payload.session_id !== 'string' ||
          typeof payload.session_token !== 'string'
        ) {
          throw new BadGatewayException(
            'Dịch vụ xác thực khuôn mặt trả về phiên không hợp lệ',
          );
        }

        return { ...payload, shard: shard.id };
      } catch (error) {
        lastError = error;
        if (!this.isRetryableShardError(error)) {
          throw error;
        }
      }
    }

    if (lastError instanceof Error) {
      throw lastError;
    }
    throw new ServiceUnavailableException('Không có Face Auth shard khả dụng');
  }

  async getSession(
    shardId: string,
    sessionId: string,
    sessionToken: string,
  ): Promise<FaceVerificationPayload> {
    return this.requestJson<FaceVerificationPayload>(
      this.resolveShard(shardId).baseUrl,
      `/api/v1/sessions/${encodeURIComponent(sessionId)}`,
      {
        method: 'GET',
        headers: {
          'X-Session-Token': sessionToken,
        },
      },
    );
  }

  async deleteSession(
    shardId: string,
    sessionId: string,
    sessionToken: string,
  ): Promise<void> {
    try {
      await this.requestJson(
        this.resolveShard(shardId).baseUrl,
        `/api/v1/sessions/${encodeURIComponent(sessionId)}`,
        {
          method: 'DELETE',
          headers: {
            'X-Session-Token': sessionToken,
          },
        },
      );
    } catch {
      // Face sessions expire automatically. Database persistence must not fail
      // merely because best-effort cleanup could not reach its shard.
    }
  }

  private async requestJson<T = Record<string, unknown>>(
    baseUrl: string,
    path: string,
    init: RequestInit,
  ): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${baseUrl}${path}`, {
        ...init,
        signal: AbortSignal.timeout(20_000),
      });
    } catch {
      throw new ServiceUnavailableException(
        'Không kết nối được dịch vụ xác thực khuôn mặt',
      );
    }

    const payload = (await response.json().catch(() => ({}))) as {
      detail?: unknown;
    };

    if (!response.ok) {
      const detail =
        typeof payload.detail === 'string'
          ? payload.detail
          : `Face Auth HTTP ${response.status}`;

      if (response.status === 429) {
        throw new HttpException(
          'Dịch vụ xác thực khuôn mặt đang bận, vui lòng thử lại',
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }

      if (response.status >= 500) {
        throw new ServiceUnavailableException(
          'Dịch vụ xác thực khuôn mặt tạm thời không sẵn sàng',
        );
      }

      throw new BadGatewayException(detail);
    }

    return payload as T;
  }

  private loadShards(): FaceAuthShard[] {
    const configured = process.env.FACE_AUTH_SHARDS?.split(',')
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => {
        const separator = item.indexOf('=');
        if (separator <= 0 || separator === item.length - 1) {
          throw new Error(
            'FACE_AUTH_SHARDS phải có dạng face-01=http://face-01:8000',
          );
        }
        const id = item.slice(0, separator).trim();
        const baseUrl = item
          .slice(separator + 1)
          .trim()
          .replace(/\/+$/, '');
        if (!/^face-(?:0[1-9]|[1-3][0-9]|40)$/.test(id)) {
          throw new Error(`Face Auth shard không hợp lệ: ${id}`);
        }
        return { id, baseUrl };
      });

    if (configured?.length) {
      return configured;
    }

    return [
      {
        id: 'face-01',
        baseUrl: (
          process.env.FACE_AUTH_INTERNAL_URL ?? 'http://face-auth:8000'
        ).replace(/\/+$/, ''),
      },
    ];
  }

  private loadShardOffset() {
    const configured = Number(process.env.FACE_SHARD_OFFSET ?? 0);
    if (!Number.isInteger(configured) || configured < 0) {
      throw new Error('FACE_SHARD_OFFSET phải là số nguyên không âm');
    }
    return configured % this.shards.length;
  }

  private resolveShard(shardId: string): FaceAuthShard {
    const shard = this.shards.find((item) => item.id === shardId);
    if (!shard) {
      throw new BadGatewayException('Face Auth shard không hợp lệ');
    }
    return shard;
  }

  private isRetryableShardError(error: unknown): boolean {
    if (!(error instanceof HttpException)) {
      return true;
    }
    return [
      HttpStatus.TOO_MANY_REQUESTS,
      HttpStatus.BAD_GATEWAY,
      HttpStatus.SERVICE_UNAVAILABLE,
      HttpStatus.GATEWAY_TIMEOUT,
    ].includes(error.getStatus());
  }
}
