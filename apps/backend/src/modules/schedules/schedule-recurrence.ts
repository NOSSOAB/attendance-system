export type ScheduleRecurrenceKind = 'weekly' | 'biweekly' | 'once';

type DateValue = Date | string | null | undefined;

export type RecurringSchedule = {
  dayOfWeek: number;
  startsAt?: DateValue;
  endsAt?: DateValue;
  recurrenceKind?: string | null;
  offering?: {
    startsAt?: DateValue;
    endsAt?: DateValue;
  } | null;
};

export type ScheduleBounds = {
  startsAt: Date | null;
  endsAt: Date | null;
};

export function resolveScheduleBounds(
  schedule: RecurringSchedule,
): ScheduleBounds {
  return {
    startsAt:
      parseDate(schedule.startsAt) ?? parseDate(schedule.offering?.startsAt),
    endsAt: parseDate(schedule.endsAt) ?? parseDate(schedule.offering?.endsAt),
  };
}

export function isDateWithinScheduleBounds(
  schedule: RecurringSchedule,
  date: Date,
) {
  const { startsAt, endsAt } = resolveScheduleBounds(schedule);
  const day = calendarDayOrdinal(date);
  const firstDay = startsAt ? calendarDayOrdinal(startsAt) : null;
  const lastDay = endsAt ? calendarDayOrdinal(endsAt) : null;

  return (
    (firstDay === null || day >= firstDay) &&
    (lastDay === null || day <= lastDay)
  );
}

export function isScheduleOccurrenceOnDate(
  schedule: RecurringSchedule,
  date: Date,
) {
  if (!isDateWithinScheduleBounds(schedule, date)) {
    return false;
  }

  const recurrenceKind = normalizeRecurrenceKind(schedule.recurrenceKind);
  if (recurrenceKind === 'once') {
    const explicitMeetingDate = parseDate(schedule.startsAt);
    return (
      explicitMeetingDate !== null &&
      calendarDayOrdinal(explicitMeetingDate) === calendarDayOrdinal(date)
    );
  }

  if (schoolIsoDay(date) !== schedule.dayOfWeek) {
    return false;
  }

  if (recurrenceKind === 'weekly') {
    return true;
  }

  const { startsAt } = resolveScheduleBounds(schedule);
  if (!startsAt) {
    // A biweekly pattern needs a stable source anchor. Falling back to weekly
    // keeps legacy rows visible until ETL supplies schedule/term startsAt.
    return true;
  }

  const firstOccurrence = firstMatchingDayOnOrAfter(
    startsAt,
    schedule.dayOfWeek,
  );
  const elapsedDays =
    calendarDayOrdinal(date) - calendarDayOrdinal(firstOccurrence);

  return elapsedDays >= 0 && Math.floor(elapsedDays / 7) % 2 === 0;
}

export function resolveScheduleOccurrenceDates(
  schedule: RecurringSchedule,
  rangeStart: Date,
  rangeEndExclusive: Date,
) {
  const dates: Date[] = [];
  let cursor = schoolStartOfDay(rangeStart);
  const end = schoolStartOfDay(rangeEndExclusive);

  while (cursor.getTime() < end.getTime()) {
    if (isScheduleOccurrenceOnDate(schedule, cursor)) {
      dates.push(new Date(cursor));
    }
    cursor = schoolAddDays(cursor, 1);
  }

  return dates;
}

function normalizeRecurrenceKind(
  value?: string | null,
): ScheduleRecurrenceKind {
  return value === 'biweekly' || value === 'once' ? value : 'weekly';
}

function firstMatchingDayOnOrAfter(date: Date, dayOfWeek: number) {
  const result = schoolStartOfDay(date);
  const daysUntilMatch = (dayOfWeek - schoolIsoDay(result) + 7) % 7;
  return schoolAddDays(result, daysUntilMatch);
}

function parseDate(value: DateValue) {
  if (!value) {
    return null;
  }

  const parsed =
    value instanceof Date ? new Date(value) : parseSchoolDate(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function calendarDayOrdinal(value: Date) {
  return schoolCalendarOrdinal(value);
}
import {
  parseSchoolDate,
  schoolAddDays,
  schoolCalendarOrdinal,
  schoolIsoDay,
  schoolStartOfDay,
} from './business-time';
