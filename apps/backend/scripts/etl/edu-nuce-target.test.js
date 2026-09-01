'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  __test,
  assertSafeTargetWrite,
  buildTargetUrls,
} = require('./edu-nuce-target');

const localEnv = {
  DATABASE_URL: 'postgresql://user:password@localhost:5432/central',
  HUCE_STUDENT_DATABASE_URL:
    'postgresql://user:password@localhost:5432/huce_student',
  HUCE_LECTURER_DATABASE_URL:
    'postgresql://user:password@localhost:5432/huce_lecturer',
  HUST_STUDENT_DATABASE_URL:
    'postgresql://user:password@localhost:5432/hust_student',
};

test('target URL guard rejects aliases, TLS bypasses and all remote apply', () => {
  assert.doesNotThrow(() => buildTargetUrls(localEnv, { apply: true }));
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL: localEnv.HUST_STUDENT_DATABASE_URL,
        },
        { apply: false },
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL:
            'postgresql://user:password@example.invalid:5432/huce_student',
        },
        { apply: true },
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL:
            'postgresql://user:password@example.invalid:5432/huce_student',
        },
        { apply: true },
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL:
            'postgresql://user:password@example.invalid:5432/huce_student?sslmode=verify-full&sslmode=disable',
        },
        { apply: false },
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL:
            'postgresql://user:password@example.invalid:5432/huce_student?sslmode=verify-full&uselibpqcompat=true',
        },
        { apply: false },
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL:
            'postgresql://user:password@localhost:5432/huce_student?host=example.invalid&sslmode=disable',
        },
        { apply: true },
      ),
    { name: 'EtlGuardError' },
  );
  assert.doesNotThrow(() =>
    buildTargetUrls(
      {
        ...localEnv,
        HUCE_STUDENT_DATABASE_URL:
          'postgresql://user:password@example.invalid:5432/huce_student?sslmode=verify-full',
      },
      { apply: false },
    ),
  );
  assert.throws(
    () =>
      buildTargetUrls(
        {
          ...localEnv,
          HUCE_STUDENT_DATABASE_URL:
            'postgresql://user:password@example.invalid:5432/huce_student?sslmode=verify-full',
        },
        { apply: true },
      ),
    { name: 'EtlGuardError' },
  );
});

test('target write guard blocks account/history mutation and destructive verbs', () => {
  assert.throws(
    () => assertSafeTargetWrite('UPDATE "StudentAccount" SET x = 1'),
    { name: 'EtlGuardError' },
  );
  assert.throws(() => assertSafeTargetWrite('DELETE FROM "Student"'), {
    name: 'EtlGuardError',
  });
  assert.doesNotThrow(() =>
    assertSafeTargetWrite('UPDATE "Course" SET "name" = $1'),
  );
});

test('empty registration snapshots cannot tombstone a target term', () => {
  assert.throws(
    () =>
      __test.assertNonEmptyImportSnapshot({
        offerings: [{ sourceId: 'TKB_LOPHOCPHAN:1' }],
        enrollments: [],
      }),
    { name: 'EtlGuardError' },
  );
});

test('snapshot confirmation is deterministic and checkpoint drop ratio is enforced', () => {
  const dataset = {
    sourceSystem: 'EDU_NUCE_IMPORT_20241108',
    term: { sourceId: 295 },
    students: [{ sourceStudentId: 1, mssv: 'SV001', fullName: 'Student One' }],
    offerings: [
      { sourceId: 'O:2', sourceStatus: '1', isActive: true },
      { sourceId: 'O:1', sourceStatus: '1', isActive: true },
    ],
    enrollments: [{ sourceId: 'E:1', sourceStatus: '1', isActive: true }],
    schedules: [{ sourceId: 'S:1', recurrenceKind: 'weekly', isActive: true }],
    scheduleLecturers: [{ sourceId: 'L:1', role: 'actual', isActive: true }],
  };
  const manifest = __test.buildSnapshotManifest(dataset);
  assert.equal(manifest.hash.length, 64);
  assert.match(manifest.confirmation, /^HUCE:295:2:1:1:[0-9a-f]{16}$/);
  assert.equal(__test.buildSnapshotManifest(dataset).hash, manifest.hash);
  const withContacts = __test.buildSnapshotManifest({
    ...dataset,
    profileFields: { includeBirthDates: false, includeContactFields: true },
  });
  assert.notEqual(withContacts.hash, manifest.hash);
  const withBirthDates = __test.buildSnapshotManifest({
    ...dataset,
    profileFields: { includeBirthDates: true, includeContactFields: false },
  });
  assert.notEqual(withBirthDates.hash, manifest.hash);
  const changedProfile = __test.buildSnapshotManifest({
    ...dataset,
    students: [
      { sourceStudentId: 1, mssv: 'SV001', fullName: 'Student Changed' },
    ],
  });
  assert.notEqual(changedProfile.hash, manifest.hash);

  assert.throws(
    () =>
      __test.assertCheckpointDropRatio(
        { snapshot: { counts: { enrollments: 100 } } },
        { counts: { offerings: 2, enrollments: 79, schedules: 1 } },
        0.2,
      ),
    { name: 'EtlGuardError' },
  );
});

test('runtime target identity and scope markers reject aliases', () => {
  assert.throws(
    () =>
      __test.assertDistinctActualTargets(
        new Map([
          [
            'central',
            {
              server_address: '10.0.0.1',
              server_port: 5432,
              database_name: 'same_db',
            },
          ],
          [
            'student',
            {
              server_address: '10.0.0.2',
              server_port: 5432,
              database_name: 'same_db',
            },
          ],
        ]),
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(
    () =>
      __test.assertScopeMarker(
        { scope: 'lecturer', schoolCode: 'HUCE' },
        'student',
      ),
    { name: 'EtlGuardError' },
  );
});

test('rerun tombstones rows absent from the full term snapshot without deleting', async () => {
  const statements = [];
  const writer = {
    async query(statement) {
      statements.push(statement);
      return { rows: [{ count: 0 }] };
    },
  };
  const dataset = {
    sourceSystem: 'EDU_NUCE_IMPORT_20241108',
    term: { sourceId: 295 },
  };

  await __test.upsertOfferings(writer, dataset);
  await __test.upsertEnrollments(writer, dataset);
  await __test.upsertSchedules(writer, dataset);
  await __test.upsertScheduleLecturers(writer, dataset);

  const sql = statements.join('\n');
  assert.match(sql, /offering\."sourceTermId" = \$3/);
  assert.match(sql, /offering\."sourceTermId" = \$2/);
  assert.match(sql, /NOT EXISTS \(/);
  assert.doesNotMatch(sql, /\bDELETE\b|\bTRUNCATE\b/i);
  assert.match(sql, /SET "isActive" = FALSE/);
});
