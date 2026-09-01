'use strict';

class EtlGuardError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'EtlGuardError';
    this.code = code;
    this.details = details;
  }
}

function normalizeText(value) {
  if (value == null) {
    return null;
  }

  const normalized = String(value).replace(/\s+/g, ' ').trim();
  return normalized.length > 0 ? normalized : null;
}

function normalizeCode(value) {
  const normalized = normalizeText(value);
  return normalized ? normalized.toUpperCase() : null;
}

function composeFullName(hoDem, ten) {
  return normalizeText(
    [normalizeText(hoDem), normalizeText(ten)].filter(Boolean).join(' '),
  );
}

function parseSourceDate(value) {
  if (value == null || value === '') {
    return null;
  }

  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : new Date(value);
  }

  const text = normalizeText(value);
  if (!text) {
    return null;
  }

  const dayFirst = text.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/);
  if (dayFirst) {
    return buildUtcDate(
      Number(dayFirst[3]),
      Number(dayFirst[2]),
      Number(dayFirst[1]),
    );
  }

  const yearFirst = text.match(/^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})/);
  if (yearFirst) {
    return buildUtcDate(
      Number(yearFirst[1]),
      Number(yearFirst[2]),
      Number(yearFirst[3]),
    );
  }

  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function buildUtcDate(year, month, day) {
  const value = new Date(Date.UTC(year, month - 1, day));
  if (
    value.getUTCFullYear() !== year ||
    value.getUTCMonth() !== month - 1 ||
    value.getUTCDate() !== day
  ) {
    return null;
  }
  return value;
}

function normalizeSqlTime(value) {
  if (value == null || value === '') {
    return null;
  }

  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) {
      return null;
    }
    return `${String(value.getUTCHours()).padStart(2, '0')}:${String(
      value.getUTCMinutes(),
    ).padStart(2, '0')}`;
  }

  const text = normalizeText(value);
  const match = text?.match(/^(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$/);
  if (!match) {
    return null;
  }

  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) {
    return null;
  }
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

function normalizeVietnameseWeekday(value) {
  const numeric = Number(value);
  if (!Number.isInteger(numeric) || numeric < 2 || numeric > 8) {
    throw new EtlGuardError(
      'INVALID_SOURCE_WEEKDAY',
      'TKB_LichHoc.Thu phải nằm trong miền 2..8.',
    );
  }
  return numeric - 1;
}

function deriveRecurrenceKind(startsAt, endsAt, flags = {}) {
  const start = parseSourceDate(startsAt);
  const end = parseSourceDate(endsAt);
  if (!start || !end) {
    throw new EtlGuardError(
      'MISSING_MEETING_DATES',
      'Không thể xác định khoảng ngày của lịch học.',
    );
  }
  if (start.getTime() > end.getTime()) {
    throw new EtlGuardError(
      'INVALID_MEETING_RANGE',
      'Ngày bắt đầu lịch học lớn hơn ngày kết thúc.',
    );
  }
  if (flags.isDaySpecific || flags.isMakeup) {
    return 'once';
  }
  if (flags.isBiweekly) {
    return 'biweekly';
  }
  return sameUtcDay(start, end) ? 'once' : 'weekly';
}

function sameUtcDay(left, right) {
  return (
    left.getUTCFullYear() === right.getUTCFullYear() &&
    left.getUTCMonth() === right.getUTCMonth() &&
    left.getUTCDate() === right.getUTCDate()
  );
}

function parseExplicitStatusSet(value, optionName) {
  const values = String(value ?? '')
    .split(',')
    .map((item) => normalizeText(item))
    .filter(Boolean)
    .map((item) => String(item));

  if (values.length === 0) {
    throw new EtlGuardError(
      'MISSING_ACTIVE_REGISTRATION_STATUSES',
      `Phải khai báo ${optionName} với ít nhất một trạng thái đăng ký active.`,
    );
  }
  return new Set(values);
}

function normalizeStatus(value) {
  const normalized = normalizeText(value);
  return normalized == null ? '__NULL__' : normalized;
}

function isActiveRegistration(value, activeStatuses) {
  return activeStatuses.has(normalizeStatus(value));
}

function dedupeByKey(rows, keyOf, signatureOf, label) {
  const unique = new Map();
  let exactDuplicateCount = 0;

  for (const row of rows) {
    const key = String(keyOf(row));
    const signature = stableJson(signatureOf(row));
    const existing = unique.get(key);
    if (!existing) {
      unique.set(key, { row, signature });
      continue;
    }
    if (existing.signature !== signature) {
      throw new EtlGuardError(
        'CONFLICTING_SOURCE_DUPLICATE',
        `Phát hiện duplicate xung đột trong ${label}.`,
        { conflictCount: 1 },
      );
    }
    exactDuplicateCount += 1;
  }

  return {
    rows: [...unique.values()].map((item) => item.row),
    exactDuplicateCount,
  };
}

function stableJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function stableSourceId(prefix, ...parts) {
  const normalizedParts = parts.map((part) => normalizeText(part));
  if (normalizedParts.some((part) => part == null)) {
    throw new EtlGuardError(
      'MISSING_SOURCE_ID',
      `Không thể tạo source ID ổn định cho ${prefix}.`,
    );
  }
  return `${prefix}:${normalizedParts.join(':')}`;
}

function assertNoProtectedIdentifierCollisions(
  sourceIdentifiers,
  protectedIdentifiers,
  label,
) {
  const protectedSet = new Set(
    [...protectedIdentifiers]
      .map((value) => normalizeCode(value))
      .filter(Boolean),
  );
  const collisionCount = sourceIdentifiers.reduce(
    (count, value) => count + (protectedSet.has(normalizeCode(value)) ? 1 : 0),
    0,
  );
  if (collisionCount > 0) {
    throw new EtlGuardError(
      'PROTECTED_TEST_ID_COLLISION',
      `Source có ${collisionCount} ${label} trùng định danh test được bảo vệ.`,
      { collisionCount },
    );
  }
}

function assertPositiveInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new EtlGuardError(
      'INVALID_POSITIVE_INTEGER',
      `${label} phải là số nguyên dương.`,
    );
  }
  return parsed;
}

function normalizeBit(value, fallback = false) {
  if (value === true || value === 1 || value === '1') {
    return true;
  }
  if (value === false || value === 0 || value === '0') {
    return false;
  }
  return fallback;
}

module.exports = {
  EtlGuardError,
  assertNoProtectedIdentifierCollisions,
  assertPositiveInteger,
  composeFullName,
  dedupeByKey,
  deriveRecurrenceKind,
  isActiveRegistration,
  normalizeBit,
  normalizeCode,
  normalizeSqlTime,
  normalizeStatus,
  normalizeText,
  normalizeVietnameseWeekday,
  parseExplicitStatusSet,
  parseSourceDate,
  stableSourceId,
};
