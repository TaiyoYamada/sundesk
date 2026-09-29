"""モデルを載せたり捨てたりする係。メモリの使い方の決まりをここで守る。

- 大きいモデル（LLM か画像生成）は、同時に 1 つだけ載せる
- 埋め込みモデルは小さいので、別枠で載せたままにする
- LoRA のアダプタは、LLM を載せるときに合わせて読む（アダプタが変われば載せ直す）

読み込みの処理（backend）は差し替えられるので、テストでは偽物を使う。
LLM と画像のモデルは、MLX 用のワーカースレッド 1 本からだけ触る。
"""

import gc
import sys
import threading
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal, Protocol

import numpy as np
from numpy.typing import NDArray

from sundesk_engine.errors import NotFoundError
from sundesk_engine.images.catalog import ImageModelSpec
from sundesk_engine.paths import confined_path
from sundesk_engine.runtime.hub import Hub

DEFAULT_EMBEDDING_MODEL = "cl-nagoya/ruri-v3-130m"

type UnloadKind = Literal["llm", "image", "embedding", "all"]


class LLMBackend(Protocol):
    def load(self, path: Path, adapter: Path | None) -> tuple[Any, Any]:
        """(モデル, トークナイザ) を返す。トークナイザは mlx-lm の `TokenizerWrapper`。"""
        ...

    def load_tokenizer(self, path: Path) -> Any: ...


class ImageGenerator(Protocol):
    def generate(
        self,
        *,
        prompt: str,
        width: int,
        height: int,
        steps: int,
        seed: int,
        output_path: Path,
        on_step: Callable[[int, int], None],
    ) -> None:
        """画像を作って `output_path` に保存する。1 段進むたびに `on_step(step, total)` を呼ぶ。"""
        ...


class ImageBackend(Protocol):
    def load(self, spec: ImageModelSpec, path: Path, quantize: int | None) -> ImageGenerator: ...


class Embedder(Protocol):
    @property
    def dimension(self) -> int: ...

    def encode(self, texts: Sequence[str]) -> NDArray[np.float32]:
        """長さ 1 に正規化したベクトルを、行ごとに返す。"""
        ...


class EmbeddingBackend(Protocol):
    def load(self, path: Path) -> Embedder: ...


@dataclass
class LoadedLLM:
    model_id: str
    adapter: str | None
    model: Any
    tokenizer: Any


@dataclass
class LoadedImage:
    model_id: str
    repo: str
    quantize: int | None
    generator: ImageGenerator


@dataclass
class LoadedEmbedder:
    model_id: str
    embedder: Embedder


def release_memory() -> None:
    """捨てたモデルのメモリを OS に返す。"""
    gc.collect()
    if "mlx.core" in sys.modules:
        import mlx.core as mx

        mx.clear_cache()
    if "torch" in sys.modules:
        import torch

        if torch.backends.mps.is_available():
            torch.mps.empty_cache()


def check_adapter(adapter: str) -> Path:
    path = Path(confined_path(adapter, "アダプタ"))
    if (
        not (path / "adapter_config.json").is_file()
        or not (path / "adapters.safetensors").is_file()
    ):
        raise NotFoundError(f"アダプタが見つかりません: {adapter}")
    return path


