import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDefined,
  IsIn,
  IsInt,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export class StudentScheduleQueryDto {
  @IsOptional()
  @IsIn(['day', 'week', 'month'])
  view?: 'day' | 'week' | 'month';

  @IsOptional()
  @IsISO8601({ strict: true })
  date?: string;
}

export class StudentHistoryQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(50)
  courseCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  status?: string;
}

export class AttendanceFaceSessionDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  sessionId!: number;
}

export class BleEvidenceDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  beaconId!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(100)
  roomId!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(100)
  deviceName!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(100)
  serviceUuid!: string;

  @Type(() => Number)
  @IsInt()
  @Min(-127)
  @Max(20)
  rssi!: number;

  @IsISO8601({ strict: true })
  scannedAt!: string;

  @Type(() => Number)
  @IsInt()
  @Min(5_000)
  @Max(8_000)
  scanDurationMs!: number;
}

export class FaceEvidenceDto {
  @IsBoolean()
  verified!: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(1)
  score?: number | null;

  @IsISO8601({ strict: true })
  verifiedAt!: string;
}

export class GpsEvidenceDto {
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  accuracyMeters!: number;

  @IsISO8601({ strict: true })
  capturedAt!: string;
}

export class AttendanceScanDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  sessionId!: number;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  faceSessionId!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  faceSessionToken!: string;

  @IsString()
  @MinLength(7)
  @MaxLength(7)
  faceShard!: string;

  @ValidateNested()
  @IsDefined()
  @Type(() => BleEvidenceDto)
  bleEvidence!: BleEvidenceDto;

  @ValidateNested()
  @IsDefined()
  @Type(() => FaceEvidenceDto)
  faceEvidence!: FaceEvidenceDto;

  @ValidateNested()
  @IsDefined()
  @Type(() => GpsEvidenceDto)
  gpsEvidence!: GpsEvidenceDto;
}
