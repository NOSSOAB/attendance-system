ALTER TABLE "Student"
ADD COLUMN "faceIdentityKey" TEXT;

ALTER TABLE "AttendanceRecord"
ADD COLUMN "faceSessionId" TEXT,
ADD COLUMN "faceIdentityKey" TEXT,
ADD COLUMN "faceSimilarity" DOUBLE PRECISION;

CREATE UNIQUE INDEX "Student_faceIdentityKey_key"
ON "Student"("faceIdentityKey");

CREATE UNIQUE INDEX "AttendanceRecord_faceSessionId_key"
ON "AttendanceRecord"("faceSessionId");
