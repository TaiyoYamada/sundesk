"""埋め込み。"""

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from sundesk_engine.engine import EngineDep
from sundesk_engine.runtime.embedding import DOCUMENT_PREFIX, QUERY_PREFIX
from sundesk_engine.runtime.manager import DEFAULT_EMBEDDING_MODEL
from sundesk_engine.streaming import run_blocking

router = APIRouter()


class EmbeddingsRequest(BaseModel):
    texts: list[str] = Field(max_length=4096)
    kind: Literal["query", "document"]
    model: str = DEFAULT_EMBEDDING_MODEL


class EmbeddingsResponse(BaseModel):
    model: str
    dimension: int
    vectors: list[list[float]]


@router.post("/embeddings")
async def post_embeddings(request: EmbeddingsRequest, engine: EngineDep) -> EmbeddingsResponse:
    prefix = QUERY_PREFIX if request.kind == "query" else DOCUMENT_PREFIX
    engine.hub.resolve(request.model)

    def work() -> EmbeddingsResponse:
        loaded = engine.models.embedder(request.model)
        vectors = engine.models.embed([prefix + text for text in request.texts], request.model)
        return EmbeddingsResponse(
            model=request.model,
            dimension=loaded.embedder.dimension,
            vectors=vectors.astype(float).tolist(),
        )

    return await run_blocking(None, work)
