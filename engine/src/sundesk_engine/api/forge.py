"""フェーズ 7: 工房。モデルを量子化し、変換し、混ぜ、枝を刈り、蒸留し、比べる（どれも NDJSON）。

作る処理は、始める前に載せている大きいモデルを捨て、作業用のモデルを係の外で読む。
終わったら（失敗しても）作業用のモデルを手放し、メモリを返す。
見つからないモデルは 404、おかしな要求は 400 にして、流し始める前に返す。
"""

from collections.abc import Callable
from typing import Literal

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from sundesk_engine.engine import Engine, EngineDep
from sundesk_engine.errors import BadRequestError
from sundesk_engine.forge.convert import ConvertSettings, DType, convert_model
from sundesk_engine.forge.distill import DistillSettings, check_same_vocabulary, distill
from sundesk_engine.forge.evaluate import perplexity, samples
from sundesk_engine.forge.quantize import Override, QuantizeSettings, quantize_model
from sundesk_engine.forge.surgery import (
    HeadRef,
    MergeMethod,
    check_prune_request,
    check_same_structure,
    fuse_model,
    merge_models,
    prune_model,
)
from sundesk_engine.forge.workpiece import Source, check_output_dir
from sundesk_engine.runtime.hub import directory_size
from sundesk_engine.runtime.manager import check_adapter
from sundesk_engine.streaming import Emit, Event, ndjson_response, run_blocking

router = APIRouter(prefix="/forge")

type MixedRecipe = Literal["mixed_2_6", "mixed_3_4", "mixed_3_6", "mixed_4_6"]
"""mlx-lm の決まった配分（`forge.quantize.MIXED_RECIPES` と同じもの）"""


class OverrideIn(BaseModel):
    pattern: str = Field(min_length=1)
    bits: int | None


class QuantizeRequest(BaseModel):
    model: str
    output_dir: str
    method: Literal["affine", "simulated"] = "affine"
    bits: int = 4
    group_size: int = 64
    mixed: MixedRecipe | None = None
    overrides: list[OverrideIn] = Field(default_factory=list[OverrideIn])
    ternary: bool = False

    def settings(self) -> QuantizeSettings:
        settings = QuantizeSettings(
            method=self.method,
            bits=self.bits,
            group_size=self.group_size,
            mixed=self.mixed,
            overrides=tuple(Override(item.pattern, item.bits) for item in self.overrides),
            ternary=self.ternary,
        )
        settings.validate()
        return settings


class ConvertQuantize(BaseModel):
    bits: int = 4
    group_size: int = 64


class ConvertRequest(BaseModel):
    model: str
    output_dir: str
    dtype: DType = "bfloat16"
    quantize: ConvertQuantize | None = None


class FuseRequest(BaseModel):
    model: str
    adapter: str
    output_dir: str
    dequantize: bool = False


class MergeRequest(BaseModel):
    models: list[str] = Field(min_length=2, max_length=2)
    output_dir: str
    method: MergeMethod = "slerp"
    t: float = Field(default=0.5, ge=0.0, le=1.0)


class HeadIn(BaseModel):
    layer: int
    head: int = Field(ge=0)


class PruneRequest(BaseModel):
    model: str
    output_dir: str
    drop_layers: list[int] = Field(default_factory=list[int])
    drop_heads: list[HeadIn] = Field(default_factory=list[HeadIn])


class DistillRequest(BaseModel):
    teacher: str
    student: str
    texts: list[str] = Field(min_length=1)
    output_dir: str
    iterations: int = Field(default=200, ge=1, le=100_000)
    learning_rate: float = Field(default=1e-5, gt=0.0, le=1.0)
    temperature: float = Field(default=2.0, gt=0.0, le=100.0)
    alpha: float = Field(default=0.5, ge=0.0, le=1.0)
    max_seq_length: int = Field(default=512, ge=16, le=32768)
    batch_size: int = Field(default=1, ge=1, le=64)
    lora_rank: int | None = Field(default=8, ge=1, le=256)


class EvaluateModel(BaseModel):
    model: str
    adapter: str | None = None


class EvaluateRequest(BaseModel):
    models: list[EvaluateModel] = Field(min_length=1, max_length=16)
    texts: list[str] = Field(default_factory=list[str])
    prompts: list[str] = Field(default_factory=list[str])
    max_tokens: int = Field(default=64, ge=1, le=4096)
    seed: int = 0
    temperature: float = Field(default=0.7, ge=0.0, le=10.0)
    """生成の温度（約束の外の追加の項目。省けば 0.7）"""
    chat_template: bool = False
    """プロンプトをチャットの形に包むか（約束の外の追加の項目）"""


def _source(engine: Engine, model_id: str) -> Source:
    """見つからなければ 404。勝手にダウンロードはしない。"""
    return Source(model_id=model_id, path=engine.hub.resolve(model_id))


def _forge(engine: Engine, job: Callable[[Emit], Event]) -> StreamingResponse:
    """大きいモデルを捨ててから `job` を動かし、返ってきた `done` を流す。"""

    def work(emit: Emit) -> None:
        engine.models.make_room()
        try:
            emit(job(emit))
        finally:
            engine.models.release()

    return ndjson_response(work, engine.mlx_executor)


