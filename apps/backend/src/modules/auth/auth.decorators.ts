import {
  createParamDecorator,
  ExecutionContext,
  SetMetadata,
} from '@nestjs/common';
import type { AuthRole, JwtPrincipal } from './auth.types';

export const AUTH_ROLES_KEY = 'auth_roles';

export const Roles = (...roles: AuthRole[]) =>
  SetMetadata(AUTH_ROLES_KEY, roles);

export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): JwtPrincipal => {
    const request = context.switchToHttp().getRequest<{
      user: JwtPrincipal;
    }>();
    return request.user;
  },
);
