'use strict';

const {
  EtlGuardError,
  assertNoProtectedIdentifierCollisions,
  composeFullName,
  dedupeByKey,
  deriveRecurrenceKind,
  normalizeBit,
  normalizeCode,
  normalizeSqlTime,
  normalizeStatus,
  normalizeText,
  normalizeVietnameseWeekday,
  parseSourceDate,
  stableSourceId,
} = require('./edu-nuce-core');
const { SOURCE_SYSTEM } = require('./edu-nuce-source');

function transformEduNuce(raw, options) {
  const report = createReport(raw);
  const term = normalizeTerm(raw.term, report);

  const activeRegistrationResult = dedupeByKey(
    raw.registrations,
    (row) => `${row.sourceStudentId}:${row.sourceOfferingId}`,
    (row) => ({
      sourceStudentId: row.sourceStudentId,
      sourceOfferingId: row.sourceOfferingId,
      sourceStatus: normalizeStatus(row.sourceStatus),
    }),
    'active registration pairs',
  );
  const activeRegistrationRows = activeRegistrationResult.rows;
  if (activeRegistrationRows.length === 0) {
    addIssue(report, 'fatal', 'ACTIVE_REGISTRATION_SNAPSHOT_EMPTY', 1);
  }
  report.counts.exactRegistrationDuplicates =
    activeRegistrationResult.exactDuplicateCount;
  report.counts.collapsedRegistrationHistoryRows =
    activeRegistrationRows.reduce(
      (total, row) => total + Math.max(0, Number(row.sourceRowCount ?? 1) - 1),
      0,
    );

  // Import every offering in the term, including cancelled and unscheduled
  // offerings. A rerun can then deactivate stale target rows deterministically.
  const scopedOfferingRows = raw.offerings;
  const courseOrphanCount = scopedOfferingRows.filter(
    (row) => Number(row.catalogMatchCount) !== 1,
  ).length;
  if (courseOrphanCount > 0) {
    addIssue(
      report,
      options.allowCourseQuarantine ? 'warning' : 'fatal',
      'COURSE_CATALOG_MAPPING_ORPHAN',
      courseOrphanCount,
    );
  }
  const usableOfferingRows = scopedOfferingRows.filter(
    (row) => Number(row.catalogMatchCount) === 1,
  );
  const usableOfferingIds = new Set(
    usableOfferingRows.map((row) => Number(row.sourceOfferingId)),
  );
  report.counts.quarantinedOfferings =
    scopedOfferingRows.length - usableOfferingRows.length;

  const usableRegistrationRows = activeRegistrationRows.filter((row) =>
    usableOfferingIds.has(Number(row.sourceOfferingId)),
  );
  const usableStudentIds = new Set(
    usableRegistrationRows.map((row) => Number(row.sourceStudentId)),
  );
  report.counts.quarantinedRegistrations =
    activeRegistrationRows.length - usableRegistrationRows.length;

  const scopedStudentRows = raw.students.filter((row) =>
    usableStudentIds.has(Number(row.sourceStudentId)),
  );
  const studentSourceResult = dedupeByKey(
    scopedStudentRows,
    (row) => row.sourceStudentId,
    studentSignature,
    'students by source ID',
  );
  const studentCodeResult = dedupeByKey(
    studentSourceResult.rows,
    (row) => normalizeCode(row.studentCode),
    (row) => ({ sourceStudentId: Number(row.sourceStudentId) }),
    'students by student code',
  );
  const sourceStudents = studentCodeResult.rows;

  const sourceStudentIds = new Set(
    sourceStudents.map((row) => Number(row.sourceStudentId)),
  );
  const orphanRegistrationStudentCount = usableRegistrationRows.filter(
    (row) => !sourceStudentIds.has(Number(row.sourceStudentId)),
  ).length;
  if (orphanRegistrationStudentCount > 0) {
    addIssue(
      report,
      'fatal',
      'REGISTRATION_STUDENT_ORPHAN',
      orphanRegistrationStudentCount,
    );
  }

  assertNoProtectedIdentifierCollisions(
    sourceStudents.map((row) => row.studentCode),
    options.protectedStudentIds,
    'mã sinh viên',
  );

  const sourceHomeroomIds = new Set(
    sourceStudents.map((row) => Number(row.sourceHomeroomClassId)),
  );
  const homeroomRows = raw.homeroomClasses.filter((row) =>
    sourceHomeroomIds.has(Number(row.sourceClassId)),
  );
  const homeroomById = new Map(
    homeroomRows.map((row) => [Number(row.sourceClassId), row]),
  );
  const missingHomeroomCount = sourceStudents.filter(
    (row) => !homeroomById.has(Number(row.sourceHomeroomClassId)),
  ).length;
  if (missingHomeroomCount > 0) {
    addIssue(report, 'fatal', 'STUDENT_HOMEROOM_ORPHAN', missingHomeroomCount);
  }

  const scopedMeetingKeys = new Set(
    raw.meetings
      .filter((meeting) =>
        usableOfferingIds.has(Number(meeting.sourceOfferingId)),
      )
      .map(
        (meeting) =>
          `${Number(meeting.sourceMeetingId)}:${Number(meeting.sourceOfferingId)}`,
      ),
  );
  const referencedActualLecturers = raw.actualLecturers.filter(
    (row) =>
      usableOfferingIds.has(Number(row.sourceOfferingId)) &&
      scopedMeetingKeys.has(
        `${Number(row.sourceMeetingId)}:${Number(row.sourceOfferingId)}`,
      ),
  );
  const referencedPlannedLecturers = raw.plannedLecturers.filter((row) =>
    usableOfferingIds.has(Number(row.sourceOfferingId)),
  );
  const lecturerRows = normalizeLecturers(
    [...referencedActualLecturers, ...referencedPlannedLecturers],
    report,
  );
  assertNoProtectedIdentifierCollisions(
    lecturerRows.map((row) => row.code),
    options.protectedLecturerIds,
    'mã giảng viên',
  );

  const requiredFacultyIds = collectRequiredFacultyIds({
    homeroomRows,
    offeringRows: usableOfferingRows,
    lecturerRows,
  });
  const faculties = resolveFaculties(requiredFacultyIds, options, report);
  const facultyIds = new Set(faculties.map((row) => row.sourceId));

  const classes = [
    ...homeroomRows.map((row) =>
      normalizeHomeroomClass(row, facultyIds, report),
    ),
    ...usableOfferingRows.map((row) =>
      normalizeTeachingClass(row, facultyIds, report),
    ),
  ].filter(Boolean);
  const classResult = dedupeByKey(
    classes,
    (row) => row.sourceKey,
    (row) => row,
    'target student classes',
  );
  const classBySourceKey = new Map(
    classResult.rows.map((row) => [row.sourceKey, row]),
  );

  const students = sourceStudents
    .map((row) => normalizeStudent(row, classBySourceKey, report))
    .filter(Boolean);

  const courseResult = dedupeByKey(
    usableOfferingRows.map((row) => normalizeCourse(row, report)),
    (row) => row.code,
    (row) => row,
    'courses by code',
  );
  const courses = courseResult.rows;
  const courseCodes = new Set(courses.map((row) => row.code));

  const normalizedOfferings = usableOfferingRows
    .map((row) =>
      normalizeOffering(
        row,
        term,
        courseCodes,
        classBySourceKey,
        options,
        report,
      ),
    )
    .filter(Boolean);
  const offeringResult = dedupeByKey(
    normalizedOfferings,
    (row) => row.sourceId,
    (row) => row,
    'course offerings',
  );
  const offerings = offeringResult.rows;
  const offeringBySourceId = new Map(
    offerings.map((row) => [row.sourceOfferingId, row]),
  );

  const studentBySourceId = new Map(
    students.map((row) => [row.sourceStudentId, row]),
  );
  const enrollments = usableRegistrationRows
    .map((row) =>
      normalizeEnrollment(row, studentBySourceId, offeringBySourceId, report),
    )
    .filter(Boolean);
  if (enrollments.length === 0) {
    addIssue(report, 'fatal', 'IMPORT_ENROLLMENT_SET_EMPTY', 1);
  }

  const scopedMeetingRows = raw.meetings.filter((row) =>
    usableOfferingIds.has(Number(row.sourceOfferingId)),
  );
  const normalizedMeetings = scopedMeetingRows
    .map((row) => normalizeMeeting(row, offeringBySourceId, report))
    .filter(Boolean);
  const meetingResult = dedupeByKey(
    normalizedMeetings,
    (row) => row.sourceId,
    (row) => row,
    'physical meetings per offering',
  );
  const schedules = meetingResult.rows;

  const lecturerBySourceId = new Map(
    lecturerRows.map((row) => [row.sourceLecturerId, row]),
  );
  const assignmentResult = buildScheduleLecturers({
    schedules,
    actualRows: referencedActualLecturers,
    plannedRows: referencedPlannedLecturers,
    lecturerBySourceId,
    report,
  });

  const scheduledOfferingIds = new Set(
    schedules.map((row) => row.sourceOfferingId),
  );
  const unscheduledOfferingCount = offerings.filter(
    (row) => !scheduledOfferingIds.has(row.sourceOfferingId),
  ).length;
  if (unscheduledOfferingCount > 0) {
    addIssue(
      report,
      'warning',
      'OFFERING_WITHOUT_PHYSICAL_MEETING',
      unscheduledOfferingCount,
    );
  }

  const scheduleAssignmentCounts = assignmentResult.actualCountBySchedule;
  const noLecturerCount = schedules.filter(
    (row) => !scheduleAssignmentCounts.has(row.sourceId),
  ).length;
  const multiLecturerCount = schedules.filter(
    (row) => (scheduleAssignmentCounts.get(row.sourceId) ?? 0) > 1,
  ).length;
  if (noLecturerCount > 0) {
    addIssue(report, 'warning', 'MEETING_WITHOUT_LECTURER', noLecturerCount);
  }
  if (multiLecturerCount > 0) {
    addIssue(report, 'warning', 'MULTI_LECTURER_MEETING', multiLecturerCount);
  }

  const schedulesWithPrimary = schedules.map((schedule) => ({
    ...schedule,
    isActive:
      schedule.isActive &&
      (assignmentResult.activeActualCountBySchedule.get(schedule.sourceId) ??
        0) > 0,
    primaryLecturerCode:
      assignmentResult.primaryBySchedule.get(schedule.sourceId) ?? null,
  }));

  report.counts = {
    ...report.counts,
    faculties: faculties.length,
    classes: classResult.rows.length,
    students: students.length,
    lecturers: lecturerRows.length,
    courses: courses.length,
    offerings: offerings.length,
    enrollments: enrollments.length,
    schedules: schedulesWithPrimary.length,
    scheduleLecturers: assignmentResult.assignments.length,
    unscheduledOfferings: unscheduledOfferingCount,
    meetingsWithoutLecturer: noLecturerCount,
    multiLecturerMeetings: multiLecturerCount,
    studentBirthDatesIncluded: options.includeBirthDates
      ? students.filter((row) => row.dateOfBirth).length
      : 0,
    studentEmailsIncluded: options.includeContactFields
      ? students.filter((row) => row.email).length
      : 0,
    studentPhoneNumbersIncluded: options.includeContactFields
      ? students.filter((row) => row.phoneNumber).length
      : 0,
    lecturerBirthDatesIncluded: options.includeBirthDates
      ? lecturerRows.filter((row) => row.dateOfBirth).length
      : 0,
    lecturerEmailsIncluded: options.includeContactFields
      ? lecturerRows.filter((row) => row.email).length
      : 0,
    lecturerPhoneNumbersIncluded: options.includeContactFields
      ? lecturerRows.filter((row) => row.phoneNumber).length
      : 0,
  };

  return {
    sourceSystem: SOURCE_SYSTEM,
    term,
    profileFields: {
      includeBirthDates: Boolean(options.includeBirthDates),
      includeContactFields: Boolean(options.includeContactFields),
    },
    faculties,
    classes: classResult.rows,
    students,
    lecturers: lecturerRows,
    courses,
    offerings,
    enrollments,
    schedules: schedulesWithPrimary,
    scheduleLecturers: assignmentResult.assignments,
    report,
  };
}

