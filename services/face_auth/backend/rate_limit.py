from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
import time
from typing import Callable


@dataclass
class _Bucket:
    tokens: float
    updated_at: float


class TokenBucketRateLimiter:
    """Small in-memory limiter for the single-instance EC2 deployment."""

    def __init__(
        self,
        rate_per_second: float,
        burst: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.rate_per_second = max(0.01, float(rate_per_second))
        self.burst = max(1, int(burst))
        self._clock = clock
        self._buckets: dict[str, _Bucket] = {}
        self._lock = Lock()
        self._rejected = 0

    @property
    def rejected(self) -> int:
        with self._lock:
            return self._rejected

    def allow(self, key: str) -> bool:
        now = self._clock()
        with self._lock:
            bucket = self._buckets.get(key)
            if bucket is None:
                bucket = _Bucket(float(self.burst), now)
                self._buckets[key] = bucket
            else:
                elapsed = max(0.0, now - bucket.updated_at)
                bucket.tokens = min(
                    float(self.burst),
                    bucket.tokens + elapsed * self.rate_per_second,
                )
                bucket.updated_at = now
            if bucket.tokens < 1.0:
                self._rejected += 1
                return False
            bucket.tokens -= 1.0
            if len(self._buckets) > 2048:
                cutoff = now - 600.0
                self._buckets = {
                    item_key: item
                    for item_key, item in self._buckets.items()
                    if item.updated_at >= cutoff
                }
            return True
