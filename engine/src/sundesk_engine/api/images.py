"""フェーズ 5: 画像生成。生成は mflux で行う。"""

import secrets
import time
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from sundesk_engine.engine import EngineDep
from sundesk_engine.errors import BadRequestError, NotFoundError
from sundesk_engine.images.catalog import IMAGE_MODELS, find_image_model
from sundesk_engine.streaming import Emit, ndjson_response, run_blocking

router = APIRouter(prefix="/images")

QUANTIZE_CHOICES = (3, 4, 5, 6, 8)
SIZE_MULTIPLE = 16


class ImageSize(BaseModel):
    width: int
    height: int


class ImageModelOut(BaseModel):
    id: str
    name: str
    repo: str
    downloaded: bool
    default_steps: int
    default_size: ImageSize


class ImageModelsResponse(BaseModel):
    models: list[ImageModelOut]


class GenerateRequest(BaseModel):
    model: str
    prompt: str = Field(min_length=1)
    width: int = Field(default=1024, ge=256, le=2048)
    height: int = Field(default=1024, ge=256, le=2048)
    steps: int | None = Field(default=None, ge=1, le=100)
    seed: int | None = Field(default=None, ge=0, lt=2**32)
    quantize: int | None = 4
    output_path: str


@router.get("/models")
async def get_image_models(engine: EngineDep) -> ImageModelsResponse:
    def work() -> ImageModelsResponse:
        return ImageModelsResponse(
            models=[
                ImageModelOut(
                    id=spec.id,
                    name=spec.name,
                    repo=spec.repo,
                    downloaded=engine.hub.is_cached(spec.repo, spec.required_files),
                    default_steps=spec.default_steps,
                    default_size=ImageSize(width=spec.default_width, height=spec.default_height),
                )
                for spec in IMAGE_MODELS
            ]
        )

    return await run_blocking(None, work)


@router.post("/generate")
async def post_generate(request: GenerateRequest, engine: EngineDep) -> StreamingResponse:
    spec = find_image_model(request.model)
    if spec is None:
        raise NotFoundError(f"画像モデルが見つかりません: {request.model}")
    if request.quantize is not None and request.quantize not in QUANTIZE_CHOICES:
        raise BadRequestError(f"quantize は {QUANTIZE_CHOICES} のどれかか null にしてください")
    if request.width % SIZE_MULTIPLE or request.height % SIZE_MULTIPLE:
        raise BadRequestError(f"幅と高さは {SIZE_MULTIPLE} の倍数にしてください")
    output_path = Path(request.output_path)
    if not output_path.is_absolute():
        raise BadRequestError(f"output_path は絶対パスで指定してください: {request.output_path}")
    if not engine.hub.is_cached(spec.repo, spec.required_files):
        raise NotFoundError(
            f"画像モデルが手元にありません。先に {spec.repo} をダウンロードしてください"
        )
    steps = request.steps or spec.default_steps
    seed = request.seed if request.seed is not None else secrets.randbelow(2**32)

    def work(emit: Emit) -> None:
        loaded = engine.models.image(
            spec,
            request.quantize,
            on_loading=lambda: emit({"type": "loading", "model": spec.id}),
        )
        started = time.perf_counter()
        loaded.generator.generate(
            prompt=request.prompt,
            width=request.width,
            height=request.height,
            steps=steps,
            seed=seed,
            output_path=output_path,
            on_step=lambda step, total: emit({"type": "progress", "step": step, "total": total}),
        )
        emit(
            {
                "type": "done",
                "path": str(output_path),
                "seed": seed,
                "seconds": round(time.perf_counter() - started, 2),
            }
        )

    return ndjson_response(work, engine.mlx_executor)
