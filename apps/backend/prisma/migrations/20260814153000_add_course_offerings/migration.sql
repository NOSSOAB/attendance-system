-- Add source-backed course offerings without changing the legacy class-based
-- schedule path. Existing rows keep a NULL offeringId and continue to work.
CREATE TABLE "CourseOffering" (
    "id" SERIAL NOT NULL,
    "schoolId" INTEGER NOT NULL,
    "courseId" INTEGER NOT NULL,
    "classId" INTEGER NOT NULL,
    "code" TEXT NOT NULL,
    "termCode" TEXT,
    "termName" TEXT,
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "sourceTermId" TEXT,
    "sourceStatus" TEXT,

    CONSTRAINT "CourseOffering_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "CourseOfferingEnrollment" (
    "id" SERIAL NOT NULL,
    "offeringId" INTEGER NOT NULL,
    "studentId" INTEGER NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "sourceStatus" TEXT,

    CONSTRAINT "CourseOfferingEnrollment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ScheduleLecturer" (
    "id" SERIAL NOT NULL,
    "scheduleId" INTEGER NOT NULL,
    "lecturerId" INTEGER NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'co_lecturer',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "sourceStatus" TEXT,

    CONSTRAINT "ScheduleLecturer_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ImportCheckpoint" (
    "id" SERIAL NOT NULL,
    "jobKey" TEXT NOT NULL,
    "targetScope" TEXT NOT NULL,
    "sourceSystem" TEXT NOT NULL,
    "termSourceId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "summary" JSONB NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ImportCheckpoint_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "DatabaseScopeMarker" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "scope" TEXT NOT NULL,
    "schoolCode" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DatabaseScopeMarker_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "DatabaseScopeMarker_singleton_check" CHECK ("id" = 1)
);

ALTER TABLE "Schedule"
ADD COLUMN "offeringId" INTEGER,
ADD COLUMN "sourceSystem" TEXT,
ADD COLUMN "sourceId" TEXT,
ADD COLUMN "startsAt" TIMESTAMP(3),
ADD COLUMN "endsAt" TIMESTAMP(3),
ADD COLUMN "recurrenceKind" TEXT NOT NULL DEFAULT 'weekly',
ADD COLUMN "isActive" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "Schedule"
ADD CONSTRAINT "Schedule_recurrenceKind_check"
CHECK ("recurrenceKind" IN ('weekly', 'biweekly', 'once'));

-- Preserve demo upsert semantics without preventing source-backed meetings
-- with the same tuple in different offerings/terms.
DROP INDEX "Schedule_courseId_classId_dayOfWeek_startTime_endTime_room_key";

CREATE UNIQUE INDEX "Schedule_legacy_meeting_key"
ON "Schedule"("courseId", "classId", "dayOfWeek", "startTime", "endTime", "room")
WHERE "offeringId" IS NULL;

CREATE UNIQUE INDEX "CourseOffering_schoolId_sourceSystem_sourceId_key"
ON "CourseOffering"("schoolId", "sourceSystem", "sourceId");

CREATE INDEX "CourseOffering_schoolId_isActive_startsAt_endsAt_idx"
ON "CourseOffering"("schoolId", "isActive", "startsAt", "endsAt");

CREATE INDEX "CourseOffering_schoolId_sourceSystem_sourceTermId_idx"
ON "CourseOffering"("schoolId", "sourceSystem", "sourceTermId");

CREATE INDEX "CourseOffering_courseId_classId_idx"
ON "CourseOffering"("courseId", "classId");

CREATE UNIQUE INDEX "CourseOfferingEnrollment_offeringId_studentId_key"
ON "CourseOfferingEnrollment"("offeringId", "studentId");

CREATE UNIQUE INDEX "CourseOfferingEnrollment_sourceSystem_sourceId_key"
ON "CourseOfferingEnrollment"("sourceSystem", "sourceId");

CREATE INDEX "CourseOfferingEnrollment_studentId_isActive_idx"
ON "CourseOfferingEnrollment"("studentId", "isActive");

CREATE INDEX "CourseOfferingEnrollment_offeringId_isActive_idx"
ON "CourseOfferingEnrollment"("offeringId", "isActive");

CREATE UNIQUE INDEX "ScheduleLecturer_scheduleId_lecturerId_key"
ON "ScheduleLecturer"("scheduleId", "lecturerId");

CREATE UNIQUE INDEX "ScheduleLecturer_sourceSystem_sourceId_key"
ON "ScheduleLecturer"("sourceSystem", "sourceId");

CREATE INDEX "ScheduleLecturer_lecturerId_isActive_idx"
ON "ScheduleLecturer"("lecturerId", "isActive");

CREATE UNIQUE INDEX "ImportCheckpoint_jobKey_targetScope_key"
ON "ImportCheckpoint"("jobKey", "targetScope");

CREATE INDEX "ImportCheckpoint_sourceSystem_termSourceId_idx"
ON "ImportCheckpoint"("sourceSystem", "termSourceId");

CREATE UNIQUE INDEX "DatabaseScopeMarker_scope_key"
ON "DatabaseScopeMarker"("scope");

CREATE UNIQUE INDEX "Schedule_sourceSystem_sourceId_key"
ON "Schedule"("sourceSystem", "sourceId");

CREATE INDEX "Schedule_offeringId_idx"
ON "Schedule"("offeringId");

CREATE INDEX "Schedule_isActive_startsAt_endsAt_idx"
ON "Schedule"("isActive", "startsAt", "endsAt");

ALTER TABLE "CourseOffering"
ADD CONSTRAINT "CourseOffering_schoolId_fkey"
FOREIGN KEY ("schoolId") REFERENCES "School"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "CourseOffering"
ADD CONSTRAINT "CourseOffering_courseId_fkey"
FOREIGN KEY ("courseId") REFERENCES "Course"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "CourseOffering"
ADD CONSTRAINT "CourseOffering_classId_fkey"
FOREIGN KEY ("classId") REFERENCES "StudentClass"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "CourseOfferingEnrollment"
ADD CONSTRAINT "CourseOfferingEnrollment_offeringId_fkey"
FOREIGN KEY ("offeringId") REFERENCES "CourseOffering"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "CourseOfferingEnrollment"
ADD CONSTRAINT "CourseOfferingEnrollment_studentId_fkey"
FOREIGN KEY ("studentId") REFERENCES "Student"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Schedule"
ADD CONSTRAINT "Schedule_offeringId_fkey"
FOREIGN KEY ("offeringId") REFERENCES "CourseOffering"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "ScheduleLecturer"
ADD CONSTRAINT "ScheduleLecturer_scheduleId_fkey"
FOREIGN KEY ("scheduleId") REFERENCES "Schedule"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ScheduleLecturer"
ADD CONSTRAINT "ScheduleLecturer_lecturerId_fkey"
FOREIGN KEY ("lecturerId") REFERENCES "Lecturer"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
