import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, Roles } from '../auth/auth.decorators';
import type { JwtPrincipal } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import {
  AttendanceFaceSessionDto,
  AttendanceScanDto,
  MobileFaceCompleteDto,
  MobileFaceEnrollmentDto,
  StudentHistoryQueryDto,
  StudentScheduleQueryDto,
} from './students.dto';
import { StudentsService } from './students.service';

@Controller('students')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('student')
export class StudentsController {
  constructor(private readonly studentsService: StudentsService) {}

  @Get('home')
  async getStudentHome(@CurrentUser() user: JwtPrincipal) {
    return this.studentsService.getStudentHome(this.identity(user));
  }

  @Get('schedule')
  async getStudentSchedule(
    @CurrentUser() user: JwtPrincipal,
    @Query() query: StudentScheduleQueryDto,
  ) {
    return this.studentsService.getSchedule({
      ...this.identity(user),
      ...query,
    });
  }

  @Post('attendance/scan')
  async scanAttendance(
    @CurrentUser() user: JwtPrincipal,
    @Body() body: AttendanceScanDto,
  ) {
    return this.studentsService.scanAttendance({
      ...this.identity(user),
      ...body,
    });
  }

  @Post('attendance/face-session')
  async startAttendanceFaceSession(
    @CurrentUser() user: JwtPrincipal,
    @Body() body: AttendanceFaceSessionDto,
  ) {
    return this.studentsService.startAttendanceFaceSession({
      ...this.identity(user),
      ...body,
    });
  }

  @Post('attendance/mobile-face-session')
  async startMobileAttendanceFaceSession(
    @CurrentUser() user: JwtPrincipal,
    @Body() body: AttendanceFaceSessionDto,
  ) {
    return this.studentsService.startMobileAttendanceFaceSession({
      ...this.identity(user),
      ...body,
    });
  }

  @Post('attendance/mobile-face-session/complete')
  async completeMobileAttendanceFaceSession(
    @CurrentUser() user: JwtPrincipal,
    @Body() body: MobileFaceCompleteDto,
  ) {
    return this.studentsService.completeMobileAttendanceFaceSession({
      ...this.identity(user),
      ...body,
    });
  }

  @Post('attendance/mobile-face-enrollment')
  async enrollMobileFace(
    @CurrentUser() user: JwtPrincipal,
    @Body() body: MobileFaceEnrollmentDto,
  ) {
    return this.studentsService.enrollMobileFace({
      ...this.identity(user),
      ...body,
    });
  }

  @Get('mobile-face-devices')
  async listMobileFaceDevices(@CurrentUser() user: JwtPrincipal) {
    return this.studentsService.listMobileFaceDevices(this.identity(user));
  }

  @Post('mobile-face-devices/:keyFingerprint/revoke')
  async revokeMobileFaceDevice(
    @CurrentUser() user: JwtPrincipal,
    @Param('keyFingerprint') keyFingerprint: string,
  ) {
    return this.studentsService.revokeMobileFaceDevice(
      this.identity(user),
      keyFingerprint,
    );
  }

  @Get('attendance-history')
  async getAttendanceHistory(
    @CurrentUser() user: JwtPrincipal,
    @Query() query: StudentHistoryQueryDto,
  ) {
    return this.studentsService.getAttendanceHistory({
      ...this.identity(user),
      ...query,
    });
  }

  @Get('attendance-history/:sessionId')
  async getAttendanceHistoryDetail(
    @CurrentUser() user: JwtPrincipal,
    @Param('sessionId', ParseIntPipe) sessionId: number,
  ) {
    return this.studentsService.getAttendanceHistoryDetail(
      sessionId,
      this.identity(user),
    );
  }

  @Get('notifications')
  async getNotifications(@CurrentUser() user: JwtPrincipal) {
    return this.studentsService.getNotifications(this.identity(user));
  }

  @Post('notifications/:notificationId/read')
  async markNotificationRead(
    @CurrentUser() user: JwtPrincipal,
    @Param('notificationId', ParseIntPipe) notificationId: number,
  ) {
    return this.studentsService.markNotificationRead(
      notificationId,
      this.identity(user),
    );
  }

  @Get('profile')
  async getProfile(@CurrentUser() user: JwtPrincipal) {
    return this.studentsService.getProfile(this.identity(user));
  }

  private identity(user: JwtPrincipal) {
    return {
      schoolCode: user.schoolCode,
      mssv: user.code,
    };
  }
}
