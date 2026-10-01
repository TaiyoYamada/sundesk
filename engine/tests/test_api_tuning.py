"""LoRA の学習と steering の API のテスト。小さなランダムの Qwen3 で、本物の計算を通す。"""

import json

import mlx.core as mx
import pytest
from conftest import Harness
from fakes import HIDDEN_SIZE, LLM_ID, ndjson
from fastapi.testclient import TestClient

TEXTS = [
    "固有値とは線形変換で向きが変わらないベクトルの伸縮率である。",
    "行列分解は線形代数の道具です。",
    "猫はかわいい。犬もかわいい。",
    "hello world, the quick brown fox.",
    "固有値分解は行列分解の一種である。",
]


@pytest.fixture(autouse=True)
def cpu_only_training(monkeypatch: pytest.MonkeyPatch) -> None:
    """テストは CPU で計算するので、mlx-lm の学習が Metal の設定に触らないようにする。"""
    monkeypatch.setattr(mx.metal, "is_available", lambda: False)


def train(harness: Harness, name: str = "adapter", **fields: object) -> list[dict[str, object]]:
    body = {
        "model": LLM_ID,
        "texts": TEXTS,
        "adapter_path": str(harness.tmp_path / name),
        "iterations": 12,
        "rank": 4,
        "learning_rate": 1e-3,
        "batch_size": 1,
        "max_seq_length": 64,
        "num_layers": 2,
    } | fields
    return ndjson(harness.client.post("/lora/train", json=body))


def test_lora_training_streams_and_saves_adapter(harness: Harness) -> None:
    events = train(harness)

    assert events[0] == {"type": "loading", "model": LLM_ID}
    progress = [e for e in events if e["type"] == "progress"]
    assert [e["iteration"] for e in progress] == [10, 12]
    assert all(e["total"] == 12 and isinstance(e["train_loss"], float) for e in progress)
    validation = [e for e in events if e["type"] == "validation"]
    assert validation
    assert all(isinstance(e["val_loss"], float) for e in validation)
    assert events[-1] == {"type": "done", "adapter_path": str(harness.tmp_path / "adapter")}

    adapter = harness.tmp_path / "adapter"
    config = json.loads((adapter / "adapter_config.json").read_text())
    assert config["fine_tune_type"] == "lora"
    assert config["num_layers"] == 2
    assert config["lora_parameters"]["rank"] == 4
    assert (adapter / "adapters.safetensors").is_file()
    # 学習で書き換えたモデルは捨てる
    assert harness.engine.models.loaded()["llm"] is None


def test_adapter_is_used_for_generation(harness: Harness) -> None:
    train(harness)
    adapter = str(harness.tmp_path / "adapter")
    request = {"model": LLM_ID, "prompt": "固有値", "max_tokens": 3, "adapter": adapter}

    events = ndjson(harness.client.post("/lab/generate", json=request))

    assert events[-1]["type"] == "done"
    assert harness.client.get("/models/loaded").json()["adapter"] == adapter
    assert harness.llm.loads[-1][1] is not None
    chat = ndjson(
        harness.client.post(
            "/chat",
            json={
                "model": LLM_ID,
                "messages": [{"role": "user", "content": "a"}],
                "max_tokens": 2,
                "adapter": adapter,
            },
        )
    )
    # 同じアダプタなら載せ直さない
    assert chat[0]["type"] != "loading"


def test_lora_needs_enough_texts(harness: Harness) -> None:
    events = train(harness, texts=["短い"])

    assert events[-1]["type"] == "error"
    assert "足りません" in str(events[-1]["message"])


def test_lora_requires_absolute_path(client: TestClient) -> None:
    response = client.post(
        "/lora/train", json={"model": LLM_ID, "texts": TEXTS, "adapter_path": "relative"}
    )

    assert response.status_code == 400


def test_steering_vector(client: TestClient) -> None:
    response = client.post(
        "/steering/vector",
        json={
            "model": LLM_ID,
            "layer": 1,
            "positive": ["猫はかわいい。", "犬もかわいい。"],
            "negative": ["行列分解は線形代数の道具です。"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["layer"] == 1
    assert len(body["vector"]) == HIDDEN_SIZE
    assert body["norm"] == pytest.approx(sum(v * v for v in body["vector"]) ** 0.5, rel=1e-4)
    assert body["norm"] > 0


def test_steering_generate(client: TestClient) -> None:
    vector = client.post(
        "/steering/vector",
        json={"model": LLM_ID, "layer": 0, "positive": ["猫"], "negative": ["行列"]},
    ).json()["vector"]
    base = {
        "model": LLM_ID,
        "prompt": "固有値とは",
        "layer": 0,
        "vector": vector,
        "max_tokens": 8,
        "temperature": 0.8,
        "seed": 3,
    }

    unchanged = client.post("/steering/generate", json=base | {"strength": 0.0}).json()
    steered = client.post("/steering/generate", json=base | {"strength": 50.0}).json()

    assert set(unchanged) == {"baseline", "steered"}
    assert unchanged["baseline"] == unchanged["steered"]
    assert steered["baseline"] == unchanged["baseline"]
    assert steered["steered"] != steered["baseline"]


def test_steering_rejects_wrong_vector_length(client: TestClient) -> None:
    response = client.post(
        "/steering/generate",
        json={"model": LLM_ID, "prompt": "a", "layer": 0, "vector": [1.0, 2.0]},
    )

    assert response.status_code == 400
    assert "ベクトルの長さ" in response.json()["detail"]
