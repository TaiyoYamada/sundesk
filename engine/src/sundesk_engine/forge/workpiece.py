"""モデルを作る処理（工房）の共通の道具。

- 作業に使うモデルは、モデルの係（`ModelManager`）の外で読む。量子化などで中身を書き換えるため
- 出来上がったモデルは、`mlx_lm.load(output_dir)` でそのまま読める形
  （`config.json`、`model*.safetensors`、トークナイザ）で書く
- 書いている途中のものは、同じ親フォルダの隠しフォルダに置き、書き終えたら名前を変える。
  途中で失敗したり止めたりしたときは消すので、中途半端なモデルが一覧に出ることはない
"""

import json
import re
import shutil
import uuid
from collections.abc import Callable, Generator, Iterable
from contextlib import contextmanager
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any

import mlx.core as mx

from sundesk_engine.errors import BadRequestError, UnsupportedError
from sundesk_engine.lab.arrays import evaluate
from sundesk_engine.paths import confined_path
from sundesk_engine.runtime.hub import directory_size
from sundesk_engine.streaming import Emit, Event

COPIED_PATTERNS = ("generation_config.json", "*.py")
"""元のフォルダから、そのまま写すファイル（トークナイザは別に書く）"""

LAYER_COUNT_KEYS = ("num_hidden_layers", "num_layers", "n_layer", "n_layers")
"""config.json の中で、層の数を表す名前"""

_LAYER_PATTERN = re.compile(r"^(.*?\blayers)\.(\d+)(?:\.|$)")


@dataclass(frozen=True)
class Source:
    """作業に使うモデル。`model_id` は要求に書かれたまま、`path` は手元のフォルダ。"""

    model_id: str
    path: Path


@dataclass
class Workpiece:
    """作業台に載せたモデル。"""

    model: Any
    tokenizer: Any
    config: dict[str, Any]
    source: Path

    @property
    def quantized(self) -> bool:
        return "quantization" in self.config


def mlx_utils() -> Any:
    """mlx-lm の utils。型の情報が足りないので、モジュールを Any として読み込む。"""
    return import_module("mlx_lm.utils")


def tree_flatten(tree: Any) -> list[tuple[str, Any]]:
    utils: Any = import_module("mlx.utils")
    return list(utils.tree_flatten(tree))


def tree_unflatten(items: list[tuple[str, Any]]) -> Any:
    utils: Any = import_module("mlx.utils")
    return utils.tree_unflatten(items)


def parameters(model: Any) -> list[tuple[str, mx.array]]:
    """モデルの重みを、名前と配列の組にして返す。"""
    return [(name, value) for name, value in tree_flatten(model.parameters())]


# MARK: - 読む


def read_config(path: Path) -> dict[str, Any]:
    """`config.json` を読む。なければ（読めなければ）空の辞書を返す。"""
    try:
        config = json.loads((path / "config.json").read_text())
    except (OSError, ValueError):
        return {}
    return dict(config) if isinstance(config, dict) else {}  # pyright: ignore[reportUnknownArgumentType]


def load_workpiece(path: Path, *, lazy: bool = True) -> Workpiece:
    """モデルとトークナイザと設定を読む。`lazy` なら、重みは使うときまで読まない。"""
    utils = mlx_utils()
    try:
        loaded: Any = utils.load_model(path, lazy=lazy)
    except FileNotFoundError as error:
        raise UnsupportedError(
            f"MLX で読める形のモデル（config.json と model*.safetensors）ではありません: {path}"
        ) from error
    except (ValueError, KeyError) as error:
        raise UnsupportedError(f"このモデルは読み込めません: {error}") from error
    model, config = loaded
    tokenizer = utils.load_tokenizer(path, eos_token_ids=config.get("eos_token_id"))
    return Workpiece(model=model, tokenizer=tokenizer, config=dict(config), source=path)


def dequantize(piece: Workpiece) -> None:
    """量子化されたモデルを、ふつうの数に戻す（その場で書き換える）。"""
    if not piece.quantized and not has_quantized_layers(piece.model):
        return
    piece.model = mlx_utils().dequantize_model(piece.model)
    piece.config.pop("quantization", None)
    piece.config.pop("quantization_config", None)


def has_quantized_layers(model: Any) -> bool:
    return any(hasattr(module, "scales") for _name, module in model.named_modules())


def vocabulary(tokenizer: Any) -> dict[str, int]:
    """トークナイザの語彙（文字列 → ID）。"""
    backend: Any = getattr(tokenizer, "_tokenizer", tokenizer)
    return {str(key): int(value) for key, value in backend.get_vocab().items()}


# MARK: - 書く


