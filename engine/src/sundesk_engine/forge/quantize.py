"""量子化。

- `affine`: MLX の本物の量子化。グループ（`group_size` 個の重み）ごとに目盛りとずれを持つ
- `simulated`: 量子化してすぐ戻した値を、float16 で保存する。本物にないビット数（1 や 7）や
  3 値（−1、0、+1。log2(3) ≈ 1.58 ビット）の効き目を試すためのもの

どちらも、量子化するのは `to_quantized` を持つ層（Linear と Embedding）の重みだけ。
重みの列の数が `group_size` で割り切れない層は、量子化しない。
"""

import math
from collections.abc import Callable
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any, Literal

import mlx.core as mx

from sundesk_engine.errors import BadRequestError, UnsupportedError
from sundesk_engine.forge.workpiece import (
    Source,
    Workpiece,
    bits_per_weight,
    cast_floats,
    count_layers,
    dequantize,
    describe_group,
    done_event,
    group_by_layer,
    load_workpiece,
    parameters,
    progress,
    save_workpiece,
    staging,
    tree_unflatten,
)
from sundesk_engine.lab.arrays import evaluate
from sundesk_engine.streaming import Emit, Event

type Method = Literal["affine", "simulated"]

AFFINE_BITS = (2, 3, 4, 5, 6, 8)
GROUP_SIZES = (32, 64, 128)
MIXED_RECIPES = ("mixed_2_6", "mixed_3_4", "mixed_3_6", "mixed_4_6")
SIMULATED_BITS = range(1, 9)
SIMULATED_DTYPE = mx.float16
_SCALE_BITS = 16
"""目盛りとずれを float16 で持つとしたときの、1 つあたりのビット数"""


@dataclass(frozen=True)
class Override:
    """重みの名前に `pattern` を含むものは、ビット数を `bits` にする（None なら量子化しない）。"""

    pattern: str
    bits: int | None


@dataclass(frozen=True)
class QuantizeSettings:
    method: Method
    bits: int
    group_size: int
    mixed: str | None = None
    overrides: tuple[Override, ...] = ()
    ternary: bool = False

    def validate(self) -> None:
        if self.group_size not in GROUP_SIZES:
            raise BadRequestError(f"group_size は {_join(GROUP_SIZES)} のどれかにしてください")
        if self.method == "affine":
            allowed: tuple[int, ...] = AFFINE_BITS
            if self.ternary:
                raise BadRequestError("ternary は method が simulated のときだけ使えます")
        else:
            allowed = tuple(SIMULATED_BITS)
            if self.mixed is not None:
                raise BadRequestError("mixed は method が affine のときだけ使えます")
        if self.mixed is not None and self.mixed not in MIXED_RECIPES:
            raise BadRequestError(f"mixed は {_join(MIXED_RECIPES)} のどれかにしてください")
        if not self.ternary and self.bits not in allowed:
            raise BadRequestError(f"bits は {_join(allowed)} のどれかにしてください")
        for override in self.overrides:
            if not override.pattern:
                raise BadRequestError("overrides の pattern が空です")
            if override.bits is not None and override.bits not in allowed:
                raise BadRequestError(
                    f"overrides の bits（{override.pattern}）は {_join(allowed)} のどれかか null に"
                    "してください"
                )


@dataclass(frozen=True)
class Precision:
    """1 つの層の量子化のしかた。"""

    bits: int
    group_size: int
    ternary: bool = False

    @property
    def effective_bits(self) -> float:
        """重み 1 つあたりのビット数。グループごとの目盛り（3 値なら目盛りだけ）を含める。"""
        if self.ternary:
            return math.log2(3) + _SCALE_BITS / self.group_size
        return self.bits + 2 * _SCALE_BITS / self.group_size


type Predicate = Callable[[str, Any], bool | dict[str, Any]]


def _join(values: Any) -> str:
    return "、".join(str(value) for value in values)


def _mixed_predicate(recipe: str, model: Any, group_size: int) -> Predicate:
    """mlx-lm の決まった配分（llama.cpp の Q4_K_M などに似せたもの）を使う。"""
    try:
        convert: Any = import_module("mlx_lm.convert")
        builder: Any = convert.mixed_quant_predicate_builder
    except (ImportError, AttributeError) as error:
        raise UnsupportedError(
            "この mlx-lm には、層ごとにビット数を変える配分がありません"
        ) from error
    try:
        return builder(recipe, model, group_size)
    except ValueError as error:
        raise UnsupportedError(f"このモデルには {recipe} を使えません: {error}") from error


def plan(model: Any, settings: QuantizeSettings) -> list[tuple[str, Any, Precision]]:
    """量子化する層と、そのしかたを決める。

    優先するのは、後ろのものほど強い順に、`bits` → `mixed` → モデルの決まり → `overrides`。
    `overrides` は、当てはまるもののうち最後に書かれたものを使う。
    """
    mixed = _mixed_predicate(settings.mixed, model, settings.group_size) if settings.mixed else None
    model_predicate: Predicate | None = getattr(model, "quant_predicate", None)
    planned: list[tuple[str, Any, Precision]] = []
    for path, module in model.named_modules():
        weight = getattr(module, "weight", None)
        if not hasattr(module, "to_quantized") or not isinstance(weight, mx.array):
            continue
        bits: int | None = settings.bits
        group_size = settings.group_size
        if mixed is not None:
            bits, group_size = _apply(mixed(path, module), bits, group_size)
        if model_predicate is not None and bits is not None:
            bits, group_size = _apply(model_predicate(path, module), bits, group_size)
        matched = [override for override in settings.overrides if override.pattern in path]
        if matched:
            bits = matched[-1].bits
        if bits is None or weight.shape[-1] % group_size != 0:
            continue
        ternary = settings.ternary and not matched
        planned.append((path, module, Precision(bits, group_size, ternary)))
    return planned


