"""モデルの管理と、メモリの使い方の決まりのテスト。"""

from conftest import Harness
from fakes import EMBEDDING_ID, IMAGE_REPO, LLM_ID, ndjson
from fastapi.testclient import TestClient

from sundesk_engine.images.catalog import IMAGE_MODELS


def test_list_models(client: TestClient) -> None:
    response = client.get("/models")

    assert response.status_code == 200
    models = {model["id"]: model for model in response.json()["models"]}
    assert set(models) == {LLM_ID, EMBEDDING_ID, IMAGE_REPO}
    assert models[LLM_ID]["kind"] == "llm"
    assert set(models[LLM_ID]) == {"id", "kind", "size_bytes", "path"}


def test_loaded_is_empty_at_start(client: TestClient) -> None:
    assert client.get("/models/loaded").json() == {
        "llm": None,
        "image": None,
        "embedding": None,
        "adapter": None,
    }


def test_download_streams_progress_then_done(harness: Harness) -> None:
    events = ndjson(harness.client.post("/models/download", json={"id": "test/remote"}))

    progress = [event for event in events if event["type"] == "progress"]
    assert progress
    assert all(event["total_bytes"] == 100 for event in progress)
    assert progress[-1]["downloaded_bytes"] == 100
    assert events[-1]["type"] == "done"
    assert events[-1]["path"]
    assert "test/remote" in harness.hub.models


def test_download_unknown_model_is_404(client: TestClient) -> None:
    response = client.post("/models/download", json={"id": "test/nothing"})

    assert response.status_code == 404


def test_download_rejects_malformed_id(client: TestClient) -> None:
    response = client.post("/models/download", json={"id": "../etc"})

    assert response.status_code == 400


def test_delete_model(harness: Harness) -> None:
    client = harness.client
    client.post("/lab/next-token", json={"model": LLM_ID, "prompt": "a"})
    assert client.get("/models/loaded").json()["llm"] == LLM_ID

    response = client.delete(f"/models/{LLM_ID}")

    assert response.status_code == 200
    assert response.json() == {"deleted": True}
    # 載っていたモデルは捨てる
    assert client.get("/models/loaded").json()["llm"] is None
    assert client.delete(f"/models/{LLM_ID}").status_code == 404


def test_unload(harness: Harness) -> None:
    client = harness.client
    client.post("/lab/next-token", json={"model": LLM_ID, "prompt": "a"})
    client.post("/embeddings", json={"texts": ["a"], "kind": "query"})

    assert client.post("/models/unload", json={"kind": "image"}).json() == {"unloaded": []}
    assert client.post("/models/unload", json={"kind": "llm"}).json() == {"unloaded": [LLM_ID]}
    assert client.get("/models/loaded").json()["embedding"] == EMBEDDING_ID
    assert client.post("/models/unload", json={"kind": "all"}).json() == {
        "unloaded": [EMBEDDING_ID]
    }
    assert client.post("/models/unload", json={"kind": "gpu"}).status_code == 400


def test_only_one_large_model_is_loaded(harness: Harness, tmp_path_factory: object) -> None:
    del tmp_path_factory
    client = harness.client
    client.post("/lab/next-token", json={"model": LLM_ID, "prompt": "a"})
    output = harness.tmp_path / "out.png"
    ndjson(
        client.post(
            "/images/generate",
            json={"model": IMAGE_MODELS[0].id, "prompt": "cat", "output_path": str(output)},
        )
    )

    assert client.get("/models/loaded").json()["llm"] is None
    assert client.get("/models/loaded").json()["image"] == IMAGE_MODELS[0].id

    client.post("/lab/next-token", json={"model": LLM_ID, "prompt": "a"})
    loaded = client.get("/models/loaded").json()
    assert loaded["llm"] == LLM_ID
    assert loaded["image"] is None
    assert len(harness.llm.loads) == 2


def test_same_model_is_not_reloaded(harness: Harness) -> None:
    for _ in range(3):
        harness.client.post("/lab/next-token", json={"model": LLM_ID, "prompt": "a"})

    assert len(harness.llm.loads) == 1


def test_token_is_required_for_every_endpoint(harness: Harness) -> None:
    from fastapi.testclient import TestClient

    from sundesk_engine.app import create_app

    client = TestClient(create_app(token="secret", engine=harness.engine))

    assert client.get("/models/loaded").status_code == 401
    assert client.post("/chat", json={}).status_code == 401
    assert client.post("/graph/build", json={"notes": []}).status_code == 401
    headers = {"Authorization": "Bearer secret"}
    assert client.get("/models/loaded", headers=headers).status_code == 200
    events = ndjson(
        client.post(
            "/lab/generate",
            json={"model": LLM_ID, "prompt": "a", "max_tokens": 2},
            headers=headers,
        )
    )
    assert events[-1]["type"] == "done"
