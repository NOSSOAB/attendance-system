'use strict';

const { EtlGuardError } = require('./edu-nuce-core');

const SOURCE_SYSTEM = 'EDU_NUCE_IMPORT_20241108';
const EXPECTED_SOURCE_DATABASE = 'EDU_NUCE_IMPORT_20241108';
const FORBIDDEN_SOURCE_COLUMNS =
  /\b(Pwd|PwdHashKey|Password|PasswordHash|RefreshToken|SoTaiKhoan|citizenId|CMND|CCCD|SoCMND|SoCCCD|CanCuoc)\b/i;
const FORBIDDEN_SOURCE_VERBS =
  /\b(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|ALTER|DROP|CREATE|EXEC|EXECUTE|GRANT|REVOKE|DENY|BACKUP|RESTORE|DBCC)\b/i;
const FORBIDDEN_SOURCE_FEATURES =
  /\b(INTO|OPENROWSET|OPENDATASOURCE|BULK|WAITFOR|USE|DECLARE|CURSOR)\b|\bNEXT\s+VALUE\s+FOR\b/i;
const ALLOWED_SOURCE_LABELS = new Set([
  'sourceAccess',
  'term',
  'students',
  'registrations',
  'homeroomClasses',
  'offerings',
  'meetings',
  'actualLecturers',
  'plannedLecturers',
]);
const SOURCE_RESULT_COLUMNS = {
  sourceAccess: ['databaseName', 'updateability', 'principalWriteCapable'],
  term: [
    'sourceTermId',
    'termCode',
    'termName',
    'startsAt',
    'endsAt',
    'isActive',
    'isVisible',
  ],
  students: [
    'sourceStudentId',
    'studentCode',
    'familyName',
    'givenName',
    'sourceStatus',
    'sourceHomeroomClassId',
    'sourceMajorId',
  ],
  registrations: [
    'sourceRegistrationId',
    'sourceStudentId',
    'sourceOfferingId',
    'sourceStatus',
    'sourceRowCount',
  ],
  homeroomClasses: [
    'sourceClassId',
    'primaryCode',
    'secondaryCode',
    'className',
    'sourceMajorId',
    'sourceFacultyId',
  ],
  offerings: [
    'sourceOfferingId',
    'offeringCode',
    'sourceStatus',
    'sourceTkbCourseId',
    'courseCode',
    'courseName',
    'credits',
    'sourceCatalogCourseId',
    'sourceCourseFacultyId',
    'catalogCourseName',
    'catalogMatchCount',
    'sourceTeachingClassId',
    'teachingClassCode',
    'teachingClassName',
    'sourceFacultyId',
    'sourceMajorId',
  ],
  meetings: [
    'sourceMeetingId',
    'sourceOfferingId',
    'sourceSchedulingGroupId',
    'sourceWeekday',
    'startPeriod',
    'endPeriod',
    'startsAt',
    'endsAt',
    'teachingStartsAt',
    'teachingEndsAt',
    'isSuspended',
    'isBiweekly',
    'isDaySpecific',
    'isMakeup',
    'resolvedStartTime',
    'resolvedEndTime',
    'sourceRoomId',
    'roomCode',
    'roomName',
  ],
  actualLecturers: [
    'sourceMeetingId',
    'sourceOfferingId',
    'sourceLecturerId',
    'sourceFacultyId',
    'lecturerCode',
    'familyName',
    'givenName',
    'isDeleted',
    'isDisabled',
    'isTerminated',
  ],
  plannedLecturers: [
    'sourceOfferingId',
    'sourceLecturerId',
    'sourceFacultyId',
    'lecturerCode',
    'familyName',
    'givenName',
    'isDeleted',
    'isDisabled',
    'isTerminated',
  ],
};

class EduNuceSource {
  constructor(runtime) {
    this.sql = runtime.sql;
    this.config = runtime.config;
    this.pool = null;
    this.accessVerified = false;
  }

  async connect() {
    this.pool = await new this.sql.ConnectionPool(this.config).connect();
  }

  async close() {
    if (this.pool) {
      await this.pool.close().catch(() => {});
      this.pool = null;
      this.accessVerified = false;
    }
  }

