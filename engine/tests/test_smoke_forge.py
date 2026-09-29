"""工房とスクラッチを、本物の小さなモデルで確かめる。ふだんのテストでは動かさない。

    SUNDESK_ENGINE_SMOKE=1 uv run pytest tests/test_smoke_forge.py -s

mlx-community/Qwen3-0.6B-4bit（約 350MB）と mlx-community/Qwen3-0.6B-bf16（約 1.2GB）を
Hugging Face のキャッシュにダウンロードする（なければ）。
作ったモデルは一時フォルダに書き、最後に消す。
"""

import base64
import json
import os
import shutil
from collections.abc import Generator
from pathlib import Path
from typing import Any

import pytest
from fakes import ndjson
from fastapi.testclient import TestClient

from sundesk_engine.app import create_app
from sundesk_engine.engine import Engine
from sundesk_engine.runtime.hub import MODELS_DIR_ENV

pytestmark = pytest.mark.skipif(
    os.environ.get("SUNDESK_ENGINE_SMOKE") != "1",
    reason="SUNDESK_ENGINE_SMOKE=1 のときだけ、本物のモデルで確かめる",
)

Q4 = "mlx-community/Qwen3-0.6B-4bit"
BF16 = "mlx-community/Qwen3-0.6B-bf16"

TEXTS = [
    "The capital of France is Paris. It is known for the Eiffel Tower, the Louvre museum, "
    "and its cafes. Paris has been a major center of finance, diplomacy, commerce, fashion, "
    "and science for centuries.",
    "In linear algebra, an eigenvector of a linear transformation is a nonzero vector that "
    "changes at most by a scalar factor when that linear transformation is applied to it. "
    "The corresponding eigenvalue is the factor by which the eigenvector is scaled.",
    "東京は日本の首都であり、政治や経済の中心です。人口は約千四百万人で、"
    "世界でも有数の大都市として知られています。",
]
PROMPT = "The capital of Japan is"


def show(title: str, value: object) -> None:
    print(f"\n== {title}\n{json.dumps(value, ensure_ascii=False)[:2000]}")


