import {
  isScheduleOccurrenceOnDate,
  resolveScheduleBounds,
  resolveScheduleOccurrenceDates,
} from './schedule-recurrence';

describe('schedule recurrence', () => {
  it('prefers meeting bounds over offering bounds', () => {
    const schedule = {
      dayOfWeek: 1,
      startsAt: new Date('2026-08-10T00:00:00.000Z'),
      endsAt: new Date('2026-08-24T00:00:00.000Z'),
      offering: {
        startsAt: new Date('2026-08-01T00:00:00.000Z'),
        endsAt: new Date('2026-09-30T00:00:00.000Z'),
      },
    };

    expect(resolveScheduleBounds(schedule)).toEqual({
      startsAt: schedule.startsAt,
      endsAt: schedule.endsAt,
    });
    expect(
      resolveScheduleOccurrenceDates(
        schedule,
        new Date('2026-08-01T00:00:00.000Z'),
        new Date('2026-09-01T00:00:00.000Z'),
      ).map((date) => date.getDate()),
    ).toEqual([10, 17, 24]);
  });

  it('anchors a biweekly meeting to the first matching weekday', () => {
    const schedule = {
      dayOfWeek: 1,
      startsAt: new Date('2026-08-01T00:00:00.000Z'),
      endsAt: new Date('2026-08-31T00:00:00.000Z'),
      recurrenceKind: 'biweekly',
    };

    expect(
      resolveScheduleOccurrenceDates(
        schedule,
        new Date('2026-08-01T00:00:00.000Z'),
        new Date('2026-09-01T00:00:00.000Z'),
      ).map((date) => date.getDate()),
    ).toEqual([3, 17, 31]);
  });

  it('emits a one-off meeting only on its explicit startsAt date', () => {
    const schedule = {
      dayOfWeek: 1,
      startsAt: new Date('2026-08-12T00:00:00.000Z'),
      endsAt: new Date('2026-08-12T23:59:59.000Z'),
      recurrenceKind: 'once',
    };

    expect(
      isScheduleOccurrenceOnDate(
        schedule,
        new Date('2026-08-12T00:00:00.000Z'),
      ),
    ).toBe(true);
    expect(
      isScheduleOccurrenceOnDate(
        schedule,
        new Date('2026-08-19T00:00:00.000Z'),
      ),
    ).toBe(false);
  });

  it('does not invent a date for a one-off meeting without startsAt', () => {
    expect(
      isScheduleOccurrenceOnDate(
        {
          dayOfWeek: 1,
          recurrenceKind: 'once',
          offering: {
            startsAt: new Date('2026-08-01T00:00:00.000Z'),
            endsAt: new Date('2026-08-31T00:00:00.000Z'),
          },
        },
        new Date('2026-08-03T00:00:00.000Z'),
      ),
    ).toBe(false);
  });
});
