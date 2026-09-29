"""知識グラフの API のテスト。"""

from conftest import Harness
from fakes import EMBEDDING_ID
from fastapi.testclient import TestClient

NOTES = [
    {
        "path": "数学/固有値.md",
        "title": "固有値",
        "links": ["数学/行列.md"],
        "chunks": [
            {
                "id": "数学/固有値.md#0",
                "heading_path": ["固有値"],
                "text": "固有値とは行列の伸縮率である。固有値分解は行列分解の一種である。",
            }
        ],
    },
    {
        "path": "数学/行列.md",
        "title": "行列",
        "chunks": [{"id": "数学/行列.md#0", "text": "行列は数を並べたものである。"}],
    },
]


def test_build_returns_the_documented_shape(client: TestClient) -> None:
    response = client.post(
        "/graph/build",
        json={"notes": NOTES, "options": {"max_concepts": 50, "min_frequency": 1}},
    )

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"concepts", "mentions", "relations"}
    assert set(body["concepts"][0]) == {
        "id",
        "label",
        "normalized",
        "score",
        "frequency",
        "pagerank",
        "community",
    }
    assert set(body["mentions"][0]) == {"concept", "chunk", "count"}
    assert set(body["relations"][0]) == {"source", "target", "kind", "weight", "evidence"}
    kinds = {relation["kind"] for relation in body["relations"]}
    assert {"link", "contains", "definition", "is_a"} <= kinds


def test_build_uses_default_options(client: TestClient) -> None:
    response = client.post("/graph/build", json={"notes": NOTES})

    labels = {concept["label"] for concept in response.json()["concepts"]}
    assert {"固有値", "行列"} <= labels


def test_similarity_loads_the_embedding_model(harness: Harness) -> None:
    response = harness.client.post(
        "/graph/build",
        json={
            "notes": NOTES,
            "options": {"min_frequency": 1, "similarity": True, "similarity_threshold": -1.0},
        },
    )

    assert response.status_code == 200
    assert any(r["kind"] == "similar" for r in response.json()["relations"])
    assert harness.engine.models.loaded()["embedding"] == EMBEDDING_ID


def test_similarity_without_embedding_model_is_404(harness: Harness) -> None:
    harness.hub.delete(EMBEDDING_ID)

    response = harness.client.post(
        "/graph/build", json={"notes": NOTES, "options": {"similarity": True}}
    )

    assert response.status_code == 404


def test_invalid_options_are_400(client: TestClient) -> None:
    response = client.post("/graph/build", json={"notes": NOTES, "options": {"max_concepts": 0}})

    assert response.status_code == 400
    assert "max_concepts" in response.json()["detail"]
