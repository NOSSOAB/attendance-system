import type {
  AttendanceFailureReason,
  AttendanceStatus,
} from './attendance.domain';

export type AttendanceDecisionInput = {
  sessionIsOpen: boolean;
  alreadySuccessful: boolean;
  evidenceFailure?: AttendanceFailureReason | null;
  faceVerified?: boolean;
  recordedAt: Date;
  lateAt: Date;
};

export type AttendanceDecisionCore = {
  status: AttendanceStatus;
  reason: AttendanceFailureReason | null;
  canRetry: boolean;
};

export function decideAttendance(
  input: AttendanceDecisionInput,
): AttendanceDecisionCore {
  if (!input.sessionIsOpen) {
    return {
      status: 'rejected_session_closed',
      reason: null,
      canRetry: false,
    };
  }

  if (input.alreadySuccessful) {
    return {
      status: 'rejected_duplicate',
      reason: null,
      canRetry: false,
    };
  }

  if (input.evidenceFailure) {
    return {
      status: 'flagged',
      reason: input.evidenceFailure,
      canRetry: true,
    };
  }

  if (input.faceVerified !== true) {
    return {
      status: 'flagged',
      reason: 'FACE_VERIFICATION_FAILED',
      canRetry: true,
    };
  }

  return {
    status:
      input.recordedAt.getTime() > input.lateAt.getTime() ? 'late' : 'present',
    reason: null,
    canRetry: false,
  };
}