  async verifyAccess({ allowWritablePrincipal = false } = {}) {
    const rows = await this.select('sourceAccess', QUERIES.sourceAccess);
    if (
      rows.length !== 1 ||
      rows[0].databaseName !== EXPECTED_SOURCE_DATABASE
    ) {
      throw new EtlGuardError(
        'SOURCE_DATABASE_IDENTITY_MISMATCH',
        `Connected database must be exactly ${EXPECTED_SOURCE_DATABASE}.`,
      );
    }
    const databaseReadOnly =
      String(rows[0].updateability).toUpperCase() === 'READ_ONLY';
    const principalWriteCapable = normalizePermissionBit(
      rows[0].principalWriteCapable,
    );
    if (!databaseReadOnly && principalWriteCapable && !allowWritablePrincipal) {
      throw new EtlGuardError(
        'SOURCE_PRINCIPAL_CAN_WRITE',
        'Source database is writable by the current principal. Use a read-only principal/database or explicitly acknowledge --allow-writable-source-principal.',
      );
    }
    this.accessVerified = true;
    return {
      databaseReadOnly,
      principalWriteCapable,
      writableOverrideUsed:
        !databaseReadOnly && principalWriteCapable && allowWritablePrincipal,
    };
  }

  async loadRaw(termId, activeRegistrationStatuses, profileOptions = {}) {
    if (!this.accessVerified) {
      throw new EtlGuardError(
        'SOURCE_ACCESS_NOT_VERIFIED',
        'Source access must pass the read-only preflight before loading data.',
      );
    }
    const termRows = await this.select('term', QUERIES.term, {
      termId: { type: this.sql.Int, value: termId },
    });
    if (termRows.length !== 1) {
      throw new EtlGuardError(
        'TERM_NOT_FOUND',
        'Không tìm thấy đúng một DM_Dot cho term ID đã chọn.',
        { termCount: termRows.length },
      );
    }

    const parameters = {
      termId: { type: this.sql.Int, value: termId },
    };
    const registrationParameters = { ...parameters };
    const statusPlaceholders = [...activeRegistrationStatuses].map(
      (status, index) => {
        const parameterName = `activeRegistrationStatus${index}`;
        registrationParameters[parameterName] = {
          type: this.sql.Int,
          value: Number(status),
        };
        return `@${parameterName}`;
      },
    );
    const [
      students,
      registrations,
      homeroomClasses,
      offerings,
      meetings,
      actualLecturers,
      plannedLecturers,
    ] = await Promise.all([
      this.select(
        'students',
        QUERIES.students(profileOptions),
        parameters,
        expectedProfileColumns('students', profileOptions),
      ),
      this.select(
        'registrations',
        buildRegistrationQuery(statusPlaceholders),
        registrationParameters,
      ),
      this.select('homeroomClasses', QUERIES.homeroomClasses, parameters),
      this.select('offerings', QUERIES.offerings, parameters),
      this.select('meetings', QUERIES.meetings, parameters),
      this.select(
        'actualLecturers',
        QUERIES.actualLecturers(profileOptions),
        parameters,
        expectedProfileColumns('actualLecturers', profileOptions),
      ),
      this.select(
        'plannedLecturers',
        QUERIES.plannedLecturers(profileOptions),
        parameters,
        expectedProfileColumns('plannedLecturers', profileOptions),
      ),
    ]);

    return {
      term: termRows[0],
      students,
      registrations,
      homeroomClasses,
      offerings,
      meetings,
      actualLecturers,
      plannedLecturers,
    };
  }

  async select(
    label,
    statement,
    parameters = {},
    expectedColumns = SOURCE_RESULT_COLUMNS[label],
  ) {
    if (!ALLOWED_SOURCE_LABELS.has(label)) {
      throw new EtlGuardError(
        'SOURCE_QUERY_NOT_ALLOWLISTED',
        `Source query ${label} is not allowlisted.`,
      );
    }
    assertReadOnlySourceStatement(label, statement);
    if (!this.pool) {
      throw new Error('SQL Server source pool is not connected.');
    }

    const request = this.pool.request();
    for (const [name, parameter] of Object.entries(parameters)) {
      request.input(name, parameter.type, parameter.value);
    }
    const result = await request.query(statement);
    assertExactResultColumns(label, result.recordset, expectedColumns);
    return result.recordset ?? [];
  }
}

function buildSourceConfig(env) {
  return buildSourceRuntime(env).config;
}

