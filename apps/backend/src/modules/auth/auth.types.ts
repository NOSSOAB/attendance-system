export type AuthRole = 'student' | 'lecturer';

export type JwtPrincipal = {
  sub: number;
  role: AuthRole;
  schoolCode: string;
  code: string;
  iat?: number;
  exp?: number;
};
