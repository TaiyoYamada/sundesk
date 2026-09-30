"""本物の小さなモデルでの確認。ふだんのテストでは動かさない。

    SUNDESK_ENGINE_SMOKE=1 uv run pytest tests/test_smoke.py -s

初回は mlx-community/Qwen3-0.6B-4bit（約 350MB）と cl-nagoya/ruri-v3-130m（約 500MB）を
Hugging Face のキャッシュにダウンロードする。画像モデルはダウンロードしない。
"""

import json
import os
from collections.abc import Generator
from pathlib import Path
from typing import Any

import numpy as np
import pytest
from fakes import ndjson
from fastapi.testclient import TestClient

from sundesk_engine.app import create_app
from sundesk_engine.engine import Engine

pytestmark = pytest.mark.skipif(
    os.environ.get("SUNDESK_ENGINE_SMOKE") != "1",
    reason="SUNDESK_ENGINE_SMOKE=1 のときだけ、本物のモデルで確かめる",
)

LLM = "mlx-community/Qwen3-0.6B-4bit"
EMBEDDING = "cl-nagoya/ruri-v3-130m"
FRANCE = "The capital of France is"


def show(title: str, value: object) -> None:
    print(f"\n== {title}\n{json.dumps(value, ensure_ascii=False)[:1500]}")


@pytest.fixture(scope="module")
def client() -> Generator[TestClient]:
    import mlx.core as mx

    # テスト全体では CPU にしているが、ここでは本物と同じく GPU で動かす
    mx.set_default_device(mx.gpu)
    engine = Engine.create_default()
    with TestClient(create_app(engine=engine)) as client:
        for model in (LLM, EMBEDDING):
            events = ndjson(client.post("/models/download", json={"id": model}))
            assert events[-1]["type"] == "done", events[-1]
            show(f"download {model}", [events[0], events[-1]])
        yield client
        show("unload", client.post("/models/unload", json={"kind": "all"}).json())
    mx.set_default_device(mx.cpu)


def test_models_are_listed(client: TestClient) -> None:
    kinds = {model["id"]: model["kind"] for model in client.get("/models").json()["models"]}

    assert kinds[LLM] == "llm"
    assert kinds[EMBEDDING] == "embedding"


def test_tokenize(client: TestClient) -> None:
    text = "東京は日本の首都です。"
    tokens = client.post("/lab/tokenize", json={"model": LLM, "text": text}).json()["tokens"]
    show("tokenize", tokens)

    for token in tokens:
        if token["start"] is not None:
            assert text[token["start"] : token["end"]] == token["text"]


def test_next_token_and_logit_lens(client: TestClient) -> None:
    next_token = client.post(
        "/lab/next-token", json={"model": LLM, "prompt": FRANCE, "top_k": 5}
    ).json()
    show("next-token", next_token)
    assert next_token["tokens"][0]["text"].strip() == "Paris"

    lens = client.post("/lab/logit-lens", json={"model": LLM, "prompt": FRANCE, "top_k": 3}).json()
    last_position = [layer["positions"][-1]["top"][0]["text"] for layer in lens["layers"]]
    show("logit-lens（最後の位置の 1 位、層ごと）", last_position)
    assert lens["num_layers"] == 28
    assert last_position[-1].strip() == "Paris"
    assert last_position[0].strip() != "Paris"


def test_attention(client: TestClient) -> None:
    for layer in (0, 13, 27):
        body = client.post(
            "/lab/attention", json={"model": LLM, "prompt": FRANCE, "layer": layer}
        ).json()
        count = len(body["tokens"])
        mean = np.array(body["mean"])
        show(f"attention layer {layer}（最後のトークンの平均）", body["mean"][-1])
        assert body["num_heads"] == 16
        assert np.allclose(mean.sum(axis=1), 1.0, atol=1e-3)
        assert np.allclose(np.triu(mean, 1), 0.0)
        assert mean.shape == (count, count)


def test_activations(client: TestClient) -> None:
    body = client.post("/lab/activations", json={"model": LLM, "prompt": FRANCE}).json()
    norms = np.array(body["norms"])
    show("activations（各層の平均ノルム）", norms.mean(axis=1).round(1).tolist())
    assert norms.shape == (28, len(body["tokens"]))


def test_generate_and_chat(client: TestClient) -> None:
    events = ndjson(
        client.post(
            "/lab/generate",
            json={
                "model": LLM,
                "prompt": "日本の首都はどこですか？一言で答えてください。/no_think",
                "chat_template": True,
                "max_tokens": 40,
                "temperature": 0.7,
                "seed": 1,
                "alternatives": 3,
            },
        )
    )
    tokens = [event for event in events if event["type"] == "token"]
    show("lab/generate", "".join(token["text"] for token in tokens))
    show("lab/generate（最初のトークン）", tokens[0])
    assert events[-1]["type"] == "done"

    chat = ndjson(
        client.post(
            "/chat",
            json={
                "model": LLM,
                "messages": [
                    {"role": "system", "content": "簡潔に日本語で答えてください。"},
                    {"role": "user", "content": "固有値とは何ですか？ /no_think"},
                ],
                "max_tokens": 120,
            },
        )
    )
    show("chat", "".join(event.get("text", "") for event in chat if event["type"] == "token"))
    show("chat done", chat[-1])
    assert chat[-1]["type"] == "done"