function normalizeTerm(row, report) {
  const startsAt = parseSourceDate(row.startsAt);
  const endsAt = parseSourceDate(row.endsAt);
  if (startsAt && endsAt && startsAt.getTime() > endsAt.getTime()) {
    addIssue(report, 'fatal', 'INVALID_TERM_RANGE', 1);
  }
  const sourceActive = normalizeBit(row.isActive, false);
  const sourceVisible = normalizeBit(row.isVisible, false);
  if (!sourceVisible) {
    addIssue(report, 'warning', 'TERM_NOT_VISIBLE', 1);
  }
  return {
    sourceId: Number(row.sourceTermId),
    code: normalizeCode(row.termCode) ?? `TERM-${row.sourceTermId}`,
    name: normalizeText(row.termName) ?? `Kỳ nguồn ${row.sourceTermId}`,
    startsAt,
    endsAt,
    isActive: sourceActive && sourceVisible,
  };
}

function studentSignature(row) {
  return {
    sourceStudentId: Number(row.sourceStudentId),
    studentCode: normalizeCode(row.studentCode),
    fullName: composeFullName(row.familyName, row.givenName),
    sourceHomeroomClassId: Number(row.sourceHomeroomClassId),
  };
}

function normalizeLecturers(rows, report) {
  const sourceResult = dedupeByKey(
    rows,
    (row) => row.sourceLecturerId,
    (row) => ({
      sourceLecturerId: Number(row.sourceLecturerId),
      code: normalizeCode(row.lecturerCode),
      fullName: composeFullName(row.familyName, row.givenName),
      sourceFacultyId: nullableNumber(row.sourceFacultyId),
    }),
    'lecturers by source ID',
  );
  const normalized = sourceResult.rows.map((row) => {
    const code = normalizeCode(row.lecturerCode);
    const fullName = composeFullName(row.familyName, row.givenName);
    if (!code || !fullName) {
      addIssue(report, 'fatal', 'LECTURER_CODE_OR_NAME_MISSING', 1);
    }
    const rawBirthDate = normalizeText(row.dateOfBirth);
    const dateOfBirth = parseSourceDate(rawBirthDate);
    if (rawBirthDate && !dateOfBirth) {
      addIssue(report, 'warning', 'LECTURER_BIRTH_DATE_INVALID', 1);
    }
    return {
      sourceLecturerId: Number(row.sourceLecturerId),
      sourceFacultyId: nullableNumber(row.sourceFacultyId),
      code,
      fullName,
      dateOfBirth,
      email: normalizeText(row.email),
      phoneNumber: normalizeText(row.phoneNumber),
      isActive: !(
        normalizeBit(row.isDeleted, false) ||
        normalizeBit(row.isDisabled, false) ||
        normalizeBit(row.isTerminated, false)
      ),
    };
  });

  return dedupeByKey(
    normalized,
    (row) => row.code,
    (row) => ({ sourceLecturerId: row.sourceLecturerId }),
    'lecturers by code',
  ).rows;
}

