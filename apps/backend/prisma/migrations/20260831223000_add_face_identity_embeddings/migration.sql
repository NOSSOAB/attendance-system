-- Store Face Auth embeddings in PostgreSQL so deployments do not require a
-- separate face_db.json volume. Source images are intentionally not stored.
CREATE TABLE "FaceIdentity" (
    "id" SERIAL NOT NULL,
    "identityKey" TEXT NOT NULL,
    "embeddings" JSONB NOT NULL,
    "meanEmbedding" JSONB NOT NULL,
    "imageCount" INTEGER NOT NULL DEFAULT 0,
    "modelName" TEXT NOT NULL DEFAULT 'buffalo_l',
    "threshold" DOUBLE PRECISION NOT NULL DEFAULT 0.60,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FaceIdentity_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FaceIdentity_identityKey_key" ON "FaceIdentity"("identityKey");
CREATE INDEX "FaceIdentity_isActive_updatedAt_idx" ON "FaceIdentity"("isActive", "updatedAt");
