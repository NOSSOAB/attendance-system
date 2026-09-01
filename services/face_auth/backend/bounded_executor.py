from __future__ import annotations

from concurrent.futures import Future, ThreadPoolExecutor
from threading import BoundedSemaphore, Lock
from typing import Any, Callable


class ExecutorQueueFullError(RuntimeError):
    pass


class BoundedExecutor:
    """Thread pool whose running + waiting tasks have a hard upper bound."""

    def __init__(self, max_workers: int, max_queue_size: int, thread_name_prefix: str) -> None:
        self.max_workers = max(1, int(max_workers))
        self.max_queue_size = max(0, int(max_queue_size))
        self._slots = BoundedSemaphore(self.max_workers + self.max_queue_size)
        self._executor = ThreadPoolExecutor(
            max_workers=self.max_workers,
            thread_name_prefix=thread_name_prefix,
        )
        self._state_lock = Lock()
        self._pending = 0
        self._peak_pending = 0

    @property
    def pending(self) -> int:
        with self._state_lock:
            return self._pending

    @property
    def waiting(self) -> int:
        return max(0, self.pending - self.max_workers)

    @property
    def peak_pending(self) -> int:
        with self._state_lock:
            return self._peak_pending

    @property
    def capacity(self) -> int:
        return self.max_workers + self.max_queue_size

    def submit(self, fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Future[Any]:
        if not self._slots.acquire(blocking=False):
            raise ExecutorQueueFullError("Verification queue is full")
        with self._state_lock:
            self._pending += 1
            self._peak_pending = max(self._peak_pending, self._pending)

        try:
            future = self._executor.submit(self._run, fn, args, kwargs)
            future.add_done_callback(self._release_if_cancelled)
            return future
        except Exception:
            self._release_slot()
            raise

    def shutdown(self, wait: bool = True, cancel_futures: bool = True) -> None:
        self._executor.shutdown(wait=wait, cancel_futures=cancel_futures)

    def _run(
        self,
        fn: Callable[..., Any],
        args: tuple[Any, ...],
        kwargs: dict[str, Any],
    ) -> Any:
        try:
            return fn(*args, **kwargs)
        finally:
            self._release_slot()

    def _release_slot(self) -> None:
        with self._state_lock:
            self._pending -= 1
        self._slots.release()

    def _release_if_cancelled(self, future: Future[Any]) -> None:
        if future.cancelled():
            self._release_slot()
