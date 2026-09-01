import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { PrismaModule } from './database/prisma/prisma.module';
import { HealthController } from './health.controller';
import { AuthModule } from './modules/auth/auth.module';
import { LecturersModule } from './modules/lecturers/lecturers.module';
import { SchoolsModule } from './modules/schools/schools.module';
import { StudentsModule } from './modules/students/students.module';
import {
  getNetworkRateLimitTracker,
  getPrincipalRateLimitTracker,
} from './rate-limit/rate-limit.tracker';

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: 60_000,
        limit: 240,
        getTracker: getPrincipalRateLimitTracker,
      },
      {
        name: 'network',
        ttl: 60_000,
        limit: 6_000,
        getTracker: getNetworkRateLimitTracker,
      },
    ]),
    PrismaModule,
    AuthModule,
    SchoolsModule,
    StudentsModule,
    LecturersModule,
  ],
  controllers: [HealthController],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
