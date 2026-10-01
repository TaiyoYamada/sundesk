"""LLM 実験室。

どれも `model` と `prompt` を取る。`chat_template` が true なら、`prompt` をユーザーの発言として
チャットの形に包んでから使う。プロンプトは 512 トークンまで。
`adapter`（省略可）を渡すと、LoRA のアダプタを付けたモデルを覗く。
"""

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from sundesk_engine.engine import Engine, EngineDep
from sundesk_engine.lab import service
from sundesk_engine.lab.sampling import SamplingOptions
from sundesk_engine.runtime.manager import LoadedLLM, check_adapter
from sundesk_engine.streaming import Emit, ndjson_response, run_blocking

router = APIRouter(prefix="/lab")


class TokenizeRequest(BaseModel):
    model: str
    text: str


class PromptRequest(BaseModel):
    model: str
    prompt: str
    chat_template: bool = False
    adapter: str | None = None


class NextTokenRequest(PromptRequest):
    top_k: int = Field(default=20, ge=1, le=1000)
    temperature: float = Field(default=1.0, ge=0.0, le=10.0)


class GenerateRequest(PromptRequest):
    max_tokens: int = Field(default=128, ge=1, le=4096)
    temperature: float = Field(default=0.7, ge=0.0, le=10.0)
    top_p: float = Field(default=1.0, gt=0.0, le=1.0)
    top_k: int = Field(default=0, ge=0)
    seed: int | None = None
    alternatives: int = Field(default=5, ge=0, le=100)


class AttentionRequest(PromptRequest):
    layer: int = 0


class LogitLensRequest(PromptRequest):
    top_k: int = Field(default=3, ge=1, le=100)


def check_request(engine: Engine, model: str, adapter: str | None) -> None:
    """見つからないものは、重い処理を始める前に 404 にする。"""
    engine.hub.resolve(model)
    if adapter:
        check_adapter(adapter)


def load(engine: Engine, request: PromptRequest) -> LoadedLLM:
    return engine.models.llm(request.model, request.adapter)


@router.post("/tokenize")
async def post_tokenize(request: TokenizeRequest, engine: EngineDep) -> service.TokenizeResponse:
    check_request(engine, request.model, None)
    return await run_blocking(
        engine.mlx_executor,
        lambda: service.tokenize(engine.models.tokenizer(request.model), request.text),
    )


@router.post("/next-token")
async def post_next_token(
    request: NextTokenRequest, engine: EngineDep
) -> service.NextTokenResponse:
    check_request(engine, request.model, request.adapter)

    def work() -> service.NextTokenResponse:
        llm = load(engine, request)
        return service.next_token(
            llm.model,
            llm.tokenizer,
            request.prompt,
            request.chat_template,
            request.top_k,
            request.temperature,
        )

    return await run_blocking(engine.mlx_executor, work)


@router.post("/generate")
async def post_generate(request: GenerateRequest, engine: EngineDep) -> StreamingResponse:
    check_request(engine, request.model, request.adapter)

    def work(emit: Emit) -> None:
        llm = engine.models.llm(
            request.model,
            request.adapter,
            on_loading=lambda: emit({"type": "loading", "model": request.model}),
        )
        service.stream_generation(
            llm.model,
            llm.tokenizer,
            prompt=request.prompt,
            chat_template=request.chat_template,
            max_tokens=request.max_tokens,
            options=SamplingOptions(
                temperature=request.temperature, top_p=request.top_p, top_k=request.top_k
            ),
            seed=request.seed,
            alternatives=request.alternatives,
            emit=emit,
        )

    return ndjson_response(work, engine.mlx_executor)


@router.post("/attention")
async def post_attention(request: AttentionRequest, engine: EngineDep) -> service.AttentionResponse:
    check_request(engine, request.model, request.adapter)

    def work() -> service.AttentionResponse:
        llm = load(engine, request)
        return service.attention(
            llm.model, llm.tokenizer, request.prompt, request.chat_template, request.layer
        )

    return await run_blocking(engine.mlx_executor, work)


@router.post("/logit-lens")
async def post_logit_lens(
    request: LogitLensRequest, engine: EngineDep
) -> service.LogitLensResponse:
    check_request(engine, request.model, request.adapter)

    def work() -> service.LogitLensResponse:
        llm = load(engine, request)
        return service.logit_lens(
            llm.model, llm.tokenizer, request.prompt, request.chat_template, request.top_k
        )

    return await run_blocking(engine.mlx_executor, work)


@router.post("/activations")
async def post_activations(
    request: PromptRequest, engine: EngineDep
) -> service.ActivationsResponse:
    check_request(engine, request.model, request.adapter)

    def work() -> service.ActivationsResponse:
        llm = load(engine, request)
        return service.activations(llm.model, llm.tokenizer, request.prompt, request.chat_template)

    return await run_blocking(engine.mlx_executor, work)
