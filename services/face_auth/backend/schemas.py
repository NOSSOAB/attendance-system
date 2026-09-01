from __future__ import annotations

from pydantic import BaseModel, Field


class StartSessionRequest(BaseModel):
    target_name: str = Field(min_length=1, max_length=200)
    skip_liveness: bool = False
