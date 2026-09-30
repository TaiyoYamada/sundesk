"""steering。残差ストリームにベクトルを足して、生成を曲げる。"""

from fastapi import APIRouter
from pydantic import BaseModel, Field

from sundesk_engine.api.lab import check_request
from sundesk_engine.engine import EngineDep
from sundesk_engine.lab import service
from sundesk_engine.streaming import run_blocking

router = APIRouter(prefix="/steering")


class VectorRequest(BaseModel):
    model: str
    layer: int
    positive: list[str] = Field(min_length=1, max_length=256)
    negative: list[str] = Field(min_length=1, max_length=256)
    chat_template: bool = False
    adapter: str | None = None


class GenerateRequest(BaseModel):
    model: str
    prompt: str
    chat_template: bool = False
    layer: int
    vector: list[float] = Field(min_length=1)
    strength: float = 1.0
    max_tokens: int = Field(default=128, ge=1, le=4096)
    temperature: float = Field(default=0.7, ge=0.0, le=10.0)
    seed: int | None = None
    adapter: str | None = None


@router.post("/vector")
async def post_vector(request: VectorRequest, engine: EngineDep) -> service.SteeringVectorResponse:
    check_request(engine, request.model, request.adapter)

    def work() -> service.SteeringVectorResponse:
        llm = engine.models.llm(request.model, request.adapter)
        return service.steering_vector(
            llm.model,
            llm.tokenizer,
            request.layer,
            request.positive,
            request.negative,
            request.chat_template,
        )

    return await run_blocking(engine.mlx_executor, work)


@router.post("/generate")
async def post_generate(
    request: GenerateRequest, engine: EngineDep
) -> service.SteeringGenerateResponse:
    check_request(engine, request.model, request.adapter)

    def work() -> service.SteeringGenerateResponse:
        llm = engine.models.llm(request.model, request.adapter)
        return service.steering_generate(
            llm.model,
            llm.tokenizer,
            prompt=request.prompt,
            chat_template=request.chat_template,
            layer=request.layer,
            vector=request.vector,
            strength=request.strength,
            max_tokens=request.max_tokens,
            temperature=request.temperature,
            seed=request.seed,
        )

    return await run_blocking(engine.mlx_executor, work)
