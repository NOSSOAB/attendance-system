import { Module } from '@nestjs/common';
import { StudentsService } from './students.service';
import { StudentsController } from './students.controller';
import { FaceAuthService } from './face-auth.service';
import { MobileFaceAuthService } from './mobile-face-auth.service';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  providers: [StudentsService, FaceAuthService, MobileFaceAuthService],
  controllers: [StudentsController],
})
export class StudentsModule {}
