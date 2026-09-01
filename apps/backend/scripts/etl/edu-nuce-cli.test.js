'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildOptions } = require('../import-edu-nuce');

const base = {
  'term-id': '295',
  'active-registration-statuses': '1,2,3',
};

test('CLI defaults to minimized profiles and requires reviewed apply guards', () => {
  const dryRun = buildOptions(base, {});
  assert.equal(dryRun.apply, false);
  assert.equal(dryRun.includeBirthDates, false);
  assert.equal(dryRun.includeContactFields, false);

  assert.throws(
    () =>
      buildOptions(
        {
          ...base,
          apply: true,
          'allow-writable-source-principal': true,
          'minimum-active-registrations': '150000',
        },
        {},
      ),
    { name: 'EtlGuardError' },
  );
  assert.throws(() => buildOptions({ ...base, apply: true }, {}), {
    name: 'EtlGuardError',
  });

  const profiled = buildOptions(
    {
      ...base,
      'include-birth-dates': true,
      'include-contact-fields': true,
    },
    {},
  );
  assert.equal(profiled.includeBirthDates, true);
  assert.equal(profiled.includeContactFields, true);
});
