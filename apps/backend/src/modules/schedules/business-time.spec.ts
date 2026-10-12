import {
  parseSchoolDate,
  schoolAddDays,
  schoolDateKey,
  schoolIsoDay,
  schoolStartOfDay,
  schoolWithTime,
} from './business-time';

describe('school calendar independent of the process timezone', () => {
  it('interprets a legacy wall timestamp as school time and accepts explicit UTC', () => {
    expect(parseSchoolDate('2026-09-10T07:00:00.000').toISOString()).toBe(
      '2026-09-10T00:00:00.000Z',
    );
    expect(parseSchoolDate('2026-09-10T00:00:00.000Z').toISOString()).toBe(
      '2026-09-10T00:00:00.000Z',
    );
  });
  it('uses the school day before UTC midnight', () => {
    const early = new Date('2026-09-09T18:30:00Z');
    expect(schoolDateKey(early)).toBe('2026-09-10');
    expect(schoolIsoDay(early)).toBe(4);
    expect(schoolStartOfDay(early).toISOString()).toBe(
      '2026-09-09T17:00:00.000Z',
    );
    expect(schoolWithTime(early, '07:00').toISOString()).toBe(
      '2026-09-10T00:00:00.000Z',
    );
  });
  it('advances the calendar across month and year boundaries', () => {
    expect(schoolDateKey(schoolAddDays(parseSchoolDate('2026-12-31'), 1))).toBe(
      '2027-01-01',
    );
    expect(
      schoolDateKey(schoolAddDays(parseSchoolDate('2026-03-01'), -1)),
    ).toBe('2026-02-28');
  });
  it('rejects impossible calendar dates and ambiguous non-ISO input', () => {
    expect(Number.isNaN(parseSchoolDate('2026-02-30').getTime())).toBe(true);
    expect(Number.isNaN(parseSchoolDate('09/10/2026').getTime())).toBe(true);
  });
});
