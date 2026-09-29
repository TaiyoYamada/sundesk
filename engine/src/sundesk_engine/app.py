"""FastAPI アプリケーションの組み立て。"""

import secrets
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

from sundesk_engine import __version__
from sundesk_engine.api import health

TOKEN_ENV = "SUNDESK_ENGINE_TOKEN"  # noqa: S105 - 環境変数の名前で、秘密の値ではない


def create_app(token: str | None = None) -> FastAPI:
    """エンジンの HTTP API を作る。

    `token` を渡すと、すべてのリクエストに `Authorization: Bearer <token>` を求める。
    アプリは起動のたびにトークンを発行し、環境変数で渡す（docs/adr/0006 を参照）。
    """
    app = FastAPI(title="sundesk-engine", version=__version__, docs_url=None, redoc_url=None)
    app.include_router(health.router)

    if token:
        expected = f"Bearer {token}"

        @app.middleware("http")
        async def require_token(  # pyright: ignore[reportUnusedFunction]
            request: Request, call_next: Callable[[Request], Awaitable[Response]]
        ) -> Response:
            provided = request.headers.get("authorization", "")
            if not secrets.compare_digest(provided, expected):
                return JSONResponse({"detail": "unauthorized"}, status_code=401)
            return await call_next(request)

    return app
