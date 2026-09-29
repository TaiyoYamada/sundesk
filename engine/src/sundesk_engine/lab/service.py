"""LLM 実験室の計算。どれも MLX 用のワーカースレッドで呼ぶ。"""

import time
from typing import Any

import mlx.core as mx
import numpy as np
from pydantic import BaseModel

from sundesk_engine.errors import BadRequestError
from sundesk_engine.lab.arrays import evaluate, to_float, to_int
from sundesk_engine.lab.generation import generate_text, generate_tokens
from sundesk_engine.lab.introspect import (
    anatomy,
    capture_attention,
    capture_hidden_states,
    hook_layers,
)
from sundesk_engine.lab.sampling import (
    Probabilities,
    SamplingOptions,
    entropy,
    probabilities,
    top_indices,
)
from sundesk_engine.lab.tokens import encode_prompt, token_text, tokenize_with_offsets
from sundesk_engine.streaming import Emit

# JSON を小さくするため、確率などは小数点以下この桁数で丸める
_DIGITS = 6
_ARGMAX_LIMIT = 10


def _round(value: float) -> float:
    return round(float(value), _DIGITS)


class TokenSpanOut(BaseModel):
    id: int
    text: str
    start: int | None
    end: int | None


class TokenizeResponse(BaseModel):
    tokens: list[TokenSpanOut]


class TokenOut(BaseModel):
    id: int
    text: str


class CandidateOut(BaseModel):
    id: int
    text: str
    probability: float


class NextTokenCandidate(CandidateOut):
    logit: float


class NextTokenResponse(BaseModel):
    tokens: list[NextTokenCandidate]
    entropy: float


class AttentionResponse(BaseModel):
    tokens: list[TokenOut]
    num_layers: int
    num_heads: int
    layer: int
    heads: list[list[list[float]]]
    mean: list[list[float]]


class LensPosition(BaseModel):
    top: list[CandidateOut]


class LensLayer(BaseModel):
    layer: int
    positions: list[LensPosition]


class LogitLensResponse(BaseModel):
    tokens: list[TokenOut]
    num_layers: int
    layers: list[LensLayer]


class ActivationsResponse(BaseModel):
    tokens: list[TokenOut]
    num_layers: int
    norms: list[list[float]]


class SteeringVectorResponse(BaseModel):
    layer: int
    vector: list[float]
    norm: float


class SteeringGenerateResponse(BaseModel):
    baseline: str
    steered: str


def _tokens(tokenizer: Any, ids: list[int]) -> list[TokenOut]:
    return [TokenOut(id=token, text=token_text(tokenizer, token)) for token in ids]


def _candidates(tokenizer: Any, probs: Probabilities, ids: list[int]) -> list[CandidateOut]:
    return [
        CandidateOut(id=token, text=token_text(tokenizer, token), probability=_round(probs[token]))
        for token in ids
    ]


def _top_probabilities(logits: mx.array, count: int) -> tuple[mx.array, mx.array]:
    """各行の確率の上位 `count` 個の (ID, 確率)。全体の softmax と並べ替えを避けて速くする。"""
    values = logits.astype(mx.float32)
    normalizer = mx.logsumexp(values, axis=-1, keepdims=True)
    if count > _ARGMAX_LIMIT:
        order = mx.argpartition(-values, kth=count - 1, axis=-1)[:, :count]
        return order, mx.exp(mx.take_along_axis(values, order, axis=-1) - normalizer)
    # 少ないときは、最大値を取っては消すのを繰り返すほうが速い
    indices: list[mx.array] = []
    probabilities_: list[mx.array] = []
    for _ in range(count):
        index = mx.argmax(values, axis=-1, keepdims=True)
        indices.append(index)
        probabilities_.append(mx.exp(mx.take_along_axis(values, index, axis=-1) - normalizer))
        values = mx.put_along_axis(values, index, mx.array(-mx.inf, dtype=mx.float32), axis=-1)
    return mx.concatenate(indices, axis=-1), mx.concatenate(probabilities_, axis=-1)


def tokenize(tokenizer: Any, text: str) -> TokenizeResponse:
    spans = tokenize_with_offsets(tokenizer, text)
    return TokenizeResponse(
        tokens=[
            TokenSpanOut(id=span.id, text=span.text, start=span.start, end=span.end)
            for span in spans
        ]
    )


def next_token(
    model: Any, tokenizer: Any, prompt: str, chat_template: bool, top_k: int, temperature: float
) -> NextTokenResponse:
    parts = anatomy(model)
    ids = encode_prompt(tokenizer, prompt, chat_template)
    logits = parts.forward(ids)[-1].astype(mx.float32)
    probs = probabilities(logits, temperature)
    raw = to_float(logits)
    return NextTokenResponse(
        tokens=[
            NextTokenCandidate(
                id=token,
                text=token_text(tokenizer, token),
                probability=_round(probs[token]),
                logit=_round(raw[token]),
            )
            for token in top_indices(probs, top_k)
        ],
        entropy=_round(entropy(probs)),
    )


def stream_generation(
    model: Any,
    tokenizer: Any,
    *,
    prompt: str,
    chat_template: bool,
    max_tokens: int,
    options: SamplingOptions,
    seed: int | None,
    alternatives: int,
    emit: Emit,
) -> None:
    ids = encode_prompt(tokenizer, prompt, chat_template)

    def on_token(token: int, text: str, probs: Probabilities) -> None:
        emit(
            {
                "type": "token",
                "id": token,
                "text": text,
                "probability": _round(probs[token]),
                "alternatives": [
                    candidate.model_dump()
                    for candidate in _candidates(
                        tokenizer, probs, top_indices(probs, alternatives, exclude=token)
                    )
                ],
            }
        )

    stats = generate_tokens(
        model,
        tokenizer,
        ids,
        max_tokens=max_tokens,
        options=options,
        rng=np.random.default_rng(seed),
        on_token=on_token,
    )
    emit(
        {
            "type": "done",
            "generated_tokens": stats.generated_tokens,
            "tokens_per_second": round(stats.tokens_per_second, 2),
        }
    )


