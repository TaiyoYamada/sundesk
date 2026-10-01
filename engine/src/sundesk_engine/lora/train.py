"""LoRA の学習。mlx-lm の tuner をそのまま使い、アダプタを mlx-lm が読める形で保存する。

保存するもの（`adapter_path` の中）:

- `adapter_config.json`: `fine_tune_type`、`num_layers`、`lora_parameters` など
- `adapters.safetensors`: 学習した重み
"""

import json
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any

import numpy as np

from sundesk_engine.errors import BadRequestError
from sundesk_engine.streaming import Emit

VALIDATION_RATIO = 0.1
LORA_SCALE = 20.0
STEPS_PER_REPORT = 10
STEPS_PER_EVAL = 50
VALIDATION_BATCHES = 25
SPLIT_SEED = 0


@dataclass(frozen=True)
class LoraSettings:
    model_id: str
    texts: list[str]
    adapter_path: Path
    iterations: int
    rank: int
    learning_rate: float
    batch_size: int
    max_seq_length: int
    num_layers: int


class TokenDataset:
    """トークン ID の列を、そのまま続きを書く学習（completion）の例として渡す。

    mlx-lm の `CacheDataset` が `process` を呼んで `(ID の列, プロンプトの長さ)` を受け取る。
    """

    def __init__(self, examples: list[list[int]]) -> None:
        self._examples = examples

    def process(self, example: list[int]) -> tuple[list[int], int]:
        return example, 0

    def __getitem__(self, index: int) -> list[int]:
        return self._examples[index]

    def __len__(self) -> int:
        return len(self._examples)


def build_examples(tokenizer: Any, texts: list[str], max_seq_length: int) -> list[list[int]]:
    """文章をトークンにし、`max_seq_length` ごとに区切る。文章の終わりには EOS を付ける。"""
    eos = getattr(tokenizer, "eos_token_id", None)
    examples: list[list[int]] = []
    for text in texts:
        if not text.strip():
            continue
        ids = [int(token) for token in tokenizer.encode(text)]
        if eos is not None and (not ids or ids[-1] != eos):
            ids.append(int(eos))
        for start in range(0, len(ids), max_seq_length):
            window = ids[start : start + max_seq_length]
            if len(window) >= 2:
                examples.append(window)
    return examples


def split_examples(
    examples: list[list[int]], batch_size: int
) -> tuple[list[list[int]], list[list[int]]]:
    """1 割を検証に回す。どちらもバッチの大きさ以上の数にする。"""
    if len(examples) < 2:
        raise BadRequestError("学習に使う文章が足りません（2 つ以上の区切りが必要です）")
    order = [int(index) for index in np.random.default_rng(SPLIT_SEED).permutation(len(examples))]
    shuffled = [examples[index] for index in order]
    validation_count = max(1, round(len(shuffled) * VALIDATION_RATIO))
    validation = shuffled[:validation_count]
    training = shuffled[validation_count:]
    if len(training) < batch_size:
        raise BadRequestError(
            f"学習に使う文章が足りません（学習用が {len(training)} 個で、"
            f"batch_size の {batch_size} より少ない）"
        )
    # 検証用がバッチより少ないと mlx-lm が受け付けないので、繰り返して埋める
    while len(validation) < batch_size:
        validation.append(validation[len(validation) % validation_count])
    return training, validation


def adapter_config(settings: LoraSettings, num_layers: int) -> dict[str, Any]:
    return {
        "fine_tune_type": "lora",
        "model": settings.model_id,
        "num_layers": num_layers,
        "lora_parameters": {"rank": settings.rank, "scale": LORA_SCALE, "dropout": 0.0},
        "iters": settings.iterations,
        "learning_rate": settings.learning_rate,
        "batch_size": settings.batch_size,
        "max_seq_length": settings.max_seq_length,
    }


def train_lora(model: Any, tokenizer: Any, settings: LoraSettings, emit: Emit) -> None:
    """`model` に LoRA の層を足して学習する。`model` は書き換わるので、終わったら捨てること。"""
    import mlx.optimizers as optim  # pyright: ignore[reportMissingTypeStubs]
    from mlx_lm.tuner.callbacks import TrainingCallback
    from mlx_lm.tuner.datasets import CacheDataset
    from mlx_lm.tuner.trainer import TrainingArgs

    # 型の情報が足りない関数は、モジュールを Any として読み込んで呼ぶ
    trainer: Any = import_module("mlx_lm.tuner.trainer")
    tuner_utils: Any = import_module("mlx_lm.tuner.utils")

    examples = build_examples(tokenizer, settings.texts, settings.max_seq_length)
    training, validation = split_examples(examples, settings.batch_size)

    layer_count = len(model.layers)
    num_layers = layer_count if settings.num_layers <= 0 else min(settings.num_layers, layer_count)
    config = adapter_config(settings, num_layers)

    model.freeze()
    tuner_utils.linear_to_lora_layers(model, num_layers, config["lora_parameters"])

    settings.adapter_path.mkdir(parents=True, exist_ok=True)
    (settings.adapter_path / "adapter_config.json").write_text(
        json.dumps(config, indent=4, ensure_ascii=False)
    )

    total = settings.iterations

    class Reporter(TrainingCallback):
        def on_train_loss_report(self, train_info: dict[str, Any]) -> None:
            emit(
                {
                    "type": "progress",
                    "iteration": int(train_info["iteration"]),
                    "total": total,
                    "train_loss": round(float(train_info["train_loss"]), 4),
                }
            )

        def on_val_loss_report(self, val_info: dict[str, Any]) -> None:
            emit(
                {
                    "type": "validation",
                    "iteration": int(val_info["iteration"]),
                    "val_loss": round(float(val_info["val_loss"]), 4),
                }
            )

    args = TrainingArgs(
        batch_size=settings.batch_size,
        iters=total,
        val_batches=VALIDATION_BATCHES,
        steps_per_report=STEPS_PER_REPORT,
        steps_per_eval=STEPS_PER_EVAL,
        # 途中の保存（反復ごとのファイル）は作らない
        steps_per_save=total + 1,
        adapter_file=str(settings.adapter_path / "adapters.safetensors"),
        max_seq_length=settings.max_seq_length,
    )
    trainer.train(
        model=model,
        optimizer=optim.Adam(learning_rate=settings.learning_rate),
        train_dataset=CacheDataset(TokenDataset(training)),
        val_dataset=CacheDataset(TokenDataset(validation)),
        args=args,
        training_callback=Reporter(),
    )
    emit({"type": "done", "adapter_path": str(settings.adapter_path)})
