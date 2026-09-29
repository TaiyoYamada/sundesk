"""重い処理を別のスレッドで動かし、結果や途中経過をイベントループに返す。

MLX や torch の計算はイベントループを止めてしまうので、必ずワーカースレッドで行う。
時間のかかる処理は NDJSON（1 行に 1 つの JSON）で逐次返す。
"""

import asyncio
import contextlib
import json
import logging
import threading
from collections.abc import AsyncIterator, Callable
from concurrent.futures import Executor
from typing import Any

from fastapi.responses import StreamingResponse

from sundesk_engine.errors import EngineError, InternalError, describe

logger = logging.getLogger(__name__)

NDJSON_MEDIA_TYPE = "application/x-ndjson"

type Event = dict[str, Any]
type Emit = Callable[[Event], None]


class StreamCancelledError(Exception):
    """受け手が接続を切った。処理を途中でやめるために投げる。"""


async def run_blocking[T](executor: Executor | None, work: Callable[[], T]) -> T:
    """`work` をワーカースレッドで動かし、終わるのを待つ。

    `EngineError` 以外の例外は、ログに残してから `InternalError` に変える。
    """
    loop = asyncio.get_running_loop()

    def guarded() -> T:
        try:
            return work()
        except EngineError:
            raise
        except Exception as error:
            logger.exception("処理に失敗しました")
            raise InternalError(describe(error)) from error

    return await loop.run_in_executor(executor, guarded)


def encode_event(event: Event) -> bytes:
    return (json.dumps(event, ensure_ascii=False) + "\n").encode()


def ndjson_response(work: Callable[[Emit], None], executor: Executor | None) -> StreamingResponse:
    """`work(emit)` をワーカースレッドで動かし、`emit` されたイベントを NDJSON で流す。

    `work` が例外を投げたら `{"type": "error", "message": ...}` を流して終える。
    受け手が接続を切ると、次の `emit` が `StreamCancelledError` を投げて処理を止める。
    """

    async def body() -> AsyncIterator[bytes]:
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        cancelled = threading.Event()

        def put(item: bytes | None) -> None:
            try:
                loop.call_soon_threadsafe(queue.put_nowait, item)
            except RuntimeError as error:
                # イベントループがもう閉じている
                raise StreamCancelledError from error

        def emit(event: Event) -> None:
            if cancelled.is_set():
                raise StreamCancelledError
            put(encode_event(event))

        def run() -> None:
            try:
                work(emit)
            except StreamCancelledError:
                logger.info("受け手が接続を切ったので、処理をやめました")
            except Exception as error:
                if not isinstance(error, EngineError):
                    logger.exception("ストリームの途中で失敗しました")
                with contextlib.suppress(StreamCancelledError):
                    put(encode_event({"type": "error", "message": describe(error)}))
            finally:
                with contextlib.suppress(StreamCancelledError):
                    put(None)

        # 終わりを待たない。受け手が切ったときは、`cancelled` で止まるのに任せる
        _ = loop.run_in_executor(executor, run)
        try:
            while (item := await queue.get()) is not None:
                yield item
        finally:
            cancelled.set()

    return StreamingResponse(body(), media_type=NDJSON_MEDIA_TYPE)
