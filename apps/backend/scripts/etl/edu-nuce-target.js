'use strict';

const { createHash } = require('node:crypto');
const { Client } = require('pg');
const { EtlGuardError } = require('./edu-nuce-core');

const SCHOOL_CODE = 'HUCE';
const DEFAULT_SCHOOL_NAME = 'Đại học Xây dựng Hà Nội';
const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1', 'postgres']);
const FORBIDDEN_WRITE_TARGETS =
  /\b(StudentAccount|LecturerAccount|faceIdentityKey|citizenId|AttendanceSession|AttendanceRecord|StudentNotification|LecturerNotification|Announcement)\b/i;
const FORBIDDEN_WRITE_VERBS = /\b(DELETE|TRUNCATE)\b/i;

const REQUIRED_COLUMNS = {
  central: {
    School: ['id', 'code', 'name'],
    ImportCheckpoint: ['jobKey', 'targetScope', 'summary'],
    DatabaseScopeMarker: ['id', 'scope', 'schoolCode'],
  },
  student: {
    School: ['id', 'code'],
    Faculty: ['id', 'schoolId', 'code'],
    StudentClass: ['id', 'facultyId', 'code'],
    Student: ['id', 'schoolId', 'classId', 'mssv'],
    Lecturer: ['id', 'schoolId', 'lecturerCode'],
    Course: ['id', 'schoolId', 'code'],
    CourseOffering: ['id', 'sourceSystem', 'sourceId', 'sourceTermId'],
    CourseOfferingEnrollment: [
      'id',
      'offeringId',
      'studentId',
      'sourceSystem',
      'sourceId',
    ],
    Schedule: [
      'id',
      'offeringId',
      'sourceSystem',
      'sourceId',
      'startsAt',
      'endsAt',
      'recurrenceKind',
      'isActive',
    ],
    ScheduleLecturer: ['scheduleId', 'lecturerId', 'sourceSystem', 'sourceId'],
    ImportCheckpoint: ['jobKey', 'targetScope', 'summary'],
    DatabaseScopeMarker: ['id', 'scope', 'schoolCode'],
  },
  lecturer: {
    School: ['id', 'code'],
    Faculty: ['id', 'schoolId', 'code'],
    Lecturer: ['id', 'schoolId', 'lecturerCode'],
    ImportCheckpoint: ['jobKey', 'targetScope', 'summary'],
    DatabaseScopeMarker: ['id', 'scope', 'schoolCode'],
  },
};

function buildTargetUrls(env, options) {
  const targets = {
    central: requiredUrl(env.DATABASE_URL, 'DATABASE_URL'),
    student: requiredUrl(
      env.HUCE_STUDENT_DATABASE_URL,
      'HUCE_STUDENT_DATABASE_URL',
    ),
    lecturer: requiredUrl(
      env.HUCE_LECTURER_DATABASE_URL,
      'HUCE_LECTURER_DATABASE_URL',
    ),
  };

  for (const scope of ['student', 'lecturer']) {
    const probe = new Client({ connectionString: targets[scope].toString() });
    if (/hust/i.test(probe.connectionParameters.database)) {
      throw new EtlGuardError(
        'HUCE_TARGET_LOOKS_LIKE_HUST',
        `HUCE ${scope} target database name looks like a HUST database.`,
      );
    }
  }

  const identities = Object.values(targets).map(targetIdentity);
  if (new Set(identities).size !== identities.length) {
    throw new EtlGuardError(
      'TARGET_DATABASE_ALIAS',
      'Central, HUCE student và HUCE lecturer phải là ba database khác nhau.',
    );
  }

  for (const hustKey of [
    'HUST_STUDENT_DATABASE_URL',
    'HUST_LECTURER_DATABASE_URL',
  ]) {
    if (!env[hustKey]) {
      continue;
    }
    const hustIdentity = targetIdentity(requiredUrl(env[hustKey], hustKey));
    if (identities.includes(hustIdentity)) {
      throw new EtlGuardError(
        'HUCE_TARGET_ALIASES_HUST',
        'Một HUCE target đang trỏ cùng database với HUST; import bị chặn.',
      );
    }
  }

  const parsedTargets = Object.values(targets).map((url) => {
    const entries = [...url.searchParams.entries()];
    const unsupportedParameter = entries.find(
      ([key]) => key.toLowerCase() !== 'sslmode',
    );
    if (unsupportedParameter) {
      throw new EtlGuardError(
        'TARGET_CONNECTION_OVERRIDE_FORBIDDEN',
        'Target URLs may only use the sslmode query parameter.',
      );
    }
    const sslModes = entries
      .filter(([key]) => key.toLowerCase() === 'sslmode')
      .map(([, value]) => value.toLowerCase());
    const connectionProbe = new Client({ connectionString: url.toString() });
    const parsedSsl = connectionProbe.connectionParameters.ssl;
    const parsedHost = connectionProbe.connectionParameters.host.toLowerCase();
    const remote = !LOCAL_HOSTS.has(parsedHost);
    const verifiesCertificate =
      parsedSsl !== false && parsedSsl?.rejectUnauthorized !== false;
    if (
      sslModes.length > 1 ||
      (remote &&
        (sslModes.length !== 1 ||
          sslModes[0] !== 'verify-full' ||
          !verifiesCertificate))
    ) {
      throw new EtlGuardError(
        'REMOTE_TARGET_TLS_REQUIRED',
        'Remote PostgreSQL targets require exactly one sslmode=verify-full with certificate verification enabled.',
      );
    }
    return { url, remote };
  });
  const remoteTargets = parsedTargets.filter((target) => target.remote);

  if (options.apply) {
    const remoteCount = remoteTargets.length;
    if (remoteCount > 0) {
      throw new EtlGuardError(
        'REMOTE_APPLY_DISABLED',
        'Remote apply is disabled until an atomic publish barrier is implemented.',
        { remoteCount },
      );
    }
  }

  return Object.fromEntries(
    Object.entries(targets).map(([key, url]) => [key, url.toString()]),
  );
}

