"""エンジンの部品をまとめたもの。テストでは部品を偽物に差し替えて作る。"""

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Annotated, cast

from fastapi import Depends, Request

from sundesk_engine.images.catalog import IMAGE_MODELS
from sundesk_engine.runtime.hub import Hub, HuggingFaceHub, models_dir_from_env
from sundesk_engine.runtime.manager import ModelManager
from sundesk_engine.scratch.session import ScratchSessions


def _mlx_executor() -> ThreadPoolExecutor:
    return ThreadPoolExecutor(max_workers=1, thread_name_prefix="mlx")


@dataclass
class Engine:
    hub: Hub
    models: ModelManager
    mlx_executor: ThreadPoolExecutor = field(default_factory=_mlx_executor)
    """LLM と画像生成の計算は、すべてこの 1 本のスレッドで順番に行う"""
    scratch: ScratchSessions = field(default_factory=ScratchSessions)
    """Python のスクラッチの、セッションごとの変数"""

    @classmethod
    def create_default(cls) -> "Engine":
        """本物の部品で作る。重いライブラリは、使うときまで読み込まない。"""
        from sundesk_engine.images.mflux_backend import MfluxBackend
        from sundesk_engine.runtime.embedding import SentenceTransformerBackend
        from sundesk_engine.runtime.mlx_backend import MlxLmBackend

        hub = HuggingFaceHub(
            image_repos=[spec.repo for spec in IMAGE_MODELS], models_dir=models_dir_from_env()
        )
        models = ModelManager(
            hub=hub,
            llm_backend=MlxLmBackend(),
            image_backend=MfluxBackend(),
            embedding_backend=SentenceTransformerBackend(),
        )
        return cls(hub=hub, models=models)

    def shutdown(self) -> None:
        self.mlx_executor.shutdown(wait=False, cancel_futures=True)


def get_engine(request: Request) -> Engine:
    return cast(Engine, request.app.state.engine)


EngineDep = Annotated[Engine, Depends(get_engine)]
