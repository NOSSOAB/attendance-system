import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AUTH_ROLES_KEY } from './auth.decorators';
import type { AuthRole, JwtPrincipal } from './auth.types';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext) {
    const allowedRoles = this.reflector.getAllAndOverride<AuthRole[]>(
      AUTH_ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!allowedRoles?.length) {
      return true;
    }

    const request = context.switchToHttp().getRequest<{
      user?: JwtPrincipal;
    }>();
    if (!request.user || !allowedRoles.includes(request.user.role)) {
      throw new ForbiddenException(
        'Tài khoản không có quyền thực hiện thao tác này',
      );
    }
    return true;
  }
}
