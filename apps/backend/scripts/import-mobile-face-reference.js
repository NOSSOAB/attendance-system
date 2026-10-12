const fs = require('node:fs');
const { Pool } = require('pg');

const inputPath = process.argv[2];
if (!inputPath)
  throw new Error(
    'Usage: node scripts/import-mobile-face-reference.js reference.json',
  );
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');

const payload = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
if (!Array.isArray(payload.identities) || payload.identities.length === 0) {
  throw new Error('No identities in reference file');
}
if (
  !Number.isInteger(payload.sourceImageCount) ||
  payload.sourceImageCount < 2 ||
  payload.sourceImageCount > 5 ||
  !Number.isFinite(payload.minimumPairSimilarity)
) {
  throw new Error('Reference must include quality results from 2-5 photos');
}

function validateIdentity(item) {
  if (
    typeof item.identityKey !== 'string' ||
    !/^[A-Z0-9_-]+:.+/.test(item.identityKey)
  ) {
    throw new Error(`Identity must be school-scoped: ${item.identityKey}`);
  }
  if (
    !Array.isArray(item.meanEmbedding) ||
    item.meanEmbedding.length !== 128 ||
    item.meanEmbedding.some(
      (value) => typeof value !== 'number' || !Number.isFinite(value),
    )
  ) {
    throw new Error(`Invalid embedding for ${item.identityKey}`);
  }
  const norm = Math.sqrt(
    item.meanEmbedding.reduce((sum, value) => sum + value * value, 0),
  );
  if (norm < 0.995 || norm > 1.005)
    throw new Error(`Embedding is not normalized: ${item.identityKey}`);
  if (
    !Number.isFinite(item.threshold) ||
    item.threshold < 0.45 ||
    item.threshold > 0.9
  ) {
    throw new Error(`Invalid threshold for ${item.identityKey}`);
  }
  if (payload.minimumPairSimilarity < item.threshold) {
    throw new Error(`Reference photos disagree for ${item.identityKey}`);
  }
}

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
  try {
    for (const item of payload.identities) {
      validateIdentity(item);
      await pool.query(
        `INSERT INTO "MobileFaceIdentity"
          ("identityKey", "modelId", "meanEmbedding", "embeddingDimension", threshold,
           "enrollmentVersion", "isActive", "enrolledAt", "createdAt", "updatedAt")
         VALUES ($1, $2, $3::jsonb, 128, $4, 1, true, NOW(), NOW(), NOW())
         ON CONFLICT ("identityKey", "modelId") DO UPDATE SET
           "meanEmbedding" = EXCLUDED."meanEmbedding",
           "embeddingDimension" = 128,
           threshold = EXCLUDED.threshold,
           "enrollmentVersion" = "MobileFaceIdentity"."enrollmentVersion" + 1,
           "isActive" = true,
           "enrolledAt" = NOW(),
           "updatedAt" = NOW()`,
        [
          item.identityKey,
          payload.modelId,
          JSON.stringify(item.meanEmbedding),
          item.threshold,
        ],
      );
      console.log(`Imported ${item.identityKey}`);
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
