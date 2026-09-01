import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import type { JwtPrincipal } from './auth.types';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<{
      headers: { authorization?: string };
      user?: JwtPrincipal;
    }>();
    const authorization = request.headers.authorization;
    const [scheme, token] = authorization?.split(' ') ?? [];

    if (scheme !== 'Bearer' || !token) {
      throw new UnauthorizedException('Thiếu access token');
    }

    try {
      const principal = await this.jwt.verifyAsync<JwtPrincipal>(token);
      if (
        !Number.isInteger(principal.sub) ||
        !['student', 'lecturer'].includes(principal.role) ||
        !principal.schoolCode ||
        !principal.code
      ) {
        throw new Error('Invalid JWT claims');
      }
      request.user = principal;
      return true;
    } catch {
      throw new UnauthorizedException(
        'Access token không hợp lệ hoặc đã hết hạn',
      );
    }
  }
}
