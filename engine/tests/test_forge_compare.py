"""蒸留と、モデルの比べ方（評価）のテスト。"""

import json
import math
from pathlib import Path
from typing import Any

import mlx.core as mx
import numpy as np
import pytest
from conftest import Harness
from fakes import LLM_ID, ndjson, tiny_tokenizer

from sundesk_engine.forge.distill import distill_losses
from sundesk_engine.forge.evaluate import perplexity
from sundesk_engine.lab.arrays import to_float, to_scalar

TEACHER = "test/teacher"
STUDENT = "test/student"
TEXTS = [
    "固有値とは線形変換で向きが変わらないベクトルの伸縮率である。",
    "行列分解は線形代数の道具です。",
    "猫はかわいい。犬もかわいい。",
    "hello world, the quick brown fox.",
    "固有値分解は行列分解の一種である。",
    "今日は晴れです。",
]


@pytest.fixture
def pair(harness: Harness) -> tuple[Path, Path]:
    teacher = harness.hub.add_disk_model(TEACHER, seed=5, num_layers=3)
    student = harness.hub.add_disk_model(STUDENT, seed=0)
    return teacher, student


def distill(harness: Harness, **fields: object) -> list[dict[str, Any]]:
    body = {
        "teacher": TEACHER,
        "student": STUDENT,
        "texts": TEXTS,
        "output_dir": str(harness.tmp_path / "Forged" / "distilled"),
        "iterations": 30,
        "learning_rate": 1e-2,
        "temperature": 2.0,
        "alpha": 0.5,
        "max_seq_length": 64,
        "batch_size": 2,
        "lora_rank": 4,
    } | fields
    return ndjson(harness.client.post("/forge/distill", json=body))


# MARK: - 蒸留


def test_distill_with_lora_writes_an_adapter(harness: Harness, pair: tuple[Path, Path]) -> None:
    from mlx_lm.utils import load

    _teacher, student = pair

    events = distill(harness)

    assert [e["model"] for e in events if e["type"] == "loading"] == [TEACHER, STUDENT]
    progress = [e for e in events if e["type"] == "progress"]
    assert [e["iteration"] for e in progress] == [10, 20, 30]
    assert all(e["total"] == 30 for e in progress)
    assert all(isinstance(e[key], float) for e in progress for key in ("loss", "kl", "ce"))
    assert progress[-1]["loss"] < progress[0]["loss"]
    validation = [e for e in events if e["type"] == "validation"]
    assert [e["iteration"] for e in validation] == [1, 30]
    assert all(isinstance(e["loss"], float) for e in validation)
    target = harness.tmp_path / "Forged" / "distilled"
    assert events[-1] == {"type": "done", "output_dir": str(target), "kind": "adapter"}

    config = json.loads((target / "adapter_config.json").read_text())
    assert config["fine_tune_type"] == "lora"
    assert config["lora_parameters"]["rank"] == 4
    assert config["distillation"]["teacher"] == TEACHER
    loaded: Any = load(str(student), adapter_path=str(target))
    ids = mx.array(tiny_tokenizer().encode("固有値"), dtype=mx.int32)[None]
    assert np.isfinite(np.asarray(loaded[0](ids))).all()
    # 学習が終わったら、どちらも載せたままにしない
    assert harness.engine.models.loaded()["llm"] is None


def test_distill_full_fine_tune_writes_a_model(harness: Harness, pair: tuple[Path, Path]) -> None:
    from mlx_lm.utils import load

    events = distill(harness, lora_rank=None, learning_rate=3e-3, alpha=1.0)

    assert events[-1]["kind"] == "model", events[-1]
    progress = [e for e in events if e["type"] == "progress"]
    assert progress[-1]["kl"] < progress[0]["kl"]
    target = harness.tmp_path / "Forged" / "distilled"
    loaded: Any = load(str(target))
    assert len(loaded[0].layers) == 2
    assert json.loads((target / "config.json").read_text())["model_type"] == "qwen3"


def test_distill_rejects_different_vocabularies(harness: Harness) -> None:
    harness.hub.add_disk_model(TEACHER, vocab_size=300)
    harness.hub.add_disk_model(STUDENT)

    response = harness.client.post(
        "/forge/distill",
        json={
            "teacher": TEACHER,
            "student": STUDENT,
            "texts": TEXTS,
            "output_dir": str(harness.tmp_path / "out"),
        },
    )

    assert response.status_code == 422
    assert "語彙" in response.json()["detail"]


