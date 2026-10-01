"""Python のスクラッチ。エンジンの中で、利用者の書いた Python を動かす。

手元の Mac の上で、自分の書いたコードを動かすためのもの。エンジンは 127.0.0.1 とトークンでしか
受け付けない（docs/adr/0006 を参照）。
"""

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from sundesk_engine.engine import EngineDep
from sundesk_engine.errors import BadRequestError, EngineError
from sundesk_engine.runtime.manager import LoadedLLM, check_adapter
from sundesk_engine.scratch.session import Interrupter, run_cell
from sundesk_engine.streaming import Emit, ndjson_response, run_blocking

router = APIRouter(prefix="/scratch")


class RunRequest(BaseModel):
    session: str = Field(min_length=1, max_length=256)
    code: str
    model: str | None = None
    adapter: str | None = None


class ResetRequest(BaseModel):
    session: str = Field(min_length=1, max_length=256)


class ResetResponse(BaseModel):
    reset: bool


@router.post("/run")
async def post_run(request: RunRequest, engine: EngineDep) -> StreamingResponse:
    if request.adapter and not request.model:
        raise BadRequestError("adapter を使うときは model も指定してください")
    if request.model:
        engine.hub.resolve(request.model)
    if request.adapter:
        check_adapter(request.adapter)
    interrupter = Interrupter()

    def work(emit: Emit) -> None:
        session = engine.scratch.session(request.session)
        llm: LoadedLLM | None = None
        if request.model:
            try:
                llm = engine.models.llm(request.model, request.adapter)
            except EngineError as error:
                emit({"type": "error", "message": error.detail, "traceback": ""})
                return
        run_cell(session, request.code, llm, emit, interrupter)

    return ndjson_response(work, engine.mlx_executor, on_cancel=interrupter.interrupt)


@router.post("/reset")
async def post_reset(request: ResetRequest, engine: EngineDep) -> ResetResponse:
    engine.scratch.reset(request.session)
    # 消した変数が持っていた配列のメモリを返す
    await run_blocking(None, engine.models.release)
    return ResetResponse(reset=True)
