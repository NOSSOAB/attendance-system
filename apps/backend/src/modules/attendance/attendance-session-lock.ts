import type { Prisma } from '@prisma/client';

// Every attendance writer acquires the parent row first. Keep the transaction
// short: face verification and other network calls must happen before this lock.
export async function lockAttendanceSession(
  tx: Prisma.TransactionClient,
  sessionId: number,
): Promise<void> {
  await tx.$queryRaw`SELECT "id" FROM "AttendanceSession" WHERE "id" = ${sessionId} FOR UPDATE`;
}