function collectRequiredFacultyIds({
  homeroomRows,
  offeringRows,
  lecturerRows,
}) {
  const ids = new Set();
  for (const row of homeroomRows) {
    addNullableNumber(ids, row.sourceFacultyId);
  }
  for (const row of offeringRows) {
    addNullableNumber(ids, row.sourceCourseFacultyId);
    addNullableNumber(ids, row.sourceFacultyId);
  }
  for (const row of lecturerRows) {
    addNullableNumber(ids, row.sourceFacultyId);
  }
  return ids;
}

function resolveFaculties(sourceIds, options, report) {
  const rows = [];
  let missingCount = 0;

  for (const sourceId of [...sourceIds].sort((left, right) => left - right)) {
    const configured = options.facultyMapping.get(String(sourceId));
    if (configured) {
      const code = normalizeCode(configured.code);
      const name = normalizeText(configured.name);
      if (!code || !name) {
        addIssue(report, 'fatal', 'INVALID_FACULTY_MAPPING_ENTRY', 1);
        continue;
      }
      rows.push({
        sourceId,
        code,
        name,
        placeholderCode: placeholderFacultyCode(sourceId),
        isPlaceholder: false,
      });
      continue;
    }

    missingCount += 1;
    if (options.allowPlaceholderFaculties) {
      rows.push({
        sourceId,
        code: placeholderFacultyCode(sourceId),
        name: `[CHƯA ĐỐI SOÁT] Khoa nguồn ${sourceId}`,
        placeholderCode: placeholderFacultyCode(sourceId),
        isPlaceholder: true,
      });
    }
  }

  if (missingCount > 0) {
    addIssue(
      report,
      options.allowPlaceholderFaculties ? 'warning' : 'fatal',
      'FACULTY_MAPPING_MISSING',
      missingCount,
    );
  }

  return dedupeByKey(
    rows,
    (row) => row.code,
    (row) => ({ sourceId: row.sourceId }),
    'faculty codes',
  ).rows;
}

