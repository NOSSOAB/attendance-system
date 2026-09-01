'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { __test } = require('./edu-nuce-transform');

function report() {
  return { counts: {}, issues: [] };
}

test('source offering status 5 is imported as inactive', () => {
  const result = __test.normalizeOffering(
    {
      sourceOfferingId: 10,
      offeringCode: 'LHP-10',
      courseCode: 'CS101',
      sourceTeachingClassId: 20,
      sourceStatus: 5,
    },
    {
      code: 'HK1',
      name: 'Học kỳ 1',
      startsAt: new Date('2026-08-01T00:00:00.000Z'),
      endsAt: new Date('2026-12-01T00:00:00.000Z'),
      isActive: true,
    },
    new Set(['CS101']),
    new Map([['TKB_LOPHOC:20', {}]]),
    { inactiveOfferingStatuses: new Set(['5']) },
    report(),
  );

  assert.equal(result.isActive, false);
});

test('meeting bounds prefer teaching dates and source flags drive recurrence', () => {
  const result = __test.normalizeMeeting(
    {
      sourceMeetingId: 30,
      sourceOfferingId: 10,
      sourceWeekday: 2,
      resolvedStartTime: '07:00:00',
      resolvedEndTime: '09:00:00',
      startsAt: new Date('2026-08-01T00:00:00.000Z'),
      endsAt: new Date('2026-12-01T00:00:00.000Z'),
      teachingStartsAt: new Date('2026-08-03T00:00:00.000Z'),
      teachingEndsAt: new Date('2026-11-30T00:00:00.000Z'),
      isBiweekly: true,
      roomCode: 'A101',
    },
    new Map([[10, { isActive: true }]]),
    report(),
  );

  assert.equal(result.startsAt.toISOString(), '2026-08-03T00:00:00.000Z');
  assert.equal(result.endsAt.toISOString(), '2026-11-30T00:00:00.000Z');
  assert.equal(result.recurrenceKind, 'biweekly');
  assert.equal(result.isActive, true);
});

test('missing room or suspended source meeting cannot become active', () => {
  const base = {
    sourceMeetingId: 30,
    sourceOfferingId: 10,
    sourceWeekday: 2,
    resolvedStartTime: '07:00:00',
    resolvedEndTime: '09:00:00',
    startsAt: new Date('2026-08-03T00:00:00.000Z'),
    endsAt: new Date('2026-11-30T00:00:00.000Z'),
  };
  const offerings = new Map([[10, { isActive: true }]]);

  assert.equal(
    __test.normalizeMeeting(base, offerings, report()).isActive,
    false,
  );
  assert.equal(
    __test.normalizeMeeting(
      { ...base, roomCode: 'A101', isSuspended: true },
      offerings,
      report(),
    ).isActive,
    false,
  );
});

test('planned lecturer remains inactive provenance and is never primary', () => {
  const result = __test.buildScheduleLecturers({
    schedules: [
      {
        sourceId: 'TKB_LICHHOC:30:LHP:10',
        sourceMeetingId: 30,
        sourceOfferingId: 10,
      },
    ],
    actualRows: [],
    plannedRows: [{ sourceOfferingId: 10, sourceLecturerId: 40 }],
    lecturerBySourceId: new Map([
      [40, { sourceLecturerId: 40, code: 'GV040', isActive: true }],
    ]),
    report: report(),
  });

  assert.equal(result.assignments.length, 1);
  assert.equal(result.assignments[0].role, 'planned');
  assert.equal(result.assignments[0].isActive, false);
  assert.equal(result.primaryBySchedule.size, 0);
  assert.equal(result.activeActualCountBySchedule.size, 0);
});
