-- AlterTable
ALTER TABLE "Lecturer" ADD COLUMN "phoneNumber" TEXT;

-- AlterTable
ALTER TABLE "AttendanceRecord" ADD COLUMN "note" TEXT;

-- CreateTable
CREATE TABLE "LecturerNotification" (
    "id" SERIAL NOT NULL,
    "lecturerId" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "type" TEXT NOT NULL DEFAULT 'general',
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "referenceKey" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LecturerNotification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LecturerNotification_referenceKey_key" ON "LecturerNotification"("referenceKey");

-- CreateIndex
CREATE INDEX "LecturerNotification_lecturerId_createdAt_idx" ON "LecturerNotification"("lecturerId", "createdAt");

-- AddForeignKey
ALTER TABLE "LecturerNotification" ADD CONSTRAINT "LecturerNotification_lecturerId_fkey" FOREIGN KEY ("lecturerId") REFERENCES "Lecturer"("id") ON DELETE CASCADE ON UPDATE CASCADE;
