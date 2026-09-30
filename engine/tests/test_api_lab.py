"""LLM 実験室の API のテスト。小さなランダムの Qwen3 で、本物の計算を通す。"""

import pytest
from conftest import Harness
from fakes import LLM_ID, NUM_HEADS, NUM_LAYERS, ndjson
from fastapi.testclient import TestClient

from sundesk_engine.lab.tokens import MAX_PROMPT_TOKENS

PROMPT = "固有値とは"


def test_tokenize_returns_offsets(client: TestClient) -> None:
    text = "固有値 hello"
    response = client.post("/lab/tokenize", json={"model": LLM_ID, "text": text})

    assert response.status_code == 200
    tokens = response.json()["tokens"]
    assert tokens
    assert set(tokens[0]) == {"id", "text", "start", "end"}
    for token in tokens:
        if token["start"] is not None:
            assert text[token["start"] : token["end"]] == token["text"]
    assert tokens[-1]["end"] == len(text)
    assert any(token["start"] is not None for token in tokens)


def test_tokenize_does_not_load_the_model(harness: Harness) -> None:
    harness.client.post("/lab/tokenize", json={"model": LLM_ID, "text": "abc"})

    assert harness.llm.loads == []


def test_next_token_probabilities(client: TestClient) -> None:
    response = client.post(
        "/lab/next-token",
        json={"model": LLM_ID, "prompt": PROMPT, "top_k": 5, "temperature": 1.0},
    )

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"tokens", "entropy"}
    assert len(body["tokens"]) == 5
    assert set(body["tokens"][0]) == {"id", "text", "probability", "logit"}
    probabilities = [token["probability"] for token in body["tokens"]]
    assert probabilities == sorted(probabilities, reverse=True)
    assert all(0 < p <= 1 for p in probabilities)
    assert body["entropy"] > 0


def test_next_token_temperature_sharpens(client: TestClient) -> None:
    def top(temperature: float) -> float:
        response = client.post(
            "/lab/next-token",
            json={"model": LLM_ID, "prompt": PROMPT, "top_k": 1, "temperature": temperature},
        )
        return response.json()["tokens"][0]["probability"]

    assert top(0.1) > top(1.0)


def test_chat_template_wraps_prompt(client: TestClient) -> None:
    plain = client.post("/lab/activations", json={"model": LLM_ID, "prompt": PROMPT}).json()
    wrapped = client.post(
        "/lab/activations", json={"model": LLM_ID, "prompt": PROMPT, "chat_template": True}
    ).json()

    assert len(wrapped["tokens"]) > len(plain["tokens"])
    assert wrapped["tokens"][0]["text"] == "<|im_start|>"


def test_generate_streams_tokens_with_alternatives(client: TestClient) -> None:
    request = {
        "model": LLM_ID,
        "prompt": PROMPT,
        "max_tokens": 6,
        "temperature": 1.0,
        "top_p": 0.9,
        "top_k": 50,
        "seed": 7,
        "alternatives": 3,
    }
    events = ndjson(client.post("/lab/generate", json=request))

    assert events[0] == {"type": "loading", "model": LLM_ID}
    tokens = [event for event in events if event["type"] == "token"]
    assert 1 <= len(tokens) <= 6
    for token in tokens:
        assert set(token) == {"type", "id", "text", "probability", "alternatives"}
        assert len(token["alternatives"]) == 3
        assert all(alt["id"] != token["id"] for alt in token["alternatives"])
    done = events[-1]
    assert done["type"] == "done"
    assert done["generated_tokens"] == len(tokens)
    assert done["tokens_per_second"] >= 0

    # 同じ種なら同じ結果になり、2 回目は載せ直さない
    again = ndjson(client.post("/lab/generate", json=request))
    assert again[0]["type"] == "token"
    assert [e["id"] for e in again if e["type"] == "token"] == [e["id"] for e in tokens]


def test_generate_greedy_picks_the_most_likely(client: TestClient) -> None:
    events = ndjson(
        client.post(
            "/lab/generate",
            json={"model": LLM_ID, "prompt": PROMPT, "max_tokens": 1, "temperature": 0},
        )
    )
    token = next(event for event in events if event["type"] == "token")
    best = client.post(
        "/lab/next-token", json={"model": LLM_ID, "prompt": PROMPT, "top_k": 1}
    ).json()["tokens"][0]

    assert token["id"] == best["id"]


def test_attention_is_causal_and_normalized(client: TestClient) -> None:
    response = client.post("/lab/attention", json={"model": LLM_ID, "prompt": PROMPT, "layer": 1})

    assert response.status_code == 200
    body = response.json()
    count = len(body["tokens"])
    assert body["num_layers"] == NUM_LAYERS
    assert body["num_heads"] == NUM_HEADS
    assert body["layer"] == 1
    assert len(body["heads"]) == NUM_HEADS
    for head in body["heads"]:
        assert len(head) == count
        for i, row in enumerate(head):
            assert len(row) == count
            assert sum(row) == pytest.approx(1.0, abs=1e-4)
            assert all(value == 0 for value in row[i + 1 :])
    assert body["mean"][0][0] == pytest.approx(1.0)


