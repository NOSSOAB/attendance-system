import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { CurrentUser, Roles } from '../auth/auth.decorators';
import type { JwtPrincipal } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import {
  CreateAttendanceSessionDto,
  LecturerExportQueryDto,
  LecturerHistoryQueryDto,
  LecturerStatisticsQueryDto,
  SaveAttendanceDto,
} from './lecturers.dto';
import { LecturersService } from './lecturers.service';

@Controller('lecturers')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('lecturer')
export class LecturersController {
  constructor(private readonly lecturersService: LecturersService) {}

  @Get('home')
  async getHome(@CurrentUser() user: JwtPrincipal) {
    return this.lecturersService.getLecturerHome(this.identity(user));
  }

  @Get('classes')
  async getClasses(@CurrentUser() user: JwtPrincipal) {
    return this.lecturersService.getLecturerClasses(this.identity(user));
  }

  @Get('classes/:scheduleId')
  async getClassDetail(
    @CurrentUser() user: JwtPrincipal,
    @Param('scheduleId', ParseIntPipe) scheduleId: number,
  ) {
    return this.lecturersService.getLecturerClassDetail(
      scheduleId,
      this.identity(user),
    );
  }

  @Post('classes/:scheduleId/attendance-sessions')
  async createAttendanceSession(
    @CurrentUser() user: JwtPrincipal,
    @Param('scheduleId', ParseIntPipe) scheduleId: number,
    @Body() body: CreateAttendanceSessionDto,
  ) {
    return this.lecturersService.createAttendanceSession(
      scheduleId,
      this.identity(user),
      body,
    );
  }

  @Post('attendance-sessions/:sessionId/save')
  async saveAttendanceSession(
    @CurrentUser() user: JwtPrincipal,
    @Param('sessionId', ParseIntPipe) sessionId: number,
    @Body() body: SaveAttendanceDto,
  ) {
    return this.lecturersService.saveAttendanceSession(
      sessionId,
      this.identity(user),
      body,
    );
  }

  @Get('history')
  async getHistory(
    @CurrentUser() user: JwtPrincipal,
    @Query() query: LecturerHistoryQueryDto,
  ) {
    return this.lecturersService.getAttendanceHistory({
      ...this.identity(user),
      ...query,
      scheduleId: query.scheduleId?.toString(),
    });
  }

  @Get('statistics')
  async getStatistics(
    @CurrentUser() user: JwtPrincipal,
    @Query() query: LecturerStatisticsQueryDto,
  ) {
    return this.lecturersService.getAttendanceStatistics({
      ...this.identity(user),
      scheduleId: query.scheduleId?.toString(),
    });
  }

  @Get('notifications')
  async getNotifications(@CurrentUser() user: JwtPrincipal) {
    return this.lecturersService.getLecturerNotifications(this.identity(user));
  }

  @Patch('notifications/:notificationId/read')
  async markNotificationAsRead(
    @CurrentUser() user: JwtPrincipal,
    @Param('notificationId', ParseIntPipe) notificationId: number,
  ) {
    return this.lecturersService.markNotificationAsRead(
      notificationId,
      this.identity(user),
    );
  }

  @Get('profile')
  async getProfile(@CurrentUser() user: JwtPrincipal) {
    return this.lecturersService.getLecturerProfile(this.identity(user));
  }

  @Get('export')
  async exportAttendance(
    @CurrentUser() user: JwtPrincipal,
    @Query() query: LecturerExportQueryDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.lecturersService.exportAttendanceReport({
      ...this.identity(user),
      scheduleId: query.scheduleId?.toString(),
      scope: query.scope,
    });

    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${result.fileName}"`,
    );

    return Buffer.from(result.buffer);
  }

  private identity(user: JwtPrincipal) {
    return {
      schoolCode: user.schoolCode,
      lecturerCode: user.code,
    };
  }
}
