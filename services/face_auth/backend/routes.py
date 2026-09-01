from __future__ import annotations

from datetime import datetime
import hmac
import time
from typing import Any

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from starlette.concurrency import run_in_threadpool

from .domain import (
    SessionAuthError,
    SessionBusyError,
    SessionCapacityError,
    SessionNotFoundError,
)
from .schemas import StartSessionRequest


router = APIRouter()


def _services(request: Request) -> Any:
    return request.app.state.services


def _translate_error(exc: Exception, request: Request | None = None) -> HTTPException:
    if isinstance(exc, HTTPException):
        return exc
    if isinstance(exc, SessionNotFoundError):
        return HTTPException(status_code=404, detail="Session not found or expired")
    if isinstance(exc, SessionAuthError):
        return HTTPException(status_code=401, detail=str(exc))
    if isinstance(exc, (SessionBusyError, SessionCapacityError)):
        return HTTPException(status_code=429, detail=str(exc))
    if isinstance(exc, ValueError):
        return HTTPException(status_code=400, detail=str(exc))
    if request is not None:
        logger = getattr(_services(request), "logger", None)
        if logger is not None:
            logger.exception("Unhandled API error")
    return HTTPException(status_code=500, detail="Internal server error")


@router.get("/api/v1/health")
@router.get("/health", include_in_schema=False)
def health(request: Request) -> dict[str, Any]:
    return _health_payload(request, include_details=False)


@router.get("/api/v1/admin/health-details")
def health_details(request: Request) -> dict[str, Any]:
    try:
        _require_admin_api_key(request)
        return _health_payload(request, include_details=True)
    except Exception as exc:
        raise _translate_error(exc, request) from exc


def _health_payload(request: Request, include_details: bool) -> dict[str, Any]:
    services = _services(request)
    try:
        identities = services.runtime.list_identities()
    except Exception as exc:
        raise _translate_error(exc, request) from exc
    payload = {
        "ok": services.runtime.ready,
        "api_version": "v1",
        "build_version": services.settings.build_version,
        "server_time": datetime.now().isoformat(timespec="seconds"),
        "identity_count": len(identities),
        "active_sessions": services.sessions.count(),
        "session_capacity": services.settings.max_sessions,
    }
    if not include_details and not services.settings.expose_health_details:
        return payload
    payload.update({
        "frame_admission_active": services.frame_admission.active,
        "frame_admission_capacity": services.frame_admission.capacity,
        "frame_admission_peak": services.frame_admission.peak_active,
        "frame_admission_rejected": services.frame_admission.rejected,
        "detector_workers": services.runtime.detector_worker_count,
        "detector_workers_in_use": services.runtime.detector_workers_in_use,
        "detector_workers_peak": services.runtime.detector_workers_peak,
        "verification_queue_pending": services.pipeline.verification_queue_pending,
        "verification_queue_waiting": services.pipeline.verification_queue_waiting,
        "verification_queue_peak": services.pipeline.verification_queue_peak,
        "verification_workers": services.settings.verification_workers,
        "verification_models_in_use": services.runtime.verification_model_workers_in_use,
        "verification_models_peak": services.runtime.verification_model_workers_peak,
        "verification_queue_capacity": services.settings.verification_queue_capacity,
        "outcome_counts": services.pipeline.outcome_counts,
        "frame_issue_counts": services.pipeline.frame_issue_counts,
        "duplicate_frames_rejected": services.pipeline.duplicate_frames_rejected,
        "session_rate_limit_rejected": services.session_start_limiter.rejected,
        "frame_rate_limit_rejected": services.frame_limiter.rejected,
        "model_load_seconds": round(services.runtime.load_seconds, 2),
        "uptime_seconds": round(time.monotonic() - services.started_at, 1),
    })
    return payload


@router.get("/api/v1/identities")
@router.get("/people", include_in_schema=False)
def identities(request: Request) -> dict[str, Any]:
    try:
        _require_client_api_key(request)
        people = _services(request).runtime.list_identities()
        return {"identities": people, "people": people, "count": len(people)}
    except Exception as exc:
        raise _translate_error(exc, request) from exc


@router.post("/api/v1/admin/reload-identities")
def reload_identities(request: Request) -> dict[str, Any]:
    try:
        _require_admin_api_key(request)
        people = _services(request).runtime.reload_database()
        return {"identities": people, "people": people, "count": len(people)}
    except Exception as exc:
        raise _translate_error(exc, request) from exc