async function preflightTargets(targetUrls, dataset, options = {}) {
  assertNonEmptyImportSnapshot(dataset);
  const manifest = buildSnapshotManifest(dataset);
  const maxDropRatio = normalizeDropRatio(options.maxDropRatio, 0.2);
  const scopes = ['central', 'student', 'lecturer'];
  const results = {};
  const actualIdentities = new Map();

  for (const scope of scopes) {
    const url = new URL(targetUrls[scope]);
    results[scope] = await withPgClient(targetUrls[scope], async (client) => {
      await assertTargetSchema(client, scope);
      const identity = await readTargetIdentity(client);
      assertExpectedDatabaseIdentity(scope, url, identity);
      const marker = await readScopeMarker(client);
      assertScopeMarker(marker, scope);
      assertCheckpointDropRatio(
        await readPreviousCheckpoint(client, dataset, scope),
        manifest,
        maxDropRatio,
      );
      actualIdentities.set(scope, identity);

      const checkpoint = await client.query(
        `SELECT COUNT(*)::int AS count
         FROM "ImportCheckpoint"
         WHERE "jobKey" = $1 AND "targetScope" = $2`,
        [buildJobKey(dataset), scope],
      );
      return {
        existingCheckpointCount: checkpoint.rows[0].count,
        databaseIdentityVerified: true,
        scopeMarker: marker ? 'verified' : 'uninitialized',
      };
    });
  }
  assertDistinctActualTargets(actualIdentities);

  await withPgClient(targetUrls.student, async (client) => {
    await assertNoDemoAccountCollision(
      client,
      'Student',
      'StudentAccount',
      'studentId',
      'mssv',
      dataset.students.map((row) => row.mssv),
    );
    await assertNoDemoAccountCollision(
      client,
      'Lecturer',
      'LecturerAccount',
      'lecturerId',
      'lecturerCode',
      dataset.lecturers.map((row) => row.code),
    );
  });
  await withPgClient(targetUrls.lecturer, async (client) => {
    await assertNoDemoAccountCollision(
      client,
      'Lecturer',
      'LecturerAccount',
      'lecturerId',
      'lecturerCode',
      dataset.lecturers.map((row) => row.code),
    );
  });

  return { scopes: results, preflightToken: manifest.hash, snapshot: manifest };
}

async function applyDataset(targetUrls, dataset, options) {
  assertNonEmptyImportSnapshot(dataset);
  assertLocalApplyTargets(targetUrls);
  const manifest = buildSnapshotManifest(dataset);
  if (options.preflightToken !== manifest.hash) {
    throw new EtlGuardError(
      'TARGET_PREFLIGHT_TOKEN_REQUIRED',
      'Apply requires a matching preflight token for the exact snapshot.',
    );
  }
  const schoolName = options.schoolName?.trim() || DEFAULT_SCHOOL_NAME;
  const completedScopes = [];

  await runTargetTransaction(
    targetUrls.central,
    'central',
    dataset,
    async (writer) => {
      await upsertSchool(writer, schoolName);
    },
  );
  completedScopes.push('central');

  await runTargetTransaction(
    targetUrls.student,
    'student',
    dataset,
    async (writer) => {
      await upsertSchool(writer, schoolName);
      await stageStudentDataset(writer, dataset);
      await upsertFaculties(writer);
      await upsertClasses(writer);
      await upsertStudents(writer, dataset.profileFields);
      await upsertLecturers(writer, dataset.profileFields);
      await upsertCourses(writer);
      await upsertOfferings(writer, dataset);
      await upsertEnrollments(writer, dataset);
      await upsertSchedules(writer, dataset);
      await upsertScheduleLecturers(writer, dataset);
    },
  );
  completedScopes.push('student');

  await runTargetTransaction(
    targetUrls.lecturer,
    'lecturer',
    dataset,
    async (writer) => {
      await upsertSchool(writer, schoolName);
      await stageLecturerDataset(writer, dataset);
      await upsertFaculties(writer);
      await upsertLecturers(writer, dataset.profileFields);
    },
  );
  completedScopes.push('lecturer');

  return { completedScopes };
}

async function runTargetTransaction(url, scope, dataset, work) {
  await withPgClient(url, async (client) => {
    const writer = new GuardedTargetWriter(client);
    await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
    try {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
        `attendance-etl:${scope}:${SCHOOL_CODE}`,
      ]);
      await upsertScopeMarker(writer, scope);
      await writeCheckpoint(writer, dataset, scope, 'in_progress');
      await work(writer);
      await writeCheckpoint(writer, dataset, scope, 'completed');
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    }
  });
}

class GuardedTargetWriter {
  constructor(client) {
    this.client = client;
  }

  query(statement, values = []) {
    assertSafeTargetWrite(statement);
    return this.client.query(statement, values);
  }
}