function normalizeHomeroomClass(row, facultyIds, report) {
  const sourceId = Number(row.sourceClassId);
  const sourceFacultyId = nullableNumber(row.sourceFacultyId);
  if (!sourceFacultyId || !facultyIds.has(sourceFacultyId)) {
    addIssue(report, 'fatal', 'HOMEROOM_FACULTY_ORPHAN', 1);
    return null;
  }
  const sourceName =
    normalizeText(row.className) ??
    normalizeText(`${row.primaryCode ?? ''}${row.secondaryCode ?? ''}`) ??
    `Lớp hành chính nguồn ${sourceId}`;
  return {
    sourceKey: `DM_LOPHOC:${sourceId}`,
    sourceFacultyId,
    code: `SRC-DMLOPHOC-${sourceId}`,
    name: sourceName,
  };
}

function normalizeTeachingClass(row, facultyIds, report) {
  const sourceId = Number(row.sourceTeachingClassId);
  const sourceFacultyId =
    nullableNumber(row.sourceFacultyId) ??
    nullableNumber(row.sourceCourseFacultyId);
  if (!sourceFacultyId || !facultyIds.has(sourceFacultyId)) {
    addIssue(report, 'fatal', 'TEACHING_CLASS_FACULTY_ORPHAN', 1);
    return null;
  }
  return {
    sourceKey: `TKB_LOPHOC:${sourceId}`,
    sourceFacultyId,
    code: `SRC-TKBLOPHOC-${sourceId}`,
    name:
      normalizeText(row.teachingClassName) ??
      normalizeText(row.teachingClassCode) ??
      `Lớp xếp lịch nguồn ${sourceId}`,
  };
}

