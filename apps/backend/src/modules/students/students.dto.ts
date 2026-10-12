import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
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
  Matches,
  ValidateIf,
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

export class MobileLivenessProofDto {
  @IsArray()
  @ArrayMinSize(3)
  @ArrayMaxSize(3)
  @IsIn(['blink', 'smile', 'turn'], { each: true })
  actions!: Array<'blink' | 'smile' | 'turn'>;

  @IsISO8601({ strict: true })
  completedAt!: string;

  @Type(() => Number)
  @IsInt()
  @Min(12)
  @Max(240)
  frameCount!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0.35)
  @Max(1)
  blinkPeak!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0.3)
  @Max(1)
  smilePeak!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0.18)
  @Max(1)
  turnPeak!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(0.3)
  neutralBlinkMax!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(0.3)
  neutralSmileMax!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(0.14)
  neutralTurnMax!: number;
}

export class MobileFaceCompleteDto {
  @Type(() => Number)
  @IsInt()
  @IsIn([3], {
    message: 'Phiên bản ứng dụng đã cũ. Hãy cài APK mới nhất',
  })
  protocolVersion!: number;

  @IsString()
  @MinLength(16)
  @MaxLength(100)
  sessionId!: string;

  @IsString()
  @MinLength(20)
  @MaxLength(200)
  nonce!: string;

  @IsString()
  @MinLength(20)
  @MaxLength(8_000)
  publicKey!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(1_000)
  signature!: string;

  @IsDefined({
    message: 'Phiên bản ứng dụng đã cũ. Hãy cài APK mới nhất',
  })
  @IsNumber({}, { each: true })
  embedding!: number[];

  @ValidateNested()
  @IsDefined({
    message: 'Phiên bản ứng dụng đã cũ. Hãy cài APK mới nhất',
  })
  @Type(() => MobileLivenessProofDto)
  livenessProof!: MobileLivenessProofDto;
}

export class MobileFaceEnrollmentDto {
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

  @IsString()
  @MinLength(20)
  @MaxLength(8_000)
  publicKey!: string;

  @IsDefined()
  @IsArray()
  @ArrayMinSize(2)
  @ArrayMaxSize(5)
  embeddings!: number[][];
}

export class BleEvidenceDto {
  @IsOptional()
  @IsBoolean()
  isMock?: boolean;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9+/]{35}=$/)
  c6Token?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  beaconId!: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  roomId!: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  deviceName!: string;

  @ValidateIf((body: BleEvidenceDto) => !body.c6Token)
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  serviceUuid?: string;

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
  @Max(100)
  accuracyMeters!: number;

  @IsISO8601({ strict: true })
  capturedAt!: string;
}

export class AttendanceScanDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  sessionId!: number;

  @ValidateIf((body: AttendanceScanDto) => !body.mobileFaceSessionId)
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  faceSessionId?: string;

  @ValidateIf((body: AttendanceScanDto) => !body.mobileFaceSessionId)
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  faceSessionToken?: string;

  @ValidateIf((body: AttendanceScanDto) => !body.mobileFaceSessionId)
  @IsString()
  @MinLength(7)
  @MaxLength(7)
  faceShard?: string;

  @IsOptional()
  @IsString()
  @MinLength(16)
  @MaxLength(100)
  mobileFaceSessionId?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => BleEvidenceDto)
  bleEvidence?: BleEvidenceDto;

  @ValidateNested()
  @IsDefined()
  @Type(() => FaceEvidenceDto)
  faceEvidence!: FaceEvidenceDto;

  @ValidateNested()
  @IsDefined()
  @Type(() => GpsEvidenceDto)
  gpsEvidence!: GpsEvidenceDto;
}