function buildSourceRuntime(env) {
  const database =
    env.EDU_NUCE_SQLSERVER_DATABASE?.trim() || EXPECTED_SOURCE_DATABASE;
  if (database !== EXPECTED_SOURCE_DATABASE) {
    throw new EtlGuardError(
      'WRONG_SOURCE_DATABASE',
      `Source database phải đúng ${EXPECTED_SOURCE_DATABASE}.`,
    );
  }

  const trusted = parseBoolean(env.EDU_NUCE_SQLSERVER_TRUSTED, false);
  const server = env.EDU_NUCE_SQLSERVER_HOST?.trim() || 'localhost';
  const encrypt = parseBoolean(env.EDU_NUCE_SQLSERVER_ENCRYPT, true);
  const trustServerCertificate = parseBoolean(
    env.EDU_NUCE_SQLSERVER_TRUST_CERTIFICATE,
    false,
  );
  const user = env.EDU_NUCE_SQLSERVER_USER?.trim();
  const password = env.EDU_NUCE_SQLSERVER_PASSWORD;
  if (!trusted && (!user || !password)) {
    throw new EtlGuardError(
      'MISSING_SOURCE_CONFIGURATION',
      'Thiếu host/user/password cho SQL Server source.',
    );
  }

  let driver;
  try {
    driver = trusted ? require('mssql/msnodesqlv8') : require('mssql');
  } catch {
    throw new EtlGuardError(
      'SOURCE_DRIVER_UNAVAILABLE',
      trusted
        ? 'Thiếu driver mssql/msnodesqlv8 cho Windows Authentication.'
        : 'Thiếu package mssql cho SQL Server source.',
    );
  }

  const config = {
    server,
    port: parsePort(env.EDU_NUCE_SQLSERVER_PORT, 1433),
    database,
    ...(trusted
      ? {
          connectionString: buildTrustedConnectionString({
            driver:
              env.EDU_NUCE_SQLSERVER_ODBC_DRIVER?.trim() ||
              'ODBC Driver 18 for SQL Server',
            server,
            port: env.EDU_NUCE_SQLSERVER_PORT?.trim() || null,
            database,
            encrypt,
            trustServerCertificate,
          }),
        }
      : {}),
    ...(trusted ? {} : { user, password }),
    connectionTimeout: parsePositiveNumber(
      env.EDU_NUCE_SQLSERVER_CONNECTION_TIMEOUT_MS,
      30_000,
    ),
    requestTimeout: parsePositiveNumber(
      env.EDU_NUCE_SQLSERVER_REQUEST_TIMEOUT_MS,
      180_000,
    ),
    pool: {
      min: 0,
      max: 4,
      idleTimeoutMillis: 30_000,
    },
    options: {
      appName: 'attendance-edu-nuce-readonly-etl',
      encrypt,
      trustServerCertificate,
      readOnlyIntent: true,
      trustedConnection: trusted,
      enableArithAbort: true,
      useUTC: true,
    },
  };

  return { sql: driver, config, trusted };
}

function buildTrustedConnectionString({
  driver,
  server,
  port,
  database,
  encrypt,
  trustServerCertificate,
}) {
  if (!/^[A-Za-z0-9 ._-]+$/.test(driver)) {
    throw new EtlGuardError(
      'INVALID_ODBC_DRIVER_NAME',
      'ODBC driver name contains unsupported characters.',
    );
  }
  if (!/^[A-Za-z0-9_.-]+(?:\\[A-Za-z0-9_.-]+)?$/.test(server)) {
    throw new EtlGuardError(
      'INVALID_SOURCE_SERVER',
      'SQL Server host/instance contains unsupported characters.',
    );
  }
  const serverTarget = port ? `${server},${parsePort(port, 1433)}` : server;
  return [
    `Driver={${driver}}`,
    `Server=${serverTarget}`,
    `Database=${database}`,
    'Trusted_Connection=Yes',
    `Encrypt=${encrypt ? 'Yes' : 'No'}`,
    `TrustServerCertificate=${trustServerCertificate ? 'Yes' : 'No'}`,
    'ApplicationIntent=ReadOnly',
    'APP=attendance-edu-nuce-readonly-etl',
    '',
  ].join(';');
}