def _apply(decision: bool | dict[str, Any], bits: int, group_size: int) -> tuple[int | None, int]:
    if decision is False:
        return None, group_size
    if isinstance(decision, dict):
        return int(decision.get("bits", bits)), int(decision.get("group_size", group_size))
    return bits, group_size


# MARK: - 本物の量子化


def quantize_affine(
    piece: Workpiece, settings: QuantizeSettings, emit: Emit, stage: str = "quantizing"
) -> None:
    """層ごとに量子化して、`piece.config` に量子化の設定を書く。"""
    dequantize(piece)
    planned = plan(piece.model, settings)
    default = {"group_size": settings.group_size, "bits": settings.bits, "mode": "affine"}
    quantization: dict[str, Any] = dict(default)
    groups = group_by_layer((path, (module, precision)) for path, module, precision in planned)
    num_layers = count_layers(piece.model)
    for index, (key, items) in enumerate(groups):
        replacements: list[tuple[str, Any]] = []
        for path, (module, precision) in items:
            replacements.append(
                (
                    path,
                    module.to_quantized(
                        group_size=precision.group_size, bits=precision.bits, mode="affine"
                    ),
                )
            )
            if (precision.bits, precision.group_size) != (settings.bits, settings.group_size):
                quantization[path] = {
                    "group_size": precision.group_size,
                    "bits": precision.bits,
                    "mode": "affine",
                }
        piece.model.update_modules(tree_unflatten(replacements))
        evaluate(*(value for _path, module in replacements for _n, value in parameters(module)))
        progress(emit, stage, (index + 1) / len(groups), describe_group(key, num_layers))
    piece.config["quantization"] = quantization
    piece.config["quantization_config"] = dict(quantization)


# MARK: - 試しの量子化


def fake_affine(weight: mx.array, bits: int, group_size: int) -> mx.array:
    """グループごとに最小から最大までを 2^bits 段に分けて丸め、すぐ戻す。"""
    shape = weight.shape
    values = mx.reshape(weight.astype(mx.float32), (-1, group_size))
    low = values.min(axis=-1, keepdims=True)
    high = values.max(axis=-1, keepdims=True)
    levels = 2**bits - 1
    scale = (high - low) / levels
    safe = mx.where(scale > 0, scale, mx.ones_like(scale))
    steps = mx.clip(mx.round((values - low) / safe), 0, levels)
    return mx.reshape(steps * scale + low, shape)


def fake_ternary(weight: mx.array, group_size: int) -> mx.array:
    """グループごとに、絶対値の平均を目盛りにして −1、0、+1 の 3 値に丸め、すぐ戻す。

    BitNet b1.58 の丸め方を、グループごとに行うもの。
    """
    shape = weight.shape
    values = mx.reshape(weight.astype(mx.float32), (-1, group_size))
    scale = mx.mean(mx.abs(values), axis=-1, keepdims=True)
    safe = mx.where(scale > 0, scale, mx.ones_like(scale))
    steps = mx.clip(mx.round(values / safe), -1, 1)
    return mx.reshape(steps * scale, shape)


def fake_quantize(weight: mx.array, precision: Precision) -> mx.array:
    if precision.ternary:
        return fake_ternary(weight, precision.group_size)
    return fake_affine(weight, precision.bits, precision.group_size)


def quantize_simulated(piece: Workpiece, settings: QuantizeSettings, emit: Emit) -> float:
    """重みを量子化してすぐ戻し、すべてを float16 にする。量子化したとみなしたビット数を返す。"""
    dequantize(piece)
    planned = plan(piece.model, settings)
    groups = group_by_layer((path, (module, precision)) for path, module, precision in planned)
    num_layers = count_layers(piece.model)
    for index, (key, items) in enumerate(groups):
        updated: list[mx.array] = []
        for _path, (module, precision) in items:
            module.weight = fake_quantize(module.weight, precision).astype(SIMULATED_DTYPE)
            updated.append(module.weight)
        evaluate(*updated)
        progress(emit, "quantizing", (index + 1) / len(groups), describe_group(key, num_layers))
    cast_floats(piece.model, SIMULATED_DTYPE)
    precisions = {f"{path}.weight": precision for path, _module, precision in planned}
    total_bits = 0.0
    total_count = 0
    for name, value in parameters(piece.model):
        precision = precisions.get(name)
        total_bits += value.size * (precision.effective_bits if precision else _SCALE_BITS)
        total_count += value.size
    return round(total_bits / total_count, 3) if total_count else 0.0


# MARK: - 全体


def quantize_model(
    source: Source, output_dir: Path, settings: QuantizeSettings, emit: Emit
) -> Event:
    """`source` を量子化して `output_dir` に書き、`done` のイベントを返す。"""
    settings.validate()
    emit({"type": "loading", "model": source.model_id})
    piece = load_workpiece(source.path)
    with staging(output_dir) as directory:
        if settings.method == "affine":
            quantize_affine(piece, settings, emit)
            bits = bits_per_weight(piece.model)
        else:
            bits = quantize_simulated(piece, settings, emit)
        progress(emit, "saving", None, "保存しています")
        save_workpiece(directory, piece.model, piece.tokenizer, piece.config, source.path)
    return done_event(output_dir, bits)
