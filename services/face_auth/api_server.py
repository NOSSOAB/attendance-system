"""Compatibility entry point.

Existing commands such as ``python -m uvicorn api_server:app`` keep working while
the implementation lives in the maintainable ``backend`` package.
"""

from backend.app import app, create_app

__all__ = ["app", "create_app"]
