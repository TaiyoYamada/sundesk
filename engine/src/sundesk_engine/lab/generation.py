"""文章の生成。チャット、実験室の 1 トークンずつの生成、steering で使う。"""

import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import mlx.core as mx
import numpy as np

from sundesk_engine.lab.arrays import evaluate
from sundesk_engine.lab.sampling import Probabilities, SamplingOptions, probabilities, sample

type OnToken = Callable[[int, str, Probabilities], None]


@dataclass(frozen=True)
class GenerationStats:
    generated_tokens: int
    tokens_per_second: float
    tail: str
    """最後に残っていた文字（途中で切れたバイト列を閉じたもの）。多くは空"""


def eos_token_ids(tokenizer: Any) -> set[int]:
    ids = getattr(tokenizer, "eos_token_ids", None)
    if ids is None:
        eos = getattr(tokenizer, "eos_token_id", None)
        return {int(eos)} if eos is not None else set()
    return {int(token) for token in ids}


def _rate(count: int, started: float | None) -> float:
    if started is None or count == 0:
        return 0.0
    elapsed = time.perf_counter() - started
    return count / elapsed if elapsed > 0 else 0.0


def generate_tokens(
    model: Any,
    tokenizer: Any,
    ids: list[int],
    *,
    max_tokens: int,
    options: SamplingOptions,
    rng: np.random.Generator,
    on_token: OnToken,
) -> GenerationStats:
    """1 トークンずつ確率を計算して抽選する。`on_token(ID, 新しく確定した文字, 確率)` を呼ぶ。

    文字の途中で切れたトークンは、文字が確定するまで空の文字列になる。
    """
    from mlx_lm.models.cache import make_prompt_cache

    cache: Any = make_prompt_cache(model)
    eos = eos_token_ids(tokenizer)
    detokenizer: Any = tokenizer.detokenizer
    detokenizer.reset()

    logits: mx.array = model(mx.array(ids, dtype=mx.int32)[None], cache=cache)[0, -1]
    evaluate(logits)
    started = time.perf_counter()
    count = 0
    for _ in range(max_tokens):
        probs = probabilities(logits, options.temperature)
        token = sample(probs, options, rng)
        if token in eos:
            break
        detokenizer.add_token(token)
        on_token(token, str(detokenizer.last_segment), probs)
        count += 1
        if count == max_tokens:
            break
        logits = model(mx.array([[token]], dtype=mx.int32), cache=cache)[0, -1]
        evaluate(logits)
    detokenizer.finalize()
    return GenerationStats(count, _rate(count, started), str(detokenizer.last_segment))


def generate_text(
    model: Any,
    tokenizer: Any,
    ids: list[int],
    *,
    max_tokens: int,
    options: SamplingOptions,
    seed: int,
) -> str:
    pieces: list[str] = []
    stats = generate_tokens(
        model,
        tokenizer,
        ids,
        max_tokens=max_tokens,
        options=options,
        rng=np.random.default_rng(seed),
        on_token=lambda _token, text, _probs: pieces.append(text),
    )
    return "".join(pieces) + stats.tail


def stream_chat(
    model: Any,
    tokenizer: Any,
    ids: list[int],
    *,
    max_tokens: int,
    temperature: float,
    top_p: float,
    on_text: Callable[[str], None],
) -> GenerationStats:
    """mlx-lm の生成でチャットの応答を作る。長いプロンプトも少しずつ読ませる。"""
    from mlx_lm.generate import generate_step
    from mlx_lm.sample_utils import make_sampler

    sampler: Any = make_sampler(temp=temperature, top_p=top_p if 0 < top_p < 1 else 0.0)
    eos = eos_token_ids(tokenizer)
    detokenizer: Any = tokenizer.detokenizer
    detokenizer.reset()
    started: float | None = None
    count = 0
    steps: Any = generate_step(
        mx.array(ids, dtype=mx.int32), model, max_tokens=max_tokens, sampler=sampler
    )
    for token, _logprobs in steps:
        if started is None:
            started = time.perf_counter()
        if int(token) in eos:
            break
        detokenizer.add_token(int(token))
        count += 1
        segment = str(detokenizer.last_segment)
        if segment:
            on_text(segment)
    detokenizer.finalize()
    return GenerationStats(count, _rate(count, started), str(detokenizer.last_segment))
