import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { RolesGuard } from './roles.guard';

const jwtSecret = process.env.JWT_SECRET?.trim();
if (
  process.env.NODE_ENV === 'production' &&
  (!jwtSecret || jwtSecret.length < 32)
) {
  throw new Error(
    'JWT_SECRET must contain at least 32 characters in production',
  );
}

@Module({
  imports: [
    JwtModule.register({
      secret: jwtSecret || 'local-development-jwt-secret-change-me',
      signOptions: {
        expiresIn: Number(process.env.JWT_TTL_SECONDS ?? 28_800),
      },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtAuthGuard, RolesGuard],
  exports: [JwtModule, JwtAuthGuard, RolesGuard],
})
export class AuthModule {}
