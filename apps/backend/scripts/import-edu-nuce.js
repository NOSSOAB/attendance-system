#!/usr/bin/env node
'use strict';

require('dotenv').config({ quiet: true });

const fs = require('node:fs');
const path = require('node:path');
const {
  EtlGuardError,
  assertPositiveInteger,
  normalizeCode,
  normalizeText,
  parseExplicitStatusSet,
} = require('./etl/edu-nuce-core');
const {
  EduNuceSource,
  SOURCE_SYSTEM,
  buildSourceRuntime,
} = require('./etl/edu-nuce-source');
const {
  assertNoFatalIssues,
  transformEduNuce,
} = require('./etl/edu-nuce-transform');
const {
  applyDataset,
  buildSnapshotManifest,
  buildTargetUrls,
  preflightTargets,
} = require('./etl/edu-nuce-target');

const BOOLEAN_OPTIONS = new Set([
  'apply',
  'dry-run',
  'allow-placeholder-faculties',
  'allow-course-quarantine',
  'allow-writable-source-principal',
  'include-birth-dates',
  'include-contact-fields',
  'help',
]);
const VALUE_OPTIONS = new Set([
  'term-id',
  'active-registration-statuses',
  'inactive-offering-statuses',
  'faculty-map-json',
  'confirm',
  'school-name',
  'protected-student-ids',
  'protected-lecturer-ids',
  'minimum-active-registrations',
  'max-snapshot-drop-ratio',
]);

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  const options = buildOptions(args, process.env);
  const facultyMapping = loadFacultyMapping(options.facultyMapPath);
  if (facultyMapping.size === 0 && !options.allowPlaceholderFaculties) {
    throw new EtlGuardError(
      'FACULTY_MAPPING_REQUIRED',
      'HRM_NUCE is unavailable. Provide --faculty-map-json or explicitly use --allow-placeholder-faculties.',
    );
  }

  const sourceRuntime = buildSourceRuntime(process.env);
  const source = new EduNuceSource(sourceRuntime);
  let dataset;
  let sourceAccess;
  try {
    await source.connect();
    sourceAccess = await source.verifyAccess({
      allowWritablePrincipal:
        !options.apply && options.allowWritableSourcePrincipal,
    });
    if (options.apply && !sourceAccess.databaseReadOnly) {
      throw new EtlGuardError(
        'APPLY_REQUIRES_READ_ONLY_SOURCE_DATABASE',
        'Apply requires the restored SQL Server source database to be READ_ONLY.',
      );
    }
    const raw = await source.loadRaw(
      options.termId,
      options.activeRegistrationStatuses,
      {
        includeBirthDates: options.includeBirthDates,
        includeContactFields: options.includeContactFields,
      },
    );
    dataset = transformEduNuce(raw, {
      facultyMapping,
      allowPlaceholderFaculties: options.allowPlaceholderFaculties,
      allowCourseQuarantine: options.allowCourseQuarantine,
      inactiveOfferingStatuses: options.inactiveOfferingStatuses,
      protectedStudentIds: options.protectedStudentIds,
      protectedLecturerIds: options.protectedLecturerIds,
      includeBirthDates: options.includeBirthDates,
      includeContactFields: options.includeContactFields,
    });
  } finally {
    await source.close();
  }

  assertNoFatalIssues(dataset.report);
  if (dataset.enrollments.length < options.minimumActiveRegistrations) {
    throw new EtlGuardError(
      'MINIMUM_ACTIVE_REGISTRATIONS_NOT_MET',
      'Active enrollment snapshot is below the operator-provided minimum.',
      {
        actual: dataset.enrollments.length,
        minimum: options.minimumActiveRegistrations,
      },
    );
  }
  const snapshot = buildSnapshotManifest(dataset);

  const targetConfigured = hasAllTargetUrls(process.env);
  let targetPreflight = { status: 'skipped_not_configured' };
  let targetUrls;
  if (options.apply || targetConfigured) {
    targetUrls = buildTargetUrls(process.env, options);
    const result = await preflightTargets(targetUrls, dataset, {
      maxDropRatio: options.maxSnapshotDropRatio,
    });
    targetPreflight = { status: 'completed', ...result };
  }

  if (!options.apply) {
    printSummary({
      ok: true,
      mode: 'dry-run',
      sourceSystem: SOURCE_SYSTEM,
      sourceAccess,
      term: publicTerm(dataset.term),
      counts: dataset.report.counts,
      issues: dataset.report.issues,
      snapshot,
      targetPreflight,
    });
    return;
  }

  const expectedConfirmation = snapshot.confirmation;
  if (options.confirm !== expectedConfirmation) {
    throw new EtlGuardError(
      'APPLY_CONFIRMATION_REQUIRED',
      `Apply requires --confirm=${expectedConfirmation}.`,
    );
  }

  const result = await applyDataset(targetUrls, dataset, {
    schoolName: options.schoolName,
    preflightToken: targetPreflight.preflightToken,
  });
  printSummary({
    ok: true,
    mode: 'apply',
    sourceSystem: SOURCE_SYSTEM,
    sourceAccess,
    term: publicTerm(dataset.term),
    counts: dataset.report.counts,
    issues: dataset.report.issues,
    snapshot,
    completedScopes: result.completedScopes,
  });
}