async function stageStudentDataset(writer, dataset) {
  await writer.query(`
    CREATE TEMP TABLE etl_faculty (
      source_id integer PRIMARY KEY,
      code text NOT NULL,
      name text NOT NULL,
      placeholder_code text NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_class (
      source_key text PRIMARY KEY,
      source_faculty_id integer NOT NULL,
      code text NOT NULL,
      name text NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_student (
      source_id integer PRIMARY KEY,
      class_source_key text NOT NULL,
      mssv text NOT NULL,
      full_name text NOT NULL,
      date_of_birth timestamp(3),
      email text,
      phone_number text,
      is_active boolean NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_lecturer (
      source_id integer PRIMARY KEY,
      source_faculty_id integer,
      code text NOT NULL,
      full_name text NOT NULL,
      date_of_birth timestamp(3),
      email text,
      phone_number text,
      is_active boolean NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_course (
      code text PRIMARY KEY,
      source_faculty_id integer NOT NULL,
      name text NOT NULL,
      credits integer NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_offering (
      source_offering_id integer PRIMARY KEY,
      source_id text UNIQUE NOT NULL,
      source_term_id text NOT NULL,
      code text NOT NULL,
      course_code text NOT NULL,
      class_source_key text NOT NULL,
      term_code text,
      term_name text,
      starts_at timestamp(3),
      ends_at timestamp(3),
      is_active boolean NOT NULL,
      source_status text
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_enrollment (
      source_student_id integer NOT NULL,
      source_offering_id integer NOT NULL,
      source_id text UNIQUE NOT NULL,
      source_status text,
      is_active boolean NOT NULL,
      PRIMARY KEY (source_student_id, source_offering_id)
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_schedule (
      source_meeting_id integer NOT NULL,
      source_offering_id integer NOT NULL,
      source_id text PRIMARY KEY,
      primary_lecturer_code text,
      day_of_week integer NOT NULL,
      start_time text NOT NULL,
      end_time text NOT NULL,
      starts_at timestamp(3),
      ends_at timestamp(3),
      recurrence_kind text NOT NULL,
      room text NOT NULL,
      is_active boolean NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_schedule_lecturer (
      schedule_source_id text NOT NULL,
      lecturer_code text NOT NULL,
      role text NOT NULL,
      is_active boolean NOT NULL,
      source_id text UNIQUE NOT NULL,
      source_status text,
      PRIMARY KEY (schedule_source_id, lecturer_code)
    ) ON COMMIT DROP
  `);

  await bulkInsert(
    writer,
    'etl_faculty',
    ['source_id', 'code', 'name', 'placeholder_code'],
    dataset.faculties.map((row) => [
      row.sourceId,
      row.code,
      row.name,
      row.placeholderCode,
    ]),
  );
  await bulkInsert(
    writer,
    'etl_class',
    ['source_key', 'source_faculty_id', 'code', 'name'],
    dataset.classes.map((row) => [
      row.sourceKey,
      row.sourceFacultyId,
      row.code,
      row.name,
    ]),
  );
  await bulkInsert(
    writer,
    'etl_student',
    [
      'source_id',
      'class_source_key',
      'mssv',
      'full_name',
      'date_of_birth',
      'email',
      'phone_number',
      'is_active',
    ],
    dataset.students.map((row) => [
      row.sourceStudentId,
      row.classSourceKey,
      row.mssv,
      row.fullName,
      row.dateOfBirth,
      row.email,
      row.phoneNumber,
      row.isActive,
    ]),
  );
  await loadLecturerStage(writer, dataset.lecturers);
  await bulkInsert(
    writer,
    'etl_course',
    ['code', 'source_faculty_id', 'name', 'credits'],
    dataset.courses.map((row) => [
      row.code,
      row.sourceFacultyId,
      row.name,
      row.credits,
    ]),
  );
  await bulkInsert(
    writer,
    'etl_offering',
    [
      'source_offering_id',
      'source_id',
      'source_term_id',
      'code',
      'course_code',
      'class_source_key',
      'term_code',
      'term_name',
      'starts_at',
      'ends_at',
      'is_active',
      'source_status',
    ],
    dataset.offerings.map((row) => [
      row.sourceOfferingId,
      row.sourceId,
      row.sourceTermId,
      row.code,
      row.courseCode,
      row.classSourceKey,
      row.termCode,
      row.termName,
      row.startsAt,
      row.endsAt,
      row.isActive,
      row.sourceStatus,
    ]),
  );
  await bulkInsert(
    writer,
    'etl_enrollment',
    [
      'source_student_id',
      'source_offering_id',
      'source_id',
      'source_status',
      'is_active',
    ],
    dataset.enrollments.map((row) => [
      row.sourceStudentId,
      row.sourceOfferingId,
      row.sourceId,
      row.sourceStatus,
      row.isActive,
    ]),
  );
  await bulkInsert(
    writer,
    'etl_schedule',
    [
      'source_meeting_id',
      'source_offering_id',
      'source_id',
      'primary_lecturer_code',
      'day_of_week',
      'start_time',
      'end_time',
      'starts_at',
      'ends_at',
      'recurrence_kind',
      'room',
      'is_active',
    ],
    dataset.schedules.map((row) => [
      row.sourceMeetingId,
      row.sourceOfferingId,
      row.sourceId,
      row.primaryLecturerCode,
      row.dayOfWeek,
      row.startTime,
      row.endTime,
      row.startsAt,
      row.endsAt,
      row.recurrenceKind,
      row.room,
      row.isActive,
    ]),
  );
  await bulkInsert(
    writer,
    'etl_schedule_lecturer',
    [
      'schedule_source_id',
      'lecturer_code',
      'role',
      'is_active',
      'source_id',
      'source_status',
    ],
    dataset.scheduleLecturers.map((row) => [
      row.scheduleSourceId,
      row.lecturerCode,
      row.role,
      row.isActive,
      row.sourceId,
      row.sourceStatus,
    ]),
  );
}

async function stageLecturerDataset(writer, dataset) {
  await writer.query(`
    CREATE TEMP TABLE etl_faculty (
      source_id integer PRIMARY KEY,
      code text NOT NULL,
      name text NOT NULL,
      placeholder_code text NOT NULL
    ) ON COMMIT DROP;
    CREATE TEMP TABLE etl_lecturer (
      source_id integer PRIMARY KEY,
      source_faculty_id integer,
      code text NOT NULL,
      full_name text NOT NULL,
      date_of_birth timestamp(3),
      email text,
      phone_number text,
      is_active boolean NOT NULL
    ) ON COMMIT DROP
  `);
  await bulkInsert(
    writer,
    'etl_faculty',
    ['source_id', 'code', 'name', 'placeholder_code'],
    dataset.faculties.map((row) => [
      row.sourceId,
      row.code,
      row.name,
      row.placeholderCode,
    ]),
  );
  await loadLecturerStage(writer, dataset.lecturers);
}

async function loadLecturerStage(writer, lecturers) {
  await bulkInsert(
    writer,
    'etl_lecturer',
    [
      'source_id',
      'source_faculty_id',
      'code',
      'full_name',
      'date_of_birth',
      'email',
      'phone_number',
      'is_active',
    ],
    lecturers.map((row) => [
      row.sourceLecturerId,
      row.sourceFacultyId,
      row.code,
      row.fullName,
      row.dateOfBirth,
      row.email,
      row.phoneNumber,
      row.isActive,
    ]),
  );
}

async function upsertSchool(writer, schoolName) {
  await writer.query(
    `INSERT INTO "School" ("code", "name", "createdAt", "updatedAt")
     VALUES ($1, $2, NOW(), NOW())
     ON CONFLICT ("code") DO UPDATE
     SET "name" = EXCLUDED."name", "updatedAt" = NOW()`,
    [SCHOOL_CODE, schoolName],
  );
}

