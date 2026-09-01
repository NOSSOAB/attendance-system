import { ServiceUnavailableException } from '@nestjs/common';
import { FaceAuthService } from './face-auth.service';

describe('FaceAuthService', () => {
  const originalApiKey = process.env.FACE_CLIENT_API_KEY;
  const originalBaseUrl = process.env.FACE_AUTH_INTERNAL_URL;
  const originalShards = process.env.FACE_AUTH_SHARDS;
  const originalShardOffset = process.env.FACE_SHARD_OFFSET;

  afterEach(() => {
    jest.restoreAllMocks();
    if (originalApiKey === undefined) {
      delete process.env.FACE_CLIENT_API_KEY;
    } else {
      process.env.FACE_CLIENT_API_KEY = originalApiKey;
    }
    if (originalBaseUrl === undefined) {
      delete process.env.FACE_AUTH_INTERNAL_URL;
    } else {
      process.env.FACE_AUTH_INTERNAL_URL = originalBaseUrl;
    }
    if (originalShards === undefined) {
      delete process.env.FACE_AUTH_SHARDS;
    } else {
      process.env.FACE_AUTH_SHARDS = originalShards;
    }
    if (originalShardOffset === undefined) {
      delete process.env.FACE_SHARD_OFFSET;
    } else {
      process.env.FACE_SHARD_OFFSET = originalShardOffset;
    }
  });

  it('refuses to create a session when the server-side key is missing', async () => {
    delete process.env.FACE_CLIENT_API_KEY;
    const service = new FaceAuthService();

    await expect(service.startSession('person_A')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('creates a liveness session using the server-side API key', async () => {
    process.env.FACE_CLIENT_API_KEY = 'server-only-secret';
    process.env.FACE_AUTH_INTERNAL_URL = 'http://face-auth:8000/';
    delete process.env.FACE_AUTH_SHARDS;
    const fetchMock = jest.spyOn(global, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          session_id: 'session-1',
          session_token: 'short-lived-token',
          stage: 'LIVENESS',
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        },
      ),
    );
    const service = new FaceAuthService();

    const result = await service.startSession('person_A');

    expect(result.session_id).toBe('session-1');
    expect(result.shard).toBe('face-01');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('http://face-auth:8000/api/v1/sessions');
    expect(init?.method).toBe('POST');
    expect(init?.headers).toMatchObject({
      'X-API-Key': 'server-only-secret',
    });
    expect(JSON.parse(String(init?.body))).toEqual({
      target_name: 'person_A',
      skip_liveness: false,
    });
  });

  it('fails over to the next shard when one shard is full', async () => {
    process.env.FACE_CLIENT_API_KEY = 'server-only-secret';
    process.env.FACE_AUTH_SHARDS =
      'face-01=http://face-01:8000,face-02=http://face-02:8000';
    const fetchMock = jest
      .spyOn(global, 'fetch')
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ detail: 'Server busy' }), {
          status: 429,
          headers: { 'Content-Type': 'application/json' },
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            session_id: 'session-2',
            session_token: 'short-lived-token',
            stage: 'LIVENESS',
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          },
        ),
      );

    const result = await new FaceAuthService().startSession('person_A');

    expect(result.shard).toBe('face-02');
    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'http://face-01:8000/api/v1/sessions',
      expect.any(Object),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'http://face-02:8000/api/v1/sessions',
      expect.any(Object),
    );
  });

  it('accepts and routes to the highest configured shard', async () => {
    process.env.FACE_CLIENT_API_KEY = 'server-only-secret';
    process.env.FACE_AUTH_SHARDS = 'face-40=http://face-40:8000';
    const fetchMock = jest.spyOn(global, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          session_id: 'session-40',
          session_token: 'short-lived-token',
          stage: 'LIVENESS',
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        },
      ),
    );

    const result = await new FaceAuthService().startSession('person_A');

    expect(result.shard).toBe('face-40');
    expect(fetchMock).toHaveBeenCalledWith(
      'http://face-40:8000/api/v1/sessions',
      expect.any(Object),
    );
  });

  it('starts each backend at its configured shard offset', async () => {
    process.env.FACE_CLIENT_API_KEY = 'server-only-secret';
    process.env.FACE_AUTH_SHARDS =
      'face-01=http://face-01:8000,face-02=http://face-02:8000';
    process.env.FACE_SHARD_OFFSET = '1';
    const fetchMock = jest.spyOn(global, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          session_id: 'session-offset',
          session_token: 'short-lived-token',
          stage: 'LIVENESS',
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        },
      ),
    );

    const result = await new FaceAuthService().startSession('person_A');

    expect(result.shard).toBe('face-02');
    expect(fetchMock).toHaveBeenCalledWith(
      'http://face-02:8000/api/v1/sessions',
      expect.any(Object),
    );
  });
});
