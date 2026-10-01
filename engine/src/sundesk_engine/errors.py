"""エンジンが返す失敗の種類と、それを HTTP の応答に変える処理。

失敗は `{"detail": "日本語のメッセージ"}` で返す（docs/engine-api.md を参照）。
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class EngineError(Exception):
    """利用者に見せてよいメッセージを持つ失敗。`status` がそのまま HTTP の状態になる。"""

    status: int = 500

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class BadRequestError(EngineError):
    """要求の中身がおかしい。"""

    status = 400


class NotFoundError(EngineError):
    """モデルやファイルが見つからない。"""

    status = 404


class UnsupportedError(EngineError):
    """対応していないモデルの構造など。"""

    status = 422


class InternalError(EngineError):
    """それ以外の失敗。"""

    status = 500


def describe(error: BaseException) -> str:
    """例外を、利用者に見せるメッセージにする。"""
    if isinstance(error, EngineError):
        return error.detail
    return f"エンジンの内部でエラーが起きました（{type(error).__name__}: {error}）"


def _format_validation(error: RequestValidationError) -> str:
    parts: list[str] = []
    for item in error.errors():
        location = ".".join(str(part) for part in item.get("loc", ()) if part != "body")
        message = str(item.get("msg", ""))
        parts.append(f"{location}: {message}" if location else message)
    return "要求の内容が正しくありません（" + "、".join(parts) + "）"


def install_handlers(app: FastAPI) -> None:
    """失敗を `{"detail": ...}` の形で返すようにする。"""

    @app.exception_handler(EngineError)
    async def handle_engine_error(  # pyright: ignore[reportUnusedFunction]
        _request: Request, error: EngineError
    ) -> JSONResponse:
        return JSONResponse({"detail": error.detail}, status_code=error.status)

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(  # pyright: ignore[reportUnusedFunction]
        _request: Request, error: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse({"detail": _format_validation(error)}, status_code=400)

    @app.exception_handler(Exception)
    async def handle_unexpected_error(  # pyright: ignore[reportUnusedFunction]
        _request: Request, error: Exception
    ) -> JSONResponse:
        logger.error("要求の処理に失敗しました", exc_info=error)
        return JSONResponse({"detail": describe(error)}, status_code=500)