def test_distill_losses() -> None:
    logits = mx.array(np.random.default_rng(0).normal(size=(1, 3, 5)).astype(np.float32))
    targets = mx.array([[1, 2, 3]], dtype=mx.int32)
    mask = mx.array([[1.0, 1.0, 0.0]])

    loss, kl, ce = distill_losses(logits, logits, targets, mask, 2.0, 0.5)

    assert to_scalar(kl) == pytest.approx(0.0, abs=1e-6)
    values = to_float(logits)[0]
    log_probs = values - np.log(np.exp(values).sum(axis=-1, keepdims=True))
    expected_ce = -(log_probs[0, 1] + log_probs[1, 2]) / 2
    assert to_scalar(ce) == pytest.approx(expected_ce, rel=1e-5)
    assert to_scalar(loss) == pytest.approx(0.5 * expected_ce, rel=1e-5)
    # 出力の数が違えば、短いほうに合わせる
    padded = mx.concatenate([logits, mx.zeros((1, 3, 2))], axis=-1)
    _loss, kl_padded, _ce = distill_losses(logits, padded, targets, mask, 2.0, 0.5)
    assert to_scalar(kl_padded) == pytest.approx(0.0, abs=1e-6)


# MARK: - 比べる


def test_evaluate_streams_one_result_per_model(harness: Harness, pair: tuple[Path, Path]) -> None:
    teacher, _student = pair
    body = {
        "models": [{"model": STUDENT, "adapter": None}, {"model": TEACHER}, {"model": STUDENT}],
        "texts": TEXTS[:3],
        "prompts": ["固有値とは", "猫は"],
        "max_tokens": 6,
        "seed": 3,
    }

    events = ndjson(harness.client.post("/forge/evaluate", json=body))

    assert [e["type"] for e in events] == ["loading", "result"] * 3 + ["done"]
    results = [e for e in events if e["type"] == "result"]
    first = results[0]
    assert set(first) == {
        "type",
        "model",
        "adapter",
        "perplexity",
        "tokens",
        "seconds",
        "tokens_per_second",
        "size_bytes",
        "peak_memory_bytes",
        "samples",
    }
    assert first["model"] == STUDENT
    assert first["adapter"] is None
    assert first["perplexity"] > 1.0
    assert first["tokens"] > 10
    assert first["seconds"] >= 0
    assert first["tokens_per_second"] >= 0
    assert first["peak_memory_bytes"] > 0
    assert results[1]["size_bytes"] == sum(
        file.stat().st_size for file in teacher.iterdir() if file.is_file()
    )
    assert len(first["samples"]) == 2
    assert all(isinstance(sample, str) for sample in first["samples"])
    # 同じモデルと同じ種なら、同じ結果になる
    assert results[2]["samples"] == first["samples"]
    assert results[2]["perplexity"] == first["perplexity"]
    assert results[1]["perplexity"] != first["perplexity"]


def test_evaluate_with_adapter(harness: Harness) -> None:
    from test_forge import make_adapter

    base = harness.hub.add_disk_model(STUDENT)
    adapter = make_adapter(base, harness.tmp_path / "adapter")
    body = {
        "models": [{"model": STUDENT}, {"model": STUDENT, "adapter": str(adapter)}],
        "texts": TEXTS,
    }

    events = ndjson(harness.client.post("/forge/evaluate", json=body))

    plain, adapted = (e for e in events if e["type"] == "result")
    assert adapted["adapter"] == str(adapter)
    assert adapted["perplexity"] != plain["perplexity"]
    assert adapted["size_bytes"] > plain["size_bytes"]
    assert plain["samples"] == []


def test_evaluate_rejects_bad_requests(harness: Harness) -> None:
    client = harness.client

    nothing = client.post("/forge/evaluate", json={"models": [{"model": LLM_ID}]})
    missing = client.post(
        "/forge/evaluate", json={"models": [{"model": "test/missing"}], "texts": ["a"]}
    )
    empty = client.post("/forge/evaluate", json={"models": [], "texts": ["a"]})

    assert nothing.status_code == 400
    assert missing.status_code == 404
    assert empty.status_code == 400


def test_perplexity_of_a_uniform_model_is_the_vocabulary_size() -> None:
    vocabulary = 50

    def uniform(inputs: mx.array) -> mx.array:
        return mx.zeros((*inputs.shape, vocabulary))

    class Tokenizer:
        def encode(self, text: str) -> list[int]:
            return [ord(character) % vocabulary for character in text]

    result = perplexity(uniform, Tokenizer(), ["abcdef", "x", "hello"])

    assert result.value == pytest.approx(vocabulary)
    assert result.tokens == 5 + 0 + 4
    assert math.isfinite(result.seconds)
