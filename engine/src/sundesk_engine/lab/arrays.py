"""MLX の配列を扱う小さな道具。型の情報が足りない呼び出しをここに閉じ込める。"""

import mlx.core as mx
import numpy as np
from numpy.typing import NDArray


def evaluate(*arrays: mx.array) -> None:
    """遅延している計算を実行する。"""
    mx.eval(*arrays)  # pyright: ignore[reportUnknownMemberType]


def to_float(array: mx.array) -> NDArray[np.float64]:
    return np.asarray(array.astype(mx.float32), dtype=np.float64)


def to_int(array: mx.array) -> NDArray[np.int64]:
    return np.asarray(array.astype(mx.int64), dtype=np.int64)
