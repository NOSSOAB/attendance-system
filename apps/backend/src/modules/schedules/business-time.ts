type CalendarParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

const DAY_MS = 86_400_000;
const formatters = new Map<string, Intl.DateTimeFormat>();

export function schoolDateParts(value: Date): CalendarParts {
  const zone = process.env.SCHOOL_TIME_ZONE?.trim() || 'Asia/Ho_Chi_Minh';
  let formatter = formatters.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    formatters.set(zone, formatter);
  }
  const parts = Object.fromEntries(
    formatter
      .formatToParts(value)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, Number(part.value)]),
  );
  return parts as CalendarParts;
}

export function schoolDateFromParts(
  parts: Pick<CalendarParts, 'year' | 'month' | 'day'> & Partial<CalendarParts>,
  milliseconds = 0,
): Date {
  const expected = { hour: 0, minute: 0, second: 0, ...parts };
  const wall = Date.UTC(
    expected.year,
    expected.month - 1,
    expected.day,
    expected.hour,
    expected.minute,
    expected.second,
    milliseconds,
  );
  let instant = wall;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const actual = schoolDateParts(new Date(instant));
    const actualWall = Date.UTC(
      actual.year,
      actual.month - 1,
      actual.day,
      actual.hour,
      actual.minute,
      actual.second,
      milliseconds,
    );
    const adjustment = wall - actualWall;
    instant += adjustment;
    if (adjustment === 0) break;
  }
  const result = new Date(instant);
  const actual = schoolDateParts(result);
  // Reject invalid calendar values and nonexistent local times instead of
  // silently moving a scheduled class to a different date/hour.
  return Object.entries(expected).every(([key, value]) => actual[key] === value)
    ? result
    : new Date(NaN);
}

export function parseSchoolDate(value: string): Date {
  const match =
    /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:\d{2})?)?$/.exec(
      value,
    );
  if (!match) return new Date(NaN);
  if (match[8]) return new Date(value);
  return schoolDateFromParts(
    {
      year: Number(match[1]),
      month: Number(match[2]),
      day: Number(match[3]),
      hour: Number(match[4] ?? 0),
      minute: Number(match[5] ?? 0),
      second: Number(match[6] ?? 0),
    },
    Number((match[7] ?? '').padEnd(3, '0').slice(0, 3)),
  );
}

export function schoolDateKey(value: Date): string {
  const { year, month, day } = schoolDateParts(value);
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function schoolStartOfDay(value: Date): Date {
  const { year, month, day } = schoolDateParts(value);
  return schoolDateFromParts({ year, month, day });
}

export function schoolAddDays(value: Date, days: number): Date {
  const parts = schoolDateParts(value);
  const calendar = new Date(
    Date.UTC(parts.year, parts.month - 1, parts.day + days),
  );
  return schoolDateFromParts(
    {
      ...parts,
      year: calendar.getUTCFullYear(),
      month: calendar.getUTCMonth() + 1,
      day: calendar.getUTCDate(),
    },
    value.getUTCMilliseconds(),
  );
}

export function schoolWithTime(value: Date, time: string): Date {
  const [hour, minute] = time.split(':').map(Number);
  const { year, month, day } = schoolDateParts(value);
  return schoolDateFromParts({ year, month, day, hour, minute, second: 0 });
}

export function schoolCalendarOrdinal(value: Date): number {
  const { year, month, day } = schoolDateParts(value);
  return Math.floor(Date.UTC(year, month - 1, day) / DAY_MS);
}

export function schoolIsoDay(value: Date): number {
  const day = new Date(schoolCalendarOrdinal(value) * DAY_MS).getUTCDay();
  return day === 0 ? 7 : day;
}
