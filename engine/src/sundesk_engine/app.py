"""FastAPI アプリケーションの組み立て。"""

import secrets
from collections.abc import AsyncGenerator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

from sundesk_engine import __version__
from sundesk_engine.api import chat, embeddings, graph, health, images, lab, lora, models, steering
from sundesk_engine.engine import Engine
from sundesk_engine.errors import install_handlers

TOKEN_ENV = "SUNDESK_ENGINE_TOKEN"  # noqa: S105 - 環境変数の名前で、秘密の値ではない


def create_app(token: str | None = None, engine: Engine | None = None) -> FastAPI:
    """エンジンの HTTP API を作る。

    `token` を渡すと、すべてのリクエストに `Authorization: Bearer <token>` を求める。
    アプリは起動のたびにトークンを発行し、環境変数で渡す（docs/adr/0006 を参照）。
    `engine` を渡すと、その部品（モデルの読み込みなど）を使う。テストで偽物を渡すためのもの。
    """
    parts = engine or Engine.create_default()

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncGenerator[None]:
        yield
        parts.shutdown()

    app = FastAPI(
        title="sundesk-engine",
        version=__version__,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )
    app.state.engine = parts
    install_handlers(app)
    for router in (
        health.router,
        graph.router,
        embeddings.router,
        chat.router,
        models.router,
        lab.router,
        images.router,
        lora.router,
        steering.router,
    ):
        app.include_router(router)

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