async function upsertFaculties(writer) {
  const collision = await writer.query(
    `SELECT COUNT(*)::int AS count
     FROM etl_faculty AS source
     JOIN "School" AS school ON school."code" = $1
     JOIN "Faculty" AS desired
       ON desired."schoolId" = school."id" AND desired."code" = source.code
     JOIN "Faculty" AS placeholder
       ON placeholder."schoolId" = school."id"
      AND placeholder."code" = source.placeholder_code
     WHERE desired."id" <> placeholder."id"`,
    [SCHOOL_CODE],
  );
  if (collision.rows[0].count > 0) {
    throw new EtlGuardError(
      'FACULTY_PLACEHOLDER_UPGRADE_COLLISION',
      'Tồn tại đồng thời faculty thật và placeholder cho cùng source ID.',
      { collisionCount: collision.rows[0].count },
    );
  }

  await writer.query(
    `UPDATE "Faculty" AS faculty
     SET "code" = source.code, "name" = source.name
     FROM etl_faculty AS source
     JOIN "School" AS school ON school."code" = $1
     WHERE faculty."schoolId" = school."id"
       AND faculty."code" = source.placeholder_code
       AND source.code <> source.placeholder_code`,
    [SCHOOL_CODE],
  );
  await writer.query(
    `INSERT INTO "Faculty" ("schoolId", "code", "name")
     SELECT school."id", source.code, source.name
     FROM etl_faculty AS source
     JOIN "School" AS school ON school."code" = $1
     ON CONFLICT ("schoolId", "code") DO UPDATE
     SET "name" = EXCLUDED."name"`,
    [SCHOOL_CODE],
  );
}

async function upsertClasses(writer) {
  await writer.query(
    `INSERT INTO "StudentClass" ("facultyId", "code", "name")
     SELECT faculty."id", source.code, source.name
     FROM etl_class AS source
     JOIN etl_faculty AS sf ON sf.source_id = source.source_faculty_id
     JOIN "School" AS school ON school."code" = $1
     JOIN "Faculty" AS faculty
       ON faculty."schoolId" = school."id" AND faculty."code" = sf.code
     ON CONFLICT ("facultyId", "code") DO UPDATE
     SET "name" = EXCLUDED."name"`,
    [SCHOOL_CODE],
  );
}

async function upsertStudents(writer, profileFields = {}) {
  await writer.query(
    `INSERT INTO "Student" (
       "schoolId", "classId", "mssv", "fullName", "dateOfBirth",
       "email", "phoneNumber", "isActive"
     )
     SELECT school."id", target_class."id", source.mssv, source.full_name,
       source.date_of_birth, source.email, source.phone_number, source.is_active
     FROM etl_student AS source
     JOIN etl_class AS sc ON sc.source_key = source.class_source_key
     JOIN etl_faculty AS sf ON sf.source_id = sc.source_faculty_id
     JOIN "School" AS school ON school."code" = $1
     JOIN "Faculty" AS faculty
       ON faculty."schoolId" = school."id" AND faculty."code" = sf.code
     JOIN "StudentClass" AS target_class
       ON target_class."facultyId" = faculty."id" AND target_class."code" = sc.code
     ON CONFLICT ("schoolId", "mssv") DO UPDATE SET
       "classId" = EXCLUDED."classId",
       "fullName" = EXCLUDED."fullName",
       "dateOfBirth" = CASE WHEN $2 THEN EXCLUDED."dateOfBirth" ELSE "Student"."dateOfBirth" END,
       "email" = CASE WHEN $3 THEN EXCLUDED."email" ELSE "Student"."email" END,
       "phoneNumber" = CASE WHEN $3 THEN EXCLUDED."phoneNumber" ELSE "Student"."phoneNumber" END,
       "isActive" = EXCLUDED."isActive"`,
    [
      SCHOOL_CODE,
      Boolean(profileFields.includeBirthDates),
      Boolean(profileFields.includeContactFields),
    ],
  );
}

async function upsertLecturers(writer, profileFields = {}) {
  await writer.query(
    `INSERT INTO "Lecturer" (
       "schoolId", "facultyId", "lecturerCode", "fullName", "dateOfBirth",
       "email", "phoneNumber", "isActive"
     )
     SELECT school."id", faculty."id", source.code, source.full_name,
       source.date_of_birth, source.email, source.phone_number, source.is_active
     FROM etl_lecturer AS source
     JOIN "School" AS school ON school."code" = $1
     LEFT JOIN etl_faculty AS sf ON sf.source_id = source.source_faculty_id
     LEFT JOIN "Faculty" AS faculty
       ON faculty."schoolId" = school."id" AND faculty."code" = sf.code
     ON CONFLICT ("schoolId", "lecturerCode") DO UPDATE SET
       "facultyId" = EXCLUDED."facultyId",
       "fullName" = EXCLUDED."fullName",
       "dateOfBirth" = CASE WHEN $2 THEN EXCLUDED."dateOfBirth" ELSE "Lecturer"."dateOfBirth" END,
       "email" = CASE WHEN $3 THEN EXCLUDED."email" ELSE "Lecturer"."email" END,
       "phoneNumber" = CASE WHEN $3 THEN EXCLUDED."phoneNumber" ELSE "Lecturer"."phoneNumber" END,
       "isActive" = EXCLUDED."isActive"`,
    [
      SCHOOL_CODE,
      Boolean(profileFields.includeBirthDates),
      Boolean(profileFields.includeContactFields),
    ],
  );
}

async function upsertCourses(writer) {
  await writer.query(
    `INSERT INTO "Course" ("schoolId", "facultyId", "code", "name", "credits")
     SELECT school."id", faculty."id", source.code, source.name, source.credits
     FROM etl_course AS source
     JOIN etl_faculty AS sf ON sf.source_id = source.source_faculty_id
     JOIN "School" AS school ON school."code" = $1
     JOIN "Faculty" AS faculty
       ON faculty."schoolId" = school."id" AND faculty."code" = sf.code
     ON CONFLICT ("schoolId", "code") DO UPDATE SET
       "facultyId" = EXCLUDED."facultyId",
       "name" = EXCLUDED."name",
       "credits" = EXCLUDED."credits"`,
    [SCHOOL_CODE],
  );
}