function assertReadOnlySourceStatement(label, statement) {
  const normalized = stripSqlStringLiterals(statement).trim();
  if (/--|\/\*/.test(normalized) || normalized.includes(';')) {
    throw new EtlGuardError(
      'SOURCE_QUERY_NOT_READ_ONLY',
      `Source query ${label} contains comments or statement separators.`,
    );
  }
  if (!/^(SELECT|WITH)\b/i.test(normalized)) {
    throw new EtlGuardError(
      'SOURCE_QUERY_NOT_READ_ONLY',
      `Source query ${label} không bắt đầu bằng SELECT/WITH.`,
    );
  }
  if (FORBIDDEN_SOURCE_VERBS.test(normalized)) {
    throw new EtlGuardError(
      'SOURCE_QUERY_NOT_READ_ONLY',
      `Source query ${label} chứa động từ bị cấm.`,
    );
  }
  if (FORBIDDEN_SOURCE_FEATURES.test(normalized)) {
    throw new EtlGuardError(
      'SOURCE_QUERY_NOT_READ_ONLY',
      `Source query ${label} contains a forbidden SQL feature.`,
    );
  }
  if (/\bSELECT\s+(?:DISTINCT\s+)?\*/i.test(normalized)) {
    throw new EtlGuardError(
      'SOURCE_WILDCARD_PROJECTION',
      `Source query ${label} must name every selected column.`,
    );
  }
  if (
    /(?:\b[A-Za-z_][A-Za-z0-9_]*|\[[^\]]+\]|"[^"]+")\s*\.\s*\*/.test(normalized)
  ) {
    throw new EtlGuardError(
      'SOURCE_WILDCARD_PROJECTION',
      `Source query ${label} must not use alias wildcard projection.`,
    );
  }
  if (FORBIDDEN_SOURCE_COLUMNS.test(normalized)) {
    throw new EtlGuardError(
      'FORBIDDEN_SOURCE_COLUMN',
      `Source query ${label} chứa cột nhạy cảm bị cấm.`,
    );
  }
}

function stripSqlStringLiterals(statement) {
  let result = '';
  let inString = false;
  for (let index = 0; index < statement.length; index += 1) {
    const character = statement[index];
    if (!inString) {
      if (character === "'") {
        inString = true;
        result += ' ';
      } else {
        result += character;
      }
      continue;
    }
    if (character === "'" && statement[index + 1] === "'") {
      result += '  ';
      index += 1;
    } else if (character === "'") {
      inString = false;
      result += ' ';
    } else {
      result += character === '\n' ? '\n' : ' ';
    }
  }
  if (inString) {
    throw new EtlGuardError(
      'SOURCE_QUERY_INVALID_STRING',
      'Source query contains an unterminated string literal.',
    );
  }
  return result;
}

function normalizePermissionBit(value) {
  return value === true || value === 1 || value === '1';
}

function expectedProfileColumns(label, profileOptions) {
  const columns = [...SOURCE_RESULT_COLUMNS[label]];
  if (profileOptions.includeBirthDates) {
    columns.push('dateOfBirth');
  }
  if (profileOptions.includeContactFields) {
    columns.push('email', 'phoneNumber');
  }
  return columns;
}

function buildProfileProjection(alias, profileOptions) {
  const columns = [];
  if (profileOptions.includeBirthDates) {
    columns.push(`${alias}.NgaySinh AS dateOfBirth`);
  }
  if (profileOptions.includeContactFields) {
    columns.push(
      `${alias}.Email AS email`,
      `${alias}.SoDienThoai AS phoneNumber`,
    );
  }
  return columns.length > 0 ? `${columns.join(',\n      ')},` : '';
}

function assertExactResultColumns(label, recordset, expectedColumns) {
  const metadataColumns = recordset?.columns
    ? Object.keys(recordset.columns)
    : recordset?.[0]
      ? Object.keys(recordset[0])
      : [];
  const actual = [...metadataColumns].sort();
  const expected = [...expectedColumns].sort();
  if (
    actual.length !== expected.length ||
    actual.some((column, index) => column !== expected[index])
  ) {
    throw new EtlGuardError(
      'SOURCE_RESULT_SHAPE_MISMATCH',
      `Source query ${label} returned an unexpected column set.`,
      {
        actualColumnCount: actual.length,
        expectedColumnCount: expected.length,
      },
    );
  }
}

function parseBoolean(value, fallback) {
  if (value == null || value === '') {
    return fallback;
  }
  return ['1', 'true', 'yes'].includes(String(value).trim().toLowerCase());
}

function parsePort(value, fallback) {
  const parsed = Number(value ?? fallback);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new EtlGuardError(
      'INVALID_SOURCE_PORT',
      'SQL Server port không hợp lệ.',
    );
  }
  return parsed;
}

