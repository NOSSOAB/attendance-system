import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import {
  PrismaTenantService,
  TenantAuthRole,
} from '../../database/prisma/prisma-tenant.service';
import { PrismaService } from '../../database/prisma/prisma.service';
import type { AuthRole } from './auth.types';

type LoginPayload = {
  schoolCode: string;
  role?: TenantAuthRole;
  identifier?: string;
  mssv?: string;
  lecturerCode?: string;
  password: string;
};

type ForgotPasswordPayload = {
  schoolCode: string;
  role?: TenantAuthRole;
  identifier?: string;
  mssv?: string;
  lecturerCode?: string;
};

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly prismaTenant: PrismaTenantService,
    private readonly jwt: JwtService,
  ) {}

  async login(payload: LoginPayload) {
    const schoolCode = payload.schoolCode?.trim();
    const role = this.normalizeRole(payload.role);
    const identifier = this.resolveIdentifier(role, payload);

    if (!schoolCode) {
      throw new BadRequestException('Vui lòng chọn trường trước khi đăng nhập');
    }

    const school = await this.findSchoolOrThrow(schoolCode);

    if (role === 'student') {
      return this.loginStudent(school, identifier, payload.password);
    }

    return this.loginLecturer(school, identifier, payload.password);
  }

  async forgotPassword(payload: ForgotPasswordPayload) {
    const schoolCode = payload.schoolCode?.trim();
    const role = this.normalizeRole(payload.role);
    const identifier = this.resolveIdentifier(role, payload);

    if (!schoolCode) {
      throw new BadRequestException(
        'Vui lòng chọn trường trước khi đặt lại mật khẩu',
      );
    }

    await this.findSchoolOrThrow(schoolCode);
    void role;
    void identifier;
    return {
      message:
        'Yêu cầu hỗ trợ mật khẩu đã được ghi nhận. Vui lòng liên hệ quản trị viên của trường để xác minh danh tính.',
    };
  }

  private async loginStudent(
    school: { code: string; name: string },
    mssv: string,
    password: string,
  ) {
    const prisma = this.prismaTenant.getClient(school.code, 'student');
    const student = await this.findStudentForAuth(prisma, school.code, mssv);

    if (!student) {
      throw new UnauthorizedException(
        'Sai th\u00f4ng tin \u0111\u0103ng nh\u1eadp',
      );
    }

    if (
      !student.account?.passwordHash ||
      !this.verifyPassword(password, student.account.passwordHash)
    ) {
      throw new UnauthorizedException(
        'Sai th\u00f4ng tin \u0111\u0103ng nh\u1eadp',
      );
    }

    await prisma.studentAccount.update({
      where: { studentId: student.id },
      data: { lastLoginAt: new Date() },
    });
    const accessToken = await this.issueAccessToken(
      'student',
      school.code,
      student.id,
      student.mssv,
    );

    return {
      message: '\u0110\u0103ng nh\u1eadp th\u00e0nh c\u00f4ng',
      role: 'student',
      accessToken,
      tokenType: 'Bearer',
      expiresInSeconds: Number(process.env.JWT_TTL_SECONDS ?? 28_800),
      user: {
        id: student.id,
        code: student.mssv,
        fullName: student.fullName,
        school: school.name,
        faculty: student.studentClass.faculty.name,
        class: student.studentClass.name,
        dateOfBirth: student.dateOfBirth,
        citizenId: student.citizenId,
        email: student.email,
      },
    };
  }

  private async loginLecturer(
    school: { code: string; name: string },
    lecturerCode: string,
    password: string,
  ) {
    const prisma = this.prismaTenant.getClient(school.code, 'lecturer');
    const lecturer = await this.findLecturerForAuth(
      prisma,
      school.code,
      lecturerCode,
    );

    if (!lecturer) {
      throw new UnauthorizedException(
        'Sai th\u00f4ng tin \u0111\u0103ng nh\u1eadp',
      );
    }

    if (
      !lecturer.account?.passwordHash ||
      !this.verifyPassword(password, lecturer.account.passwordHash)
    ) {
      throw new UnauthorizedException(
        'Sai th\u00f4ng tin \u0111\u0103ng nh\u1eadp',
      );
    }

    await prisma.lecturerAccount.update({
      where: { lecturerId: lecturer.id },
      data: { lastLoginAt: new Date() },
    });
    const accessToken = await this.issueAccessToken(
      'lecturer',
      school.code,
      lecturer.id,
      lecturer.lecturerCode,
    );

    return {
      message: '\u0110\u0103ng nh\u1eadp th\u00e0nh c\u00f4ng',
      role: 'lecturer',
      accessToken,
      tokenType: 'Bearer',
      expiresInSeconds: Number(process.env.JWT_TTL_SECONDS ?? 28_800),
      user: {
        id: lecturer.id,
        code: lecturer.lecturerCode,
        fullName: lecturer.fullName,
        school: school.name,
        faculty: lecturer.faculty?.name,
        class: null,
        dateOfBirth: lecturer.dateOfBirth,
        citizenId: lecturer.citizenId,
        email: lecturer.email,
      },
    };
  }

  private async resetStudentPassword(schoolCode: string, mssv: string) {
    const prisma = this.prismaTenant.getClient(schoolCode, 'student');
    const student = await this.findStudentForAuth(prisma, schoolCode, mssv);

    if (!student) {
      throw new UnauthorizedException(
        'Kh\u00f4ng t\u00ecm th\u1ea5y sinh vi\u00ean \u0111\u1ec3 \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u',
      );
    }

    const expectedPassword = this.buildDatePassword(student.dateOfBirth);

    if (!expectedPassword) {
      throw new UnauthorizedException(
        'T\u00e0i kho\u1ea3n ch\u01b0a c\u00f3 ng\u00e0y sinh \u0111\u1ec3 \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u',
      );
    }

    await this.syncStudentPassword(prisma, student.id, expectedPassword, null);

    return {
      message:
        '\u0110\u00e3 \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u v\u1ec1 ng\u00e0y sinh \u0111\u00e3 \u0111\u0103ng k\u00fd. H\u00e3y d\u00f9ng ng\u00e0y sinh \u0111\u1ec3 \u0111\u0103ng nh\u1eadp l\u1ea1i.',
    };
  }

  private async resetLecturerPassword(
    schoolCode: string,
    lecturerCode: string,
  ) {
    const prisma = this.prismaTenant.getClient(schoolCode, 'lecturer');
    const lecturer = await this.findLecturerForAuth(
      prisma,
      schoolCode,
      lecturerCode,
    );

    if (!lecturer) {
      throw new UnauthorizedException(
        'Kh\u00f4ng t\u00ecm th\u1ea5y gi\u1ea3ng vi\u00ean \u0111\u1ec3 \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u',
      );
    }

    const expectedPassword = this.buildDatePassword(lecturer.dateOfBirth);

    if (!expectedPassword) {
      throw new UnauthorizedException(
        'T\u00e0i kho\u1ea3n ch\u01b0a c\u00f3 ng\u00e0y sinh \u0111\u1ec3 \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u',
      );
    }

    await this.syncLecturerPassword(
      prisma,
      lecturer.id,
      expectedPassword,
      null,
    );

    return {
      message:
        '\u0110\u00e3 \u0111\u1eb7t l\u1ea1i m\u1eadt kh\u1ea9u v\u1ec1 ng\u00e0y sinh \u0111\u00e3 \u0111\u0103ng k\u00fd. H\u00e3y d\u00f9ng ng\u00e0y sinh \u0111\u1ec3 \u0111\u0103ng nh\u1eadp l\u1ea1i.',
    };
  }

  private async findStudentForAuth(
    prisma: PrismaClient,
    schoolCode: string,
    mssv: string,
  ) {
    return prisma.student.findFirst({
      where: {
        mssv,
        isActive: true,
        school: {
          code: schoolCode,
        },
      },
      include: {
        account: true,
        school: true,
        studentClass: {
          include: {
            faculty: true,
          },
        },
      },
    });
  }

  private async findLecturerForAuth(
    prisma: PrismaClient,
    schoolCode: string,
    lecturerCode: string,
  ) {
    const lecturerPrisma = prisma as PrismaClient & {
      lecturer: {
        findFirst: (args: Record<string, unknown>) => Promise<any>;
      };
    };

    return lecturerPrisma.lecturer.findFirst({
      where: {
        lecturerCode,
        isActive: true,
        school: {
          code: schoolCode,
        },
      },
      include: {
        account: true,
        school: true,
        faculty: true,
      },
    });
  }

  private async syncStudentPassword(
    prisma: PrismaClient,
    studentId: number,
    password: string,
    lastLoginAt: Date | null,
  ) {
    const passwordHash = this.hashPassword(password);

    await prisma.studentAccount.upsert({
      where: {
        studentId,
      },
      update: {
        passwordHash,
        lastLoginAt: lastLoginAt ?? undefined,
      },
      create: {
        studentId,
        passwordHash,
        lastLoginAt: lastLoginAt ?? undefined,
      },
    });
  }

  private async syncLecturerPassword(
    prisma: PrismaClient,
    lecturerId: number,
    password: string,
    lastLoginAt: Date | null,
  ) {
    const passwordHash = this.hashPassword(password);
    const lecturerPrisma = prisma as PrismaClient & {
      lecturerAccount: {
        upsert: (args: Record<string, unknown>) => Promise<any>;
      };
    };

    await lecturerPrisma.lecturerAccount.upsert({
      where: {
        lecturerId,
      },
      update: {
        passwordHash,
        lastLoginAt: lastLoginAt ?? undefined,
      },
      create: {
        lecturerId,
        passwordHash,
        lastLoginAt: lastLoginAt ?? undefined,
      },
    });
  }

  private hashPassword(password: string) {
    const salt = randomBytes(16).toString('hex');
    const hash = scryptSync(password, salt, 64).toString('hex');
    return `${salt}:${hash}`;
  }

  private verifyPassword(password: string, storedHash: string) {
    const [salt, expectedHex, extra] = storedHash.split(':');
    if (!salt || !expectedHex || extra) {
      return false;
    }

    try {
      const expected = Buffer.from(expectedHex, 'hex');
      const actual = scryptSync(password, salt, expected.length);
      return (
        expected.length > 0 &&
        actual.length === expected.length &&
        timingSafeEqual(actual, expected)
      );
    } catch {
      return false;
    }
  }

  private issueAccessToken(
    role: AuthRole,
    schoolCode: string,
    subject: number,
    code: string,
  ) {
    return this.jwt.signAsync({
      sub: subject,
      role,
      schoolCode: schoolCode.toUpperCase(),
      code,
    });
  }

  private buildDatePassword(dateOfBirth: Date | null): string | null {
    if (!dateOfBirth) {
      return null;
    }

    const day = `${dateOfBirth.getDate()}`.padStart(2, '0');
    const month = `${dateOfBirth.getMonth() + 1}`.padStart(2, '0');
    const year = `${dateOfBirth.getFullYear()}`;

    return `${day}${month}${year}`;
  }

  private normalizeRole(role?: string): TenantAuthRole {
    return role === 'lecturer' ? 'lecturer' : 'student';
  }

  private resolveIdentifier(
    role: TenantAuthRole,
    payload: LoginPayload | ForgotPasswordPayload,
  ) {
    const rawValue =
      role === 'student'
        ? (payload.identifier ?? payload.mssv)
        : (payload.identifier ?? payload.lecturerCode);

    const identifier = rawValue?.trim();

    if (!identifier) {
      throw new BadRequestException(
        role === 'student'
          ? 'Vui lòng nhập mã sinh viên'
          : 'Vui lòng nhập mã giảng viên',
      );
    }

    return identifier;
  }

  private async findSchoolOrThrow(schoolCode: string) {
    const school = await this.prisma.school.findUnique({
      where: {
        code: schoolCode,
      },
      select: {
        code: true,
        name: true,
      },
    });

    if (!school) {
      throw new BadRequestException('Trường được chọn không tồn tại');
    }

    return school;
  }
}