async function upsertOfferings(writer, dataset) {
  const sourceSystem = dataset.sourceSystem;
  const sourceTermId = String(dataset.term.sourceId);
  await writer.query(
    `UPDATE "CourseOffering" AS offering
     SET "isActive" = FALSE,
         "sourceStatus" = 'inactive_not_in_source_term_snapshot'
     FROM "School" AS school
     WHERE offering."schoolId" = school."id"
       AND school."code" = $1
       AND offering."sourceSystem" = $2
       AND offering."sourceTermId" = $3
       AND NOT EXISTS (
         SELECT 1 FROM etl_offering AS source
         WHERE source.source_id = offering."sourceId"
       )`,
    [SCHOOL_CODE, sourceSystem, sourceTermId],
  );
  await writer.query(
    `INSERT INTO "CourseOffering" (
       "schoolId", "courseId", "classId", "code", "termCode", "termName",
       "startsAt", "endsAt", "isActive", "sourceSystem", "sourceId",
       "sourceTermId", "sourceStatus"
     )
     SELECT school."id", course."id", target_class."id", source.code,
       source.term_code, source.term_name, source.starts_at, source.ends_at,
       source.is_active, $2, source.source_id, source.source_term_id,
       source.source_status
     FROM etl_offering AS source
     JOIN "School" AS school ON school."code" = $1
     JOIN "Course" AS course
       ON course."schoolId" = school."id" AND course."code" = source.course_code
     JOIN etl_class AS sc ON sc.source_key = source.class_source_key
     JOIN etl_faculty AS sf ON sf.source_id = sc.source_faculty_id
     JOIN "Faculty" AS faculty
       ON faculty."schoolId" = school."id" AND faculty."code" = sf.code
     JOIN "StudentClass" AS target_class
       ON target_class."facultyId" = faculty."id" AND target_class."code" = sc.code
     ON CONFLICT ("schoolId", "sourceSystem", "sourceId") DO UPDATE SET
       "courseId" = EXCLUDED."courseId",
       "classId" = EXCLUDED."classId",
       "code" = EXCLUDED."code",
       "termCode" = EXCLUDED."termCode",
       "termName" = EXCLUDED."termName",
       "startsAt" = EXCLUDED."startsAt",
       "endsAt" = EXCLUDED."endsAt",
       "isActive" = EXCLUDED."isActive",
       "sourceTermId" = EXCLUDED."sourceTermId",
       "sourceStatus" = EXCLUDED."sourceStatus"`,
    [SCHOOL_CODE, sourceSystem],
  );
}

async function upsertEnrollments(writer, dataset) {
  const sourceSystem = dataset.sourceSystem;
  const sourceTermId = String(dataset.term.sourceId);
  const collision = await writer.query(
    `SELECT COUNT(*)::int AS count
     FROM etl_enrollment AS source
     JOIN etl_offering AS so ON so.source_offering_id = source.source_offering_id
     JOIN "CourseOffering" AS offering
       ON offering."sourceSystem" = $1 AND offering."sourceId" = so.source_id
     JOIN "School" AS school ON school."id" = offering."schoolId" AND school."code" = $2
     JOIN "Student" AS student
       ON student."schoolId" = school."id"
      AND student."mssv" = (
        SELECT s.mssv FROM etl_student AS s WHERE s.source_id = source.source_student_id
      )
     JOIN "CourseOfferingEnrollment" AS existing
       ON existing."offeringId" = offering."id" AND existing."studentId" = student."id"
     WHERE existing."sourceSystem" IS DISTINCT FROM $1`,
    [sourceSystem, SCHOOL_CODE],
  );
  if (collision.rows[0].count > 0) {
    throw new EtlGuardError(
      'ENROLLMENT_SOURCE_COLLISION',
      'Enrollment target đã thuộc source khác; import bị chặn.',
      { collisionCount: collision.rows[0].count },
    );
  }

  await writer.query(
    `UPDATE "CourseOfferingEnrollment" AS enrollment
     SET "isActive" = FALSE,
         "sourceStatus" = 'inactive_not_in_active_source_set'
     FROM "CourseOffering" AS offering
     WHERE enrollment."offeringId" = offering."id"
       AND offering."sourceSystem" = $1
       AND offering."sourceTermId" = $2
       AND enrollment."sourceSystem" = $1
       AND NOT EXISTS (
         SELECT 1 FROM etl_enrollment AS source
         WHERE source.source_id = enrollment."sourceId"
       )`,
    [sourceSystem, sourceTermId],
  );
  await writer.query(
    `INSERT INTO "CourseOfferingEnrollment" (
       "offeringId", "studentId", "isActive", "sourceSystem", "sourceId", "sourceStatus"
     )
     SELECT offering."id", student."id", source.is_active, $1,
       source.source_id, source.source_status
     FROM etl_enrollment AS source
     JOIN etl_offering AS so ON so.source_offering_id = source.source_offering_id
     JOIN "CourseOffering" AS offering
       ON offering."sourceSystem" = $1 AND offering."sourceId" = so.source_id
     JOIN "School" AS school ON school."id" = offering."schoolId" AND school."code" = $2
     JOIN etl_student AS ss ON ss.source_id = source.source_student_id
     JOIN "Student" AS student
       ON student."schoolId" = school."id" AND student."mssv" = ss.mssv
     ON CONFLICT ("offeringId", "studentId") DO UPDATE SET
       "isActive" = EXCLUDED."isActive",
       "sourceSystem" = EXCLUDED."sourceSystem",
       "sourceId" = EXCLUDED."sourceId",
       "sourceStatus" = EXCLUDED."sourceStatus"`,
    [sourceSystem, SCHOOL_CODE],
  );
  await writer.query(
    `INSERT INTO "Enrollment" ("studentId", "courseId")
     SELECT DISTINCT student."id", offering."courseId"
     FROM etl_enrollment AS source
     JOIN etl_offering AS so ON so.source_offering_id = source.source_offering_id
     JOIN "CourseOffering" AS offering
       ON offering."sourceSystem" = $1 AND offering."sourceId" = so.source_id
     JOIN "School" AS school ON school."id" = offering."schoolId" AND school."code" = $2
     JOIN etl_student AS ss ON ss.source_id = source.source_student_id
     JOIN "Student" AS student
       ON student."schoolId" = school."id" AND student."mssv" = ss.mssv
     ON CONFLICT ("studentId", "courseId") DO NOTHING`,
    [sourceSystem, SCHOOL_CODE],
  );
}

