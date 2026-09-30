"""モデルの手術: LoRA の焼き込み、2 つのモデルの合成、層やヘッドの枝刈り。"""

import math
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any, Literal

import mlx.core as mx

from sundesk_engine.errors import BadRequestError, UnsupportedError
from sundesk_engine.forge.workpiece import (
    LAYER_COUNT_KEYS,
    Source,
    Workpiece,
    bits_per_weight,
    count_layers,
    dequantize,
    describe_group,
    done_event,
    group_by_layer,
    layer_index,
    layer_prefix,
    load_workpiece,
    materialize,
    parameters,
    progress,
    read_config,
    save_workpiece,
    staging,
    tree_unflatten,
)
from sundesk_engine.lab.arrays import evaluate, to_scalar
from sundesk_engine.lab.introspect import anatomy
from sundesk_engine.streaming import Emit, Event

type MergeMethod = Literal["linear", "slerp"]

MERGED_DTYPE = mx.float16
_PARALLEL_THRESHOLD = 1e-6
"""2 つの重みがほぼ同じ向きなら、slerp の代わりに線形補間を使う（sin ω で割れないため）"""


# MARK: - 焼き込み


def fuse_model(
    source: Source, adapter: Path, output_dir: Path, dequantize_output: bool, emit: Emit
) -> Event:
    """LoRA のアダプタを本体の重みに足し込み、1 つのモデルとして書く。"""
    emit({"type": "loading", "model": source.model_id})
    piece = load_workpiece(source.path)
    tuner: Any = import_module("mlx_lm.tuner.utils")
    try:
        tuner.load_adapters(piece.model, str(adapter))
    except ValueError as error:
        raise UnsupportedError(f"このアダプタはこのモデルに付けられません: {error}") from error
    fused = [
        (name, module.fuse(dequantize=dequantize_output))
        for name, module in piece.model.named_modules()
        if hasattr(module, "fuse")
    ]
    if fused:
        piece.model.update_modules(tree_unflatten(fused))
    if dequantize_output:
        dequantize(piece)
    with staging(output_dir) as directory:
        materialize(piece.model, emit, "fusing")
        bits = bits_per_weight(piece.model)
        progress(emit, "saving", None, "保存しています")
        save_workpiece(directory, piece.model, piece.tokenizer, piece.config, source.path)
    return done_event(output_dir, bits)


# MARK: - 合成

STRUCTURE_KEYS = (
    "model_type",
    "hidden_size",
    "num_hidden_layers",
    "intermediate_size",
    "num_attention_heads",
    "num_key_value_heads",
    "head_dim",
    "vocab_size",
    "tie_word_embeddings",
)
"""混ぜられるかどうかを、読み込む前に config.json で確かめる項目"""


def check_same_structure(first: Path, second: Path) -> None:
    """2 つのモデルの構造が同じでなければ `UnsupportedError`（422）。

    ここでは config.json だけを比べる。重みの形は、読んでから確かめる。
    """
    left, right = read_config(first), read_config(second)
    different = [key for key in STRUCTURE_KEYS if left.get(key) != right.get(key)]
    if different:
        details = "、".join(f"{key}: {left.get(key)} と {right.get(key)}" for key in different)
        raise UnsupportedError(f"モデルの構造が違うので混ぜられません（{details}）")


def lerp(a: mx.array, b: mx.array, t: float) -> mx.array:
    """(1 − t)·a + t·b"""
    return (1.0 - t) * a.astype(mx.float32) + t * b.astype(mx.float32)


def slerp(a: mx.array, b: mx.array, t: float) -> mx.array:
    """球面の線形補間。重みを 1 本のベクトルとみなし、2 つの間の角 ω に沿って混ぜる。

    sin((1 − t)ω)/sin ω · a + sin(tω)/sin ω · b。ほぼ平行なら線形補間にする。
    """
    x = a.astype(mx.float32)
    y = b.astype(mx.float32)
    norms = mx.linalg.norm(mx.reshape(x, (-1,))) * mx.linalg.norm(mx.reshape(y, (-1,)))
    if to_scalar(norms) == 0.0:
        return lerp(a, b, t)
    cosine = min(max(to_scalar(mx.sum(x * y) / norms), -1.0), 1.0)
    omega = math.acos(cosine)
    sine = math.sin(omega)
    if sine < _PARALLEL_THRESHOLD:
        return lerp(a, b, t)
    return (math.sin((1.0 - t) * omega) / sine) * x + (math.sin(t * omega) / sine) * y


