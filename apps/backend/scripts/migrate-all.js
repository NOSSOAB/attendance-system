const { Client } = require('pg');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const databaseUrlKeys = [
  'DATABASE_URL',
  'HUCE_STUDENT_DATABASE_URL',
  'HUCE_LECTURER_DATABASE_URL',
  'HUST_STUDENT_DATABASE_URL',
  'HUST_LECTURER_DATABASE_URL',
];

function getRequiredUrl(key) {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }

  return new URL(value);
}

function databaseName(url) {
  const name = decodeURIComponent(url.pathname.replace(/^\//, ''));
  if (!/^[A-Za-z0-9_]+$/.test(name)) {
    throw new Error(
      'Database names may only contain letters, digits, and underscores',
    );
  }

  return name;
}

async function ensureDatabasesExist() {
  const adminUrl = getRequiredUrl('POSTGRES_ADMIN_DATABASE_URL');
  const targetUrls = databaseUrlKeys.map(getRequiredUrl);
  const admin = new Client({ connectionString: adminUrl.toString() });

  await admin.connect();
  try {
    for (const targetUrl of targetUrls) {
      const name = databaseName(targetUrl);
      const existing = await admin.query(
        'SELECT 1 FROM pg_database WHERE datname = $1',
        [name],
      );

      if (existing.rowCount === 0) {
        await admin.query(`CREATE DATABASE "${name}"`);
        console.log(`Created database ${name}`);
      }
    }
  } finally {
    await admin.end();
  }
}

function migrateDatabases() {
  const prisma = path.resolve(
    __dirname,
    '..',
    'node_modules',
    '.bin',
    'prisma',
  );

  for (const key of databaseUrlKeys) {
    const url = getRequiredUrl(key);
    const name = databaseName(url);
    console.log(`Applying Prisma migrations to ${name}`);

    const result = spawnSync(prisma, ['migrate', 'deploy'], {
      cwd: path.resolve(__dirname, '..'),
      env: { ...process.env, DATABASE_URL: url.toString() },
      stdio: 'inherit',
    });

    if (result.status !== 0) {
      throw new Error(`Prisma migration failed for ${name}`);
    }
  }
}

async function main() {
  await ensureDatabasesExist();
  migrateDatabases();
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
