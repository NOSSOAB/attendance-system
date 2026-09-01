'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  EtlGuardError,
  composeFullName,
  dedupeByKey,
  deriveRecurrenceKind,
  isActiveRegistration,
  normalizeSqlTime,
  normalizeVietnameseWeekday,
  parseExplicitStatusSet,
  parseSourceDate,
} = require('./edu-nuce-core');

test('normalizes Vietnamese names, source dates, SQL time and weekday', () => {
  assert.equal(composeFullName('  Nguyễn   Văn ', ' An '), 'Nguyễn Văn An');
  assert.equal(
    parseSourceDate('27/09/2007').toISOString(),
    '2007-09-27T00:00:00.000Z',
  );
  assert.equal(normalizeSqlTime('7:05:00'), '07:05');
  assert.equal(normalizeVietnameseWeekday(2), 1);
  assert.equal(normalizeVietnameseWeekday(8), 7);
});

test('requires an explicit active registration status set', () => {
  assert.throws(
    () => parseExplicitStatusSet('', '--active-registration-statuses'),
    (error) =>
      error instanceof EtlGuardError &&
      error.code === 'MISSING_ACTIVE_REGISTRATION_STATUSES',
  );

  const activeStatuses = parseExplicitStatusSet(
    '1, 3',
    '--active-registration-statuses',
  );
  assert.equal(isActiveRegistration(1, activeStatuses), true);
  assert.equal(isActiveRegistration(2, activeStatuses), false);
  assert.equal(isActiveRegistration('3', activeStatuses), true);
});

test('derives once versus weekly recurrence from physical meeting bounds', () => {
  assert.equal(deriveRecurrenceKind('2026-08-12', '2026-08-12'), 'once');
  assert.equal(deriveRecurrenceKind('2026-08-12', '2026-12-12'), 'weekly');
  assert.equal(
    deriveRecurrenceKind('2026-08-12', '2026-12-12', {
      isBiweekly: true,
    }),
    'biweekly',
  );
  assert.equal(
    deriveRecurrenceKind('2026-08-12', '2026-12-12', {
      isDaySpecific: true,
    }),
    'once',
  );
});

test('dedupes identical source rows but aborts conflicting duplicates', () => {
  const exact = dedupeByKey(
    [
      { id: 1, code: 'A' },
      { id: 1, code: 'A' },
    ],
    (row) => row.id,
    (row) => row,
    'test rows',
  );
  assert.equal(exact.rows.length, 1);
  assert.equal(exact.exactDuplicateCount, 1);

  assert.throws(
    () =>
      dedupeByKey(
        [
          { id: 1, code: 'A' },
          { id: 1, code: 'B' },
        ],
        (row) => row.id,
        (row) => row,
        'test rows',
      ),
    (error) =>
      error instanceof EtlGuardError &&
      error.code === 'CONFLICTING_SOURCE_DUPLICATE',
  );
});
