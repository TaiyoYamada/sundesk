"""いくつかのモデルを、同じ文章と同じプロンプトで比べる。"""

import math
import time
from dataclasses import dataclass
from typing import Any

import mlx.core as mx
import numpy as np

from sundesk_engine.lab.arrays import evaluate, to_scalar
from sundesk_engine.lab.generation import generate_tokens
from sundesk_engine.lab.sampling import SamplingOptions
from sundesk_engine.lab.tokens import encode_prompt, has_chat_template

PERPLEXITY_WINDOW = 1024
"""パープレキシティは、この長さの窓ごとに計算する（長い文章でもメモリを使いすぎないように）"""


@dataclass(frozen=True)
class Perplexity:
    value: float | None
    """exp(平均の負の対数尤度)。当てる位置が 1 つもなければ None"""
    tokens: int
    seconds: float


@dataclass(frozen=True)
class Samples:
    texts: list[str]
    generated_tokens: int
    seconds: float

    @property
    def tokens_per_second(self) -> float:
        return self.generated_tokens / self.seconds if self.seconds > 0 else 0.0


def perplexity(model: Any, tokenizer: Any, texts: list[str]) -> Perplexity:
    """文章の続きを当てる難しさ。各トークンを、それより前のトークンから当てる確率で測る。"""
    started = time.perf_counter()
    total = 0.0
    count = 0
    for text in texts:
        ids = [int(token) for token in tokenizer.encode(text)]
        for start in range(0, max(len(ids) - 1, 0), PERPLEXITY_WINDOW):
            window = ids[start : start + PERPLEXITY_WINDOW + 1]
            if len(window) < 2:
                continue
            inputs = mx.array(window[:-1], dtype=mx.int32)[None]
            targets = mx.array(window[1:], dtype=mx.int32)[None]
            logits = model(inputs).astype(mx.float32)
            chosen = mx.take_along_axis(logits, targets[..., None], axis=-1)[..., 0]
            negative = mx.sum(mx.logsumexp(logits, axis=-1) - chosen)
            evaluate(negative)
            total += to_scalar(negative)
            count += len(window) - 1
    value = math.exp(total / count) if count else None
    return Perplexity(value=value, tokens=count, seconds=time.perf_counter() - started)


def samples(
    model: Any,
    tokenizer: Any,
    prompts: list[str],
    *,
    max_tokens: int,
    temperature: float,
    seed: int,
    chat_template: bool,
) -> Samples:
    """プロンプトごとに、同じ種で生成する。"""
    texts: list[str] = []
    generated = 0
    seconds = 0.0
    for prompt in prompts:
        ids = encode_prompt(
            tokenizer, prompt, chat_template and has_chat_template(tokenizer), limit=None
        )
        pieces: list[str] = []
        started = time.perf_counter()
        stats = generate_tokens(
            model,
            tokenizer,
            ids,
            max_tokens=max_tokens,
            options=SamplingOptions(temperature=temperature),
            rng=np.random.default_rng(seed),
            on_token=lambda _token, text, _probs, pieces=pieces: pieces.append(text),
        )
        seconds += time.perf_counter() - started
        generated += stats.generated_tokens
        texts.append("".join(pieces) + stats.tail)
    return Samples(texts=texts, generated_tokens=generated, seconds=seconds)