@router.post("/quantize")
async def post_quantize(request: QuantizeRequest, engine: EngineDep) -> StreamingResponse:
    settings = request.settings()
    output_dir = check_output_dir(request.output_dir)
    source = _source(engine, request.model)
    return _forge(engine, lambda emit: quantize_model(source, output_dir, settings, emit))


@router.post("/convert")
async def post_convert(request: ConvertRequest, engine: EngineDep) -> StreamingResponse:
    quantize = (
        QuantizeSettings(
            method="affine", bits=request.quantize.bits, group_size=request.quantize.group_size
        )
        if request.quantize
        else None
    )
    if quantize is not None:
        quantize.validate()
    settings = ConvertSettings(dtype=request.dtype, quantize=quantize)
    output_dir = check_output_dir(request.output_dir)
    source = _source(engine, request.model)
    return _forge(engine, lambda emit: convert_model(source, output_dir, settings, emit))


@router.post("/fuse")
async def post_fuse(request: FuseRequest, engine: EngineDep) -> StreamingResponse:
    output_dir = check_output_dir(request.output_dir)
    source = _source(engine, request.model)
    adapter = check_adapter(request.adapter)
    return _forge(
        engine,
        lambda emit: fuse_model(source, adapter, output_dir, request.dequantize, emit),
    )


@router.post("/merge")
async def post_merge(request: MergeRequest, engine: EngineDep) -> StreamingResponse:
    output_dir = check_output_dir(request.output_dir)
    first, second = (_source(engine, model_id) for model_id in request.models)
    check_same_structure(first.path, second.path)
    return _forge(
        engine,
        lambda emit: merge_models((first, second), output_dir, request.method, request.t, emit),
    )


@router.post("/prune")
async def post_prune(request: PruneRequest, engine: EngineDep) -> StreamingResponse:
    output_dir = check_output_dir(request.output_dir)
    source = _source(engine, request.model)
    heads = [HeadRef(layer=item.layer, head=item.head) for item in request.drop_heads]
    check_prune_request(source.path, request.drop_layers, heads)
    return _forge(
        engine,
        lambda emit: prune_model(source, output_dir, request.drop_layers, heads, emit),
    )


@router.post("/distill")
async def post_distill(request: DistillRequest, engine: EngineDep) -> StreamingResponse:
    output_dir = check_output_dir(request.output_dir)
    teacher = _source(engine, request.teacher)
    student = _source(engine, request.student)
    # トークナイザを読むのは少し時間がかかるので、イベントループの外で行う
    await run_blocking(None, lambda: check_same_vocabulary(teacher.path, student.path))
    settings = DistillSettings(
        texts=request.texts,
        iterations=request.iterations,
        learning_rate=request.learning_rate,
        temperature=request.temperature,
        alpha=request.alpha,
        max_seq_length=request.max_seq_length,
        batch_size=request.batch_size,
        lora_rank=request.lora_rank,
    )
    return _forge(engine, lambda emit: distill(teacher, student, output_dir, settings, emit))


@router.post("/evaluate")
async def post_evaluate(request: EvaluateRequest, engine: EngineDep) -> StreamingResponse:
    if not request.texts and not request.prompts:
        raise BadRequestError("texts か prompts のどちらかに、1 つ以上の文を入れてください")
    sizes: list[int] = []
    for entry in request.models:
        size = directory_size(engine.hub.resolve(entry.model))
        if entry.adapter:
            size += directory_size(check_adapter(entry.adapter))
        sizes.append(size)

    def measure(entry: EvaluateModel, size: int) -> Event:
        """1 つのモデルを載せて測る。関数を分けて、終わったらモデルへの参照が残らないようにする。"""
        import mlx.core as mx

        # 載せるところからのメモリの山を測るため、毎回いったん外してから載せる
        engine.models.make_room()
        mx.reset_peak_memory()
        llm = engine.models.llm(entry.model, entry.adapter)
        scored = perplexity(llm.model, llm.tokenizer, request.texts)
        generated = samples(
            llm.model,
            llm.tokenizer,
            request.prompts,
            max_tokens=request.max_tokens,
            temperature=request.temperature,
            seed=request.seed,
            chat_template=request.chat_template,
        )
        speed = (
            generated.tokens_per_second
            if request.prompts
            else (scored.tokens / scored.seconds if scored.seconds > 0 else 0.0)
        )
        return {
            "type": "result",
            "model": entry.model,
            "adapter": entry.adapter,
            "perplexity": None if scored.value is None else round(scored.value, 4),
            "tokens": scored.tokens,
            "seconds": round(scored.seconds, 3),
            "tokens_per_second": round(speed, 2),
            "size_bytes": size,
            "peak_memory_bytes": int(mx.get_peak_memory()),
            "samples": generated.texts,
        }

    def work(emit: Emit) -> None:
        for entry, size in zip(request.models, sizes, strict=True):
            emit({"type": "loading", "model": entry.model})
            emit(measure(entry, size))
        emit({"type": "done"})

    return ndjson_response(work, engine.mlx_executor)
