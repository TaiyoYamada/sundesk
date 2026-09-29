"""モデルの置き場（Hugging Face のキャッシュ）、ストリーム、抽選のテスト。"""

import asyncio
import json
import threading
from pathlib import Path
from typing import Any

import numpy as np
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from sundesk_engine.errors import BadRequestError, NotFoundError, install_handlers
from sundesk_engine.lab.sampling import SamplingOptions, entropy, sample, top_indices
from sundesk_engine.runtime.hub import (
    MODELS_DIR_ENV,
    DownloadPlan,
    HuggingFaceHub,
    RemoteFile,
    models_dir_from_env,
)
from sundesk_engine.streaming import Emit, ndjson_response


def make_repo(cache: Path, model_id: str, files: dict[str, str], commit: str = "abc") -> Path:
    """Hugging Face のキャッシュと同じ構造を作る。"""
    repo = cache / ("models--" + model_id.replace("/", "--"))
    snapshot = repo / "snapshots" / commit
    (repo / "blobs").mkdir(parents=True)
    (repo / "refs").mkdir()
    (repo / "refs" / "main").write_text(commit)
    for index, (name, content) in enumerate(files.items()):
        blob = repo / "blobs" / f"blob{index}"
        blob.write_text(content)
        target = snapshot / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(blob)
    return snapshot


def test_hub_lists_and_classifies_models(tmp_path: Path) -> None:
    make_repo(
        tmp_path,
        "mlx-community/Tiny-4bit",
        {
            "config.json": json.dumps({"architectures": ["Qwen3ForCausalLM"]}),
            "model.safetensors": "x" * 10,
        },
    )
    make_repo(tmp_path, "cl-nagoya/ruri-v3-130m", {"modules.json": "[]", "config.json": "{}"})
    make_repo(
        tmp_path,
        "Tongyi-MAI/Z-Image-Turbo",
        {"transformer/a.safetensors": "t", "vae/b.safetensors": "v"},
    )
    make_repo(tmp_path, "someone/data", {"README.md": "hello"})
    hub = HuggingFaceHub(tmp_path, image_repos=["Tongyi-MAI/Z-Image-Turbo"])

    models = {model.id: model for model in hub.list_models()}

    assert {model_id: model.kind for model_id, model in models.items()} == {
        "mlx-community/Tiny-4bit": "llm",
        "cl-nagoya/ruri-v3-130m": "embedding",
        "Tongyi-MAI/Z-Image-Turbo": "image",
        "someone/data": "other",
    }
    tiny = models["mlx-community/Tiny-4bit"]
    assert tiny.size_bytes == len(json.dumps({"architectures": ["Qwen3ForCausalLM"]})) + 10
    assert tiny.path.endswith("snapshots/abc")


def test_hub_lists_local_model_folders(tmp_path: Path) -> None:
    make_repo(
        tmp_path / "cache",
        "mlx-community/Tiny-4bit",
        {"config.json": json.dumps({"architectures": ["Qwen3ForCausalLM"]})},
    )
    models_dir = tmp_path / "Models"
    local = models_dir / "tiny-3bit"
    local.mkdir(parents=True)
    (local / "config.json").write_text(json.dumps({"architectures": ["Qwen3ForCausalLM"]}))
    (local / "model.safetensors").write_bytes(b"x" * 100)
    (models_dir / ".tiny.partial-1234").mkdir()
    (models_dir / ".tiny.partial-1234" / "config.json").write_text("{}")
    (models_dir / "notes").mkdir()
    (models_dir / "stray.txt").write_text("a")
    hub = HuggingFaceHub(tmp_path / "cache", models_dir=models_dir)

    models = hub.list_models()

    assert [(model.id, model.name, model.source) for model in models] == [
        ("mlx-community/Tiny-4bit", "Tiny-4bit", "hub"),
        (str(local), "tiny-3bit", "local"),
    ]
    assert models[1].kind == "llm"
    assert models[1].path == str(local)
    assert models[1].size_bytes == 100 + len(json.dumps({"architectures": ["Qwen3ForCausalLM"]}))
    assert hub.resolve(str(local)) == local
    # 手元のフォルダは消さない（アプリが消す）
    with pytest.raises(BadRequestError):
        hub.delete(str(local))
    assert (
        HuggingFaceHub(tmp_path / "cache", models_dir=tmp_path / "missing").list_models()[1:] == []
    )


def test_models_dir_comes_from_the_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv(MODELS_DIR_ENV, str(tmp_path))
    assert models_dir_from_env() == tmp_path
    monkeypatch.setenv(MODELS_DIR_ENV, "relative/path")
    assert models_dir_from_env() is None
    monkeypatch.delenv(MODELS_DIR_ENV)
    assert models_dir_from_env() is None


def test_hub_resolve_and_delete(tmp_path: Path) -> None:
    snapshot = make_repo(tmp_path, "org/model", {"config.json": "{}"})
    hub = HuggingFaceHub(tmp_path)

    assert hub.resolve("org/model") == snapshot
    assert hub.is_cached("org/model", ["config.json"])
    assert not hub.is_cached("org/model", ["vae/*.safetensors"])
    assert hub.delete("org/model")
    assert not hub.delete("org/model")
    with pytest.raises(NotFoundError):
        hub.resolve("org/model")
    with pytest.raises(BadRequestError):
        hub.resolve("../../etc")