def check_output_dir(value: str) -> Path:
    """書き出し先を確かめる。絶対パスで、まだないか空のフォルダでなければ 400 にする。"""
    path = Path(confined_path(value, "output_dir "))
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise BadRequestError(f"output_dir にはもう中身があります。別の場所にしてください: {value}")
    return path


@contextmanager
def staging(output_dir: Path) -> Generator[Path]:
    """書いている途中のものを置く隠しフォルダを作り、`with` を抜けたら `output_dir` に移す。

    例外（接続が切れたときを含む）で抜けたときは、途中のものを消す。
    """
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_dir.parent / f".{output_dir.name}.partial-{uuid.uuid4().hex[:8]}"
    temporary.mkdir()
    try:
        yield temporary
        if output_dir.exists():
            output_dir.rmdir()  # 空のフォルダだけを消せる。中身があれば失敗する
        temporary.rename(output_dir)
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def save_workpiece(
    directory: Path, model: Any, tokenizer: Any, config: dict[str, Any], source: Path
) -> None:
    """mlx-lm がそのまま読める形で書く。"""
    utils = mlx_utils()
    utils.save_model(directory, model, donate_model=False)
    # save_config は渡した辞書を書き換えるので、写しを渡す
    utils.save_config(json.loads(json.dumps(config)), config_path=directory / "config.json")
    tokenizer.save_pretrained(str(directory))
    for pattern in COPIED_PATTERNS:
        for file in source.glob(pattern):
            if file.is_file() and not (directory / file.name).exists():
                shutil.copy(file, directory / file.name)


def bits_per_weight(model: Any) -> float:
    """重み 1 つあたりの平均のビット数（量子化の目盛りなども含めた、保存に使う大きさ）。"""
    return round(float(mlx_utils().compute_bits_per_weight(model)), 3)


def done_event(output_dir: Path, bits: float, **extra: Any) -> Event:
    return {
        "type": "done",
        "output_dir": str(output_dir),
        "size_bytes": directory_size(output_dir),
        "bits_per_weight": bits,
    } | extra


# MARK: - 途中経過


def progress(emit: Emit, stage: str, fraction: float | None, message: str) -> None:
    emit(
        {
            "type": "progress",
            "stage": stage,
            "fraction": None if fraction is None else round(min(max(fraction, 0.0), 1.0), 4),
            "message": message,
        }
    )


def layer_prefix(path: str) -> str | None:
    """`model.layers.3.mlp.up_proj` のような名前から、層の部分（`model.layers.3`）を取り出す。"""
    match = _LAYER_PATTERN.match(path)
    return f"{match.group(1)}.{match.group(2)}" if match else None


def layer_index(path: str) -> int | None:
    match = _LAYER_PATTERN.match(path)
    return int(match.group(2)) if match else None


def group_by_layer[T](items: Iterable[tuple[str, T]]) -> list[tuple[str, list[tuple[str, T]]]]:
    """名前の付いたものを、層ごと（層の外のものは 1 つずつ）にまとめる。順番は保つ。"""
    groups: dict[str, list[tuple[str, T]]] = {}
    for name, item in items:
        key = layer_prefix(name) or name.rsplit(".", 1)[0]
        groups.setdefault(key, []).append((name, item))
    return list(groups.items())


def describe_group(key: str, num_layers: int) -> str:
    index = layer_index(key)
    return f"層 {index + 1}/{num_layers}" if index is not None else key


def count_layers(model: Any) -> int:
    layers = getattr(model, "layers", None)
    return len(layers) if isinstance(layers, list) else 0  # pyright: ignore[reportUnknownArgumentType]


def materialize(model: Any, emit: Emit, stage: str) -> None:
    """遅らせていた計算（読み込みや型の変換）を、層ごとに実行しながら途中経過を流す。"""
    groups = group_by_layer(parameters(model))
    num_layers = count_layers(model)
    for index, (key, items) in enumerate(groups):
        evaluate(*(value for _name, value in items))
        progress(emit, stage, (index + 1) / len(groups), describe_group(key, num_layers))


def cast_floats(model: Any, dtype: mx.Dtype) -> None:
    """浮動小数点の重みを `dtype` にする。

    モデルが型を変えてはいけない重み（`cast_predicate`）を決めていれば、それに従う。
    """
    keep: Callable[[str], bool] = getattr(model, "cast_predicate", lambda _name: True)
    updated = [
        (name, value.astype(dtype))
        for name, value in parameters(model)
        if keep(name) and mx.issubdtype(value.dtype, mx.floating) and value.dtype != dtype
    ]
    if updated:
        model.update(tree_unflatten(updated))
