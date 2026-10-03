"""画像生成の API のテスト。画像モデルは偽物を使う（本物はダウンロードしない）。"""

from conftest import Harness
from fakes import ndjson
from fastapi.testclient import TestClient

from sundesk_engine.images.catalog import IMAGE_MODELS


def test_image_models(client: TestClient) -> None:
    response = client.get("/images/models")

    assert response.status_code == 200
    models = {model["id"]: model for model in response.json()["models"]}
    assert set(models) == {"z-image-turbo", "flux2-klein-4b"}
    z_image = models["z-image-turbo"]
    assert z_image == {
        "id": "z-image-turbo",
        "name": "Z-Image Turbo",
        "repo": "mflux-community/z-image-turbo-mflux-q4",
        "downloaded": True,
        "default_steps": 9,
        "default_size": {"width": 1024, "height": 1024},
    }
    assert models["flux2-klein-4b"]["downloaded"] is False


def test_generate_streams_progress_and_saves(harness: Harness) -> None:
    output = harness.tmp_path / "images" / "a.png"
    events = ndjson(
        harness.client.post(
            "/images/generate",
            json={
                "model": "z-image-turbo",
                "prompt": "夕焼けの猫",
                "width": 512,
                "height": 768,
                "steps": 3,
                "seed": 42,
                "quantize": 8,
                "output_path": str(output),
            },
        )
    )

    assert events[0] == {"type": "loading", "model": "z-image-turbo"}
    assert [e for e in events if e["type"] == "progress"] == [
        {"type": "progress", "step": step, "total": 3} for step in (1, 2, 3)
    ]
    done = events[-1]
    assert done["type"] == "done"
    assert done["path"] == str(output)
    assert done["seed"] == 42
    assert done["seconds"] >= 0
    assert output.read_bytes() == "夕焼けの猫:512x768:42".encode()
    assert harness.image.loads == [("z-image-turbo", 8)]


def test_generate_picks_seed_and_default_steps(harness: Harness) -> None:
    output = harness.tmp_path / "b.png"
    events = ndjson(
        harness.client.post(
            "/images/generate",
            json={"model": "z-image-turbo", "prompt": "犬", "output_path": str(output)},
        )
    )

    progress = [e for e in events if e["type"] == "progress"]
    assert progress[-1]["total"] == IMAGE_MODELS[0].default_steps
    assert isinstance(events[-1]["seed"], int)


def test_generate_changes_quantization_reloads(harness: Harness) -> None:
    output = str(harness.tmp_path / "c.png")
    for quantize in (4, 4, None):
        harness.client.post(
            "/images/generate",
            json={
                "model": "z-image-turbo",
                "prompt": "a",
                "steps": 1,
                "quantize": quantize,
                "output_path": output,
            },
        )

    assert harness.image.loads == [("z-image-turbo", 4), ("z-image-turbo", None)]


def test_generate_errors(client: TestClient, harness: Harness) -> None:
    output = str(harness.tmp_path / "d.png")

    def post(**fields: object) -> int:
        body = {"model": "z-image-turbo", "prompt": "a", "output_path": output} | fields
        return client.post("/images/generate", json=body).status_code

    assert post(model="unknown") == 404
    assert post(model="flux2-klein-4b") == 404
    assert post(quantize=7) == 400
    assert post(width=1000) == 400
    assert post(output_path="relative.png") == 400


def test_generate_failure_emits_error_line(harness: Harness) -> None:
    harness.image.fail = True
    events = ndjson(
        harness.client.post(
            "/images/generate",
            json={
                "model": "z-image-turbo",
                "prompt": "a",
                "steps": 4,
                "output_path": str(harness.tmp_path / "e.png"),
            },
        )
    )

    assert [e["type"] for e in events] == ["loading", "progress", "progress", "error"]
    assert "失敗" in events[-1]["message"]