@router.post("/api/v1/sessions")
@router.post("/session/start", include_in_schema=False)
def start_session(request: Request, payload: StartSessionRequest) -> dict[str, Any]:
    try:
        _require_client_api_key(request)
        services = _services(request)
        # Session creation is performed by NestJS, so IP-based throttling would
        # put every student behind the same bucket. The target identity is
        # authenticated by NestJS and gives each student an independent budget.
        session_rate_key = payload.target_name.strip().casefold()
        if not services.session_start_limiter.allow(session_rate_key):
            raise HTTPException(
                status_code=429,
                detail="Too many session starts; retry later",
                headers={"Retry-After": "5"},
            )
        return services.pipeline.create_session(
            payload.target_name,
            skip_liveness=payload.skip_liveness,
        )
    except Exception as exc:
        raise _translate_error(exc, request) from exc


@router.get("/api/v1/sessions/{session_id}")
def session_status(request: Request, session_id: str) -> dict[str, Any]:
    try:
        _require_session_token(request, session_id)
        return _services(request).pipeline.get_status(session_id)
    except Exception as exc:
        raise _translate_error(exc, request) from exc


@router.post("/api/v1/sessions/{session_id}/reset")
@router.post("/session/{session_id}/reset", include_in_schema=False)
def reset_session(request: Request, session_id: str) -> dict[str, Any]:
    try:
        _require_session_token(request, session_id)
        return _services(request).pipeline.reset_session(session_id)
    except Exception as exc:
        raise _translate_error(exc, request) from exc


@router.delete("/api/v1/sessions/{session_id}")
def delete_session(request: Request, session_id: str) -> dict[str, Any]:
    try:
        _require_session_token(request, session_id)
        deleted = _services(request).pipeline.delete_session(session_id)
        return {"deleted": deleted, "session_id": session_id}
    except Exception as exc:
        raise _translate_error(exc, request) from exc


@router.post("/api/v1/sessions/{session_id}/frames")
@router.post("/session/{session_id}/frame", include_in_schema=False)
async def process_frame(
    request: Request,
    session_id: str,
    image: UploadFile = File(...),
    mirror: bool = Form(False),
    rotation_degrees: int = Form(-1),
) -> dict[str, Any]:
    services = _services(request)
    try:
        _require_session_token(request, session_id)
    except Exception as exc:
        raise _translate_error(exc, request) from exc
    # A classroom normally shares one public/NAT IP. Limit each authenticated
    # face session instead of throttling the entire classroom as one client.
    if not services.frame_limiter.allow(session_id):
        raise HTTPException(
            status_code=429,
            detail="Frame rate limit exceeded; retry with backoff",
            headers={"Retry-After": "1"},
        )
    content = await image.read(services.settings.max_upload_bytes + 1)
    await image.close()
    if len(content) > services.settings.max_upload_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Image exceeds {services.settings.max_upload_bytes} bytes",
        )

    acquired = False
    try:
        acquired = await services.frame_admission.acquire(services.settings.queue_timeout_seconds)
        if not acquired:
            raise HTTPException(
                status_code=429,
                detail="Backend is busy; retry this session's next frame with backoff",
                headers={"Retry-After": "1"},
            )
        return await run_in_threadpool(
            services.pipeline.process_frame,
            session_id,
            content,
            mirror,
            rotation_degrees,
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise _translate_error(exc, request) from exc
    finally:
        if acquired:
            services.frame_admission.release()


def _require_client_api_key(request: Request) -> None:
    settings = _services(request).settings
    if not settings.require_client_api_key:
        return
    supplied = request.headers.get("X-API-Key", "")
    if not supplied or not hmac.compare_digest(settings.client_api_key, supplied):
        raise HTTPException(status_code=401, detail="Invalid or missing client API key")


def _require_admin_api_key(request: Request) -> None:
    expected = _services(request).settings.admin_api_key
    if not expected:
        raise HTTPException(status_code=503, detail="Admin endpoint is disabled")
    supplied = request.headers.get("X-Admin-Key", "")
    if not supplied or not hmac.compare_digest(expected, supplied):
        raise HTTPException(status_code=401, detail="Invalid or missing admin API key")


def _require_session_token(request: Request, session_id: str) -> None:
    token = request.headers.get("X-Session-Token", "")
    _services(request).sessions.require_token(session_id, token)


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For", "")
    if forwarded:
        return forwarded.split(",")[-1].strip()
    return request.client.host if request.client is not None else "unknown"
