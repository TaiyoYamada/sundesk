"""死活確認。アプリは起動直後にこれを繰り返し呼び、応答が返れば稼働中とみなす。"""

import platform

from fastapi import APIRouter
from pydantic import BaseModel

from sundesk_engine import __version__

router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    version: str
    python_version: str


@router.get("/health")
async def get_health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        version=__version__,
        python_version=platform.python_version(),
    )