function buildOptions(args, env) {
  if (args.apply && args['dry-run']) {
    throw new EtlGuardError(
      'CONFLICTING_MODE_OPTIONS',
      '--apply and --dry-run cannot be used together.',
    );
  }
  if (args.apply && args['allow-writable-source-principal']) {
    throw new EtlGuardError(
      'WRITABLE_SOURCE_OVERRIDE_FORBIDDEN_FOR_APPLY',
      '--allow-writable-source-principal is only available for dry-run.',
    );
  }
  if (args.apply && !args['minimum-active-registrations']) {
    throw new EtlGuardError(
      'APPLY_MINIMUM_REGISTRATION_REQUIRED',
      'Apply requires --minimum-active-registrations from a reviewed dry-run.',
    );
  }
  const termId = assertPositiveInteger(args['term-id'], '--term-id');
  const activeRegistrationStatuses = parseNumericStatusSet(
    args['active-registration-statuses'],
    '--active-registration-statuses',
  );
  const inactiveOfferingStatuses = parseNumericStatusSet(
    args['inactive-offering-statuses'] ?? '5',
    '--inactive-offering-statuses',
  );
  return {
    termId,
    activeRegistrationStatuses,
    inactiveOfferingStatuses,
    facultyMapPath: args['faculty-map-json'] ?? env.EDU_NUCE_FACULTY_MAP_JSON,
    allowPlaceholderFaculties: Boolean(args['allow-placeholder-faculties']),
    allowCourseQuarantine: Boolean(args['allow-course-quarantine']),
    allowWritableSourcePrincipal: Boolean(
      args['allow-writable-source-principal'],
    ),
    includeBirthDates: Boolean(args['include-birth-dates']),
    includeContactFields: Boolean(args['include-contact-fields']),
    apply: Boolean(args.apply),
    minimumActiveRegistrations: assertPositiveInteger(
      args['minimum-active-registrations'] ??
        env.EDU_NUCE_MINIMUM_ACTIVE_REGISTRATIONS ??
        1,
      '--minimum-active-registrations',
    ),
    maxSnapshotDropRatio: parseDropRatio(
      args['max-snapshot-drop-ratio'] ??
        env.EDU_NUCE_MAX_SNAPSHOT_DROP_RATIO ??
        '0.2',
    ),
    confirm: args.confirm,
    schoolName: args['school-name'] ?? env.EDU_NUCE_SCHOOL_NAME,
    protectedStudentIds: parseIdentifierSet(
      args['protected-student-ids'] ??
        env.EDU_NUCE_PROTECTED_STUDENT_IDS ??
        '1389570',
    ),
    protectedLecturerIds: parseIdentifierSet(
      args['protected-lecturer-ids'] ??
        env.EDU_NUCE_PROTECTED_LECTURER_IDS ??
        'GV001,GV002,GV003',
    ),
  };
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      throw new EtlGuardError(
        'UNKNOWN_ARGUMENT',
        'Only named --options are accepted.',
      );
    }
    const separator = token.indexOf('=');
    const name = token.slice(2, separator === -1 ? undefined : separator);
    if (!BOOLEAN_OPTIONS.has(name) && !VALUE_OPTIONS.has(name)) {
      throw new EtlGuardError('UNKNOWN_ARGUMENT', `Unknown option --${name}.`);
    }
    if (Object.hasOwn(result, name)) {
      throw new EtlGuardError(
        'DUPLICATE_ARGUMENT',
        `Option --${name} was repeated.`,
      );
    }
    if (BOOLEAN_OPTIONS.has(name)) {
      if (separator !== -1) {
        throw new EtlGuardError(
          'INVALID_BOOLEAN_ARGUMENT',
          `Option --${name} does not accept a value.`,
        );
      }
      result[name] = true;
      continue;
    }
    const value = separator === -1 ? argv[++index] : token.slice(separator + 1);
    if (value == null || value.startsWith('--') || value.trim() === '') {
      throw new EtlGuardError(
        'MISSING_ARGUMENT_VALUE',
        `Option --${name} requires a value.`,
      );
    }
    result[name] = value;
  }
  return result;
}

