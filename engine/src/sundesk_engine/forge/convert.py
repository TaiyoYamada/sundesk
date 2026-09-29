"""Hugging Face の transformers の形式のモデルを、MLX の形式に変える。

重みの名前の付け替えなどは、mlx-lm のモデル（`sanitize`）に任せる。
safetensors がなく PyTorch の `.bin` だけがあるときは、いったん safetensors に書き直してから読む。
"""

import tempfile
from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any, Literal

import mlx.core as mx
import numpy as np

from sundesk_engine.errors import UnsupportedError
from sundesk_engine.forge.quantize import QuantizeSettings, quantize_affine
from sundesk_engine.forge.workpiece import (
    Source,
    bits_per_weight,
    cast_floats,
    dequantize,
    done_event,
    load_workpiece,
    materialize,
    progress,
    save_workpiece,
    staging,
)
from sundesk_engine.streaming import Emit, Event

type DType = Literal["float16", "bfloat16", "float32"]

DTYPES: dict[str, mx.Dtype] = {
    "float16": mx.float16,
    "bfloat16": mx.bfloat16,
    "float32": mx.float32,
}


@dataclass(frozen=True)
class ConvertSettings:
    dtype: DType
    quantize: QuantizeSettings | None


def _torch_to_mlx(tensor: Any) -> mx.array:
    """PyTorch の配列を MLX の配列にする。bfloat16 は numpy にないので、float32 を経由する。"""
    import torch

    if tensor.dtype == torch.bfloat16:
        return mx.array(tensor.detach().to(torch.float32).numpy()).astype(mx.bfloat16)
    return mx.array(np.asarray(tensor.detach().numpy()))


@contextmanager
def readable_checkpoint(path: Path) -> Generator[Path]:
    """mlx-lm が読める（`model*.safetensors` がある）フォルダを返す。

    PyTorch の `.bin` だけなら、一時フォルダに safetensors を書き、
    ほかのファイルは symlink で並べる。
    """
    if any(path.glob("model*.safetensors")):
        yield path
        return
    checkpoints = sorted(path.glob("pytorch_model*.bin"))
    if not checkpoints:
        raise UnsupportedError(
            f"変換できる重み（model*.safetensors か pytorch_model*.bin）がありません: {path}"
        )
    import torch

    with tempfile.TemporaryDirectory(prefix="sundesk-convert-") as temporary:
        directory = Path(temporary)
        for file in path.iterdir():
            if (
                file.is_file()
                and file.suffix != ".bin"
                and not file.name.endswith(".bin.index.json")
            ):
                (directory / file.name).symlink_to(file.resolve())
        count = len(checkpoints)
        for index, checkpoint in enumerate(checkpoints, start=1):
            state: Any = torch.load(checkpoint, map_location="cpu", weights_only=True)
            weights = {str(name): _torch_to_mlx(tensor) for name, tensor in state.items()}
            name = (
                "model.safetensors"
                if count == 1
                else f"model-{index:05d}-of-{count:05d}.safetensors"
            )
            save: Any = import_module("mlx.core").save_safetensors
            save(str(directory / name), weights)
            del state, weights
        yield directory


def convert_model(source: Source, output_dir: Path, settings: ConvertSettings, emit: Emit) -> Event:
    if settings.quantize is not None:
        settings.quantize.validate()
    emit({"type": "loading", "model": source.model_id})
    with readable_checkpoint(source.path) as readable:
        piece = load_workpiece(readable)
        # 遅らせて読んだ重みは一時フォルダを指すので、書き終えるまで `with` の中にいる
        with staging(output_dir) as directory:
            if settings.quantize is not None:
                dequantize(piece)
            cast_floats(piece.model, DTYPES[settings.dtype])
            piece.config["torch_dtype"] = settings.dtype
            if settings.quantize is not None:
                quantize_affine(piece, settings.quantize, emit, stage="converting")
            else:
                materialize(piece.model, emit, "converting")
            bits = bits_per_weight(piece.model)
            progress(emit, "saving", None, "保存しています")
            save_workpiece(directory, piece.model, piece.tokenizer, piece.config, source.path)
    return done_event(output_dir, bits)
