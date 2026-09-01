ALTER TABLE "AttendanceSession"
ADD COLUMN "lateAt" TIMESTAMP(3),
ADD COLUMN "beaconId" TEXT,
ADD COLUMN "roomId" TEXT,
ADD COLUMN "bleServiceUuid" TEXT,
ADD COLUMN "bleMinRssi" INTEGER NOT NULL DEFAULT -80;

ALTER TABLE "AttendanceRecord"
ADD COLUMN "faceVerifiedAt" TIMESTAMP(3),
ADD COLUMN "bleBeaconId" TEXT,
ADD COLUMN "bleRoomId" TEXT,
ADD COLUMN "bleDeviceName" TEXT,
ADD COLUMN "bleServiceUuid" TEXT,
ADD COLUMN "bleRssi" INTEGER,
ADD COLUMN "bleScannedAt" TIMESTAMP(3),
ADD COLUMN "bleScanDurationMs" INTEGER,
ADD COLUMN "decisionReason" TEXT,
ADD COLUMN "evidence" JSONB;
