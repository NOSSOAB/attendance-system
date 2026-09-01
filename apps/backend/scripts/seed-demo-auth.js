require('dotenv').config();

const { spawnSync } = require('child_process');
const { randomBytes, scryptSync } = require('crypto');
const path = require('path');
const { Client } = require('pg');

const backendDir = path.resolve(__dirname, '..');
const adminConnectionString =
  process.env.POSTGRES_ADMIN_DATABASE_URL ??
  buildAdminConnectionString(process.env.DATABASE_URL);

const schoolConfigs = [
  {
    code: 'HUCE',
    name: 'Đại học Xây dựng Hà Nội',
    facultyCode: 'CNTT',
    facultyName: 'Công nghệ thông tin',
    classCode: '65CNTT1',
    className: '65CNTT1',
    studentDbUrl: process.env.HUCE_STUDENT_DATABASE_URL,
    lecturerDbUrl: process.env.HUCE_LECTURER_DATABASE_URL,
  },
  {
    code: 'HUST',
    name: 'Đại học Bách khoa Hà Nội',
    facultyCode: 'SOICT',
    facultyName: 'Công nghệ thông tin',
    classCode: 'K68-CNTT1',
    className: 'K68-CNTT1',
    studentDbUrl: process.env.HUST_STUDENT_DATABASE_URL,
    lecturerDbUrl: process.env.HUST_LECTURER_DATABASE_URL,
  },
];

const demoStudent = {
  mssv: '1389570',
  faceIdentityKey: process.env.DEMO_STUDENT_FACE_IDENTITY?.trim() || null,
  fullName: 'Sinh viên mẫu 1389570',
  dateOfBirth: '2007-09-27T00:00:00.000Z',
  email: '1389570@demo.local',
  phoneNumber: '0000000000',
  citizenId: 'DEMO-1389570',
  password: '27092007',
};

const demoLecturers = [
  {
    lecturerCode: 'GV001',
    fullName: 'Giảng viên demo GV001',
    dateOfBirth: '1985-08-12T00:00:00.000Z',
    email: 'gv001@demo.local',
  },
  {
    lecturerCode: 'GV002',
    fullName: 'Giảng viên demo GV002',
    dateOfBirth: '1987-04-18T00:00:00.000Z',
    email: 'gv002@demo.local',
  },
  {
    lecturerCode: 'GV003',
    fullName: 'Giảng viên demo GV003',
    dateOfBirth: '1984-11-05T00:00:00.000Z',
    email: 'gv003@demo.local',
  },
];

function buildAdminConnectionString(databaseUrl) {
  if (!databaseUrl) {
    return null;
  }

  try {
    const parsedUrl = new URL(databaseUrl);
    parsedUrl.pathname = '/postgres';
    parsedUrl.search = '';
    parsedUrl.hash = '';
    return parsedUrl.toString();
  } catch {
    return null;
  }
}

function buildAnnouncementSeeds() {
  const now = Date.now();

  return [
    {
      title: 'Thay đổi phòng học',
      body: 'Buổi học Cơ sở dữ liệu được chuyển sang phòng Lab 02 để đồng bộ với lịch thực hành.',
      type: 'warning',
      createdAt: new Date(now - 10 * 60 * 1000).toISOString(),
    },
    {
      title: 'Cập nhật module điểm danh',
      body: 'Sinh viên có thể theo dõi lịch học, lịch sử điểm danh và thông báo ngay trong ứng dụng.',
      type: 'info',
      createdAt: new Date(now - 2 * 60 * 60 * 1000).toISOString(),
    },
    {
      title: 'Thông báo học vụ',
      body: 'Nhà trường sẽ cập nhật lịch học tuần tới vào 18:00 tối nay. Vui lòng theo dõi thông báo mới.',
      type: 'general',
      createdAt: new Date(now - 24 * 60 * 60 * 1000).toISOString(),
    },
  ];
}