def test_attention_accepts_negative_layer(client: TestClient) -> None:
    response = client.post("/lab/attention", json={"model": LLM_ID, "prompt": PROMPT, "layer": -1})

    assert response.json()["layer"] == NUM_LAYERS - 1


def test_attention_rejects_unknown_layer(client: TestClient) -> None:
    response = client.post(
        "/lab/attention", json={"model": LLM_ID, "prompt": PROMPT, "layer": NUM_LAYERS}
    )

    assert response.status_code == 400
    assert "層" in response.json()["detail"]


def test_logit_lens_last_layer_matches_prediction(client: TestClient) -> None:
    response = client.post("/lab/logit-lens", json={"model": LLM_ID, "prompt": PROMPT, "top_k": 2})

    assert response.status_code == 200
    body = response.json()
    count = len(body["tokens"])
    assert body["num_layers"] == NUM_LAYERS
    assert [layer["layer"] for layer in body["layers"]] == list(range(NUM_LAYERS))
    for layer in body["layers"]:
        assert len(layer["positions"]) == count
        for position in layer["positions"]:
            assert len(position["top"]) == 2
            assert set(position["top"][0]) == {"id", "text", "probability"}
    best = client.post(
        "/lab/next-token", json={"model": LLM_ID, "prompt": PROMPT, "top_k": 1}
    ).json()["tokens"][0]
    assert body["layers"][-1]["positions"][-1]["top"][0]["id"] == best["id"]


def test_activations_shape(client: TestClient) -> None:
    body = client.post("/lab/activations", json={"model": LLM_ID, "prompt": PROMPT}).json()

    assert body["num_layers"] == NUM_LAYERS
    assert len(body["norms"]) == NUM_LAYERS
    assert all(len(row) == len(body["tokens"]) for row in body["norms"])
    assert all(value > 0 for row in body["norms"] for value in row)


@pytest.mark.parametrize(
    "path", ["/lab/next-token", "/lab/attention", "/lab/logit-lens", "/lab/activations"]
)
def test_prompt_longer_than_limit_is_rejected(client: TestClient, path: str) -> None:
    prompt = "hello world " * MAX_PROMPT_TOKENS
    response = client.post(path, json={"model": LLM_ID, "prompt": prompt})

    assert response.status_code == 400
    assert "512" in response.json()["detail"]


def test_generate_reports_long_prompt_as_error_line(client: TestClient) -> None:
    prompt = "hello world " * MAX_PROMPT_TOKENS
    events = ndjson(client.post("/lab/generate", json={"model": LLM_ID, "prompt": prompt}))

    assert events[-1]["type"] == "error"
    assert "512" in events[-1]["message"]


def test_unknown_model_is_404(client: TestClient) -> None:
    for path in ("/lab/next-token", "/lab/generate", "/lab/attention"):
        response = client.post(path, json={"model": "test/missing", "prompt": PROMPT})
        assert response.status_code == 404
        assert "test/missing" in response.json()["detail"]


def test_missing_adapter_is_404(client: TestClient, harness: Harness) -> None:
    adapter = str(harness.tmp_path / "no-adapter")
    response = client.post(
        "/lab/next-token", json={"model": LLM_ID, "prompt": PROMPT, "adapter": adapter}
    )

    assert response.status_code == 404


def test_unsupported_structure_is_422(harness: Harness) -> None:
    class Opaque:
        def __call__(self, *_args: object) -> None:
            return None

    original = harness.llm.load
    harness.llm.load = lambda path, adapter: (Opaque(), original(path, adapter)[1])  # type: ignore[method-assign]

    for path in ("/lab/next-token", "/lab/attention", "/lab/logit-lens", "/lab/activations"):
        response = harness.client.post(path, json={"model": LLM_ID, "prompt": PROMPT})
        assert response.status_code == 422, path
        assert "構造" in response.json()["detail"]


def test_invalid_request_is_400_with_japanese_detail(client: TestClient) -> None:
    response = client.post("/lab/next-token", json={"model": LLM_ID})

    assert response.status_code == 400
    assert isinstance(response.json()["detail"], str)
    assert "prompt" in response.json()["detail"]


def test_logit_lens_with_many_candidates(client: TestClient) -> None:
    body = client.post(
        "/lab/logit-lens", json={"model": LLM_ID, "prompt": PROMPT, "top_k": 12}
    ).json()

    top = body["layers"][0]["positions"][0]["top"]
    assert len(top) == 12
    probabilities = [candidate["probability"] for candidate in top]
    assert probabilities == sorted(probabilities, reverse=True)