function normalizeStudent(row, classBySourceKey, report) {
  const sourceStudentId = Number(row.sourceStudentId);
  const classSourceKey = `DM_LOPHOC:${Number(row.sourceHomeroomClassId)}`;
  if (!classBySourceKey.has(classSourceKey)) {
    addIssue(report, 'fatal', 'STUDENT_TARGET_CLASS_ORPHAN', 1);
    return null;
  }
  const mssv = normalizeCode(row.studentCode);
  const fullName = composeFullName(row.familyName, row.givenName);
  if (!mssv || !fullName) {
    addIssue(report, 'fatal', 'STUDENT_CODE_OR_NAME_MISSING', 1);
    return null;
  }
  const rawBirthDate = normalizeText(row.dateOfBirth);
  const dateOfBirth = parseSourceDate(rawBirthDate);
  if (rawBirthDate && !dateOfBirth) {
    addIssue(report, 'warning', 'STUDENT_BIRTH_DATE_INVALID', 1);
  }
  return {
    sourceStudentId,
    classSourceKey,
    mssv,
    fullName,
    dateOfBirth,
    email: normalizeText(row.email),
    phoneNumber: normalizeText(row.phoneNumber),
    isActive: true,
  };
}

function normalizeCourse(row, report) {
  const code = normalizeCode(row.courseCode);
  const name =
    normalizeText(row.catalogCourseName) ?? normalizeText(row.courseName);
  const sourceFacultyId = nullableNumber(row.sourceCourseFacultyId);
  if (!code || !name || !sourceFacultyId) {
    addIssue(report, 'fatal', 'COURSE_REQUIRED_FIELD_MISSING', 1);
  }
  const rawCredits = Number(row.credits);
  let credits = 3;
  if (Number.isFinite(rawCredits) && rawCredits >= 0) {
    credits = Math.round(rawCredits);
    if (!Number.isInteger(rawCredits)) {
      addIssue(report, 'warning', 'COURSE_CREDITS_ROUNDED_TO_INTEGER', 1);
    }
  } else {
    addIssue(report, 'warning', 'COURSE_CREDITS_DEFAULTED', 1);
  }
  return { code, name, sourceFacultyId, credits };
}

