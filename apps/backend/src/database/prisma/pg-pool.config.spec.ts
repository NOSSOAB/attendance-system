import { createPgPoolConfig } from './pg-pool.config';

describe('createPgPoolConfig', () => {
  const originalMax = process.env.DATABASE_POOL_MAX;

  afterEach(() => {
    if (originalMax === undefined) {
      delete process.env.DATABASE_POOL_MAX;
    } else {
      process.env.DATABASE_POOL_MAX = originalMax;
    }
  });

  it('uses a bounded production pool', () => {
    process.env.DATABASE_POOL_MAX = '24';
    expect(createPgPoolConfig('postgresql://localhost/test')).toMatchObject({
      max: 24,
      connectionTimeoutMillis: 5_000,
    });
  });

  it('caps invalidly large pools', () => {
    process.env.DATABASE_POOL_MAX = '500';
    expect(createPgPoolConfig('postgresql://localhost/test').max).toBe(50);
  });
});
