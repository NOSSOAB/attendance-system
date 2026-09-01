type RateLimitRequest = {
  ip?: string;
  headers?: { authorization?: unknown };
  body?: unknown;
  socket?: { remoteAddress?: string };
};

function networkAddress(request: RateLimitRequest): string {
  return request.ip ?? request.socket?.remoteAddress ?? 'unknown';
}

export function getPrincipalRateLimitTracker(
  request: RateLimitRequest,
): string {
  const authorization = request.headers?.authorization;
  if (
    typeof authorization === 'string' &&
    authorization.startsWith('Bearer ') &&
    authorization.length > 7
  ) {
    // ThrottlerGuard hashes the tracker before storing it. A valid JWT gives
    // each signed-in user an independent bucket even behind campus NAT.
    return `token:${authorization.slice(7)}`;
  }

  if (typeof request.body === 'object' && request.body !== null) {
    const body = request.body as Record<string, unknown>;
    const schoolCode =
      typeof body.schoolCode === 'string' ? body.schoolCode.trim() : '';
    const role = typeof body.role === 'string' ? body.role.trim() : 'student';
    const rawIdentifier = body.identifier ?? body.mssv ?? body.lecturerCode;
    const identifier =
      typeof rawIdentifier === 'string' ? rawIdentifier.trim() : '';
    if (schoolCode && identifier) {
      return `account:${schoolCode.toUpperCase()}:${role}:${identifier}`;
    }
  }

  return `ip:${networkAddress(request)}`;
}

export function getNetworkRateLimitTracker(request: RateLimitRequest): string {
  return `network:${networkAddress(request)}`;
}
