-- Keep mobile vectors separate from existing buffalo_l/ArcFace records. A
-- vector is meaningful only for the exact model that created it.
CREATE TABLE "MobileFaceIdentity" (
    "id" SERIAL NOT NULL,
    "identityKey" TEXT NOT NULL,
    "modelId" TEXT NOT NULL,
    "meanEmbedding" JSONB NOT NULL,
    "embeddingDimension" INTEGER NOT NULL,
    "threshold" DOUBLE PRECISION NOT NULL,
    "enrollmentVersion" INTEGER NOT NULL DEFAULT 1,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "enrolledAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MobileFaceIdentity_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MobileFaceIdentity_identityKey_modelId_key"
    ON "MobileFaceIdentity"("identityKey", "modelId");
CREATE INDEX "MobileFaceIdentity_identityKey_isActive_idx"
    ON "MobileFaceIdentity"("identityKey", "isActive");
CREATE INDEX "MobileFaceIdentity_modelId_isActive_updatedAt_idx"
    ON "MobileFaceIdentity"("modelId", "isActive", "updatedAt");

-- The raw nonce and Play Integrity token are intentionally never persisted.
CREATE TABLE "MobileFaceSession" (
    "id" TEXT NOT NULL,
    "identityKey" TEXT NOT NULL,
    "attendanceSessionId" INTEGER NOT NULL,
    "nonceHash" TEXT NOT NULL,
    "modelId" TEXT NOT NULL,
    "challenges" JSONB NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "auditRequired" BOOLEAN NOT NULL DEFAULT false,
    "auditStatus" TEXT NOT NULL DEFAULT 'pending',
    "integrityVerdict" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MobileFaceSession_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MobileFaceSession_nonceHash_key"
    ON "MobileFaceSession"("nonceHash");
CREATE INDEX "MobileFaceSession_identityKey_attendanceSessionId_expiresAt_idx"
    ON "MobileFaceSession"("identityKey", "attendanceSessionId", "expiresAt");
CREATE INDEX "MobileFaceSession_expiresAt_consumedAt_idx"
    ON "MobileFaceSession"("expiresAt", "consumedAt");
