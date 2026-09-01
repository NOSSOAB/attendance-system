'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  EduNuceSource,
  __test,
  assertReadOnlySourceStatement,
  buildRegistrationQuery,
} = require('./edu-nuce-source');

test('profile fields are opt-in and result columns are exact', () => {
  const minimal = __test.buildStudentsQuery({
    includeBirthDates: false,
    includeContactFields: false,
  });
  assert.doesNotMatch(minimal, /NgaySinh|SoDienThoai|\.Email/);
  const explicit = __test.buildStudentsQuery({
    includeBirthDates: true,
    includeContactFields: true,
  });
  assert.match(explicit, /NgaySinh/);
  assert.match(explicit, /SoDienThoai/);
  assert.match(explicit, /\.Email/);

  const recordset = [{ safe: 1, PasswordHash: 'not-read' }];
  assert.throws(
    () => __test.assertExactResultColumns('test', recordset, ['safe']),
    { name: 'EtlGuardError' },
  );
});

test('source access preflight blocks a writable principal by default', async () => {
  const source = new EduNuceSource({ sql: {}, config: {} });
  source.select = async () => [
    {
      databaseName: 'EDU_NUCE_IMPORT_20241108',
      updateability: 'READ_WRITE',
      principalWriteCapable: true,
    },
  ];

  await assert.rejects(() => source.verifyAccess(), { name: 'EtlGuardError' });
  const acknowledged = await source.verifyAccess({
    allowWritablePrincipal: true,
  });
  assert.equal(acknowledged.writableOverrideUsed, true);
  assert.equal(source.accessVerified, true);
});

test('trusted ODBC connection string enforces read-only intent', () => {
  const connectionString = __test.buildTrustedConnectionString({
    driver: 'ODBC Driver 18 for SQL Server',
    server: 'localhost',
    port: null,
    database: 'EDU_NUCE_IMPORT_20241108',
    encrypt: true,
    trustServerCertificate: true,
  });
  assert.match(connectionString, /ApplicationIntent=ReadOnly/);
  assert.match(connectionString, /TrustServerCertificate=Yes/);
  assert.match(connectionString, /Server=localhost;/);
});

test('source guard rejects mutation, SELECT INTO, wildcard and comments', () => {
  for (const statement of [
    'UPDATE dbo.DM_Dot SET IsActive = 0',
    'SELECT Id INTO #copy FROM dbo.DM_Dot',
    'SELECT * FROM dbo.DM_Dot',
    'SELECT sv.* FROM dbo.DT_SinhVien AS sv',
    'SELECT [sv].* FROM dbo.DT_SinhVien AS sv',
    'SELECT "sv".* FROM dbo.DT_SinhVien AS sv',
    'SELECT PasswordHash FROM dbo.Users',
    'SELECT RefreshToken FROM dbo.Users',
    'SELECT CMND FROM dbo.DT_SinhVien',
    'SELECT NEXT VALUE FOR dbo.ImportSequence',
    'SELECT Id FROM dbo.DM_Dot -- hidden mutation',
    'GRANT SELECT TO public',
  ]) {
    assert.throws(() => assertReadOnlySourceStatement('test', statement), {
      name: 'EtlGuardError',
    });
  }
  assert.doesNotThrow(() =>
    assertReadOnlySourceStatement(
      'test',
      'SELECT COUNT(*) AS rowCount FROM dbo.DM_Dot',
    ),
  );
  assert.doesNotThrow(() =>
    assertReadOnlySourceStatement(
      'test',
      "SELECT 'safe -- text; UPDATE dbo.X' AS harmlessLiteral",
    ),
  );
});

test('registration query ranks the full history before filtering active status', () => {
  const query = buildRegistrationQuery(['@status0', '@status1']);
  const rankPosition = query.indexOf('ROW_NUMBER()');
  const activeFilterPosition = query.lastIndexOf('sourceStatus IN');

  assert.ok(rankPosition > -1);
  assert.ok(activeFilterPosition > rankPosition);
  assert.match(
    query,
    /COALESCE\(dk\.NgayCapNhat, dk\.NgayTao, dk\.NgayDangKy\) DESC/,
  );
  assert.match(query, /dk\.Id DESC/);
  assert.doesNotMatch(query, /WHERE[\s\S]*dk\.IDTrangThaiDangKy IN/);
});
