from __future__ import annotations

from threading import Lock
import hashlib
import hmac
import time
from typing import Callable

from .domain import AuthSession, SessionAuthError, SessionCapacityError, SessionNotFoundError


class SessionStore:
    """Small in-memory store suitable for a single-PC local deployment."""

    def __init__(
        self,
        ttl_seconds: float,
        max_sessions: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.ttl_seconds = ttl_seconds
        self.max_sessions = max_sessions
        self._clock = clock
        self._sessions: dict[str, AuthSession] = {}
        self._lock = Lock()

    def add(self, session: AuthSession) -> AuthSession:
        with self._lock:
            self._cleanup_locked()
            if len(self._sessions) >= self.max_sessions:
                terminal = sorted(
                    (item for item in self._sessions.values() if item.terminal),
                    key=lambda item: item.updated_at,
                )
                if terminal:
                    self._sessions.pop(terminal[0].session_id, None)
                else:
                    raise SessionCapacityError(
                        f"Server dang co toi da {self.max_sessions} phien dang hoat dong"
                    )
            self._sessions[session.session_id] = session
            return session

    def get(self, session_id: str, touch: bool = True) -> AuthSession:
        with self._lock:
            self._cleanup_locked()
            session = self._sessions.get(session_id)
            if session is None:
                raise SessionNotFoundError(session_id)
            if touch:
                session.touch()
            return session

    def remove(self, session_id: str) -> bool:
        with self._lock:
            return self._sessions.pop(session_id, None) is not None

    def require_token(self, session_id: str, token: str) -> None:
        session = self.get(session_id, touch=False)
        supplied_digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
        if not token or not hmac.compare_digest(session.session_token_digest, supplied_digest):
            raise SessionAuthError("Invalid or missing session token")

    def cleanup(self) -> int:
        with self._lock:
            return self._cleanup_locked()

    def count(self) -> int:
        with self._lock:
            self._cleanup_locked()
            return len(self._sessions)

    def _cleanup_locked(self) -> int:
        now = self._clock()
        expired = [
            session_id
            for session_id, session in self._sessions.items()
            if now - session.updated_at > self.ttl_seconds
        ]
        for session_id in expired:
            self._sessions.pop(session_id, None)
        return len(expired)