function parsePositiveNumber(value, fallback) {
  const parsed = Number(value ?? fallback);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

const QUERIES = {
  sourceAccess: `
    SELECT
      DB_NAME() AS databaseName,
      CONVERT(nvarchar(60), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')) AS updateability,
      CONVERT(bit, CASE WHEN EXISTS (
        SELECT 1
        FROM fn_my_permissions(NULL, 'DATABASE') AS permission
        WHERE permission.permission_name IN (
          'INSERT', 'UPDATE', 'DELETE', 'ALTER', 'CONTROL', 'TAKE OWNERSHIP',
          'CREATE TABLE', 'CREATE VIEW', 'CREATE PROCEDURE', 'CREATE FUNCTION',
          'CREATE TYPE', 'CREATE DEFAULT', 'CREATE RULE'
        )
      ) OR EXISTS (
        SELECT 1
        FROM sys.tables AS sourceTable
        INNER JOIN sys.schemas AS sourceSchema
          ON sourceSchema.schema_id = sourceTable.schema_id
        WHERE
          HAS_PERMS_BY_NAME(
            QUOTENAME(sourceSchema.name) + '.' + QUOTENAME(sourceTable.name),
            'OBJECT',
            'INSERT'
          ) = 1
          OR HAS_PERMS_BY_NAME(
            QUOTENAME(sourceSchema.name) + '.' + QUOTENAME(sourceTable.name),
            'OBJECT',
            'UPDATE'
          ) = 1
          OR HAS_PERMS_BY_NAME(
            QUOTENAME(sourceSchema.name) + '.' + QUOTENAME(sourceTable.name),
            'OBJECT',
            'DELETE'
          ) = 1
          OR HAS_PERMS_BY_NAME(
            QUOTENAME(sourceSchema.name) + '.' + QUOTENAME(sourceTable.name),
            'OBJECT',
            'ALTER'
          ) = 1
          OR HAS_PERMS_BY_NAME(
            QUOTENAME(sourceSchema.name) + '.' + QUOTENAME(sourceTable.name),
            'OBJECT',
            'CONTROL'
          ) = 1
      ) THEN 1 ELSE 0 END) AS principalWriteCapable
  `,
  term: `
    SELECT
      d.Id AS sourceTermId,
      d.MaDot AS termCode,
      d.TenDot AS termName,
      d.TuNgay AS startsAt,
      d.DenNgay AS endsAt,
      d.IsActive AS isActive,
      d.IsVisible AS isVisible
    FROM dbo.DM_Dot AS d
    WHERE d.Id = @termId
  `,
  students: (profileOptions) => `
    SELECT DISTINCT
      sv.Id AS sourceStudentId,
      sv.MaSinhVien AS studentCode,
      sv.HoDem AS familyName,
      sv.Ten AS givenName,
      ${buildProfileProjection('sv', profileOptions)}
      sv.TrangThai AS sourceStatus,
      sv.IDLopHoc AS sourceHomeroomClassId,
      sv.IDNganh AS sourceMajorId
    FROM dbo.DT_SinhVien AS sv
    INNER JOIN dbo.DT_DangKyHocPhan AS dk
      ON dk.IDSinhVien = sv.Id
    INNER JOIN dbo.TKB_LopHocPhan AS lhp
      ON lhp.Id = dk.IDLopHocPhan
    WHERE lhp.IDDot = @termId
  `,
  homeroomClasses: `
    SELECT DISTINCT
      lop.Id AS sourceClassId,
      lop.MaLopChu AS primaryCode,
      lop.MaLopSo AS secondaryCode,
      lop.TenLop AS className,
      lop.IDNganh AS sourceMajorId,
      nganh.IDKhoa AS sourceFacultyId
    FROM dbo.DM_LopHoc AS lop
    LEFT JOIN dbo.DM_Nganh AS nganh
      ON nganh.Id = lop.IDNganh
    WHERE EXISTS (
      SELECT 1
      FROM dbo.DT_SinhVien AS sv
      INNER JOIN dbo.DT_DangKyHocPhan AS dk
        ON dk.IDSinhVien = sv.Id
      INNER JOIN dbo.TKB_LopHocPhan AS lhp
        ON lhp.Id = dk.IDLopHocPhan
      WHERE sv.IDLopHoc = lop.Id
        AND lhp.IDDot = @termId
    )
  `,
  offerings: `
    SELECT
      lhp.Id AS sourceOfferingId,
      lhp.MaLopHocPhan AS offeringCode,
      lhp.IDTrangThaiLopHocPhan AS sourceStatus,
      mon.Id AS sourceTkbCourseId,
      mon.MaMonHoc AS courseCode,
      mon.TenMonHoc AS courseName,
      mon.SoTinChi AS credits,
      catalog.Id AS sourceCatalogCourseId,
      catalog.IDKhoa AS sourceCourseFacultyId,
      catalog.TenMonHoc AS catalogCourseName,
      catalogMatch.matchCount AS catalogMatchCount,
      lop.Id AS sourceTeachingClassId,
      lop.MaLopHoc AS teachingClassCode,
      lop.TenLopHoc AS teachingClassName,
      lop.IDKhoa AS sourceFacultyId,
      lop.IDNganh AS sourceMajorId
    FROM dbo.TKB_LopHocPhan AS lhp
    INNER JOIN dbo.TKB_MonHoc AS mon
      ON mon.Id = lhp.IDMonHoc
    INNER JOIN dbo.TKB_LopHoc AS lop
      ON lop.Id = mon.IDLopHoc
    OUTER APPLY (
      SELECT
        COUNT(*) AS matchCount,
        MIN(dm.Id) AS matchedId
      FROM dbo.DM_MonHoc AS dm
      WHERE UPPER(LTRIM(RTRIM(dm.MaMonHoc))) =
        UPPER(LTRIM(RTRIM(mon.MaMonHoc)))
    ) AS catalogMatch
    LEFT JOIN dbo.DM_MonHoc AS catalog
      ON catalog.Id = catalogMatch.matchedId
    WHERE lhp.IDDot = @termId
  `,
  meetings: `
    SELECT
      lich.Id AS sourceMeetingId,
      lhp.Id AS sourceOfferingId,
      xep.Id AS sourceSchedulingGroupId,
      lich.Thu AS sourceWeekday,
      lich.TuTiet AS startPeriod,
      lich.DenTiet AS endPeriod,
      lich.NgayBatDau AS startsAt,
      lich.NgayKetThuc AS endsAt,
      lich.NgayBatDauHoc AS teachingStartsAt,
      lich.NgayKetThucHoc AS teachingEndsAt,
      lich.IsTamNgung AS isSuspended,
      lich.IsHocCachTuan AS isBiweekly,
      lich.IsLichTheoNgay AS isDaySpecific,
      lich.IsHocBu AS isMakeup,
      COALESCE(caStart.TuGio, tietStart.TuGio) AS resolvedStartTime,
      COALESCE(caEnd.DenGio, tietEnd.DenGio) AS resolvedEndTime,
      phong.Id AS sourceRoomId,
      phong.MaPhong AS roomCode,
      phong.TenPhong AS roomName
    FROM dbo.TKB_LopHocPhan AS lhp
    INNER JOIN dbo.TKB_DanhSachLopXepLichHoc AS ds
      ON ds.IDLopHocPhan = lhp.Id
    INNER JOIN dbo.TKB_LopXepLichHoc AS xep
      ON xep.Id = ds.IDLopXepLichHoc
    INNER JOIN dbo.TKB_LichHoc AS lich
      ON lich.IDLopXepLichHoc = xep.Id
    LEFT JOIN dbo.DM_CaHoc_HocKy AS caStart
      ON caStart.IDDot = xep.IDDot
      AND caStart.Tiet = lich.TuTiet
    LEFT JOIN dbo.DM_CaHoc_HocKy AS caEnd
      ON caEnd.IDDot = xep.IDDot
      AND caEnd.Tiet = lich.DenTiet
    LEFT JOIN dbo.DM_TietHoc AS tietStart
      ON tietStart.Tiet = lich.TuTiet
      AND ISNULL(tietStart.IsDeleted, 0) = 0
    LEFT JOIN dbo.DM_TietHoc AS tietEnd
      ON tietEnd.Tiet = lich.DenTiet
      AND ISNULL(tietEnd.IsDeleted, 0) = 0
    LEFT JOIN dbo.DM_Phong AS phong
      ON phong.Id = COALESCE(NULLIF(lich.IDPhongDoi, 0), lich.IDPhong)
    WHERE lhp.IDDot = @termId
  `,
  actualLecturers: (profileOptions) => `
    SELECT DISTINCT
      lich.Id AS sourceMeetingId,
      lhp.Id AS sourceOfferingId,
      gv.Id AS sourceLecturerId,
      gv.IDKhoa AS sourceFacultyId,
      gv.MaGiangVien AS lecturerCode,
      gv.HoDem AS familyName,
      gv.Ten AS givenName,
      ${buildProfileProjection('gv', profileOptions)}
      gv.IsDeleted AS isDeleted,
      gv.IsDisabled AS isDisabled,
      gv.IsChamDutHopDong AS isTerminated
    FROM dbo.TKB_LopHocPhan AS lhp
    INNER JOIN dbo.TKB_DanhSachLopXepLichHoc AS ds
      ON ds.IDLopHocPhan = lhp.Id
    INNER JOIN dbo.TKB_LopXepLichHoc AS xep
      ON xep.Id = ds.IDLopXepLichHoc
    INNER JOIN dbo.TKB_LichHoc AS lich
      ON lich.IDLopXepLichHoc = xep.Id
    INNER JOIN dbo.TKB_LichHocGiangVien AS lgv
      ON lgv.IDLichHoc = lich.Id
    INNER JOIN dbo.DM_GiangVien AS gv
      ON gv.Id = lgv.IDGiangVien
    WHERE lhp.IDDot = @termId
  `,
  plannedLecturers: (profileOptions) => `
    SELECT DISTINCT
      lhp.Id AS sourceOfferingId,
      gv.Id AS sourceLecturerId,
      gv.IDKhoa AS sourceFacultyId,
      gv.MaGiangVien AS lecturerCode,
      gv.HoDem AS familyName,
      gv.Ten AS givenName,
      ${buildProfileProjection('gv', profileOptions)}
      gv.IsDeleted AS isDeleted,
      gv.IsDisabled AS isDisabled,
      gv.IsChamDutHopDong AS isTerminated
    FROM dbo.TKB_LopHocPhan AS lhp
    INNER JOIN dbo.TKB_GiangVienDuKien AS dukien
      ON dukien.IDLopHocPhan = lhp.Id
    INNER JOIN dbo.DM_GiangVien AS gv
      ON gv.Id = dukien.IDGiangVien
    WHERE lhp.IDDot = @termId
  `,
};

function buildRegistrationQuery(statusPlaceholders) {
  if (statusPlaceholders.length === 0) {
    throw new EtlGuardError(
      'MISSING_ACTIVE_REGISTRATION_STATUSES',
      'Danh sách trạng thái đăng ký active không được rỗng.',
    );
  }

  return `
    WITH rankedRegistration AS (
      SELECT
        dk.Id AS sourceRegistrationId,
        dk.IDSinhVien AS sourceStudentId,
        dk.IDLopHocPhan AS sourceOfferingId,
        dk.IDTrangThaiDangKy AS sourceStatus,
        COUNT(*) OVER (
          PARTITION BY dk.IDSinhVien, dk.IDLopHocPhan
        ) AS sourceRowCount,
        ROW_NUMBER() OVER (
          PARTITION BY dk.IDSinhVien, dk.IDLopHocPhan
          ORDER BY
            COALESCE(dk.NgayCapNhat, dk.NgayTao, dk.NgayDangKy) DESC,
            dk.Id DESC
        ) AS currentRank
      FROM dbo.DT_DangKyHocPhan AS dk
      INNER JOIN dbo.TKB_LopHocPhan AS lhp
        ON lhp.Id = dk.IDLopHocPhan
      WHERE lhp.IDDot = @termId
    )
    SELECT
      sourceRegistrationId,
      sourceStudentId,
      sourceOfferingId,
      sourceStatus,
      sourceRowCount
    FROM rankedRegistration
    WHERE currentRank = 1
      AND sourceStatus IN (${statusPlaceholders.join(', ')})
  `;
}

module.exports = {
  EduNuceSource,
  EXPECTED_SOURCE_DATABASE,
  SOURCE_SYSTEM,
  __test: {
    assertExactResultColumns,
    buildActualLecturersQuery: QUERIES.actualLecturers,
    buildPlannedLecturersQuery: QUERIES.plannedLecturers,
    buildStudentsQuery: QUERIES.students,
    buildTrustedConnectionString,
  },
  assertReadOnlySourceStatement,
  buildRegistrationQuery,
  buildSourceConfig,
  buildSourceRuntime,
};