async function upsertSchedules(writer, dataset) {
  const sourceSystem = dataset.sourceSystem;
  const sourceTermId = String(dataset.term.sourceId);
  await writer.query(
    `UPDATE "Schedule" AS schedule
     SET "isActive" = FALSE
     FROM "CourseOffering" AS offering
     WHERE schedule."offeringId" = offering."id"
       AND schedule."sourceSystem" = $1
       AND offering."sourceSystem" = $1
       AND offering."sourceTermId" = $2
       AND NOT EXISTS (
         SELECT 1 FROM etl_schedule AS source
         WHERE source.source_id = schedule."sourceId"
       )`,
    [sourceSystem, sourceTermId],
  );
  await writer.query(
    `INSERT INTO "Schedule" (
       "courseId", "classId", "lecturerId", "offeringId", "sourceSystem", "sourceId",
       "startsAt", "endsAt", "recurrenceKind", "isActive", "dayOfWeek",
       "startTime", "endTime", "room"
     )
     SELECT offering."courseId", offering."classId", lecturer."id", offering."id",
       $1, source.source_id, source.starts_at, source.ends_at,
       source.recurrence_kind, source.is_active, source.day_of_week,
       source.start_time, source.end_time, source.room
     FROM etl_schedule AS source
     JOIN etl_offering AS so ON so.source_offering_id = source.source_offering_id
     JOIN "CourseOffering" AS offering
       ON offering."sourceSystem" = $1 AND offering."sourceId" = so.source_id
     JOIN "School" AS school ON school."id" = offering."schoolId" AND school."code" = $2
     LEFT JOIN "Lecturer" AS lecturer
       ON lecturer."schoolId" = school."id"
      AND lecturer."lecturerCode" = source.primary_lecturer_code
     ON CONFLICT ("sourceSystem", "sourceId") DO UPDATE SET
       "courseId" = EXCLUDED."courseId",
       "classId" = EXCLUDED."classId",
       "lecturerId" = EXCLUDED."lecturerId",
       "offeringId" = EXCLUDED."offeringId",
       "startsAt" = EXCLUDED."startsAt",
       "endsAt" = EXCLUDED."endsAt",
       "recurrenceKind" = EXCLUDED."recurrenceKind",
       "isActive" = EXCLUDED."isActive",
       "dayOfWeek" = EXCLUDED."dayOfWeek",
       "startTime" = EXCLUDED."startTime",
       "endTime" = EXCLUDED."endTime",
       "room" = EXCLUDED."room"`,
    [sourceSystem, SCHOOL_CODE],
  );
}

async function upsertScheduleLecturers(writer, dataset) {
  const sourceSystem = dataset.sourceSystem;
  const sourceTermId = String(dataset.term.sourceId);
  const collision = await writer.query(
    `SELECT COUNT(*)::int AS count
     FROM etl_schedule_lecturer AS source
     JOIN "Schedule" AS schedule
       ON schedule."sourceSystem" = $1 AND schedule."sourceId" = source.schedule_source_id
     JOIN "CourseOffering" AS offering ON offering."id" = schedule."offeringId"
     JOIN "School" AS school ON school."id" = offering."schoolId" AND school."code" = $2
     JOIN "Lecturer" AS lecturer
       ON lecturer."schoolId" = school."id" AND lecturer."lecturerCode" = source.lecturer_code
     JOIN "ScheduleLecturer" AS existing
       ON existing."scheduleId" = schedule."id" AND existing."lecturerId" = lecturer."id"
     WHERE existing."sourceSystem" IS DISTINCT FROM $1`,
    [sourceSystem, SCHOOL_CODE],
  );
  if (collision.rows[0].count > 0) {
    throw new EtlGuardError(
      'SCHEDULE_LECTURER_SOURCE_COLLISION',
      'Schedule lecturer target đã thuộc source khác; import bị chặn.',
      { collisionCount: collision.rows[0].count },
    );
  }

  await writer.query(
    `UPDATE "ScheduleLecturer" AS assignment
     SET "isActive" = FALSE, "sourceStatus" = 'inactive_not_in_source_set'
     FROM "Schedule" AS schedule
     JOIN "CourseOffering" AS offering ON offering."id" = schedule."offeringId"
     WHERE assignment."scheduleId" = schedule."id"
       AND schedule."sourceSystem" = $1
       AND offering."sourceSystem" = $1
       AND offering."sourceTermId" = $2
       AND assignment."sourceSystem" = $1
       AND NOT EXISTS (
         SELECT 1 FROM etl_schedule_lecturer AS source
         WHERE source.source_id = assignment."sourceId"
       )`,
    [sourceSystem, sourceTermId],
  );
  await writer.query(
    `INSERT INTO "ScheduleLecturer" (
       "scheduleId", "lecturerId", "role", "isActive", "sourceSystem", "sourceId", "sourceStatus"
     )
     SELECT schedule."id", lecturer."id", source.role, source.is_active,
       $1, source.source_id, source.source_status
     FROM etl_schedule_lecturer AS source
     JOIN "Schedule" AS schedule
       ON schedule."sourceSystem" = $1 AND schedule."sourceId" = source.schedule_source_id
     JOIN "CourseOffering" AS offering ON offering."id" = schedule."offeringId"
     JOIN "School" AS school ON school."id" = offering."schoolId" AND school."code" = $2
     JOIN "Lecturer" AS lecturer
       ON lecturer."schoolId" = school."id" AND lecturer."lecturerCode" = source.lecturer_code
     ON CONFLICT ("scheduleId", "lecturerId") DO UPDATE SET
       "role" = EXCLUDED."role",
       "isActive" = EXCLUDED."isActive",
       "sourceSystem" = EXCLUDED."sourceSystem",
       "sourceId" = EXCLUDED."sourceId",
       "sourceStatus" = EXCLUDED."sourceStatus"`,
    [sourceSystem, SCHOOL_CODE],
  );
}

async function upsertScopeMarker(writer, scope) {
  const schoolCode = scope === 'central' ? null : SCHOOL_CODE;
  const result = await writer.query(
    `INSERT INTO "DatabaseScopeMarker" (
       "id", "scope", "schoolCode", "createdAt", "updatedAt"
     ) VALUES (1, $1, $2, NOW(), NOW())
     ON CONFLICT ("id") DO UPDATE SET
       "scope" = EXCLUDED."scope",
       "schoolCode" = EXCLUDED."schoolCode",
       "updatedAt" = NOW()
     WHERE "DatabaseScopeMarker"."scope" = EXCLUDED."scope"
       AND "DatabaseScopeMarker"."schoolCode" IS NOT DISTINCT FROM EXCLUDED."schoolCode"`,
    [scope, schoolCode],
  );
  if (result.rowCount !== 1) {
    throw new EtlGuardError(
      'TARGET_SCOPE_MARKER_CONFLICT',
      'Target database already belongs to a different scope.',
    );
  }
}

