"""mlx-lm のモデルの中身を覗くための道具。

対応するのは `model.model.embed_tokens`、`layers`、`norm` を持つモデル
（Llama、Qwen、Mistral など）。
層の出力は、`layers` の各要素を一時的に包んで受け取る。モデル本体の計算（マスクの作り方など）は
そのまま使うので、自前で層を回すよりも、モデルごとの違いに強い。
"""

import sys
from collections.abc import Callable, Generator
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any

import mlx.core as mx

from sundesk_engine.errors import UnsupportedError
from sundesk_engine.lab.arrays import evaluate

type LayerCallback = Callable[[int, mx.array], mx.array | None]

_SDPA_NAME = "scaled_dot_product_attention"
_SDPA_PARAMETERS = ("queries", "keys", "values", "cache", "scale", "mask", "sinks")


@dataclass
class Anatomy:
    """覗くのに使う、モデルの部品。"""

    model: Any
    layers: list[Any]
    norm: Any
    head: Callable[[mx.array], mx.array]

    @property
    def num_layers(self) -> int:
        return len(self.layers)

    @property
    def hidden_size(self) -> int | None:
        """残差ストリームの次元。最後の正規化の重みの長さから分かる。"""
        weight = getattr(self.norm, "weight", None)
        return int(weight.shape[0]) if isinstance(weight, mx.array) else None

    def forward(self, ids: list[int]) -> mx.array:
        """キャッシュなしで順伝播し、各位置の logits（`[位置, 語彙]`）を返す。"""
        logits = self.model(mx.array(ids, dtype=mx.int32)[None])
        if not isinstance(logits, mx.array):
            raise UnsupportedError("このモデルの出力の形には対応していません")
        return logits[0]

    def unembed(self, hidden: mx.array) -> mx.array:
        """途中の状態を、最後の正規化と出力層に通す。"""
        return self.head(self.norm(hidden))

    def check_layer(self, layer: int) -> int:
        """負の番号は後ろから数える。範囲外なら 400 にする。"""
        from sundesk_engine.errors import BadRequestError

        if not -self.num_layers <= layer < self.num_layers:
            raise BadRequestError(
                f"層の番号は 0 から {self.num_layers - 1} までです（指定: {layer}）"
            )
        return layer % self.num_layers


def anatomy(model: Any) -> Anatomy:
    """モデルの部品を取り出す。対応していない構造なら `UnsupportedError`。"""
    inner = getattr(model, "model", None)
    embed = getattr(inner, "embed_tokens", None)
    layers = getattr(inner, "layers", None)
    norm = getattr(inner, "norm", None)
    if inner is None or embed is None or norm is None or not isinstance(layers, list) or not layers:
        raise UnsupportedError(
            "このモデルの構造には対応していません"
            "（model.model.embed_tokens、layers、norm を持つモデルだけを覗けます）"
        )
    lm_head = getattr(model, "lm_head", None)
    if lm_head is not None:
        head: Callable[[mx.array], mx.array] = lm_head
    elif hasattr(embed, "as_linear"):
        head = embed.as_linear
    else:
        raise UnsupportedError("このモデルの出力層を見つけられません")
    return Anatomy(model=model, layers=layers, norm=norm, head=head)  # pyright: ignore[reportUnknownArgumentType]


class _LayerHook:
    """層を包み、出力を受け取る（書き換えることもできる）。"""

    def __init__(self, layer: Any, index: int, callback: LayerCallback) -> None:
        self._layer = layer
        self._index = index
        self._callback = callback

    def __call__(self, *args: Any, **kwargs: Any) -> Any:
        output = self._layer(*args, **kwargs)
        if not isinstance(output, mx.array):
            raise UnsupportedError("このモデルの層の出力の形には対応していません")
        replaced = self._callback(self._index, output)
        return output if replaced is None else replaced

    def __getattr__(self, name: str) -> Any:
        return getattr(self._layer, name)


