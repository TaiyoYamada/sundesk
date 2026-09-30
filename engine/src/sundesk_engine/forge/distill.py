"""知識の蒸留。先生モデルの出力の確率分布を、生徒モデルに学ばせる。

損失は alpha × KL(先生 ‖ 生徒, 温度 T) × T² + (1 − alpha) × 次のトークンの交差エントロピー。
KL は温度で柔らかくした分布どうしで測り、T² を掛けて勾配の大きさを温度によらず揃える（Hinton ら）。

- `lora_rank` があれば、生徒のすべての層に LoRA を付けて学習し、アダプタとして書く
- なければ、生徒の全体を学習し、モデルとして書く（量子化された生徒は、戻してから学習する）
"""

import json
from collections.abc import Iterator
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any

import mlx.core as mx
import numpy as np

from sundesk_engine.errors import BadRequestError, UnsupportedError
from sundesk_engine.forge.workpiece import (
    Source,
    dequantize,
    load_workpiece,
    mlx_utils,
    save_workpiece,
    staging,
    tree_flatten,
    vocabulary,
)
from sundesk_engine.lab.arrays import evaluate, to_scalar
from sundesk_engine.lora.train import LORA_SCALE, build_examples, split_examples
from sundesk_engine.streaming import Emit, Event

STEPS_PER_REPORT = 10
STEPS_PER_EVAL = 50
VALIDATION_BATCHES = 25
SHUFFLE_SEED = 0


@dataclass(frozen=True)
class DistillSettings:
    texts: list[str]
    iterations: int
    learning_rate: float
    temperature: float
    alpha: float
    max_seq_length: int
    batch_size: int
    lora_rank: int | None


@dataclass(frozen=True)
class Batch:
    tokens: mx.array
    """`[バッチ, 長さ]` のトークン ID（足りないところは 0 で埋める）"""
    mask: mx.array
    """`[バッチ, 長さ − 1]`。次のトークンを当てる位置のうち、本物のトークンのところが 1"""


def make_batch(examples: list[list[int]]) -> Batch:
    length = max(len(example) for example in examples)
    tokens = np.zeros((len(examples), length), dtype=np.int32)
    mask = np.zeros((len(examples), length - 1), dtype=np.float32)
    for row, example in enumerate(examples):
        tokens[row, : len(example)] = example
        mask[row, : len(example) - 1] = 1.0
    return Batch(tokens=mx.array(tokens), mask=mx.array(mask))


def batches(examples: list[list[int]], batch_size: int, seed: int) -> Iterator[Batch]:
    """学習用のバッチを、並びを変えながら限りなく作る。"""
    rng = np.random.default_rng(seed)
    while True:
        order = [int(index) for index in rng.permutation(len(examples))]
        for start in range(0, len(order) - batch_size + 1, batch_size):
            yield make_batch([examples[index] for index in order[start : start + batch_size]])


def check_vocabulary(teacher: Any, student: Any) -> None:
    """2 つのトークナイザの語彙が同じでなければ `UnsupportedError`（422）。"""
    if vocabulary(teacher) != vocabulary(student):
        raise UnsupportedError("先生と生徒の語彙（トークナイザ）が違うので、蒸留できません")


def check_same_vocabulary(teacher: Path, student: Path) -> None:
    """読み込む前に、トークナイザだけを読んで語彙を比べる。"""
    utils = mlx_utils()
    try:
        tokenizers = [utils.load_tokenizer(path) for path in (teacher, student)]
    except (OSError, ValueError) as error:
        raise UnsupportedError(f"トークナイザを読み込めません: {error}") from error
    check_vocabulary(*tokenizers)


def distill_losses(
    student_logits: mx.array,
    teacher_logits: mx.array,
    targets: mx.array,
    mask: mx.array,
    temperature: float,
    alpha: float,
) -> tuple[mx.array, mx.array, mx.array]:
    """(損失, KL, 交差エントロピー) を返す。どれも本物のトークンの位置の平均。

    出力の数（語彙の大きさ）が埋め草の分だけ違うときは、短いほうに合わせる。
    """
    vocab = min(student_logits.shape[-1], teacher_logits.shape[-1])
    student = student_logits[..., :vocab].astype(mx.float32)
    teacher = teacher_logits[..., :vocab].astype(mx.float32)
    count = mx.maximum(mask.sum(), 1.0)

    teacher_log = teacher / temperature - mx.logsumexp(
        teacher / temperature, axis=-1, keepdims=True
    )
    student_log = student / temperature - mx.logsumexp(
        student / temperature, axis=-1, keepdims=True
    )
    kl_per_position = mx.sum(mx.exp(teacher_log) * (teacher_log - student_log), axis=-1)
    kl = mx.sum(kl_per_position * mask) / count

    log_normalizer = mx.logsumexp(student, axis=-1)
    target_logits = mx.take_along_axis(student, targets[..., None], axis=-1)[..., 0]
    ce = mx.sum((log_normalizer - target_logits) * mask) / count

    loss = alpha * kl * temperature**2 + (1.0 - alpha) * ce
    return loss, kl, ce


