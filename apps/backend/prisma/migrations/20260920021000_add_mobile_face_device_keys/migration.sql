-- Android Keystore is used as the no-cost device binding mechanism. The
-- private key remains on the handset; only its DER-encoded public key is kept.
CREATE TABLE "MobileFaceDeviceKey" (
    "id" SERIAL NOT NULL,
    "identityKey" TEXT NOT NULL,
    "keyFingerprint" TEXT NOT NULL,
    "publicKeyDer" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "enrolledAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "MobileFaceDeviceKey_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MobileFaceDeviceKey_keyFingerprint_key"
    ON "MobileFaceDeviceKey"("keyFingerprint");
CREATE INDEX "MobileFaceDeviceKey_identityKey_isActive_idx"
    ON "MobileFaceDeviceKey"("identityKey", "isActive");

ALTER TABLE "MobileFaceSession"
    ADD COLUMN "deviceKeyFingerprint" TEXT;