function buildCourseSeeds() {
  const now = new Date();
  const openStart = new Date(now.getTime() - 10 * 60 * 1000);
  const openEnd = new Date(now.getTime() + 35 * 60 * 1000);

  return [
    {
      code: 'AI101',
      name: 'Nhập môn trí tuệ nhân tạo',
      credits: 3,
      lecturerCode: 'GV002',
      room: 'Phòng B-202',
      occurrenceDate: shiftDate(now, 0),
      startTime: formatTime(openStart),
      endTime: formatTime(openEnd),
      session: {
        status: 'open',
        openedAt: new Date(now.getTime() - 18 * 60 * 1000).toISOString(),
        closesAt: new Date(now.getTime() + 25 * 60 * 1000).toISOString(),
        notificationType: 'attendance_open',
      },
    },
    {
      code: 'DB202',
      name: 'Cơ sở dữ liệu',
      credits: 3,
      lecturerCode: 'GV003',
      room: 'Phòng Lab 02',
      occurrenceDate: shiftDate(now, -1),
      startTime: '13:00',
      endTime: '15:00',
      session: {
        status: 'closed',
        notificationType: 'attendance_success',
      },
      record: {
        status: 'late',
        scanResult: 'success',
        scanAttempts: 1,
        checkInAtOffsetMinutes: 14,
      },
    },
    {
      code: 'SE303',
      name: 'Kỹ thuật phần mềm',
      credits: 3,
      lecturerCode: 'GV001',
      room: 'Giảng đường 304',
      occurrenceDate: shiftDate(now, -3),
      startTime: '09:00',
      endTime: '10:30',
      session: {
        status: 'closed',
        notificationType: 'attendance_review',
      },
      record: {
        status: 'needs_review',
        scanResult: 'success',
        scanAttempts: 1,
        checkInAtOffsetMinutes: 4,
        lastFailureReason: 'Cần đối chiếu thêm khuôn mặt với ảnh hồ sơ',
      },
    },
    {
      code: 'NET205',
      name: 'Mạng máy tính',
      credits: 3,
      lecturerCode: 'GV003',
      room: 'Phòng A-305',
      occurrenceDate: shiftDate(now, -5),
      startTime: '07:30',
      endTime: '09:00',
      session: {
        status: 'closed',
        notificationType: 'attendance_failed',
      },
      record: {
        status: 'failed',
        scanResult: 'failed',
        scanAttempts: 2,
        lastFailureReason: 'Không nhận diện được khuôn mặt trong 2 lần thử',
      },
    },
    {
      code: 'WEB210',
      name: 'Lập trình web',
      credits: 2,
      lecturerCode: 'GV001',
      room: 'Phòng C-105',
      occurrenceDate: shiftDate(now, -7),
      startTime: '15:00',
      endTime: '16:30',
      session: {
        status: 'closed',
        notificationType: null,
      },
    },
    {
      code: 'MATH201',
      name: 'Giải tích nâng cao',
      credits: 3,
      lecturerCode: 'GV002',
      room: 'Giảng đường 402',
      occurrenceDate: shiftDate(now, 2),
      startTime: '09:30',
      endTime: '11:00',
      session: {
        status: 'scheduled',
        notificationType: 'attendance_closing',
      },
    },
  ].map((course) => ({
    ...course,
    dayOfWeek: getIsoDayOfWeek(course.occurrenceDate),
  }));
}

async function withClient(connectionString, run) {
  const client = new Client({ connectionString });
  await client.connect();

  try {
    return await run(client);
  } finally {
    await client.end().catch(() => {});
  }
}