def test_steering(client: TestClient) -> None:
    vector = client.post(
        "/steering/vector",
        json={
            "model": LLM,
            "layer": 12,
            "positive": [
                "I love this! It is wonderful and makes me so happy.",
                "What a fantastic, joyful day. Everything is great!",
                "This is the best thing ever. I am delighted.",
            ],
            "negative": [
                "I hate this. It is terrible and makes me so sad.",
                "What an awful, miserable day. Everything is wrong.",
                "This is the worst thing ever. I am furious.",
            ],
        },
    ).json()
    show("steering vector", {"layer": vector["layer"], "norm": vector["norm"]})
    result = client.post(
        "/steering/generate",
        json={
            "model": LLM,
            "prompt": "Write one sentence about Mondays. /no_think",
            "chat_template": True,
            "layer": 12,
            "vector": vector["vector"],
            "strength": 2.0,
            "max_tokens": 60,
            "temperature": 0.0,
            "seed": 0,
        },
    ).json()
    show("steering generate", result)
    assert result["baseline"] != result["steered"]


def test_lora(client: TestClient, tmp_path_factory: pytest.TempPathFactory) -> None:
    adapter = tmp_path_factory.mktemp("lora") / "sundesk"
    texts = [
        f"sundesk は山田さんの Mac のためのノートアプリです。メモ {i} では固有値を学びました。"
        for i in range(20)
    ]
    events = ndjson(
        client.post(
            "/lora/train",
            json={
                "model": LLM,
                "texts": texts,
                "adapter_path": str(adapter),
                "iterations": 30,
                "rank": 8,
                "learning_rate": 1e-4,
                "batch_size": 2,
                "max_seq_length": 128,
                "num_layers": 8,
            },
        )
    )
    show("lora events", [event for event in events if event["type"] != "progress"])
    progress = [event for event in events if event["type"] == "progress"]
    show("lora progress", progress)
    assert events[-1]["type"] == "done"
    assert (adapter / "adapters.safetensors").is_file()
    assert progress[-1]["train_loss"] < progress[0]["train_loss"]

    generated = ndjson(
        client.post(
            "/lab/generate",
            json={
                "model": LLM,
                "prompt": "sundesk は",
                "max_tokens": 30,
                "temperature": 0.0,
                "adapter": str(adapter),
            },
        )
    )
    show("lora generate", "".join(e["text"] for e in generated if e["type"] == "token"))
    assert client.get("/models/loaded").json()["adapter"] == str(adapter)


def test_embeddings_and_graph(client: TestClient) -> None:
    query = client.post("/embeddings", json={"texts": ["固有値とは何か"], "kind": "query"}).json()
    documents = client.post(
        "/embeddings",
        json={
            "texts": [
                "固有値は線形変換で向きが変わらないベクトルの伸縮率である。",
                "カレーの作り方",
            ],
            "kind": "document",
        },
    ).json()
    scores = np.array(documents["vectors"]) @ np.array(query["vectors"][0])
    show("embeddings", {"dimension": query["dimension"], "scores": scores.round(3).tolist()})
    assert query["dimension"] == 512
    assert scores[0] > scores[1]

    notes: list[dict[str, Any]] = [
        {
            "path": f"{index}.md",
            "title": title,
            "chunks": [{"id": f"{index}.md#0", "text": text}],
        }
        for index, (title, text) in enumerate(
            [
                ("固有値", "固有値とは行列の伸縮率である。固有ベクトルと対になる。"),
                ("固有ベクトル", "固有ベクトルは向きが変わらないベクトルである。"),
                ("カレー", "カレーは玉ねぎと人参を煮込む料理である。"),
                ("シチュー", "シチューは牛乳と野菜を煮込む料理である。"),
            ]
        )
    ]
    graph = client.post(
        "/graph/build",
        json={
            "notes": notes,
            "options": {"min_frequency": 1, "similarity": True},
        },
    ).json()
    names = {concept["id"]: concept["label"] for concept in graph["concepts"]}
    similar = [
        (names[r["source"]], names[r["target"]], r["weight"])
        for r in graph["relations"]
        if r["kind"] == "similar"
    ]
    show("graph similar", similar)
    assert graph["concepts"]


def test_memory_policy(client: TestClient, tmp_path_factory: pytest.TempPathFactory) -> None:
    del tmp_path_factory
    client.post("/lab/next-token", json={"model": LLM, "prompt": "a"})
    loaded = client.get("/models/loaded").json()
    show("loaded", loaded)
    assert loaded["llm"] == LLM
    assert loaded["embedding"] == EMBEDDING
    assert Path(client.get("/models").json()["models"][0]["path"]).exists()
