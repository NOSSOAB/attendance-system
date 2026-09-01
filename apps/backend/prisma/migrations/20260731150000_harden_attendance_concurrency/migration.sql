WITH ranked_open_sessions AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      PARTITION BY "scheduleId"
      ORDER BY COALESCE("openedAt", "createdAt") DESC, "id" DESC
    ) AS row_number
  FROM "AttendanceSession"
  WHERE "status" = 'open'
)
UPDATE "AttendanceSession"
SET "status" = 'closed'
WHERE "id" IN (
  SELECT "id"
  FROM ranked_open_sessions
  WHERE row_number > 1
);

CREATE UNIQUE INDEX "AttendanceSession_one_open_per_schedule_idx"
ON "AttendanceSession" ("scheduleId")
WHERE "status" = 'open';
