import {
  getNetworkRateLimitTracker,
  getPrincipalRateLimitTracker,
} from './rate-limit.tracker';

describe('rate limit trackers', () => {
  it('gives signed-in students independent buckets behind one IP', () => {
    const first = getPrincipalRateLimitTracker({
      ip: '203.0.113.10',
      headers: { authorization: 'Bearer token-a' },
    });
    const second = getPrincipalRateLimitTracker({
      ip: '203.0.113.10',
      headers: { authorization: 'Bearer token-b' },
    });

    expect(first).not.toBe(second);
    expect(getNetworkRateLimitTracker({ ip: '203.0.113.10' })).toBe(
      'network:203.0.113.10',
    );
  });

  it('limits login attempts by account instead of the classroom IP', () => {
    expect(
      getPrincipalRateLimitTracker({
        ip: '203.0.113.10',
        body: {
          schoolCode: 'huce',
          role: 'student',
          identifier: '1389570',
        },
      }),
    ).toBe('account:HUCE:student:1389570');
  });
});