class Distiller:
    """先生と生徒を持ち、生徒を 1 段ずつ学習する。"""

    def __init__(self, teacher: Any, student: Any, settings: DistillSettings) -> None:
        import mlx.optimizers as optim  # pyright: ignore[reportMissingTypeStubs]

        nn: Any = import_module("mlx.nn")

        self.teacher = teacher
        self.student = student
        self.settings = settings
        self.optimizer: Any = optim.Adam(learning_rate=settings.learning_rate)
        self._value_and_grad: Any = nn.value_and_grad(student, self._loss)

    def _loss(self, batch: Batch, teacher_logits: mx.array) -> tuple[mx.array, mx.array, mx.array]:
        logits = self.student(batch.tokens[:, :-1])
        return distill_losses(
            logits,
            teacher_logits,
            batch.tokens[:, 1:],
            batch.mask,
            self.settings.temperature,
            self.settings.alpha,
        )

    def _teacher_logits(self, batch: Batch) -> mx.array:
        return mx.stop_gradient(self.teacher(batch.tokens[:, :-1]))

    def step(self, batch: Batch) -> tuple[float, float, float]:
        teacher_logits = self._teacher_logits(batch)
        (loss, kl, ce), grads = self._value_and_grad(batch, teacher_logits)
        self.optimizer.update(self.student, grads)
        evaluate(loss, kl, ce, self.student.parameters(), self.optimizer.state)
        return to_scalar(loss), to_scalar(kl), to_scalar(ce)

    def validate(self, examples: list[list[int]]) -> float:
        size = self.settings.batch_size
        total = 0.0
        count = 0
        for start in range(0, len(examples), size):
            if count >= VALIDATION_BATCHES:
                break
            batch = make_batch(examples[start : start + size])
            loss, _kl, _ce = self._loss(batch, self._teacher_logits(batch))
            evaluate(loss)
            total += to_scalar(loss)
            count += 1
        return total / max(count, 1)


def _adapter_config(
    student_id: str, teacher_id: str, num_layers: int, settings: DistillSettings
) -> dict[str, Any]:
    return {
        "fine_tune_type": "lora",
        "model": student_id,
        "num_layers": num_layers,
        "lora_parameters": {"rank": settings.lora_rank, "scale": LORA_SCALE, "dropout": 0.0},
        "iters": settings.iterations,
        "learning_rate": settings.learning_rate,
        "batch_size": settings.batch_size,
        "max_seq_length": settings.max_seq_length,
        "distillation": {
            "teacher": teacher_id,
            "temperature": settings.temperature,
            "alpha": settings.alpha,
        },
    }


def distill(
    teacher_source: Source,
    student_source: Source,
    output_dir: Path,
    settings: DistillSettings,
    emit: Emit,
) -> Event:
    """先生と生徒を読み、生徒を学習して `output_dir` に書く。`done` のイベントを返す。"""
    emit({"type": "loading", "model": teacher_source.model_id})
    teacher = load_workpiece(teacher_source.path, lazy=False)
    teacher.model.freeze()
    emit({"type": "loading", "model": student_source.model_id})
    student = load_workpiece(student_source.path, lazy=False)
    check_vocabulary(teacher.tokenizer, student.tokenizer)

    examples = build_examples(student.tokenizer, settings.texts, settings.max_seq_length)
    training, validation = split_examples(examples, settings.batch_size)

    num_layers = len(student.model.layers)
    # LoRA の重みの初期値を、毎回同じにする
    mx.random.seed(SHUFFLE_SEED)
    if settings.lora_rank is not None:
        tuner: Any = import_module("mlx_lm.tuner.utils")
        student.model.freeze()
        tuner.linear_to_lora_layers(
            student.model,
            num_layers,
            {"rank": settings.lora_rank, "scale": LORA_SCALE, "dropout": 0.0},
        )
    else:
        # 量子化された重みは学習できないので、ふつうの数に戻す
        dequantize(student)
        student.model.unfreeze()
    student.model.train()
    trainable = tree_flatten(student.model.trainable_parameters())
    if not trainable:
        raise BadRequestError("学習できる重みがありません")

    distiller = Distiller(teacher.model, student.model, settings)
    total = settings.iterations
    window: list[tuple[float, float, float]] = []
    stream = batches(training, settings.batch_size, SHUFFLE_SEED)
    with staging(output_dir) as directory:
        for iteration in range(1, total + 1):
            if iteration == 1 or iteration % STEPS_PER_EVAL == 0 or iteration == total:
                loss = distiller.validate(validation)
                emit({"type": "validation", "iteration": iteration, "loss": round(loss, 4)})
            window.append(distiller.step(next(stream)))
            if iteration % STEPS_PER_REPORT == 0 or iteration == total:
                averages = np.mean(np.array(window), axis=0)
                emit(
                    {
                        "type": "progress",
                        "iteration": iteration,
                        "total": total,
                        "loss": round(float(averages[0]), 4),
                        "kl": round(float(averages[1]), 4),
                        "ce": round(float(averages[2]), 4),
                    }
                )
                window.clear()
        student.model.eval()
        if settings.lora_rank is not None:
            weights = dict(tree_flatten(student.model.trainable_parameters()))
            save: Any = import_module("mlx.core").save_safetensors
            save(str(directory / "adapters.safetensors"), weights)
            config = _adapter_config(
                student_source.model_id, teacher_source.model_id, num_layers, settings
            )
            (directory / "adapter_config.json").write_text(
                json.dumps(config, indent=4, ensure_ascii=False)
            )
            kind = "adapter"
        else:
            save_workpiece(
                directory, student.model, student.tokenizer, student.config, student_source.path
            )
            kind = "model"
    return {"type": "done", "output_dir": str(output_dir), "kind": kind}