class ModelManager:
    def __init__(
        self,
        hub: Hub,
        llm_backend: LLMBackend,
        image_backend: ImageBackend,
        embedding_backend: EmbeddingBackend,
        release: Callable[[], None] = release_memory,
    ) -> None:
        self.hub = hub
        self._llm_backend = llm_backend
        self._image_backend = image_backend
        self._embedding_backend = embedding_backend
        self._release = release
        self._lock = threading.RLock()
        self._embedding_lock = threading.Lock()
        self._llm: LoadedLLM | None = None
        self._image: LoadedImage | None = None
        self._embedder: LoadedEmbedder | None = None
        self._tokenizer: tuple[str, Any] | None = None

    # MARK: - LLM

    def llm(
        self,
        model_id: str,
        adapter: str | None = None,
        on_loading: Callable[[], None] | None = None,
    ) -> LoadedLLM:
        """LLM を返す。載っていなければ、他の大きいモデルを捨ててから載せる。"""
        with self._lock:
            path = self.hub.resolve(model_id)
            adapter_path = check_adapter(adapter) if adapter else None
            current = self._llm
            if current and current.model_id == model_id and current.adapter == adapter:
                return current
            self._drop_large()
            if on_loading:
                on_loading()
            model, tokenizer = self._llm_backend.load(path, adapter_path)
            self._llm = LoadedLLM(model_id, adapter, model, tokenizer)
            return self._llm

    def tokenizer(self, model_id: str) -> Any:
        """トークナイザだけを返す。LLM が載っていればそれを使い、なければ軽く読む。"""
        with self._lock:
            if self._llm and self._llm.model_id == model_id:
                return self._llm.tokenizer
            if self._tokenizer and self._tokenizer[0] == model_id:
                return self._tokenizer[1]
            tokenizer = self._llm_backend.load_tokenizer(self.hub.resolve(model_id))
            self._tokenizer = (model_id, tokenizer)
            return tokenizer

    def discard_llm(self) -> None:
        """学習などで中身を書き換えた LLM を捨てる。"""
        with self._lock:
            if self._llm is not None:
                self._llm = None
                self._release()

    # MARK: - 画像

    def image(
        self,
        spec: ImageModelSpec,
        quantize: int | None,
        on_loading: Callable[[], None] | None = None,
    ) -> LoadedImage:
        with self._lock:
            path = self.hub.resolve(spec.repo)
            current = self._image
            if current and current.model_id == spec.id and current.quantize == quantize:
                return current
            self._drop_large()
            if on_loading:
                on_loading()
            generator = self._image_backend.load(spec, path, quantize)
            self._image = LoadedImage(spec.id, spec.repo, quantize, generator)
            return self._image

    # MARK: - 埋め込み

    def embedder(self, model_id: str = DEFAULT_EMBEDDING_MODEL) -> LoadedEmbedder:
        with self._embedding_lock:
            current = self._embedder
            if current and current.model_id == model_id:
                return current
            path = self.hub.resolve(model_id)
            self._embedder = None
            loaded = LoadedEmbedder(model_id, self._embedding_backend.load(path))
            self._embedder = loaded
            return loaded

    def embed(
        self, texts: Sequence[str], model_id: str = DEFAULT_EMBEDDING_MODEL
    ) -> NDArray[np.float32]:
        """埋め込みは 1 度に 1 つずつ計算する（torch のモデルを複数のスレッドから触らない）。"""
        loaded = self.embedder(model_id)
        with self._embedding_lock:
            return loaded.embedder.encode(texts)

    # MARK: - 状態

    def loaded(self) -> dict[str, str | None]:
        # 載せている最中でも待たずに答えられるよう、ロックは取らない（参照の読み出しは不可分）
        llm, image, embedder = self._llm, self._image, self._embedder
        return {
            "llm": llm.model_id if llm else None,
            "image": image.model_id if image else None,
            "embedding": embedder.model_id if embedder else None,
            "adapter": llm.adapter if llm else None,
        }

    def unload(self, kind: UnloadKind) -> list[str]:
        """指定した種類のモデルを捨てて、捨てたモデルの ID を返す。"""
        unloaded: list[str] = []
        with self._lock:
            if kind in ("llm", "all") and self._llm is not None:
                unloaded.append(self._llm.model_id)
                self._llm = None
            if kind in ("image", "all") and self._image is not None:
                unloaded.append(self._image.model_id)
                self._image = None
            if kind == "all":
                self._tokenizer = None
        if kind in ("embedding", "all"):
            with self._embedding_lock:
                if self._embedder is not None:
                    unloaded.append(self._embedder.model_id)
                    self._embedder = None
        if unloaded:
            self._release()
        return unloaded

    def make_room(self) -> None:
        """モデルを作る処理（量子化や蒸留）の前に、載せている大きいモデルを捨てる。

        作る処理が読むモデルは、この係の外で持ち、終わったら `release` で片付ける。
        """
        with self._lock:
            self._drop_large()
            self._tokenizer = None

    def release(self) -> None:
        """捨てたモデルのメモリを返す。"""
        self._release()

    def forget(self, model_id: str) -> list[str]:
        """消すモデル（Hugging Face の ID）が載っていれば捨てる。"""
        with self._lock:
            kinds: list[UnloadKind] = []
            if self._llm is not None and self._llm.model_id == model_id:
                kinds.append("llm")
            if self._image is not None and self._image.repo == model_id:
                kinds.append("image")
            if self._tokenizer and self._tokenizer[0] == model_id:
                self._tokenizer = None
        with self._embedding_lock:
            if self._embedder is not None and self._embedder.model_id == model_id:
                kinds.append("embedding")
        unloaded: list[str] = []
        for kind in kinds:
            unloaded.extend(self.unload(kind))
        return unloaded

    def _drop_large(self) -> None:
        if self._llm is None and self._image is None:
            return
        self._llm = None
        self._image = None
        self._release()
