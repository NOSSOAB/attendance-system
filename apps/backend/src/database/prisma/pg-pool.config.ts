import type { PoolConfig } from 'pg';

export function createPgPoolConfig(connectionString: string): PoolConfig {
  const configuredMax = Number(process.env.DATABASE_POOL_MAX ?? 20);
  const max = Number.isInteger(configuredMax)
    ? Math.min(50, Math.max(2, configuredMax))
    : 20;

  return {
    connectionString,
    max,
    connectionTimeoutMillis: 5_000,
    idleTimeoutMillis: 30_000,
    allowExitOnIdle: false,
  };
}
