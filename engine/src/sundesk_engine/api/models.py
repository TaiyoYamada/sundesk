"""フェーズ 4: モデルの管理。"""

from typing import Literal

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from sundesk_engine.engine import EngineDep
from sundesk_engine.errors import NotFoundError
from sundesk_engine.images.catalog import find_image_repo
from sundesk_engine.runtime.hub import DEFAULT_IGNORE_PATTERNS, ModelKind, ModelSource
from sundesk_engine.streaming import Emit, ndjson_response, run_blocking

router = APIRouter()


class ModelOut(BaseModel):
    id: str
    kind: ModelKind
    size_bytes: int
    path: str
    name: str
    source: ModelSource


class ModelsResponse(BaseModel):
    models: list[ModelOut]


class DownloadRequest(BaseModel):
    id: str


class DeleteResponse(BaseModel):
    deleted: bool


class LoadedResponse(BaseModel):
    llm: str | None
    image: str | None
    embedding: str | None
    adapter: str | None


class UnloadRequest(BaseModel):
    kind: Literal["llm", "image", "embedding", "all"]


class UnloadResponse(BaseModel):
    unloaded: list[str]


@router.get("/models")
async def get_models(engine: EngineDep) -> ModelsResponse:
    models = await run_blocking(None, engine.hub.list_models)
    return ModelsResponse(
        models=[
            ModelOut(
                id=model.id,
                kind=model.kind,
                size_bytes=model.size_bytes,
                path=model.path,
                name=model.name,
                source=model.source,
            )
            for model in models
        ]
    )


@router.post("/models/download")
async def post_models_download(request: DownloadRequest, engine: EngineDep) -> StreamingResponse:
    image = find_image_repo(request.id)
    allow = list(image.download_patterns) if image else None
    ignore = None if image else DEFAULT_IGNORE_PATTERNS
    # 存在しないモデルなどは、流し始める前に 4xx にする
    plan = await run_blocking(None, lambda: engine.hub.plan_download(request.id, allow, ignore))

    def work(emit: Emit) -> None:
        total = plan.total_bytes

        def progress(downloaded: int) -> None:
            emit({"type": "progress", "downloaded_bytes": downloaded, "total_bytes": total})

        path = engine.hub.download(plan, progress)
        emit({"type": "done", "path": str(path)})

    return ndjson_response(work, None)


@router.get("/models/loaded")
async def get_models_loaded(engine: EngineDep) -> LoadedResponse:
    state = engine.models.loaded()
    return LoadedResponse(
        llm=state["llm"],
        image=state["image"],
        embedding=state["embedding"],
        adapter=state["adapter"],
    )


@router.post("/models/unload")
async def post_models_unload(request: UnloadRequest, engine: EngineDep) -> UnloadResponse:
    # 計算の途中で捨てないように、MLX のスレッドで順番を待つ
    unloaded = await run_blocking(engine.mlx_executor, lambda: engine.models.unload(request.kind))
    return UnloadResponse(unloaded=unloaded)


@router.delete("/models/{model_id:path}")
async def delete_model(model_id: str, engine: EngineDep) -> DeleteResponse:
    # 消せるのは Hugging Face のキャッシュのモデルだけ。手元のフォルダはアプリが消す
    def work() -> bool:
        engine.models.forget(model_id)
        return engine.hub.delete(model_id)

    deleted = await run_blocking(engine.mlx_executor, work)
    if not deleted:
        raise NotFoundError(f"モデルが手元にありません: {model_id}")
    return DeleteResponse(deleted=True)
