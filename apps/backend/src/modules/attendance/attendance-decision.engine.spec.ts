import { decideAttendance } from './attendance-decision.engine';

describe('decideAttendance', () => {
  const recordedAt = new Date('2026-07-31T08:05:00.000Z');
  const base = {
    sessionIsOpen: true,
    alreadySuccessful: false,
    faceVerified: true,
    recordedAt,
    lateAt: new Date('2026-07-31T08:10:00.000Z'),
  };

  it('returns present before the late threshold', () => {
    expect(decideAttendance(base).status).toBe('present');
  });

  it('returns late after the late threshold', () => {
    expect(
      decideAttendance({
        ...base,
        lateAt: new Date('2026-07-31T08:00:00.000Z'),
      }).status,
    ).toBe('late');
  });

  it('rejects a closed session', () => {
    expect(decideAttendance({ ...base, sessionIsOpen: false }).status).toBe(
      'rejected_session_closed',
    );
  });

  it('rejects an already successful attendance', () => {
    expect(decideAttendance({ ...base, alreadySuccessful: true }).status).toBe(
      'rejected_duplicate',
    );
  });

  it('flags failed face verification', () => {
    expect(decideAttendance({ ...base, faceVerified: false })).toMatchObject({
      status: 'flagged',
      reason: 'FACE_VERIFICATION_FAILED',
    });
  });

  it('preserves a BLE failure reason', () => {
    expect(
      decideAttendance({
        ...base,
        evidenceFailure: 'BLE_SIGNAL_TOO_WEAK',
      }),
    ).toMatchObject({
      status: 'flagged',
      reason: 'BLE_SIGNAL_TOO_WEAK',
    });
  });
});