def attention(
    model: Any, tokenizer: Any, prompt: str, chat_template: bool, layer: int
) -> AttentionResponse:
    parts = anatomy(model)
    index = parts.check_layer(layer)
    ids = encode_prompt(tokenizer, prompt, chat_template)
    weights = capture_attention(parts, ids, index)
    values = np.round(to_float(weights), _DIGITS)
    return AttentionResponse(
        tokens=_tokens(tokenizer, ids),
        num_layers=parts.num_layers,
        num_heads=int(values.shape[0]),
        layer=index,
        heads=values.tolist(),
        mean=np.round(values.mean(axis=0), _DIGITS).tolist(),
    )


def logit_lens(
    model: Any, tokenizer: Any, prompt: str, chat_template: bool, top_k: int
) -> LogitLensResponse:
    parts = anatomy(model)
    ids = encode_prompt(tokenizer, prompt, chat_template)
    _logits, states = capture_hidden_states(parts, ids)
    count = max(1, min(top_k, 100))
    layers: list[LensLayer] = []
    for index, state in enumerate(states):
        # 層ごとに計算して、語彙の大きさの配列を一度にたくさん持たないようにする
        order, values = _top_probabilities(parts.unembed(state[None])[0], count)
        evaluate(order, values)
        order_np = to_int(order)
        values_np = to_float(values)
        positions: list[LensPosition] = []
        for row_ids, row_values in zip(order_np, values_np, strict=True):
            ranked = sorted(
                zip(row_ids.tolist(), row_values.tolist(), strict=True), key=lambda p: -p[1]
            )
            positions.append(
                LensPosition(
                    top=[
                        CandidateOut(
                            id=int(token),
                            text=token_text(tokenizer, int(token)),
                            probability=_round(value),
                        )
                        for token, value in ranked
                    ]
                )
            )
        layers.append(LensLayer(layer=index, positions=positions))
    return LogitLensResponse(
        tokens=_tokens(tokenizer, ids), num_layers=parts.num_layers, layers=layers
    )


def activations(
    model: Any, tokenizer: Any, prompt: str, chat_template: bool
) -> ActivationsResponse:
    parts = anatomy(model)
    ids = encode_prompt(tokenizer, prompt, chat_template)
    _logits, states = capture_hidden_states(parts, ids)
    norms = [mx.linalg.norm(state.astype(mx.float32), axis=-1) for state in states]
    evaluate(*norms)
    return ActivationsResponse(
        tokens=_tokens(tokenizer, ids),
        num_layers=parts.num_layers,
        norms=[np.round(to_float(norm), 4).tolist() for norm in norms],
    )


def steering_vector(
    model: Any,
    tokenizer: Any,
    layer: int,
    positive: list[str],
    negative: list[str],
    chat_template: bool,
) -> SteeringVectorResponse:
    if not positive or not negative:
        raise BadRequestError("positive と negative には、それぞれ 1 つ以上の文を入れてください")
    parts = anatomy(model)
    index = parts.check_layer(layer)

    def mean_state(prompts: list[str]) -> mx.array:
        total: mx.array | None = None
        for prompt in prompts:
            ids = encode_prompt(tokenizer, prompt, chat_template)
            _logits, states = capture_hidden_states(parts, ids)
            last = states[index][-1].astype(mx.float32)
            total = last if total is None else total + last
        assert total is not None  # noqa: S101 - prompts は空でない
        return total / len(prompts)

    vector = mean_state(positive) - mean_state(negative)
    values = to_float(vector)
    return SteeringVectorResponse(
        layer=index,
        vector=np.round(values, _DIGITS).tolist(),
        norm=_round(float(np.linalg.norm(values))),
    )


def steering_generate(
    model: Any,
    tokenizer: Any,
    *,
    prompt: str,
    chat_template: bool,
    layer: int,
    vector: list[float],
    strength: float,
    max_tokens: int,
    temperature: float,
    seed: int | None,
) -> SteeringGenerateResponse:
    parts = anatomy(model)
    index = parts.check_layer(layer)
    ids = encode_prompt(tokenizer, prompt, chat_template)
    hidden_size = parts.hidden_size
    if hidden_size is not None and len(vector) != hidden_size:
        raise BadRequestError(
            f"ベクトルの長さ（{len(vector)}）がモデルの次元（{hidden_size}）と合いません"
        )
    options = SamplingOptions(temperature=temperature)
    chosen_seed = seed if seed is not None else time.time_ns() % (2**32)

    baseline = generate_text(
        model, tokenizer, ids, max_tokens=max_tokens, options=options, seed=chosen_seed
    )

    direction = mx.array(vector, dtype=mx.float32)

    def add(position: int, output: mx.array) -> mx.array | None:
        if position != index:
            return None
        if output.shape[-1] != direction.shape[0]:
            raise BadRequestError(
                f"ベクトルの長さ（{direction.shape[0]}）がモデルの次元（{output.shape[-1]}）と合いません"
            )
        return output + (strength * direction).astype(output.dtype)

    with hook_layers(parts, add):
        steered = generate_text(
            model, tokenizer, ids, max_tokens=max_tokens, options=options, seed=chosen_seed
        )
    return SteeringGenerateResponse(baseline=baseline, steered=steered)
