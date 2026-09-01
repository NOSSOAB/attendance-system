from __future__ import annotations

import asyncio


class FrameAdmissionController:
    """Bounds decoded/inference frame work and exposes overload counters."""

    def __init__(self, capacity: int) -> None:
        self.capacity = max(1, int(capacity))
        self._semaphore = asyncio.Semaphore(self.capacity)
        self.active = 0
        self.peak_active = 0
        self.accepted = 0
        self.rejected = 0

    async def acquire(self, timeout_seconds: float) -> bool:
        try:
            await asyncio.wait_for(
                self._semaphore.acquire(),
                timeout=max(0.001, float(timeout_seconds)),
            )
        except asyncio.TimeoutError:
            self.rejected += 1
            return False
        self.active += 1
        self.accepted += 1
        self.peak_active = max(self.peak_active, self.active)
        return True

    def release(self) -> None:
        self.active = max(0, self.active - 1)
        self._semaphore.release()

    @property
    def utilization(self) -> float:
        return self.active / self.capacity
