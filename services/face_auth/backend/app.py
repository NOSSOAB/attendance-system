from __future__ import annotations

from contextlib import asynccontextmanager
from dataclasses import dataclass
import os
from pathlib import Path
import time
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool

from modules.utils import ensure_runtime_dirs, load_config, setup_logging

from .admission import FrameAdmissionController
from .pipeline import AuthenticationPipeline
from .rate_limit import TokenBucketRateLimiter
from .routes import router
from .runtime import InferenceRuntime
from .session_store import SessionStore
from .settings import BackendSettings, env_bool


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = Path(
    os.environ.get("FACE_CONFIG_PATH", str(PROJECT_ROOT / "config.yaml"))
).resolve()


@dataclass
class ApplicationServices:
    settings: BackendSettings
    runtime: InferenceRuntime
    sessions: SessionStore
    pipeline: AuthenticationPipeline
    frame_admission: FrameAdmissionController
    session_start_limiter: TokenBucketRateLimiter
    frame_limiter: TokenBucketRateLimiter
    started_at: float
    logger: object


def create_app() -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        config = load_config(CONFIG_PATH)
        ensure_runtime_dirs(config)
        settings = BackendSettings.from_config(config)
        if settings.require_client_api_key and not settings.client_api_key:
            raise RuntimeError(
                "FACE_CLIENT_API_KEY must be set when security.require_client_api_key is enabled"
            )
        logger = setup_logging(config, "face_auth_backend")
        runtime = InferenceRuntime(settings, logger)
        sessions = SessionStore(settings.session_ttl_seconds, settings.max_sessions)
        pipeline = AuthenticationPipeline(settings, runtime, sessions, logger)
        services = ApplicationServices(
            settings=settings,
            runtime=runtime,
            sessions=sessions,
            pipeline=pipeline,
            frame_admission=FrameAdmissionController(settings.max_inflight_frames),
            session_start_limiter=TokenBucketRateLimiter(
                settings.session_start_rate_per_minute / 60.0,
                settings.session_start_burst,
            ),
            frame_limiter=TokenBucketRateLimiter(
                settings.frame_rate_per_second,
                settings.frame_rate_burst,
            ),
            started_at=time.monotonic(),
            logger=logger,
        )
        app.state.services = services

        # Model startup is intentionally outside request handling. The server only
        # reports ready after every PC-side model and face database is available.
        await run_in_threadpool(runtime.load)
        logger.info("Backend API ready")
        try:
            yield
        finally:
            logger.info("Backend API shutting down")
            await run_in_threadpool(pipeline.close)
            runtime.close()

    production = env_bool("FACE_PRODUCTION", False)
    expose_docs = env_bool("FACE_EXPOSE_DOCS", not production)
    app = FastAPI(
        title="Face Auth PC Backend",
        version="2.0.0",
        lifespan=lifespan,
        docs_url="/docs" if expose_docs else None,
        redoc_url="/redoc" if expose_docs else None,
        openapi_url="/openapi.json" if expose_docs else None,
    )
    cors_origins_raw = os.environ.get("FACE_CORS_ORIGINS")
    cors_origins = (
        [item.strip() for item in cors_origins_raw.split(",") if item.strip()]
        if cors_origins_raw is not None
        else ([] if production else ["*"])
    )
    if cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=cors_origins,
            allow_methods=["GET", "POST", "DELETE"],
            allow_headers=["Content-Type", "X-API-Key", "X-Admin-Key", "X-Session-Token"],
        )
    app.include_router(router)
    return app


app = create_app()
