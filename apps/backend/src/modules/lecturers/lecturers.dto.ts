import { Type } from 'class-transformer';
import {
  IsArray,
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class LecturerHistoryQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  scheduleId?: number;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  courseKeyword?: string;

  @IsOptional()
  @IsISO8601({ strict: true })
  attendanceDate?: string;
}

export class LecturerStatisticsQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  scheduleId?: number;
}

export class LecturerExportQueryDto extends LecturerStatisticsQueryDto {
  @IsOptional()
  @IsIn(['today', 'all'])
  scope?: 'today' | 'all';
}

export class CreateAttendanceSessionDto {
  @IsOptional()
  @IsISO8601({ strict: true })
  startAt?: string;

  @IsOptional()
  @IsISO8601({ strict: true })
  endAt?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(240)
  durationMinutes?: number;
}

export class SaveAttendanceRecordDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  recordId?: number;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  studentId!: number;

  @IsIn(['OK', 'REVIEW', 'ABSENT'])
  status!: 'OK' | 'REVIEW' | 'ABSENT';

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;

  @IsOptional()
  @IsISO8601({ strict: true })
  checkInAt?: string | null;
}

export class SaveAttendanceDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SaveAttendanceRecordDto)
  records!: SaveAttendanceRecordDto[];
}
