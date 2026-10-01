"""LoRA の学習（NDJSON）。"""

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from sundesk_engine.engine import EngineDep
from sundesk_engine.errors import BadRequestError
from sundesk_engine.lora.train import LoraSettings, train_lora
from sundesk_engine.streaming import Emit, ndjson_response

router = APIRouter(prefix="/lora")


class TrainRequest(BaseModel):
    model: str
    texts: list[str] = Field(min_length=1)
    adapter_path: str
    iterations: int = Field(default=200, ge=1, le=100000)
    rank: int = Field(default=8, ge=1, le=256)
    learning_rate: float = Field(default=1e-5, gt=0.0, le=1.0)
    batch_size: int = Field(default=1, ge=1, le=64)
    max_seq_length: int = Field(default=1024, ge=16, le=32768)
    num_layers: int = Field(default=8, ge=-1)
    """LoRA を付ける層の数（後ろから数える）。-1 ならすべて"""


@router.post("/train")
async def post_train(request: TrainRequest, engine: EngineDep) -> StreamingResponse:
    adapter_path = Path(request.adapter_path)
    if not adapter_path.is_absolute():
        raise BadRequestError(f"adapter_path は絶対パスで指定してください: {request.adapter_path}")
    engine.hub.resolve(request.model)
    settings = LoraSettings(
        model_id=request.model,
        texts=request.texts,
        adapter_path=adapter_path,
        iterations=request.iterations,
        rank=request.rank,
        learning_rate=request.learning_rate,
        batch_size=request.batch_size,
        max_seq_length=request.max_seq_length,
        num_layers=request.num_layers,
    )

    def work(emit: Emit) -> None:
        # 学習はモデルを書き換えるので、アダプタなしで読み直してから使い、終わったら捨てる
        engine.models.discard_llm()
        llm = engine.models.llm(
            request.model,
            None,
            on_loading=lambda: emit({"type": "loading", "model": request.model}),
        )
        try:
            train_lora(llm.model, llm.tokenizer, settings, emit)
        finally:
            engine.models.discard_llm()

    return ndjson_response(work, engine.mlx_executor)
