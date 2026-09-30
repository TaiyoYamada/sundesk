"""テストで使う偽物の部品。重いモデルの代わりに、小さなランダムの Qwen3 と BPE を使う。

本物の mlx-lm のモデルの形をしているので、実験室や LoRA のコードはそのまま動く。
"""

import hashlib
import json
import threading
from collections.abc import Callable, Sequence
from functools import cache
from importlib import import_module
from pathlib import Path
from typing import Any

import mlx.core as mx
import numpy as np
from httpx2 import Response
from numpy.typing import NDArray

from sundesk_engine.engine import Engine
from sundesk_engine.errors import NotFoundError
from sundesk_engine.images.catalog import ImageModelSpec
from sundesk_engine.runtime.hub import DownloadPlan, LocalModel, RemoteFile, validate_model_id
from sundesk_engine.runtime.manager import Embedder, ImageGenerator, ModelManager

LLM_ID = "test/tiny-llm"
EMBEDDING_ID = "cl-nagoya/ruri-v3-130m"
IMAGE_REPO = "Tongyi-MAI/Z-Image-Turbo"
HIDDEN_SIZE = 32
NUM_LAYERS = 2
NUM_HEADS = 4
EMBEDDING_DIMENSION = 8

_CORPUS = [
    "固有値とは線形変換で向きが変わらないベクトルの伸縮率である。",
    "行列分解は線形代数の道具です。固有値分解は行列分解の一種である。",
    "hello world, the quick brown fox jumps over the lazy dog.",
    "猫はかわいい。犬もかわいい。今日は晴れです。",
]
_CHAT_TEMPLATE = (
    "{% for m in messages %}<|im_start|>{{ m['role'] }}\n{{ m['content'] }}<|im_end|>\n"
    "{% endfor %}{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}"
)


@cache
def _hf_tokenizer(vocab_size: int = 400) -> Any:
    from transformers import PreTrainedTokenizerFast

    # tokenizers には型の情報がないので、モジュールを Any として読み込む
    library: Any = import_module("tokenizers")
    decoders, models = library.decoders, library.models
    pre_tokenizers, trainers = library.pre_tokenizers, library.trainers
    tokenizer: Any = library.Tokenizer(models.BPE())
    tokenizer.pre_tokenizer = pre_tokenizers.ByteLevel(add_prefix_space=False)
    tokenizer.decoder = decoders.ByteLevel()
    trainer: Any = trainers.BpeTrainer(
        vocab_size=vocab_size,
        special_tokens=["<|endoftext|>", "<|im_start|>", "<|im_end|>"],
        initial_alphabet=pre_tokenizers.ByteLevel.alphabet(),
    )
    tokenizer.train_from_iterator(_CORPUS * 10, trainer)
    hf: Any = PreTrainedTokenizerFast(
        tokenizer_object=tokenizer, eos_token="<|im_end|>", pad_token="<|endoftext|>"
    )
    hf.chat_template = _CHAT_TEMPLATE
    return hf


def tiny_tokenizer(vocab_size: int = 400) -> Any:
    from mlx_lm.tokenizer_utils import BPEStreamingDetokenizer, TokenizerWrapper

    detokenizer: Any = BPEStreamingDetokenizer
    return TokenizerWrapper(_hf_tokenizer(vocab_size), detokenizer_class=detokenizer)


def tiny_config(
    *,
    hidden_size: int = HIDDEN_SIZE,
    num_layers: int = NUM_LAYERS,
    head_dim: int = 8,
    intermediate_size: int = 64,
    vocab_size: int = 400,
) -> dict[str, Any]:
    return {
        "model_type": "qwen3",
        "architectures": ["Qwen3ForCausalLM"],
        "hidden_size": hidden_size,
        "num_hidden_layers": num_layers,
        "intermediate_size": intermediate_size,
        "num_attention_heads": NUM_HEADS,
        "rms_norm_eps": 1e-6,
        "vocab_size": len(_hf_tokenizer(vocab_size)),
        "num_key_value_heads": 2,
        "max_position_embeddings": 1024,
        "rope_theta": 10000.0,
        "head_dim": head_dim,
        "tie_word_embeddings": True,
    }


def tiny_model(seed: int = 0, config: dict[str, Any] | None = None) -> Any:
    from mlx_lm.models import qwen3

    mx.random.seed(seed)
    values = dict(config or tiny_config())
    values.pop("architectures", None)
    arguments: Any = qwen3.ModelArgs
    model: Any = qwen3.Model(arguments.from_dict(values))
    mx.eval(model.parameters())  # pyright: ignore[reportUnknownMemberType]
    model.eval()
    return model


def write_tiny_model(
    path: Path,
    *,
    seed: int = 0,
    num_layers: int = NUM_LAYERS,
    head_dim: int = 16,
    vocab_size: int = 400,
) -> Path:
    """小さなランダムの Qwen3 を、mlx-lm が読めるフォルダとして書く。

    量子化のグループ（32、64）で割り切れるよう、ふだんの偽物より少し大きくする。
    """
    utils: Any = import_module("mlx_lm.utils")
    config = tiny_config(
        hidden_size=64,
        num_layers=num_layers,
        head_dim=head_dim,
        intermediate_size=128,
        vocab_size=vocab_size,
    )
    model = tiny_model(seed, config)
    path.mkdir(parents=True, exist_ok=True)
    utils.save_model(path, model)
    utils.save_config(dict(config), config_path=path / "config.json")
    tiny_tokenizer(vocab_size).save_pretrained(str(path))
    return path


