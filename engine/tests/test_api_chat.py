"""チャットと埋め込みの API のテスト。"""

import numpy as np
import pytest
from conftest import Harness
from fakes import EMBEDDING_DIMENSION, EMBEDDING_ID, LLM_ID, ndjson
from fastapi.testclient import TestClient

from sundesk_engine.api import chat

MESSAGES = [
    {"role": "system", "content": "あなたは助手です。"},
    {"role": "user", "content": "固有値とは"},
]


def test_chat_streams_loading_tokens_and_done(client: TestClient) -> None:
    request = {"model": LLM_ID, "messages": MESSAGES, "max_tokens": 5, "temperature": 0.0}
    events = ndjson(client.post("/chat", json=request))

    assert events[0] == {"type": "loading", "model": LLM_ID}
    assert all(set(event) == {"type", "text"} for event in events if event["type"] == "token")
    done = events[-1]
    assert done["type"] == "done"
    assert set(done) == {"type", "prompt_tokens", "generated_tokens", "tokens_per_second"}
    assert done["prompt_tokens"] > 0
    assert 1 <= done["generated_tokens"] <= 5

    again = ndjson(client.post("/chat", json=request))
    assert again[0]["type"] != "loading"
    text = "".join(e["text"] for e in events if e["type"] == "token")
    assert "".join(e["text"] for e in again if e["type"] == "token") == text


def test_chat_unknown_model_is_404_before_streaming(client: TestClient) -> None:
    response = client.post("/chat", json={"model": "test/missing", "messages": MESSAGES})

    assert response.status_code == 404
    assert response.json()["detail"]


def test_chat_rejects_unknown_role(client: TestClient) -> None:
    response = client.post(
        "/chat", json={"model": LLM_ID, "messages": [{"role": "tool", "content": "x"}]}
    )

    assert response.status_code == 400


def test_chat_adapter_must_be_absolute(client: TestClient) -> None:
    response = client.post(
        "/chat", json={"model": LLM_ID, "messages": MESSAGES, "adapter": "relative/path"}
    )

    assert response.status_code == 400


def test_chat_failure_mid_stream_emits_error_line(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("壊れた")

    monkeypatch.setattr(chat, "stream_chat", broken)
    events = ndjson(client.post("/chat", json={"model": LLM_ID, "messages": MESSAGES}))

    assert events[0]["type"] == "loading"
    assert events[-1]["type"] == "error"
    assert "壊れた" in events[-1]["message"]


def test_embeddings_are_normalized_and_prefixed(harness: Harness) -> None:
    client = harness.client
    query = client.post("/embeddings", json={"texts": ["固有値とは", "行列"], "kind": "query"})
    document = client.post("/embeddings", json={"texts": ["固有値とは"], "kind": "document"})

    assert query.status_code == 200
    body = query.json()
    assert body["model"] == EMBEDDING_ID
    assert body["dimension"] == EMBEDDING_DIMENSION
    assert len(body["vectors"]) == 2
    assert all(len(vector) == EMBEDDING_DIMENSION for vector in body["vectors"])
    norms = [float(np.linalg.norm(np.array(vector))) for vector in body["vectors"]]
    assert norms == pytest.approx([1.0, 1.0], abs=1e-5)
    # 質問と文書では前に付ける文字列が違うので、同じ文でもベクトルが変わる
    assert document.json()["vectors"][0] != body["vectors"][0]
    assert harness.engine.models.loaded()["embedding"] == EMBEDDING_ID


def test_embeddings_unknown_model_is_404(client: TestClient) -> None:
    response = client.post(
        "/embeddings", json={"texts": ["a"], "kind": "query", "model": "test/missing"}
    )

    assert response.status_code == 404


def test_embeddings_reject_unknown_kind(client: TestClient) -> None:
    response = client.post("/embeddings", json={"texts": ["a"], "kind": "topic"})

    assert response.status_code == 400
