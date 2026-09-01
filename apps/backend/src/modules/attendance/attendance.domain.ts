export const attendanceStatuses = [
  'present',
  'late',
  'flagged',
  'rejected_session_closed',
  'rejected_duplicate',
] as const;

export type AttendanceStatus = (typeof attendanceStatuses)[number];

export const attendanceFailureReasons = [
  'BLE_NOT_FOUND',
  'BLE_SIGNAL_TOO_WEAK',
  'BLE_ROOM_MISMATCH',
  'FACE_VERIFICATION_FAILED',
  'INVALID_EVIDENCE',
] as const;

export type AttendanceFailureReason = (typeof attendanceFailureReasons)[number];

export type BleEvidence = {
  beaconId?: string;
  roomId?: string;
  deviceName?: string;
  serviceUuid?: string;
  rssi?: number;
  scannedAt?: string;
  scanDurationMs?: number;
};

export type FaceEvidence = {
  verified?: boolean;
  score?: number | null;
  verifiedAt?: string;
};

export type GpsEvidence = {
  latitude?: number;
  longitude?: number;
  accuracyMeters?: number;
  capturedAt?: string;
};

export type AttendanceEvidence = {
  bleEvidence?: BleEvidence | null;
  faceEvidence?: FaceEvidence | null;
  gpsEvidence?: GpsEvidence | null;
};

export type AttendanceDecision = {
  status: AttendanceStatus;
  reason: AttendanceFailureReason | null;
  recordedAt: string;
  message: string;
  canRetry: boolean;
};

export type BleSessionExpectation = {
  beaconId: string;
  roomId: string;
  deviceName: string;
  serviceUuid: string;
  minRssi: number;
};