async function writeCheckpoint(writer, dataset, scope, status) {
  const summary = JSON.stringify({
    counts: dataset.report.counts,
    issues: dataset.report.issues,
    snapshot: buildSnapshotManifest(dataset),
  });
  await writer.query(
    `INSERT INTO "ImportCheckpoint" (
       "jobKey", "targetScope", "sourceSystem", "termSourceId", "status",
       "summary", "startedAt", "completedAt", "updatedAt"
     ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, NOW(),
       CASE WHEN $5 = 'completed' THEN NOW() ELSE NULL END, NOW())
     ON CONFLICT ("jobKey", "targetScope") DO UPDATE SET
       "sourceSystem" = EXCLUDED."sourceSystem",
       "termSourceId" = EXCLUDED."termSourceId",
       "status" = EXCLUDED."status",
       "summary" = EXCLUDED."summary",
       "startedAt" = CASE
         WHEN EXCLUDED."status" = 'in_progress' THEN NOW()
         ELSE "ImportCheckpoint"."startedAt"
       END,
       "completedAt" = CASE
         WHEN EXCLUDED."status" = 'completed' THEN NOW()
         ELSE NULL
       END,
       "updatedAt" = NOW()`,
    [
      buildJobKey(dataset),
      scope,
      dataset.sourceSystem,
      String(dataset.term.sourceId),
      status,
      summary,
    ],
  );
}

async function bulkInsert(writer, table, columns, rows) {
  if (rows.length === 0) {
    return;
  }
  const batchSize = Math.max(1, Math.floor(50_000 / columns.length));
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    const values = [];
    const tuples = batch.map((row) => {
      const placeholders = row.map((value) => {
        values.push(value);
        return `$${values.length}`;
      });
      return `(${placeholders.join(', ')})`;
    });
    await writer.query(
      `INSERT INTO ${quoteIdentifier(table)} (${columns
        .map(quoteIdentifier)
        .join(', ')}) VALUES ${tuples.join(', ')}`,
      values,
    );
  }
}

async function assertTargetSchema(client, scope) {
  const result = await client.query(
    `SELECT table_name, column_name
     FROM information_schema.columns
     WHERE table_schema = 'public'`,
  );
  const available = new Map();
  for (const row of result.rows) {
    const columns = available.get(row.table_name) ?? new Set();
    columns.add(row.column_name);
    available.set(row.table_name, columns);
  }
  let missingCount = 0;
  for (const [table, columns] of Object.entries(REQUIRED_COLUMNS[scope])) {
    const targetColumns = available.get(table) ?? new Set();
    missingCount += columns.filter(
      (column) => !targetColumns.has(column),
    ).length;
  }
  if (missingCount > 0) {
    throw new EtlGuardError(
      'TARGET_SCHEMA_NOT_READY',
      `Target ${scope} chưa có migration ETL bắt buộc.`,
      { missingCount },
    );
  }
}

async function assertNoDemoAccountCollision(
  client,
  entityTable,
  accountTable,
  accountForeignKey,
  identifierColumn,
  incomingIdentifiers,
) {
  if (incomingIdentifiers.length === 0) {
    return;
  }
  const result = await client.query(
    `SELECT entity.${quoteIdentifier(identifierColumn)} AS identifier
     FROM ${quoteIdentifier(entityTable)} AS entity
     JOIN ${quoteIdentifier(accountTable)} AS account
       ON account.${quoteIdentifier(accountForeignKey)} = entity."id"
     WHERE COALESCE(entity."email", '') ILIKE '%@demo.local'
        OR COALESCE(entity."fullName", '') ILIKE '%demo%'`,
  );
  const incoming = new Set(
    incomingIdentifiers.map((value) => String(value).trim().toUpperCase()),
  );
  const collisionCount = result.rows.reduce(
    (count, row) =>
      count +
      (incoming.has(String(row.identifier).trim().toUpperCase()) ? 1 : 0),
    0,
  );
  if (collisionCount > 0) {
    throw new EtlGuardError(
      'TARGET_TEST_ACCOUNT_COLLISION',
      'Source identifier trùng target test account; import bị chặn.',
      { collisionCount },
    );
  }
}

function assertSafeTargetWrite(statement) {
  if (FORBIDDEN_WRITE_VERBS.test(statement)) {
    throw new EtlGuardError(
      'FORBIDDEN_TARGET_MUTATION',
      'ETL không cho phép DELETE/TRUNCATE.',
    );
  }
  if (FORBIDDEN_WRITE_TARGETS.test(statement)) {
    throw new EtlGuardError(
      'FORBIDDEN_TARGET_ENTITY',
      'ETL cố chạm entity/field ứng dụng bị bảo vệ.',
    );
  }
}

function assertNonEmptyImportSnapshot(dataset) {
  if (!Array.isArray(dataset.offerings) || dataset.offerings.length === 0) {
    throw new EtlGuardError(
      'EMPTY_OFFERING_SNAPSHOT',
      'Term offering snapshot is empty; target tombstones are blocked.',
    );
  }
  if (!Array.isArray(dataset.enrollments) || dataset.enrollments.length === 0) {
    throw new EtlGuardError(
      'EMPTY_ENROLLMENT_SNAPSHOT',
      'Active enrollment snapshot is empty; target tombstones are blocked.',
    );
  }
}

function buildSnapshotManifest(dataset) {
  assertNonEmptyImportSnapshot(dataset);
  const collections = {
    profileFields: [dataset.profileFields ?? {}],
    faculties: dataset.faculties ?? [],
    classes: dataset.classes ?? [],
    students: dataset.students ?? [],
    lecturers: dataset.lecturers ?? [],
    courses: dataset.courses ?? [],
    offerings: dataset.offerings,
    enrollments: dataset.enrollments,
    schedules: dataset.schedules ?? [],
    scheduleLecturers: dataset.scheduleLecturers ?? [],
  };
  const hash = createHash('sha256');
  hash.update(`${dataset.sourceSystem}|${dataset.term.sourceId}\n`);
  const counts = {};
  for (const [name, rows] of Object.entries(collections)) {
    const values = rows.map(canonicalJson).sort();
    counts[name] = rows.length;
    hash.update(`${name}:${rows.length}\n`);
    for (const value of values) {
      hash.update(`${value}\n`);
    }
  }
  const digest = hash.digest('hex');
  return {
    algorithm: 'sha256',
    hash: digest,
    counts,
    confirmation: `${SCHOOL_CODE}:${dataset.term.sourceId}:${counts.offerings}:${counts.enrollments}:${counts.schedules}:${digest.slice(0, 16)}`,
  };
}