def merge_models(
    sources: tuple[Source, Source],
    output_dir: Path,
    method: MergeMethod,
    t: float,
    emit: Emit,
) -> Event:
    """同じ構造の 2 つのモデルを混ぜる。量子化されていれば戻してから混ぜ、float16 で書く。"""
    if not 0.0 <= t <= 1.0:
        raise BadRequestError("t は 0 から 1 までにしてください")
    pieces: list[Workpiece] = []
    for source in sources:
        emit({"type": "loading", "model": source.model_id})
        piece = load_workpiece(source.path)
        dequantize(piece)
        pieces.append(piece)
    first, second = pieces
    if first.config.get("model_type") != second.config.get("model_type"):
        raise UnsupportedError(
            "モデルの種類が違うので混ぜられません"
            f"（{first.config.get('model_type')} と {second.config.get('model_type')}）"
        )
    left = dict(parameters(first.model))
    right = dict(parameters(second.model))
    if left.keys() != right.keys():
        raise UnsupportedError("モデルの構造（重みの名前）が違うので混ぜられません")
    for name, value in left.items():
        if value.shape != right[name].shape:
            raise UnsupportedError(
                "モデルの構造が違うので混ぜられません"
                f"（{name}: {value.shape} と {right[name].shape}）"
            )
    combine = slerp if method == "slerp" else lerp
    groups = group_by_layer(left.items())
    num_layers = count_layers(first.model)
    with staging(output_dir) as directory:
        for index, (key, items) in enumerate(groups):
            merged = [
                (name, combine(value, right[name], t).astype(MERGED_DTYPE)) for name, value in items
            ]
            evaluate(*(value for _name, value in merged))
            # 混ぜ終えた重みから入れ替え、元の重みを早めに手放す
            first.model.update(tree_unflatten(merged))
            for name, _value in items:
                right.pop(name)
            progress(emit, "merging", (index + 1) / len(groups), describe_group(key, num_layers))
        del second, right, left
        first.config["torch_dtype"] = "float16"
        bits = bits_per_weight(first.model)
        progress(emit, "saving", None, "保存しています")
        save_workpiece(directory, first.model, first.tokenizer, first.config, sources[0].path)
    return done_event(output_dir, bits)


# MARK: - 枝刈り


@dataclass(frozen=True)
class HeadRef:
    layer: int
    head: int


def _head_count(attention: Any, config: dict[str, Any]) -> int:
    for name in ("n_heads", "num_heads", "num_attention_heads"):
        value = getattr(attention, name, None)
        if isinstance(value, int) and value > 0:
            return value
    value = config.get("num_attention_heads")
    if isinstance(value, int) and value > 0:
        return value
    raise UnsupportedError("このモデルの Attention のヘッドの数が分かりません")