function normalizeOffering(
  row,
  term,
  courseCodes,
  classBySourceKey,
  options,
  report,
) {
  const sourceOfferingId = Number(row.sourceOfferingId);
  const code = normalizeCode(row.offeringCode);
  const courseCode = normalizeCode(row.courseCode);
  const classSourceKey = `TKB_LOPHOC:${Number(row.sourceTeachingClassId)}`;
  if (!code || !courseCodes.has(courseCode)) {
    addIssue(report, 'fatal', 'OFFERING_COURSE_OR_CODE_ORPHAN', 1);
    return null;
  }
  if (!classBySourceKey.has(classSourceKey)) {
    addIssue(report, 'fatal', 'OFFERING_TEACHING_CLASS_ORPHAN', 1);
    return null;
  }
  const sourceStatus = normalizeStatus(row.sourceStatus);
  const isCanceled = options.inactiveOfferingStatuses.has(sourceStatus);
  if (isCanceled) {
    addIssue(report, 'warning', 'OFFERING_SOURCE_CANCELED', 1);
  }
  return {
    sourceOfferingId,
    sourceId: stableSourceId('TKB_LOPHOCPHAN', sourceOfferingId),
    sourceTermId: String(term.sourceId),
    code,
    courseCode,
    classSourceKey,
    termCode: term.code,
    termName: term.name,
    startsAt: term.startsAt,
    endsAt: term.endsAt,
    isActive: term.isActive && !isCanceled,
    sourceStatus,
  };
}

function normalizeEnrollment(
  row,
  studentBySourceId,
  offeringBySourceId,
  report,
) {
  const sourceStudentId = Number(row.sourceStudentId);
  const sourceOfferingId = Number(row.sourceOfferingId);
  if (!studentBySourceId.has(sourceStudentId)) {
    addIssue(report, 'fatal', 'ENROLLMENT_STUDENT_ORPHAN', 1);
    return null;
  }
  if (!offeringBySourceId.has(sourceOfferingId)) {
    addIssue(report, 'fatal', 'ENROLLMENT_OFFERING_ORPHAN', 1);
    return null;
  }
  return {
    sourceStudentId,
    sourceOfferingId,
    sourceId: stableSourceId('DANGKY_PAIR', sourceStudentId, sourceOfferingId),
    sourceStatus: normalizeStatus(row.sourceStatus),
    isActive: true,
  };
}

