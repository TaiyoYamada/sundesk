"""フェーズ 2: 知識グラフ。"""

import numpy as np
from fastapi import APIRouter
from numpy.typing import NDArray

from sundesk_engine.engine import EngineDep
from sundesk_engine.graph.builder import build_graph
from sundesk_engine.graph.schemas import BuildRequest, BuildResponse
from sundesk_engine.runtime.embedding import TOPIC_PREFIX
from sundesk_engine.runtime.manager import DEFAULT_EMBEDDING_MODEL
from sundesk_engine.streaming import run_blocking

router = APIRouter()


@router.post("/graph/build")
async def post_graph_build(request: BuildRequest, engine: EngineDep) -> BuildResponse:
    model_id = request.options.embedding_model or DEFAULT_EMBEDDING_MODEL
    if request.options.similarity:
        # 埋め込みモデルがなければ、重い解析を始める前に 404 にする
        engine.hub.resolve(model_id)

    def embed(texts: list[str]) -> NDArray[np.float32]:
        return engine.models.embed([TOPIC_PREFIX + text for text in texts], model_id)

    # 形態素解析は CPU を長く使うので、イベントループの外で行う
    return await run_blocking(None, lambda: build_graph(request, embed))
