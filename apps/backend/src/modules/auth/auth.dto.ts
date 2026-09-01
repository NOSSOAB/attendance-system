import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class LoginDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(20)
  schoolCode!: string;

  @IsOptional()
  @IsIn(['student', 'lecturer'])
  role?: 'student' | 'lecturer';

  @IsOptional()
  @IsString()
  @MaxLength(100)
  identifier?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  mssv?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  lecturerCode?: string;

  @IsString()
  @MinLength(6)
  @MaxLength(200)
  password!: string;
}

export class ForgotPasswordDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(20)
  schoolCode!: string;

  @IsOptional()
  @IsIn(['student', 'lecturer'])
  role?: 'student' | 'lecturer';

  @IsOptional()
  @IsString()
  @MaxLength(100)
  identifier?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  mssv?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  lecturerCode?: string;
}