function normalizeMeeting(row, offeringBySourceId, report) {
  const sourceMeetingId = Number(row.sourceMeetingId);
  const sourceOfferingId = Number(row.sourceOfferingId);
  if (!offeringBySourceId.has(sourceOfferingId)) {
    addIssue(report, 'fatal', 'MEETING_OFFERING_ORPHAN', 1);
    return null;
  }
  const startTime = normalizeSqlTime(row.resolvedStartTime);
  const endTime = normalizeSqlTime(row.resolvedEndTime);
  const startsAt =
    parseSourceDate(row.teachingStartsAt) ?? parseSourceDate(row.startsAt);
  const endsAt =
    parseSourceDate(row.teachingEndsAt) ?? parseSourceDate(row.endsAt);
  if (!startTime || !endTime) {
    addIssue(report, 'fatal', 'MEETING_TIME_MAPPING_MISSING', 1);
  }
  if (!startsAt || !endsAt) {
    addIssue(report, 'fatal', 'MEETING_DATE_MISSING', 1);
  }
  let dayOfWeek = null;
  let recurrenceKind = null;
  try {
    dayOfWeek = normalizeVietnameseWeekday(row.sourceWeekday);
    recurrenceKind = deriveRecurrenceKind(startsAt, endsAt, {
      isBiweekly: normalizeBit(row.isBiweekly, false),
      isDaySpecific: normalizeBit(row.isDaySpecific, false),
      isMakeup: normalizeBit(row.isMakeup, false),
    });
  } catch (error) {
    if (error instanceof EtlGuardError) {
      addIssue(report, 'fatal', error.code, 1);
    } else {
      throw error;
    }
  }
  const room = normalizeText(row.roomName) ?? normalizeText(row.roomCode);
  if (!room) {
    addIssue(report, 'warning', 'MEETING_ROOM_MISSING', 1);
  }
  const isSuspended = normalizeBit(row.isSuspended, false);
  if (isSuspended) {
    addIssue(report, 'warning', 'MEETING_SOURCE_SUSPENDED', 1);
  }
  return {
    sourceMeetingId,
    sourceOfferingId,
    sourceId: stableSourceId(
      'TKB_LICHHOC',
      sourceMeetingId,
      'LHP',
      sourceOfferingId,
    ),
    dayOfWeek,
    startTime,
    endTime,
    startsAt,
    endsAt,
    recurrenceKind,
    room: room ?? 'Chưa xếp phòng',
    isActive:
      offeringBySourceId.get(sourceOfferingId).isActive &&
      !isSuspended &&
      Boolean(room),
  };
}