function parseDbName(connectionString) {
  if (!connectionString) {
    throw new Error('Missing database URL');
  }

  const url = new URL(connectionString);
  return url.pathname.replace(/^\//, '');
}

function assertDbName(dbName) {
  if (!/^[a-z0-9_]+$/i.test(dbName)) {
    throw new Error(`Invalid database name: ${dbName}`);
  }
}

function getIsoDayOfWeek(dateValue) {
  const day = dateValue.getDay();
  return day === 0 ? 7 : day;
}

function shiftDate(dateValue, dayOffset) {
  const value = new Date(dateValue);
  value.setHours(0, 0, 0, 0);
  value.setDate(value.getDate() + dayOffset);
  return value;
}

function combineDateAndTime(dateValue, timeValue) {
  const [hours, minutes] = timeValue.split(':').map((value) => Number(value));
  const result = new Date(dateValue);
  result.setHours(hours || 0, minutes || 0, 0, 0);
  return result;
}

function formatTime(dateValue) {
  const hours = `${dateValue.getHours()}`.padStart(2, '0');
  const minutes = `${dateValue.getMinutes()}`.padStart(2, '0');
  return `${hours}:${minutes}`;
}

async function ensureDatabaseExists(dbName) {
  assertDbName(dbName);

  if (!adminConnectionString) {
    throw new Error(
      'Missing POSTGRES_ADMIN_DATABASE_URL or DATABASE_URL for database bootstrap',
    );
  }

  await withClient(adminConnectionString, async (client) => {
    const existing = await client.query(
      'select 1 from pg_database where datname = $1',
      [dbName],
    );

    if (existing.rowCount > 0) {
      return;
    }

    await client.query(`CREATE DATABASE "${dbName}"`);
  });
}

function runMigrations(connectionString) {
  const prismaCliPath = path.resolve(
    backendDir,
    'node_modules',
    'prisma',
    'build',
    'index.js',
  );
  const result = spawnSync(
    process.execPath,
    [prismaCliPath, 'migrate', 'deploy'],
    {
      cwd: backendDir,
      env: {
        ...process.env,
        DATABASE_URL: connectionString,
      },
      encoding: 'utf8',
    },
  );

  if (result.status !== 0) {
    throw new Error(
      [
        `Prisma migrate deploy failed for ${connectionString}`,
        result.stdout?.trim(),
        result.stderr?.trim(),
      ]
        .filter(Boolean)
        .join('\n'),
    );
  }
}

function buildDatePassword(dateValue) {
  const date = new Date(dateValue);
  const day = `${date.getDate()}`.padStart(2, '0');
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const year = `${date.getFullYear()}`;
  return `${day}${month}${year}`;
}

function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const hash = scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

async function upsertSchoolCatalog() {
  const connectionString = process.env.DATABASE_URL;

  if (!connectionString) {
    throw new Error('Missing DATABASE_URL');
  }

  await withClient(connectionString, async (client) => {
    for (const school of schoolConfigs) {
      await client.query(
        `
          INSERT INTO "School" ("code", "name", "createdAt", "updatedAt")
          VALUES ($1, $2, NOW(), NOW())
          ON CONFLICT ("code")
          DO UPDATE SET
            "name" = EXCLUDED."name",
            "updatedAt" = NOW()
        `,
        [school.code, school.name],
      );
    }
  });
}

async function upsertStudentTenant(school) {
  if (!school.studentDbUrl) {
    throw new Error(`Missing student DB URL for ${school.code}`);
  }

  const courseSeeds = buildCourseSeeds();

  await withClient(school.studentDbUrl, async (client) => {
    const schoolResult = await client.query(
      `
        INSERT INTO "School" ("code", "name", "createdAt", "updatedAt")
        VALUES ($1, $2, NOW(), NOW())
        ON CONFLICT ("code")
        DO UPDATE SET
          "name" = EXCLUDED."name",
          "updatedAt" = NOW()
        RETURNING "id"
      `,
      [school.code, school.name],
    );
    const schoolId = schoolResult.rows[0].id;

    const facultyResult = await client.query(
      `
        INSERT INTO "Faculty" ("schoolId", "code", "name")
        VALUES ($1, $2, $3)
        ON CONFLICT ("schoolId", "code")
        DO UPDATE SET "name" = EXCLUDED."name"
        RETURNING "id"
      `,
      [schoolId, school.facultyCode, school.facultyName],
    );
    const facultyId = facultyResult.rows[0].id;

    const classResult = await client.query(
      `
        INSERT INTO "StudentClass" ("facultyId", "code", "name")
        VALUES ($1, $2, $3)
        ON CONFLICT ("facultyId", "code")
        DO UPDATE SET "name" = EXCLUDED."name"
        RETURNING "id"
      `,
      [facultyId, school.classCode, school.className],
    );
    const classId = classResult.rows[0].id;

    const studentResult = await client.query(
      `
        INSERT INTO "Student" (
          "schoolId",
          "classId",
          "mssv",
          "fullName",
          "faceIdentityKey",
          "dateOfBirth",
          "citizenId",
          "email",
          "phoneNumber",
          "isActive"
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, TRUE)
        ON CONFLICT ("schoolId", "mssv")
        DO UPDATE SET
          "classId" = EXCLUDED."classId",
          "fullName" = EXCLUDED."fullName",
          "faceIdentityKey" = EXCLUDED."faceIdentityKey",
          "dateOfBirth" = EXCLUDED."dateOfBirth",
          "citizenId" = EXCLUDED."citizenId",
          "email" = EXCLUDED."email",
          "phoneNumber" = EXCLUDED."phoneNumber",
          "isActive" = TRUE
        RETURNING "id"
      `,
      [
        schoolId,
        classId,
        demoStudent.mssv,
        demoStudent.fullName,
        demoStudent.faceIdentityKey,
        demoStudent.dateOfBirth,
        demoStudent.citizenId,
        demoStudent.email,
        demoStudent.phoneNumber,
      ],
    );
    const studentId = studentResult.rows[0].id;

    await client.query(
      `
        INSERT INTO "StudentAccount" ("studentId", "passwordHash", "lastLoginAt")
        VALUES ($1, $2, NULL)
        ON CONFLICT ("studentId")
        DO UPDATE SET
          "passwordHash" = EXCLUDED."passwordHash",
          "lastLoginAt" = NULL
      `,
      [studentId, hashPassword(demoStudent.password)],
    );

    const lecturerIds = new Map();

    for (const lecturer of demoLecturers) {
      const lecturerResult = await client.query(
        `
          INSERT INTO "Lecturer" (
            "schoolId",
            "facultyId",
            "lecturerCode",
            "fullName",
            "dateOfBirth",
            "email",
            "isActive"
          )
          VALUES ($1, $2, $3, $4, $5, $6, TRUE)
          ON CONFLICT ("schoolId", "lecturerCode")
          DO UPDATE SET
            "facultyId" = EXCLUDED."facultyId",
            "fullName" = EXCLUDED."fullName",
            "dateOfBirth" = EXCLUDED."dateOfBirth",
            "email" = EXCLUDED."email",
            "isActive" = TRUE
          RETURNING "id"
        `,
        [
          schoolId,
          facultyId,
          lecturer.lecturerCode,
          lecturer.fullName,
          lecturer.dateOfBirth,
          lecturer.email,
        ],
      );

      lecturerIds.set(lecturer.lecturerCode, lecturerResult.rows[0].id);
    }

    const scheduleIdsByCourseCode = new Map();

    for (const course of courseSeeds) {
      const courseResult = await client.query(
        `
          INSERT INTO "Course" ("schoolId", "facultyId", "code", "name", "credits")
          VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT ("schoolId", "code")
          DO UPDATE SET
            "facultyId" = EXCLUDED."facultyId",
            "name" = EXCLUDED."name",
            "credits" = EXCLUDED."credits"
          RETURNING "id"
        `,
        [schoolId, facultyId, course.code, course.name, course.credits],
      );
      const courseId = courseResult.rows[0].id;

      await client.query(
        `
          INSERT INTO "Enrollment" ("studentId", "courseId")
          VALUES ($1, $2)
          ON CONFLICT ("studentId", "courseId") DO NOTHING
        `,
        [studentId, courseId],
      );

      const scheduleResult = await client.query(
        `
          INSERT INTO "Schedule" (
            "courseId",
            "classId",
            "lecturerId",
            "dayOfWeek",
            "startTime",
            "endTime",
            "room"
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT (
            "courseId",
            "classId",
            "dayOfWeek",
            "startTime",
            "endTime",
            "room"
          )
          WHERE "offeringId" IS NULL
          DO UPDATE SET
            "lecturerId" = EXCLUDED."lecturerId"
          RETURNING "id"
        `,
        [
          courseId,
          classId,
          lecturerIds.get(course.lecturerCode) ?? null,
          course.dayOfWeek,
          course.startTime,
          course.endTime,
          course.room,
        ],
      );

      scheduleIdsByCourseCode.set(course.code, scheduleResult.rows[0].id);
    }

    const demoScheduleIds = [...scheduleIdsByCourseCode.values()];

    if (demoScheduleIds.length > 0) {
      await client.query(
        `
          DELETE FROM "StudentNotification"
          WHERE "studentId" = $1
            AND (
              "sessionId" IS NULL OR "sessionId" IN (
                SELECT "id"
                FROM "AttendanceSession"
                WHERE "scheduleId" = ANY($2::int[])
              )
            )
        `,
        [studentId, demoScheduleIds],
      );

      await client.query(
        `
          DELETE FROM "AttendanceRecord"
          WHERE "studentId" = $1
            AND "sessionId" IN (
              SELECT "id"
              FROM "AttendanceSession"
              WHERE "scheduleId" = ANY($2::int[])
            )
        `,
        [studentId, demoScheduleIds],
      );

      await client.query(
        `
          DELETE FROM "AttendanceSession"
          WHERE "scheduleId" = ANY($1::int[])
        `,
        [demoScheduleIds],
      );
    }

    for (const course of courseSeeds) {
      const scheduleId = scheduleIdsByCourseCode.get(course.code);
      const occurrenceStart = combineDateAndTime(
        course.occurrenceDate,
        course.startTime,
      );
      const occurrenceEnd = combineDateAndTime(
        course.occurrenceDate,
        course.endTime,
      );
      const openedAt =
        course.session.status === 'open' || course.session.status === 'closed'
          ? (course.session.openedAt ??
            new Date(occurrenceStart.getTime() - 20 * 60 * 1000).toISOString())
          : null;
      const closesAt =
        course.session.status === 'open' || course.session.status === 'closed'
          ? (course.session.closesAt ??
            new Date(occurrenceStart.getTime() + 20 * 60 * 1000).toISOString())
          : null;

      const sessionResult = await client.query(
        `
          INSERT INTO "AttendanceSession" (
            "scheduleId",
            "attendanceDate",
            "openedAt",
            "closesAt",
            "status",
            "createdAt",
            "updatedAt"
          )
          VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
          RETURNING "id"
        `,
        [
          scheduleId,
          occurrenceStart.toISOString(),
          openedAt,
          closesAt,
          course.session.status,
        ],
      );
      const sessionId = sessionResult.rows[0].id;

      if (course.record) {
        const checkInAt =
          course.record.checkInAtOffsetMinutes == null
            ? null
            : new Date(
                occurrenceStart.getTime() +
                  course.record.checkInAtOffsetMinutes * 60 * 1000,
              ).toISOString();

        await client.query(
          `
            INSERT INTO "AttendanceRecord" (
              "sessionId",
              "studentId",
              "status",
              "scanResult",
              "checkInAt",
              "scanAttempts",
              "lastFailureReason",
              "createdAt",
              "updatedAt"
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
          `,
          [
            sessionId,
            studentId,
            course.record.status,
            course.record.scanResult,
            checkInAt,
            course.record.scanAttempts,
            course.record.lastFailureReason ?? null,
          ],
        );
      }

      const notifications = buildNotificationsForCourse(
        course,
        sessionId,
        occurrenceStart,
        occurrenceEnd,
      );

      for (const notification of notifications) {
        await client.query(
          `
            INSERT INTO "StudentNotification" (
              "studentId",
              "sessionId",
              "title",
              "body",
              "type",
              "isRead",
              "createdAt",
              "updatedAt"
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
          `,
          [
            studentId,
            sessionId,
            notification.title,
            notification.body,
            notification.type,
            notification.isRead,
            notification.createdAt,
          ],
        );
      }
    }

    const announcementSeeds = buildAnnouncementSeeds();
    const announcementTitles = announcementSeeds.map(
      (announcement) => announcement.title,
    );

    await client.query(
      `
        DELETE FROM "Announcement"
        WHERE "schoolId" = $1
          AND "classId" = $2
          AND "title" = ANY($3::text[])
      `,
      [schoolId, classId, announcementTitles],
    );

    for (const announcement of announcementSeeds) {
      await client.query(
        `
          INSERT INTO "Announcement" (
            "schoolId",
            "classId",
            "title",
            "body",
            "type",
            "createdAt",
            "updatedAt"
          )
          VALUES ($1, $2, $3, $4, $5, $6, $6)
        `,
        [
          schoolId,
          classId,
          announcement.title,
          announcement.body,
          announcement.type,
          announcement.createdAt,
        ],
      );
    }
  });
}

function buildNotificationsForCourse(
  course,
  sessionId,
  occurrenceStart,
  occurrenceEnd,
) {
  const baseTime = new Date(occurrenceStart);
  const notifications = [];

  if (course.session.status === 'open') {
    notifications.push({
      title: `Môn học ${course.name} đã mở điểm danh`,
      body: `Buổi học ${course.code} đang mở điểm danh từ ${course.startTime} đến ${course.endTime}.`,
      type: 'attendance_open',
      isRead: false,
      createdAt: new Date(baseTime.getTime() - 5 * 60 * 1000).toISOString(),
    });

    notifications.push({
      title: `Phiên điểm danh ${course.code} sắp đóng`,
      body: `Bạn còn ít phút để hoàn thành điểm danh cho môn ${course.name}.`,
      type: 'attendance_closing',
      isRead: false,
      createdAt: new Date(
        Math.min(
          Date.now() - 2 * 60 * 1000,
          occurrenceEnd.getTime() - 5 * 60 * 1000,
        ),
      ).toISOString(),
    });
  }

  if (course.record?.status === 'late') {
    notifications.push({
      title: `Điểm danh thành công cho ${course.code}`,
      body: `Bạn đã điểm danh thành công và được ghi nhận trạng thái Muộn.`,
      type: 'attendance_success',
      isRead: true,
      createdAt: new Date(
        occurrenceEnd.getTime() + 10 * 60 * 1000,
      ).toISOString(),
    });
  }

  if (course.record?.status === 'needs_review') {
    notifications.push({
      title: `Cần kiểm tra lại điểm danh ${course.code}`,
      body: `Hệ thống cần đối chiếu thêm khuôn mặt cho buổi học ${course.name}.`,
      type: 'attendance_review',
      isRead: false,
      createdAt: new Date(
        occurrenceEnd.getTime() + 8 * 60 * 1000,
      ).toISOString(),
    });
  }

  if (course.record?.status === 'failed') {
    notifications.push({
      title: `Điểm danh thất bại cho ${course.code}`,
      body: `Hệ thống ghi nhận điểm danh thất bại. Nếu buổi học vẫn mở, bạn có thể thử lại.`,
      type: 'attendance_failed',
      isRead: false,
      createdAt: new Date(
        occurrenceEnd.getTime() + 6 * 60 * 1000,
      ).toISOString(),
    });
  }

  return notifications;
}

async function upsertLecturerTenant(school) {
  if (!school.lecturerDbUrl) {
    throw new Error(`Missing lecturer DB URL for ${school.code}`);
  }

  await withClient(school.lecturerDbUrl, async (client) => {
    const schoolResult = await client.query(
      `
        INSERT INTO "School" ("code", "name", "createdAt", "updatedAt")
        VALUES ($1, $2, NOW(), NOW())
        ON CONFLICT ("code")
        DO UPDATE SET
          "name" = EXCLUDED."name",
          "updatedAt" = NOW()
        RETURNING "id"
      `,
      [school.code, school.name],
    );
    const schoolId = schoolResult.rows[0].id;

    const facultyResult = await client.query(
      `
        INSERT INTO "Faculty" ("schoolId", "code", "name")
        VALUES ($1, $2, $3)
        ON CONFLICT ("schoolId", "code")
        DO UPDATE SET "name" = EXCLUDED."name"
        RETURNING "id"
      `,
      [schoolId, school.facultyCode, school.facultyName],
    );
    const facultyId = facultyResult.rows[0].id;

    for (const lecturer of demoLecturers) {
      const lecturerResult = await client.query(
        `
          INSERT INTO "Lecturer" (
            "schoolId",
            "facultyId",
            "lecturerCode",
            "fullName",
            "dateOfBirth",
            "email",
            "isActive"
          )
          VALUES ($1, $2, $3, $4, $5, $6, TRUE)
          ON CONFLICT ("schoolId", "lecturerCode")
          DO UPDATE SET
            "facultyId" = EXCLUDED."facultyId",
            "fullName" = EXCLUDED."fullName",
            "dateOfBirth" = EXCLUDED."dateOfBirth",
            "email" = EXCLUDED."email",
            "isActive" = TRUE
          RETURNING "id"
        `,
        [
          schoolId,
          facultyId,
          lecturer.lecturerCode,
          lecturer.fullName,
          lecturer.dateOfBirth,
          lecturer.email,
        ],
      );
      const lecturerId = lecturerResult.rows[0].id;

      await client.query(
        `
          INSERT INTO "LecturerAccount" (
            "lecturerId",
            "passwordHash",
            "lastLoginAt"
          )
          VALUES ($1, $2, NULL)
          ON CONFLICT ("lecturerId")
          DO UPDATE SET
            "passwordHash" = EXCLUDED."passwordHash",
            "lastLoginAt" = NULL
        `,
        [lecturerId, hashPassword(buildDatePassword(lecturer.dateOfBirth))],
      );
    }
  });
}

async function main() {
  if (!process.env.DATABASE_URL) {
    throw new Error('Missing DATABASE_URL');
  }

  await ensureDatabaseExists(parseDbName(process.env.DATABASE_URL));

  for (const school of schoolConfigs) {
    await ensureDatabaseExists(parseDbName(school.studentDbUrl));
    await ensureDatabaseExists(parseDbName(school.lecturerDbUrl));
  }

  runMigrations(process.env.DATABASE_URL);
  await upsertSchoolCatalog();

  for (const school of schoolConfigs) {
    runMigrations(school.studentDbUrl);
    runMigrations(school.lecturerDbUrl);
    await upsertStudentTenant(school);
    await upsertLecturerTenant(school);
  }

  console.log(
    `Demo student ready: MSSV ${demoStudent.mssv} (mật khẩu theo quy tắc ngày sinh ddmmyyyy)`,
  );
  console.log(
    `Demo lecturers ready: ${demoLecturers.map((lecturer) => lecturer.lecturerCode).join(', ')} (mật khẩu theo quy tắc ngày sinh ddmmyyyy)`,
  );
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