def test_hub_resolves_absolute_directories(tmp_path: Path) -> None:
    hub = HuggingFaceHub(tmp_path / "cache")

    assert hub.resolve(str(tmp_path)) == tmp_path
    with pytest.raises(NotFoundError):
        hub.resolve(str(tmp_path / "missing"))


def test_hub_download_reports_progress(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import huggingface_hub

    hub = HuggingFaceHub(tmp_path, poll_interval=0.01)
    plan = DownloadPlan(
        model_id="org/model",
        revision="abc",
        files=(RemoteFile("a.safetensors", 4, "e1"), RemoteFile("b.json", 2, "e2")),
        allow_patterns=None,
        ignore_patterns=("*.bin",),
    )
    release = threading.Event()
    calls: list[dict[str, Any]] = []

    def fake_snapshot_download(repo_id: str, **kwargs: Any) -> str:
        calls.append({"repo_id": repo_id} | kwargs)
        blobs = tmp_path / "models--org--model" / "blobs"
        blobs.mkdir(parents=True)
        (blobs / "e1.1234.incomplete").write_bytes(b"12")
        release.wait(0.2)
        (blobs / "e1").write_bytes(b"1234")
        (blobs / "e2").write_bytes(b"12")
        return str(tmp_path / "snapshot")

    monkeypatch.setattr(huggingface_hub, "snapshot_download", fake_snapshot_download)
    progress: list[int] = []

    path = hub.download(plan, progress.append)

    assert path == tmp_path / "snapshot"
    assert 2 in progress
    assert progress[-1] == 6
    assert progress == sorted(progress)
    assert calls[0]["ignore_patterns"] == ["*.bin"]
    assert calls[0]["revision"] == "abc"


def stream_app(work: Any) -> TestClient:
    app = FastAPI()
    install_handlers(app)

    @app.get("/stream")
    async def stream() -> Any:  # pyright: ignore[reportUnusedFunction]
        return ndjson_response(work, None)

    return TestClient(app)


def test_stream_emits_events_then_error_line() -> None:
    def work(emit: Emit) -> None:
        emit({"type": "progress", "value": "日本語"})
        raise NotFoundError("見つかりません")

    response = stream_app(work).get("/stream")

    assert response.headers["content-type"].startswith("application/x-ndjson")
    lines = response.text.splitlines()
    assert lines[0] == '{"type": "progress", "value": "日本語"}'
    assert json.loads(lines[1]) == {"type": "error", "message": "見つかりません"}


def test_stream_hides_nothing_about_unexpected_errors() -> None:
    def work(_emit: Emit) -> None:
        raise ValueError("おかしい")

    events = [json.loads(line) for line in stream_app(work).get("/stream").text.splitlines()]

    assert events[0]["type"] == "error"
    assert "ValueError" in events[0]["message"]
    assert "おかしい" in events[0]["message"]


def test_stream_stops_work_when_client_leaves() -> None:
    from sundesk_engine.streaming import StreamCancelledError

    stopped = threading.Event()

    def work(emit: Emit) -> None:
        try:
            for index in range(10_000):
                emit({"type": "tick", "index": index})
        except StreamCancelledError:
            stopped.set()
            raise

    async def consume_one() -> None:
        response = ndjson_response(work, None)
        iterator: Any = response.body_iterator
        await anext(iterator)
        await iterator.aclose()

    asyncio.run(consume_one())

    assert stopped.wait(2)


def test_sampling_top_k_and_top_p() -> None:
    probs = np.array([0.5, 0.3, 0.15, 0.05])
    rng = np.random.default_rng(0)

    top1 = {sample(probs, SamplingOptions(temperature=1.0, top_k=1), rng) for _ in range(20)}
    nucleus = {sample(probs, SamplingOptions(temperature=1.0, top_p=0.7), rng) for _ in range(200)}
    greedy = sample(probs, SamplingOptions(temperature=0.0), rng)

    assert top1 == {0}
    assert nucleus == {0, 1}
    assert greedy == 0
    assert top_indices(probs, 2) == [0, 1]
    assert top_indices(probs, 2, exclude=0) == [1, 2]
    assert entropy(np.array([0.5, 0.5])) == pytest.approx(np.log(2))


def test_unexpected_errors_become_json_500() -> None:
    app = FastAPI()
    install_handlers(app)

    @app.get("/boom")
    async def boom() -> None:  # pyright: ignore[reportUnusedFunction]
        raise RuntimeError("こわれた")

    response = TestClient(app, raise_server_exceptions=False).get("/boom")

    assert response.status_code == 500
    assert "こわれた" in response.json()["detail"]


def test_confined_path_allows_home_and_temp_only(tmp_path: Path) -> None:
    from sundesk_engine.paths import confined_path

    assert confined_path(str(tmp_path / "out"), "出力") == str(tmp_path / "out")
    assert confined_path("~/models/a", "出力").endswith("/models/a")
    for bad in ["relative/path", "/etc/passwd", "~/../../etc"]:
        with pytest.raises(BadRequestError):
            confined_path(bad, "出力")