function buildScheduleLecturers({
  schedules,
  actualRows,
  plannedRows,
  lecturerBySourceId,
  report,
}) {
  const actualByMeeting = groupRows(
    actualRows,
    (row) => `${Number(row.sourceMeetingId)}:${Number(row.sourceOfferingId)}`,
  );
  const plannedByOffering = groupRows(plannedRows, (row) =>
    String(Number(row.sourceOfferingId)),
  );
  const assignments = [];
  const primaryBySchedule = new Map();
  const actualCountBySchedule = new Map();
  const activeActualCountBySchedule = new Map();

  for (const schedule of schedules) {
    const meetingKey = `${schedule.sourceMeetingId}:${schedule.sourceOfferingId}`;
    const actual = actualByMeeting.get(meetingKey) ?? [];
    const planned =
      plannedByOffering.get(String(schedule.sourceOfferingId)) ?? [];
    const selected = [
      ...planned.map((row) => ({ ...row, role: 'planned' })),
      ...actual.map((row) => ({ ...row, role: 'actual' })),
    ];
    const normalized = selected
      .map((row) => {
        const lecturer = lecturerBySourceId.get(Number(row.sourceLecturerId));
        if (!lecturer) {
          addIssue(report, 'fatal', 'SCHEDULE_LECTURER_ORPHAN', 1);
          return null;
        }
        return {
          scheduleSourceId: schedule.sourceId,
          lecturerCode: lecturer.code,
          role: row.role,
          isActive: row.role === 'actual' && lecturer.isActive,
          sourceId: stableSourceId(
            row.role === 'actual' ? 'LICH_GV' : 'DUKIEN_GV',
            schedule.sourceMeetingId,
            schedule.sourceOfferingId,
            lecturer.sourceLecturerId,
          ),
          sourceStatus:
            row.role === 'planned'
              ? 'planned'
              : lecturer.isActive
                ? 'active'
                : 'inactive',
        };
      })
      .filter(Boolean);
    const byLecturerCode = new Map();
    for (const assignment of normalized) {
      const existing = byLecturerCode.get(assignment.lecturerCode);
      if (!existing || assignment.role === 'actual') {
        byLecturerCode.set(assignment.lecturerCode, assignment);
      }
    }
    const unique = [...byLecturerCode.values()].sort((left, right) =>
      left.lecturerCode.localeCompare(right.lecturerCode),
    );
    assignments.push(...unique);
    const actualAssignments = unique.filter((row) => row.role === 'actual');
    const activeActualAssignments = actualAssignments.filter(
      (row) => row.isActive,
    );
    if (actualAssignments.length > 0) {
      actualCountBySchedule.set(schedule.sourceId, actualAssignments.length);
    }
    if (activeActualAssignments.length > 0) {
      activeActualCountBySchedule.set(
        schedule.sourceId,
        activeActualAssignments.length,
      );
      primaryBySchedule.set(
        schedule.sourceId,
        activeActualAssignments[0].lecturerCode,
      );
    }
  }

  return {
    assignments,
    primaryBySchedule,
    actualCountBySchedule,
    activeActualCountBySchedule,
  };
}

function createReport(raw) {
  return {
    counts: {
      sourceStudents: raw.students.length,
      sourceActiveRegistrationPairs: raw.registrations.length,
      sourceOfferings: raw.offerings.length,
      sourceMeetings: raw.meetings.length,
      sourceActualLecturerAssignments: raw.actualLecturers.length,
      sourcePlannedLecturerAssignments: raw.plannedLecturers.length,
    },
    issues: [],
  };
}

function addIssue(report, severity, code, count) {
  const existing = report.issues.find(
    (issue) => issue.severity === severity && issue.code === code,
  );
  if (existing) {
    existing.count += count;
  } else {
    report.issues.push({ severity, code, count });
  }
}

function assertNoFatalIssues(report) {
  const fatalCount = report.issues
    .filter((issue) => issue.severity === 'fatal')
    .reduce((total, issue) => total + issue.count, 0);
  if (fatalCount > 0) {
    throw new EtlGuardError(
      'PREFLIGHT_FAILED',
      'Preflight ETL thất bại; không được phép ghi target.',
      { fatalCount },
    );
  }
}

function placeholderFacultyCode(sourceId) {
  return `SRC-FAC-${sourceId}`;
}

function addNullableNumber(set, value) {
  const parsed = nullableNumber(value);
  if (parsed != null) {
    set.add(parsed);
  }
}

function nullableNumber(value) {
  if (value == null || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function countBy(rows, keyOf) {
  const result = new Map();
  for (const row of rows) {
    const key = keyOf(row);
    result.set(key, (result.get(key) ?? 0) + 1);
  }
  return result;
}

function groupRows(rows, keyOf) {
  const result = new Map();
  for (const row of rows) {
    const key = keyOf(row);
    const existing = result.get(key) ?? [];
    existing.push(row);
    result.set(key, existing);
  }
  return result;
}

module.exports = {
  __test: {
    buildScheduleLecturers,
    normalizeMeeting,
    normalizeOffering,
  },
  assertNoFatalIssues,
  transformEduNuce,
};