function parseNumericStatusSet(value, optionName) {
  const statuses = parseExplicitStatusSet(value, optionName);
  for (const status of statuses) {
    const numeric = Number(status);
    if (!Number.isInteger(numeric)) {
      throw new EtlGuardError(
        'INVALID_STATUS_SET',
        `${optionName} must contain only integer source status IDs.`,
      );
    }
  }
  return new Set([...statuses].map((status) => String(Number(status))));
}

function parseIdentifierSet(value) {
  return new Set(
    String(value ?? '')
      .split(',')
      .map(normalizeCode)
      .filter(Boolean),
  );
}

function parseDropRatio(value) {
  const ratio = Number(value);
  if (!Number.isFinite(ratio) || ratio < 0 || ratio >= 1) {
    throw new EtlGuardError(
      'INVALID_DROP_RATIO',
      '--max-snapshot-drop-ratio must satisfy 0 <= ratio < 1.',
    );
  }
  return ratio;
}

function loadFacultyMapping(filePath) {
  if (!filePath?.trim()) {
    return new Map();
  }
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8'));
  } catch {
    throw new EtlGuardError(
      'FACULTY_MAPPING_UNREADABLE',
      'Faculty mapping JSON cannot be read or parsed.',
    );
  }
  const rows = Array.isArray(parsed)
    ? parsed
    : Object.entries(parsed).map(([sourceId, value]) => ({
        sourceId,
        ...(value && typeof value === 'object' ? value : {}),
      }));
  const mapping = new Map();
  for (const row of rows) {
    const sourceId = Number(row.sourceId);
    const code = normalizeCode(row.code);
    const name = normalizeText(row.name);
    if (!Number.isInteger(sourceId) || sourceId <= 0 || !code || !name) {
      throw new EtlGuardError(
        'INVALID_FACULTY_MAPPING',
        'Every faculty mapping needs a positive sourceId, code and name.',
      );
    }
    if (mapping.has(String(sourceId))) {
      throw new EtlGuardError(
        'DUPLICATE_FACULTY_MAPPING',
        'Faculty mapping contains a duplicate sourceId.',
      );
    }
    mapping.set(String(sourceId), { code, name });
  }
  return mapping;
}

function hasAllTargetUrls(env) {
  return [
    'DATABASE_URL',
    'HUCE_STUDENT_DATABASE_URL',
    'HUCE_LECTURER_DATABASE_URL',
  ].every((key) => Boolean(env[key]?.trim()));
}

function publicTerm(term) {
  return {
    sourceId: term.sourceId,
    code: term.code,
    isActive: term.isActive,
  };
}

function printSummary(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function usage() {
  return [
    'Dry-run (default):',
    '  npm run etl:edu-nuce -- --term-id=295 --active-registration-statuses=1,2,3 --faculty-map-json=<path>',
    '',
    'Apply (local targets only; source DB must be READ_ONLY):',
    '  First copy the exact --confirm value from a reviewed dry-run, then run with --apply and --minimum-active-registrations.',
    '',
    'Safety overrides:',
    '  --allow-placeholder-faculties  --allow-course-quarantine',
    '  --allow-writable-source-principal',
    '  --include-birth-dates  --include-contact-fields',
  ].join('\n');
}

if (require.main === module) {
  main().catch((error) => {
    if (error instanceof EtlGuardError) {
      process.stderr.write(
        `${JSON.stringify({ ok: false, code: error.code, message: error.message, details: error.details })}\n`,
      );
    } else {
      process.stderr.write(
        `${JSON.stringify({ ok: false, code: 'UNEXPECTED_ETL_FAILURE', message: 'ETL failed; inspect secured local logs without exposing connection strings or row data.' })}\n`,
      );
    }
    process.exitCode = 1;
  });
}

module.exports = {
  buildOptions,
  loadFacultyMapping,
  parseArgs,
  parseNumericStatusSet,
};