function canonicalJson(value) {
  if (value === undefined) {
    return '"__undefined__"';
  }
  if (value instanceof Date) {
    return JSON.stringify(value.toISOString());
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function normalizeDropRatio(value, fallback) {
  const ratio = value == null ? fallback : Number(value);
  if (!Number.isFinite(ratio) || ratio < 0 || ratio >= 1) {
    throw new EtlGuardError(
      'INVALID_DROP_RATIO',
      'Maximum snapshot drop ratio must satisfy 0 <= ratio < 1.',
    );
  }
  return ratio;
}

async function readPreviousCheckpoint(client, dataset, scope) {
  const result = await client.query(
    `SELECT "summary"
     FROM "ImportCheckpoint"
     WHERE "sourceSystem" = $1
       AND "termSourceId" = $2
       AND "targetScope" = $3
       AND "status" = 'completed'
     ORDER BY "completedAt" DESC NULLS LAST
     LIMIT 1`,
    [dataset.sourceSystem, String(dataset.term.sourceId), scope],
  );
  return result.rows[0]?.summary ?? null;
}

function assertCheckpointDropRatio(previousSummary, manifest, maxDropRatio) {
  if (!previousSummary) {
    return;
  }
  const previousCounts =
    previousSummary.snapshot?.counts ?? previousSummary.counts ?? {};
  for (const name of ['offerings', 'enrollments', 'schedules']) {
    const previous = Number(previousCounts[name]);
    const current = Number(manifest.counts[name]);
    if (!Number.isFinite(previous) || previous <= 0 || current >= previous) {
      continue;
    }
    const dropRatio = (previous - current) / previous;
    if (dropRatio > maxDropRatio) {
      throw new EtlGuardError(
        'SNAPSHOT_DROP_RATIO_EXCEEDED',
        'Source snapshot dropped beyond the configured checkpoint limit.',
        { entity: name, previous, current, dropRatio, maxDropRatio },
      );
    }
  }
}

async function readTargetIdentity(client) {
  const result = await client.query(
    `SELECT
       current_database() AS database_name,
       COALESCE(inet_server_addr()::text, 'local_socket') AS server_address,
       COALESCE(inet_server_port(), 0)::int AS server_port,
       COALESCE((SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()), FALSE) AS ssl`,
  );
  return result.rows[0];
}

function assertExpectedDatabaseIdentity(scope, url, identity) {
  const probe = new Client({ connectionString: url.toString() });
  const expectedDatabase = probe.connectionParameters.database;
  if (!expectedDatabase || identity.database_name !== expectedDatabase) {
    throw new EtlGuardError(
      'TARGET_DATABASE_IDENTITY_MISMATCH',
      `Connected ${scope} database does not match its parsed connection target.`,
    );
  }
  const parsedHost = probe.connectionParameters.host.toLowerCase();
  const remote = !LOCAL_HOSTS.has(parsedHost);
  if (remote && identity.ssl !== true) {
    throw new EtlGuardError(
      'REMOTE_TARGET_TLS_NOT_ACTIVE',
      `Connected ${scope} target did not negotiate TLS.`,
    );
  }
}

function assertDistinctActualTargets(identities) {
  const values = [...identities.values()];
  const keys = values.map(
    (identity) =>
      `${identity.server_address}:${identity.server_port}/${identity.database_name}`,
  );
  const databaseNames = values.map((identity) => identity.database_name);
  if (
    new Set(keys).size !== keys.length ||
    new Set(databaseNames).size !== databaseNames.length
  ) {
    throw new EtlGuardError(
      'TARGET_DATABASE_RUNTIME_ALIAS',
      'Two target scopes resolved to the same PostgreSQL database.',
    );
  }
}

async function readScopeMarker(client) {
  const result = await client.query(
    `SELECT "scope", "schoolCode"
     FROM "DatabaseScopeMarker"
     WHERE "id" = 1`,
  );
  return result.rows[0] ?? null;
}

function assertScopeMarker(marker, scope) {
  if (!marker) {
    return;
  }
  const expectedSchoolCode = scope === 'central' ? null : SCHOOL_CODE;
  if (
    marker.scope !== scope ||
    (marker.schoolCode ?? null) !== expectedSchoolCode
  ) {
    throw new EtlGuardError(
      'TARGET_SCOPE_MARKER_MISMATCH',
      `Target marker does not match scope ${scope}.`,
    );
  }
}

function assertLocalApplyTargets(targetUrls) {
  const remoteCount = Object.values(targetUrls).filter((value) => {
    const probe = new Client({ connectionString: value });
    return !LOCAL_HOSTS.has(probe.connectionParameters.host.toLowerCase());
  }).length;
  if (remoteCount > 0) {
    throw new EtlGuardError(
      'REMOTE_APPLY_DISABLED',
      'Remote apply is disabled until an atomic publish barrier is implemented.',
      { remoteCount },
    );
  }
}

function buildJobKey(dataset) {
  return `${dataset.sourceSystem}:term:${dataset.term.sourceId}:v1`;
}

function requiredUrl(value, envKey) {
  if (!value?.trim()) {
    throw new EtlGuardError(
      'MISSING_TARGET_URL',
      `Thiếu biến môi trường ${envKey}.`,
    );
  }
  let parsed;
  try {
    parsed = new URL(value.trim());
  } catch {
    throw new EtlGuardError('INVALID_TARGET_URL', `${envKey} không hợp lệ.`);
  }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) {
    throw new EtlGuardError(
      'INVALID_TARGET_PROTOCOL',
      `${envKey} phải dùng PostgreSQL.`,
    );
  }
  if (parsed.hash) {
    throw new EtlGuardError(
      'TARGET_URL_FRAGMENT_FORBIDDEN',
      `${envKey} must not contain a URL fragment.`,
    );
  }
  return parsed;
}

function targetIdentity(url) {
  return `${url.hostname.toLowerCase()}:${url.port || '5432'}${url.pathname}`;
}

async function withPgClient(connectionString, run) {
  const client = new Client({
    connectionString,
    application_name: 'attendance-edu-nuce-etl',
  });
  await client.connect();
  try {
    return await run(client);
  } finally {
    await client.end().catch(() => {});
  }
}

function quoteIdentifier(value) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) {
    throw new EtlGuardError(
      'INVALID_SQL_IDENTIFIER',
      'SQL identifier không hợp lệ.',
    );
  }
  return `"${value}"`;
}

module.exports = {
  SCHOOL_CODE,
  __test: {
    assertCheckpointDropRatio,
    assertDistinctActualTargets,
    assertNonEmptyImportSnapshot,
    assertScopeMarker,
    buildSnapshotManifest,
    upsertEnrollments,
    upsertOfferings,
    upsertScheduleLecturers,
    upsertSchedules,
  },
  applyDataset,
  assertSafeTargetWrite,
  buildJobKey,
  buildSnapshotManifest,
  buildTargetUrls,
  preflightTargets,
};