class Smoke:
    def __init__(self, client: TestClient, root: Path) -> None:
        self.client = client
        self.root = root

    def path(self, name: str) -> str:
        return str(self.root / name)

    def forge(self, name: str, **body: object) -> dict[str, Any]:
        events = ndjson(self.client.post(f"/forge/{name}", json=body))
        done = events[-1]
        show(f"forge/{name}", [e for e in events if e["type"] != "progress"][-3:])
        assert done["type"] == "done", done
        return done

    def evaluate(self, models: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
        events = ndjson(
            self.client.post(
                "/forge/evaluate",
                json={
                    "models": models,
                    "texts": TEXTS,
                    "prompts": [PROMPT],
                    "max_tokens": 12,
                    "seed": 0,
                    "temperature": 0.0,
                },
            )
        )
        assert events[-1] == {"type": "done"}
        results = [e for e in events if e["type"] == "result"]
        table = [
            {
                "model": Path(r["model"]).name,
                "adapter": bool(r["adapter"]),
                "ppl": r["perplexity"],
                "tokens": r["tokens"],
                "s": r["seconds"],
                "tok/s": r["tokens_per_second"],
                "MB": round(r["size_bytes"] / 1e6),
                "peak MB": round(r["peak_memory_bytes"] / 1e6),
                "sample": r["samples"][0],
            }
            for r in results
        ]
        for row in table:
            print(row)
        return {f"{Path(r['model']).name}{'+adapter' if r['adapter'] else ''}": r for r in results}


@pytest.fixture(scope="module")
def smoke(tmp_path_factory: pytest.TempPathFactory) -> Generator[Smoke]:
    import mlx.core as mx

    root = tmp_path_factory.mktemp("forged")
    previous = os.environ.get(MODELS_DIR_ENV)
    os.environ[MODELS_DIR_ENV] = str(root)
    mx.set_default_device(mx.gpu)
    engine = Engine.create_default()
    try:
        with TestClient(create_app(engine=engine)) as client:
            for model in (Q4, BF16):
                events = ndjson(client.post("/models/download", json={"id": model}))
                assert events[-1]["type"] == "done", events[-1]
            yield Smoke(client, root)
            show("unload", client.post("/models/unload", json={"kind": "all"}).json())
    finally:
        mx.set_default_device(mx.cpu)
        if previous is None:
            os.environ.pop(MODELS_DIR_ENV, None)
        else:
            os.environ[MODELS_DIR_ENV] = previous
        shutil.rmtree(root, ignore_errors=True)


def test_forge_and_compare(smoke: Smoke) -> None:
    three = smoke.forge(
        "quantize", model=Q4, output_dir=smoke.path("q3"), method="affine", bits=3, group_size=64
    )
    ternary = smoke.forge(
        "quantize",
        model=BF16,
        output_dir=smoke.path("ternary"),
        method="simulated",
        ternary=True,
        group_size=64,
    )
    converted = smoke.forge(
        "convert",
        model=BF16,
        output_dir=smoke.path("converted-q4"),
        dtype="bfloat16",
        quantize={"bits": 4, "group_size": 64},
    )
    pruned = smoke.forge(
        "prune",
        model=Q4,
        output_dir=smoke.path("pruned"),
        drop_layers=[20, 21],
        drop_heads=[{"layer": 3, "head": 5}],
    )
    assert pruned["num_layers"] == 26
    assert 3.0 < three["bits_per_weight"] < 4.0
    assert ternary["bits_per_weight"] < 2.5
    assert 4.0 < converted["bits_per_weight"] < 5.0

    listed = {m["name"]: m for m in smoke.client.get("/models").json()["models"]}
    show("models（local）", [m for m in listed.values() if m["source"] == "local"])
    assert listed["q3"]["source"] == "local"
    assert listed["q3"]["id"] == smoke.path("q3")
    assert listed["Qwen3-0.6B-4bit"]["source"] == "hub"

    results = smoke.evaluate(
        [
            {"model": BF16},
            {"model": Q4},
            {"model": smoke.path("converted-q4")},
            {"model": smoke.path("q3")},
            {"model": smoke.path("pruned")},
            {"model": smoke.path("ternary")},
        ]
    )
    ppl = {name: result["perplexity"] for name, result in results.items()}
    assert ppl["Qwen3-0.6B-bf16"] < ppl["q3"]
    assert ppl["Qwen3-0.6B-4bit"] < ppl["q3"]
    assert abs(ppl["converted-q4"] - ppl["Qwen3-0.6B-4bit"]) / ppl["Qwen3-0.6B-4bit"] < 0.15
    assert ppl["q3"] < ppl["ternary"]


def test_distill_fuse_and_merge(smoke: Smoke) -> None:
    student = smoke.path("q3")
    if not Path(student).exists():
        smoke.forge("quantize", model=Q4, output_dir=student, bits=3, group_size=64)
    texts = [text for text in TEXTS for _ in range(8)]
    events = ndjson(
        smoke.client.post(
            "/forge/distill",
            json={
                "teacher": BF16,
                "student": student,
                "texts": texts,
                "output_dir": smoke.path("distilled-adapter"),
                "iterations": 40,
                "learning_rate": 1e-4,
                "temperature": 2.0,
                "alpha": 0.8,
                "max_seq_length": 128,
                "batch_size": 2,
                "lora_rank": 8,
            },
        )
    )
    show("distill", [e for e in events if e["type"] in ("progress", "validation", "done")])
    assert events[-1]["type"] == "done", events[-1]
    assert events[-1]["kind"] == "adapter"
    progress = [e for e in events if e["type"] == "progress"]
    assert progress[-1]["kl"] < progress[0]["kl"]

    fused = smoke.forge(
        "fuse",
        model=student,
        adapter=smoke.path("distilled-adapter"),
        output_dir=smoke.path("q3-fused"),
    )
    assert fused["bits_per_weight"] < 4.0
    # 量子化したまま焼き込むと、差分が 3 ビットの目盛りに丸められて効き目が薄れる。戻せばそのまま
    exact = smoke.forge(
        "fuse",
        model=student,
        adapter=smoke.path("distilled-adapter"),
        output_dir=smoke.path("q3-fused-dequantized"),
        dequantize=True,
    )
    assert exact["bits_per_weight"] == 16.0
    merged = smoke.forge(
        "merge",
        models=[BF16, student],
        output_dir=smoke.path("merged"),
        method="slerp",
        t=0.5,
    )
    assert merged["bits_per_weight"] == 16.0

    results = smoke.evaluate(
        [
            {"model": student},
            {"model": student, "adapter": smoke.path("distilled-adapter")},
            {"model": smoke.path("q3-fused")},
            {"model": smoke.path("q3-fused-dequantized")},
            {"model": smoke.path("merged")},
        ]
    )
    adapted = results["q3+adapter"]["perplexity"]
    assert adapted < results["q3"]["perplexity"]
    assert results["q3-fused"]["perplexity"] < results["q3"]["perplexity"]
    assert abs(results["q3-fused-dequantized"]["perplexity"] - adapted) / adapted < 0.05


def test_scratch_plots_weight_norms(smoke: Smoke) -> None:
    code = """
norms = []
for index, layer in enumerate(model.layers):
    projection = layer.self_attn.o_proj
    weight = mx.dequantize(projection.weight, projection.scales, projection.biases,
                           group_size=projection.group_size, bits=projection.bits)
    norms.append({"層": index, "ノルム": float(mx.linalg.norm(weight.astype(mx.float32)))})
print(len(norms), "層")
plt.plot([row["ノルム"] for row in norms])
plt.title("o_proj norms")
show(norms[:3])
generate("The capital of France is", max_tokens=5)
"""
    events = ndjson(
        smoke.client.post("/scratch/run", json={"session": "smoke", "code": code, "model": Q4})
    )
    summary = [
        {**e, "png_base64": f"{len(base64.b64decode(e['png_base64']))} bytes"}
        if e["type"] == "image"
        else e
        for e in events
    ]
    show("scratch", summary)
    types = [e["type"] for e in events]
    assert types == ["stdout", "table", "image", "value", "done"], events
    assert events[0]["text"] == "28 層\n"
    assert events[1]["columns"] == ["層", "ノルム"]
    assert "Paris" in events[3]["repr"]
    assert smoke.client.post("/scratch/reset", json={"session": "smoke"}).json() == {"reset": True}