def zero_head(attention: Any, head: int, num_heads: int) -> bool:
    """ヘッド `head` の出力を 0 にする。出力の射影（o_proj）の、そのヘッドの列を 0 にする。

    量子化された層で、ヘッドの幅がグループの倍数なら、そのグループの目盛りとずれを 0 にする
    （ほかの重みは変わらない）。そうでなければ、量子化では 0 をちょうど表せないので、
    その層だけ戻して（量子化しないで）持つ。そのときは True を返す。
    """
    nn: Any = import_module("mlx.nn")
    projection: Any = getattr(attention, "o_proj", None)
    if projection is None:
        raise UnsupportedError("このモデルの Attention には o_proj がないので、ヘッドを消せません")
    quantized = hasattr(projection, "scales")
    if quantized:
        width = projection.weight.shape[1] * 32 // projection.bits
    else:
        width = projection.weight.shape[1]
    head_dim = width // num_heads
    start, end = head * head_dim, (head + 1) * head_dim
    if quantized and head_dim % projection.group_size == 0:
        group = projection.group_size
        columns = mx.arange(projection.scales.shape[1])
        keep = mx.logical_or(columns < start // group, columns >= end // group)
        projection.scales = mx.where(keep[None], projection.scales, 0)
        projection.biases = mx.where(keep[None], projection.biases, 0)
        return False
    if quantized:
        weight = mx.dequantize(
            projection.weight,
            projection.scales,
            projection.biases,
            group_size=projection.group_size,
            bits=projection.bits,
            mode=projection.mode,
        )
    else:
        weight = projection.weight
    columns = mx.arange(width)
    keep = mx.logical_or(columns < start, columns >= end)
    zeroed = mx.where(keep[None], weight, mx.zeros_like(weight))
    if not quantized:
        projection.weight = zeroed
        return False
    linear: Any = nn.Linear(width, weight.shape[0], bias="bias" in projection)
    linear.weight = zeroed
    if "bias" in projection:
        linear.bias = projection.bias
    attention.o_proj = linear
    return True


def _renumber_quantization(config: dict[str, Any], mapping: dict[int, int | None]) -> None:
    """層ごとの量子化の設定（`model.layers.3.mlp...` の鍵）を、新しい層の番号に付け替える。"""
    quantization = config.get("quantization")
    if not isinstance(quantization, dict):
        return
    updated: dict[str, Any] = {}
    for key, value in quantization.items():  # pyright: ignore[reportUnknownVariableType]
        name = str(key)  # pyright: ignore[reportUnknownArgumentType]
        prefix = layer_prefix(name)
        index = layer_index(name)
        if prefix is None or index is None:
            updated[name] = value
            continue
        target = mapping.get(index)
        if target is None:
            continue
        base = prefix.rsplit(".", 1)[0]
        updated[f"{base}.{target}{name[len(prefix) :]}"] = value
    config["quantization"] = updated
    config["quantization_config"] = dict(updated)


def _shrink_config(config: dict[str, Any], dropped: set[int], num_layers: int) -> None:
    kept = num_layers - len(dropped)
    for key, value in list(config.items()):
        if key in LAYER_COUNT_KEYS and value == num_layers:
            config[key] = kept
        elif isinstance(value, list) and len(value) == num_layers:  # pyright: ignore[reportUnknownArgumentType]
            # 層ごとの設定（`layer_types` など）
            config[key] = [item for index, item in enumerate(value) if index not in dropped]  # pyright: ignore[reportUnknownVariableType, reportUnknownArgumentType]


def check_prune_request(path: Path, drop_layers: list[int], drop_heads: list[HeadRef]) -> None:
    """読み込む前に、config.json で分かる範囲の番号を確かめる（おかしければ 400）。"""
    config = read_config(path)
    num_layers = config.get("num_hidden_layers")
    if isinstance(num_layers, int) and num_layers > 0:
        for layer in [*drop_layers, *(ref.layer for ref in drop_heads)]:
            if not -num_layers <= layer < num_layers:
                raise BadRequestError(
                    f"層の番号は 0 から {num_layers - 1} までです（指定: {layer}）"
                )
        if len({layer % num_layers for layer in drop_layers}) >= num_layers:
            raise BadRequestError("すべての層を取り除くことはできません")
    num_heads = config.get("num_attention_heads")
    if isinstance(num_heads, int) and num_heads > 0:
        for ref in drop_heads:
            if not 0 <= ref.head < num_heads:
                raise BadRequestError(
                    f"ヘッドの番号は 0 から {num_heads - 1} までです（指定: {ref.head}）"
                )


def prune_model(
    source: Source,
    output_dir: Path,
    drop_layers: list[int],
    drop_heads: list[HeadRef],
    emit: Emit,
) -> Event:
    """層を取り除き、ヘッドの出力を 0 にする。層とヘッドの番号は、取り除く前のもので数える。"""
    emit({"type": "loading", "model": source.model_id})
    piece = load_workpiece(source.path)
    parts = anatomy(piece.model)
    num_layers = parts.num_layers
    dropped = {parts.check_layer(layer) for layer in drop_layers}
    if len(dropped) >= num_layers:
        raise BadRequestError("すべての層を取り除くことはできません")
    heads: list[tuple[int, Any, int, int]] = []
    for ref in drop_heads:
        index = parts.check_layer(ref.layer)
        attention: Any = getattr(parts.layers[index], "self_attn", None)
        if attention is None:
            raise UnsupportedError("このモデルの層には self_attn がないので、ヘッドを消せません")
        count = _head_count(attention, piece.config)
        if not 0 <= ref.head < count:
            raise BadRequestError(f"ヘッドの番号は 0 から {count - 1} までです（指定: {ref.head}）")
        if index not in dropped:
            heads.append((index, attention, ref.head, count))
    for index, attention, head, count in heads:
        if zero_head(attention, head, count):
            # 量子化しないで持つ層を、読むときにも量子化しないよう設定に書く
            quantization = piece.config.get("quantization")
            if isinstance(quantization, dict):
                quantization[f"model.layers.{index}.self_attn.o_proj"] = False
    progress(emit, "pruning", None, f"{len(dropped)} 層と {len(heads)} 個のヘッドを取り除きます")
    kept = [layer for index, layer in enumerate(parts.layers) if index not in dropped]
    piece.model.model.layers = kept
    mapping: dict[int, int | None] = {}
    position = 0
    for index in range(num_layers):
        if index in dropped:
            mapping[index] = None
        else:
            mapping[index] = position
            position += 1
    _renumber_quantization(piece.config, mapping)
    _shrink_config(piece.config, dropped, num_layers)
    with staging(output_dir) as directory:
        materialize(piece.model, emit, "pruning")
        bits = bits_per_weight(piece.model)
        progress(emit, "saving", None, "保存しています")
        save_workpiece(directory, piece.model, piece.tokenizer, piece.config, source.path)
    return done_event(output_dir, bits, num_layers=len(kept))
