"""スクラッチの `show(x)` で出すもの（図、表、画像）を、出力の行にする。"""

import base64
import io
import math
from collections.abc import Mapping, Sequence
from typing import Any

import mlx.core as mx
import numpy as np

from sundesk_engine.lab.arrays import to_float
from sundesk_engine.streaming import Event

MAX_TABLE_ROWS = 10_000
MAX_VALUE_LENGTH = 20_000
FIGURE_DPI = 100


def figure_event(figure: Any) -> Event:
    """matplotlib の図を PNG にする。"""
    buffer = io.BytesIO()
    figure.savefig(buffer, format="png", dpi=FIGURE_DPI, bbox_inches="tight")
    return _png_event(buffer.getvalue())


def image_event(image: Any) -> Event:
    """PIL の画像を PNG にする。"""
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return _png_event(buffer.getvalue())


def _png_event(data: bytes) -> Event:
    return {"type": "image", "png_base64": base64.b64encode(data).decode("ascii")}


def value_event(value: object) -> Event:
    text = repr(value)
    if len(text) > MAX_VALUE_LENGTH:
        text = text[:MAX_VALUE_LENGTH] + "…"
    return {"type": "value", "repr": text}


def cell(value: object) -> object:
    """表の 1 つのマスを、JSON にできる値にする。NaN と無限大は null にする。"""
    if isinstance(value, np.generic):
        generic: Any = value  # pyright: ignore[reportUnknownVariableType]
        value = generic.item()
    elif isinstance(value, mx.array) and value.size == 1:
        value = float(to_float(value).reshape(-1)[0])
    if value is None or isinstance(value, bool | int | str):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    return str(value)


def table_event(columns: Sequence[object], rows: Sequence[Sequence[object]]) -> Event:
    return {
        "type": "table",
        "columns": [str(column) for column in columns],
        "rows": [[cell(item) for item in row] for row in rows[:MAX_TABLE_ROWS]],
    }


def _records_table(records: Sequence[Mapping[Any, Any]]) -> Event:
    columns: list[object] = []
    for record in records:
        for key in record:
            if key not in columns:
                columns.append(key)
    rows = [[record.get(column) for column in columns] for record in records]
    return table_event(columns, rows)


def _array_event(array: np.ndarray[Any, Any]) -> Event:
    if array.ndim == 1:
        return table_event(["値"], [[item] for item in array.tolist()])
    if array.ndim == 2:
        return table_event([str(index) for index in range(array.shape[1])], array.tolist())
    if array.ndim == 3 and array.shape[2] in (1, 3, 4):
        from PIL import Image

        pixels = array
        if pixels.dtype != np.uint8:
            pixels = (np.clip(pixels.astype(np.float64), 0.0, 1.0) * 255).round().astype(np.uint8)
        if pixels.shape[2] == 1:
            pixels = pixels[:, :, 0]
        return image_event(Image.fromarray(pixels))
    raise TypeError(
        f"show() に渡せる配列は 1〜2 次元（表）か、高さ×幅×色（画像）です: {array.shape}"
    )


def to_events(value: object) -> list[Event]:
    """`show(x)` の `x` を、出力の行にする。"""
    from matplotlib.figure import Figure
    from PIL import Image

    kind = type(value).__name__
    if isinstance(value, Figure):
        return [figure_event(value)]
    if isinstance(value, Image.Image):
        return [image_event(value)]
    if isinstance(value, mx.array):
        return [
            _array_event(
                np.asarray(value.astype(mx.float32) if value.dtype == mx.bfloat16 else value)
            )
        ]
    if isinstance(value, np.ndarray):
        return [_array_event(value)]  # pyright: ignore[reportUnknownArgumentType]
    if isinstance(value, Sequence) and not isinstance(value, str | bytes) and value:
        items: Sequence[object] = list(value)  # pyright: ignore[reportUnknownArgumentType]
        if all(isinstance(item, Mapping) for item in items):
            return [_records_table(items)]  # pyright: ignore[reportArgumentType]
        if all(isinstance(item, Sequence) and not isinstance(item, str | bytes) for item in items):
            rows: list[Sequence[object]] = list(items)  # pyright: ignore[reportAssignmentType]
            width = max(len(row) for row in rows)
            return [table_event([str(index) for index in range(width)], rows)]
    raise TypeError(
        "show() に渡せるのは、matplotlib の図、PIL の画像、dict の list、2 次元の配列です"
        f"（渡されたもの: {kind}）"
    )