class FakeLLMBackend:
    def __init__(self) -> None:
        self.loads: list[tuple[Path, Path | None]] = []

    def load(self, path: Path, adapter: Path | None) -> tuple[Any, Any]:
        self.loads.append((path, adapter))
        if (path / "config.json").is_file():
            # 本物のフォルダ（工房で作ったものなど）は、mlx-lm で読む
            from sundesk_engine.runtime.mlx_backend import MlxLmBackend

            return MlxLmBackend().load(path, adapter)
        model = tiny_model()
        if adapter is not None:
            from mlx_lm.tuner.utils import load_adapters

            load_adapters(model, str(adapter))
            model.eval()
        return model, tiny_tokenizer()

    def load_tokenizer(self, path: Path) -> Any:
        del path
        return tiny_tokenizer()


class FakeImageGenerator:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail

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
        for step in range(1, steps + 1):
            on_step(step, steps)
            if self.fail and step == 2:
                raise RuntimeError("生成に失敗しました")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(f"{prompt}:{width}x{height}:{seed}".encode())


class FakeImageBackend:
    def __init__(self) -> None:
        self.loads: list[tuple[str, int | None]] = []
        self.fail = False

    def load(self, spec: ImageModelSpec, path: Path, quantize: int | None) -> ImageGenerator:
        del path
        self.loads.append((spec.id, quantize))
        return FakeImageGenerator(fail=self.fail)


class FakeEmbedder:
    @property
    def dimension(self) -> int:
        return EMBEDDING_DIMENSION

    def encode(self, texts: Sequence[str]) -> NDArray[np.float32]:
        rows: list[NDArray[np.float32]] = []
        for text in texts:
            digest = hashlib.sha256(text.encode()).digest()
            vector = np.frombuffer(digest[: EMBEDDING_DIMENSION * 4], dtype=np.uint32)
            values = vector.astype(np.float32) / np.float32(2**32) - np.float32(0.5)
            rows.append(values / np.linalg.norm(values))
        return np.stack(rows).astype(np.float32)


class FakeEmbeddingBackend:
    def __init__(self) -> None:
        self.loads = 0

    def load(self, path: Path) -> Embedder:
        del path
        self.loads += 1
        return FakeEmbedder()


class FakeHub:
    """手元のモデルの一覧を、メモリの上だけで持つ。"""

    def __init__(self, root: Path, models: Sequence[str] = ()) -> None:
        self.root = root
        self.models: dict[str, str] = {}
        self.remote: dict[str, list[RemoteFile]] = {
            "test/remote": [RemoteFile("config.json", 10, "a"), RemoteFile("model.bin", 90, "b")]
        }
        self._lock = threading.Lock()
        for model_id in models:
            self.add(model_id)

    def add(self, model_id: str, kind: str = "llm") -> Path:
        path = self.root / model_id.replace("/", "--")
        path.mkdir(parents=True, exist_ok=True)
        self.models[model_id] = kind
        return path

    def resolve(self, model_id: str) -> Path:
        local = Path(model_id)
        if local.is_absolute():
            if local.is_dir():
                return local
            raise NotFoundError(f"モデルのディレクトリが見つかりません: {model_id}")
        if model_id not in self.models:
            raise NotFoundError(f"モデルが手元にありません: {model_id}")
        return self.root / model_id.replace("/", "--")

    def is_cached(self, model_id: str, required: Sequence[str] = ()) -> bool:
        del required
        return model_id in self.models

    def add_disk_model(self, model_id: str, **options: Any) -> Path:
        """本物のファイルを持つ小さなモデルを加える（工房のテスト用）。"""
        return write_tiny_model(self.add(model_id), **options)

    def list_models(self) -> list[LocalModel]:
        return [
            LocalModel(
                id=model_id,
                kind=kind,  # pyright: ignore[reportArgumentType]
                size_bytes=123,
                path=str(self.resolve(model_id)),
                name=model_id.split("/", 1)[-1],
                source="hub",
            )
            for model_id, kind in sorted(self.models.items())
        ]

    def delete(self, model_id: str) -> bool:
        return self.models.pop(model_id, None) is not None

    def plan_download(
        self,
        model_id: str,
        allow_patterns: Sequence[str] | None,
        ignore_patterns: Sequence[str] | None,
    ) -> DownloadPlan:
        validate_model_id(model_id)
        if model_id not in self.remote:
            raise NotFoundError(f"Hugging Face にモデルが見つかりません: {model_id}")
        return DownloadPlan(
            model_id=model_id,
            revision="main",
            files=tuple(self.remote[model_id]),
            allow_patterns=tuple(allow_patterns) if allow_patterns else None,
            ignore_patterns=tuple(ignore_patterns) if ignore_patterns else None,
        )

    def download(self, plan: DownloadPlan, on_progress: Callable[[int], None]) -> Path:
        done = 0
        for file in plan.files:
            done += file.size
            on_progress(done)
        return self.add(plan.model_id)


def make_engine(root: Path) -> tuple[Engine, FakeHub, FakeLLMBackend, FakeImageBackend]:
    hub = FakeHub(root, [LLM_ID, EMBEDDING_ID])
    hub.add(IMAGE_REPO, "image")
    llm = FakeLLMBackend()
    image = FakeImageBackend()
    manager = ModelManager(
        hub=hub,
        llm_backend=llm,
        image_backend=image,
        embedding_backend=FakeEmbeddingBackend(),
        release=lambda: None,
    )
    return Engine(hub=hub, models=manager), hub, llm, image


def ndjson(response: Response) -> list[dict[str, Any]]:
    """NDJSON の応答を、イベントの列にする。"""
    assert response.status_code == 200, response.text
    assert response.headers["content-type"].startswith("application/x-ndjson")
    return [json.loads(line) for line in response.text.splitlines() if line]