@contextmanager
def hook_layers(parts: Anatomy, callback: LayerCallback) -> Generator[None]:
    """`with` の中だけ、すべての層の出力を `callback(層の番号, 出力)` に渡す。

    `callback` が配列を返すと、その層の出力をそれに置き換える。
    """
    originals = list(parts.layers)
    try:
        for index, layer in enumerate(originals):
            parts.layers[index] = _LayerHook(layer, index, callback)
        yield
    finally:
        parts.layers[:] = originals


def capture_hidden_states(parts: Anatomy, ids: list[int]) -> tuple[mx.array, list[mx.array]]:
    """順伝播して、logits（`[位置, 語彙]`）と各層の出力（`[位置, 次元]`）を返す。"""
    states: list[mx.array] = []

    def keep(_index: int, output: mx.array) -> None:
        states.append(output[0])

    with hook_layers(parts, keep):
        logits = parts.forward(ids)
    evaluate(logits, *states)
    return logits, states


def _attention_weights(
    queries: mx.array, keys: mx.array, scale: float, mask: mx.array | str | None
) -> mx.array:
    """softmax(QKᵀ × scale + mask) を明示的に計算する。形は `[ヘッド, 問い, 鍵]`。"""
    q = queries.astype(mx.float32)
    k = keys.astype(mx.float32)
    repeats = q.shape[1] // k.shape[1]
    if repeats > 1:
        k = mx.repeat(k, repeats, axis=1)
    scores = (q * scale) @ k.swapaxes(-1, -2)
    if mask is not None:
        if isinstance(mask, str):
            query_length, key_length = scores.shape[-2:]
            query_positions = mx.arange(key_length - query_length, key_length)
            key_positions = mx.arange(key_length)
            mask = query_positions[:, None] >= key_positions[None]
        if mask.dtype == mx.bool_:
            scores = mx.where(mask, scores, mx.array(-mx.inf, dtype=mx.float32))
        else:
            scores = scores + mask.astype(mx.float32)
    return mx.softmax(scores, axis=-1)[0]


def capture_attention(parts: Anatomy, ids: list[int], layer: int) -> mx.array:
    """指定した層の Attention の重み（`[ヘッド, 問い, 鍵]`）を返す。

    モデルのモジュールが `mlx_lm.models.base` から取り込んだ `scaled_dot_product_attention` を
    一時的に差し替え、同じ入力から重みを明示的に計算する。出力はもとの関数のものを使う。
    """
    target = parts.layers[layer]
    attention = getattr(target, "self_attn", None)
    module = sys.modules.get(type(attention).__module__) if attention is not None else None
    original: Any = getattr(module, _SDPA_NAME, None) if module is not None else None
    if module is None or original is None:
        raise UnsupportedError("このモデルでは Attention の重みを取り出せません")

    active = False
    captured: list[mx.array] = []

    def patched(*args: Any, **kwargs: Any) -> Any:
        if active and not captured:
            bound = dict(zip(_SDPA_PARAMETERS, args, strict=False)) | kwargs
            keys = bound.get("keys")
            if not isinstance(keys, mx.array):
                raise UnsupportedError("量子化したキャッシュの Attention は取り出せません")
            captured.append(
                _attention_weights(bound["queries"], keys, float(bound["scale"]), bound.get("mask"))
            )
        return original(*args, **kwargs)

    class _Activate:
        def __call__(self, *args: Any, **kwargs: Any) -> Any:
            nonlocal active
            active = True
            try:
                return target(*args, **kwargs)
            finally:
                active = False

        def __getattr__(self, name: str) -> Any:
            return getattr(target, name)

    setattr(module, _SDPA_NAME, patched)
    parts.layers[layer] = _Activate()
    try:
        parts.forward(ids)
    finally:
        parts.layers[layer] = target
        setattr(module, _SDPA_NAME, original)
    if not captured:
        raise UnsupportedError("このモデルでは Attention の重みを取り出せません")
    weights = captured[0]
    evaluate(weights)
    return weights
