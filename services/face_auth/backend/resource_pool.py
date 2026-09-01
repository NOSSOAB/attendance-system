from __future__ import annotations

from contextlib import contextmanager
from queue import LifoQueue
from threading import Lock
from typing import Generic, Iterator, TypeVar


T = TypeVar("T")


class ResourcePool(Generic[T]):
    """Small blocking pool for native model objects that are not thread-safe."""

    def __init__(self, resources: list[T]) -> None:
        if not resources:
            raise ValueError("ResourcePool requires at least one resource")
        self._resources = list(resources)
        self._available: LifoQueue[T] = LifoQueue(maxsize=len(resources))
        for resource in resources:
            self._available.put_nowait(resource)
        self._state_lock = Lock()
        self._in_use = 0
        self._peak_in_use = 0
        self._acquisitions = 0

    @property
    def resources(self) -> tuple[T, ...]:
        return tuple(self._resources)

    @property
    def capacity(self) -> int:
        return len(self._resources)

    @property
    def in_use(self) -> int:
        with self._state_lock:
            return self._in_use

    @property
    def peak_in_use(self) -> int:
        with self._state_lock:
            return self._peak_in_use

    @property
    def acquisitions(self) -> int:
        with self._state_lock:
            return self._acquisitions

    @contextmanager
    def checkout(self) -> Iterator[T]:
        resource = self._available.get(block=True)
        with self._state_lock:
            self._in_use += 1
            self._acquisitions += 1
            self._peak_in_use = max(self._peak_in_use, self._in_use)
        try:
            yield resource
        finally:
            with self._state_lock:
                self._in_use -= 1
            self._available.put_nowait(resource)
