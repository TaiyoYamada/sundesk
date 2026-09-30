"""工房（量子化、変換、焼き込み、合成、枝刈り）のテスト。

小さなランダムの Qwen3 を、本物のファイルにして使う。
"""

import json
import math
from importlib import import_module
from pathlib import Path
from typing import Any

import mlx.core as mx
import numpy as np
import pytest
from conftest import Harness
from fakes import ndjson, write_tiny_model

from sundesk_engine.forge.quantize import fake_affine, fake_ternary
from sundesk_engine.forge.surgery import lerp, slerp
from sundesk_engine.forge.workpiece import layer_prefix, tree_flatten
from sundesk_engine.lab.arrays import to_float

DISK = "test/disk-llm"


@pytest.fixture
def disk(harness: Harness) -> Path:
    return harness.hub.add_disk_model(DISK)


def load(path: Path, adapter: Path | None = None) -> tuple[Any, Any]:
    from mlx_lm.utils import load as mlx_load

    loaded: Any = mlx_load(str(path), adapter_path=str(adapter) if adapter else None)
    return loaded[0], loaded[1]


def weights(path: Path) -> dict[str, np.ndarray[Any, Any]]:
    arrays: Any = mx.load(str(path / "model.safetensors"))
    return {
        str(name): np.asarray(value.astype(mx.float32)) if value.dtype != mx.uint32 else value
        for name, value in arrays.items()
    }


def logits(model: Any, ids: list[int]) -> np.ndarray[Any, Any]:
    output = model(mx.array(ids, dtype=mx.int32)[None])[0].astype(mx.float32)
    return np.asarray(output)


def forge(harness: Harness, name: str, **body: object) -> list[dict[str, Any]]:
    return ndjson(harness.client.post(f"/forge/{name}", json=body))


def output(harness: Harness, name: str = "out") -> str:
    return str(harness.tmp_path / "Forged" / name)


# MARK: - 量子化


def test_quantize_affine_writes_a_loadable_model(harness: Harness, disk: Path) -> None:
    del disk
    harness.client.post("/lab/next-token", json={"model": DISK, "prompt": "a"})
    assert harness.engine.models.loaded()["llm"] == DISK
    target = output(harness)

    events = forge(harness, "quantize", model=DISK, output_dir=target, bits=4, group_size=32)

    assert events[0] == {"type": "loading", "model": DISK}
    progress = [e for e in events if e["type"] == "progress"]
    assert {e["stage"] for e in progress} == {"quantizing", "saving"}
    fractions = [e["fraction"] for e in progress if e["stage"] == "quantizing"]
    assert fractions == sorted(fractions)
    assert fractions[-1] == 1.0
    assert any(e["message"] == "層 1/2" for e in progress)
    done = events[-1]
    assert done["type"] == "done"
    assert done["output_dir"] == target
    assert done["size_bytes"] > 0
    assert 4.0 < done["bits_per_weight"] < 8.0
    # 作る前に、載せていたモデルは捨てる
    assert harness.engine.models.loaded()["llm"] is None

    config = json.loads((Path(target) / "config.json").read_text())
    assert config["quantization"] == {"group_size": 32, "bits": 4, "mode": "affine"}
    model, tokenizer = load(Path(target))
    assert model.layers[0].mlp.up_proj.bits == 4
    assert np.isfinite(logits(model, tokenizer.encode("固有値"))).all()
    # 途中の隠しフォルダは残らない
    assert [p.name for p in Path(target).parent.iterdir()] == ["out"]


def test_quantize_mixed_recipe_and_overrides(harness: Harness, disk: Path) -> None:
    del disk
    target = output(harness)

    events = forge(
        harness,
        "quantize",
        model=DISK,
        output_dir=target,
        bits=4,
        group_size=32,
        mixed="mixed_3_6",
        overrides=[{"pattern": "embed_tokens", "bits": 8}, {"pattern": "k_proj", "bits": None}],
    )

    assert events[-1]["type"] == "done", events[-1]
    quantization = json.loads((Path(target) / "config.json").read_text())["quantization"]
    assert quantization["model.embed_tokens"]["bits"] == 8
    assert quantization["model.layers.0.mlp.up_proj"]["bits"] == 3
    # 2 層なら、後ろの 1/8（1 層目）の down_proj と v_proj を 6 ビットにする
    assert quantization["model.layers.0.mlp.down_proj"]["bits"] == 3
    assert quantization["model.layers.1.mlp.down_proj"]["bits"] == 6
    assert quantization["model.layers.1.self_attn.v_proj"]["bits"] == 6
    model, _tokenizer = load(Path(target))
    assert model.model.embed_tokens.bits == 8
    assert not hasattr(model.layers[0].self_attn.k_proj, "scales")
    assert model.layers[1].self_attn.q_proj.bits == 3


def test_quantize_requantizes_a_quantized_model(harness: Harness, disk: Path) -> None:
    del disk
    first = output(harness, "four")
    forge(harness, "quantize", model=DISK, output_dir=first, bits=4, group_size=32)

    second = output(harness, "eight")
    events = forge(harness, "quantize", model=first, output_dir=second, bits=8, group_size=64)

    assert events[-1]["type"] == "done", events[-1]
    model, _tokenizer = load(Path(second))
    assert model.layers[0].mlp.up_proj.bits == 8
    assert model.layers[0].mlp.up_proj.group_size == 64


def test_quantize_simulated_keeps_float16(harness: Harness, disk: Path) -> None:
    del disk
    target = output(harness)

    events = forge(
        harness,
        "quantize",
        model=DISK,
        output_dir=target,
        method="simulated",
        bits=3,
        group_size=32,
    )

    done = events[-1]
    assert done["type"] == "done", done
    # 3 ビット + 目盛りとずれ（16 ビット × 2 / 32）= 4 ビット。ノルムなどの 16 ビットが少し混じる
    assert 4.0 <= done["bits_per_weight"] < 4.5
    config = json.loads((Path(target) / "config.json").read_text())
    assert "quantization" not in config
    stored = mx.load(str(Path(target) / "model.safetensors"))
    assert isinstance(stored, dict)
    assert {value.dtype for value in stored.values()} == {mx.float16}
    groups = to_float(stored["model.layers.0.mlp.up_proj.weight"])
    groups = groups.reshape(-1, 32)
    assert max(len(np.unique(row)) for row in groups) <= 8
    model, tokenizer = load(Path(target))
    assert np.isfinite(logits(model, tokenizer.encode("固有値"))).all()


def test_quantize_simulated_ternary(harness: Harness, disk: Path) -> None:
    del disk
    target = output(harness)

    events = forge(
        harness,
        "quantize",
        model=DISK,
        output_dir=target,
        method="simulated",
        ternary=True,
        group_size=64,
    )

    done = events[-1]
    assert done["type"] == "done", done
    assert math.log2(3) < done["bits_per_weight"] < 2.5
    stored = mx.load(str(Path(target) / "model.safetensors"))
    assert isinstance(stored, dict)
    rows = to_float(stored["model.layers.1.self_attn.q_proj.weight"])
    for row in rows.reshape(-1, 64):
        values = np.unique(np.abs(row))
        assert len(values[values > 0]) <= 1


@pytest.mark.parametrize(
    ("fields", "status"),
    [
        ({"bits": 7}, 400),
        ({"group_size": 48}, 400),
        ({"method": "simulated", "bits": 9}, 400),
        ({"method": "simulated", "bits": 3, "mixed": "mixed_3_6"}, 400),
        ({"ternary": True}, 400),
        ({"mixed": "mixed_9_9"}, 400),
        ({"overrides": [{"pattern": "lm_head", "bits": 7}]}, 400),
        ({"output_dir": "relative/path"}, 400),
        ({"model": "test/missing"}, 404),
        ({"model": "/no/such/folder"}, 404),
    ],
)
def test_quantize_rejects_bad_requests(
    harness: Harness, disk: Path, fields: dict[str, object], status: int
) -> None:
    del disk
    body = {"model": DISK, "output_dir": output(harness), "bits": 4, "group_size": 32} | fields

    response = harness.client.post("/forge/quantize", json=body)

    assert response.status_code == status, response.text


def test_output_dir_must_be_new(harness: Harness, disk: Path) -> None:
    del disk
    target = Path(output(harness))
    target.mkdir(parents=True)
    (target / "keep.txt").write_text("大事なもの")

    response = harness.client.post(
        "/forge/quantize", json={"model": DISK, "output_dir": str(target), "group_size": 32}
    )

    assert response.status_code == 400
    assert (target / "keep.txt").read_text() == "大事なもの"


def test_fake_quantization_math() -> None:
    weight = mx.array(np.linspace(-1.0, 1.0, 64, dtype=np.float32).reshape(2, 32))

    one_bit = to_float(fake_affine(weight, 1, 32))
    two_bits = to_float(fake_affine(weight, 2, 32))
    ternary = to_float(fake_ternary(weight, 32))

    for row, original in zip(one_bit, to_float(weight), strict=True):
        levels = {round(float(value), 5) for value in row}
        assert levels == {round(float(original.min()), 5), round(float(original.max()), 5)}
    assert all(len(np.unique(row)) == 4 for row in two_bits)
    first = to_float(weight)[0]
    scale = float(np.abs(first).mean())
    expected = np.clip(np.rint(first / scale), -1.0, 1.0) * scale
    assert np.allclose(ternary[0], expected)


def test_layer_prefix() -> None:
    assert layer_prefix("model.layers.12.mlp.up_proj") == "model.layers.12"
    assert layer_prefix("model.layers.3") == "model.layers.3"
    assert layer_prefix("model.embed_tokens") is None


# MARK: - 変換


def test_convert_changes_dtype_and_quantizes(harness: Harness, disk: Path) -> None:
    del disk
    plain = output(harness, "bf16")
    events = forge(harness, "convert", model=DISK, output_dir=plain, dtype="bfloat16")

    assert events[-1]["type"] == "done", events[-1]
    assert events[-1]["bits_per_weight"] == 16.0
    assert {e["stage"] for e in events if e["type"] == "progress"} == {"converting", "saving"}
    stored = mx.load(str(Path(plain) / "model.safetensors"))
    assert isinstance(stored, dict)
    assert {value.dtype for value in stored.values()} == {mx.bfloat16}
    assert json.loads((Path(plain) / "config.json").read_text())["torch_dtype"] == "bfloat16"

    quantized = output(harness, "q4")
    events = forge(
        harness,
        "convert",
        model=DISK,
        output_dir=quantized,
        dtype="float16",
        quantize={"bits": 4, "group_size": 64},
    )

    assert events[-1]["type"] == "done", events[-1]
    model, _tokenizer = load(Path(quantized))
    assert model.layers[0].mlp.up_proj.bits == 4


def test_convert_reads_pytorch_checkpoints(harness: Harness, tmp_path: Path) -> None:
    import torch

    source = write_tiny_model(tmp_path / "hf", seed=3)
    original = weights(source)
    torch.save(
        {name: torch.tensor(value.tolist()) for name, value in original.items()},
        source / "pytorch_model.bin",
    )
    for file in source.glob("model*.safetensors*"):
        file.unlink()
    target = output(harness)

    events = forge(harness, "convert", model=str(source), output_dir=target, dtype="float32")

    assert events[-1]["type"] == "done", events[-1]
    converted = weights(Path(target))
    assert converted.keys() == original.keys()
    for name, value in original.items():
        assert np.allclose(converted[name], value)
    load(Path(target))


def test_convert_without_weights_is_422(harness: Harness, tmp_path: Path) -> None:
    source = tmp_path / "empty"
    source.mkdir()
    (source / "config.json").write_text("{}")

    events = forge(harness, "convert", model=str(source), output_dir=output(harness))

    assert events[-1]["type"] == "error"
    assert "変換できる重み" in events[-1]["message"]
    assert not Path(output(harness)).exists()


# MARK: - 焼き込み


def make_adapter(base: Path, path: Path) -> Path:
    """重みを乱数にした LoRA のアダプタを作る（学習の代わり）。"""
    tuner: Any = import_module("mlx_lm.tuner.utils")
    utils: Any = import_module("mlx_lm.utils")

    loaded: Any = utils.load_model(base)
    model = loaded[0]
    parameters = {"rank": 4, "scale": 2.0, "dropout": 0.0}
    model.freeze()
    tuner.linear_to_lora_layers(model, 2, parameters)
    mx.random.seed(7)
    trainable: Any = tree_flatten(model.trainable_parameters())
    randomized = {name: mx.random.normal(value.shape) * 0.1 for name, value in trainable}
    path.mkdir(parents=True)
    save: Any = getattr(mx, "save_safetensors")  # noqa: B009 - 型の情報が足りない関数を Any で呼ぶ
    save(str(path / "adapters.safetensors"), randomized)
    config = {"fine_tune_type": "lora", "num_layers": 2, "lora_parameters": parameters}
    (path / "adapter_config.json").write_text(json.dumps(config))
    return path


def test_fuse_matches_model_with_adapter(harness: Harness, disk: Path) -> None:
    adapter = make_adapter(disk, harness.tmp_path / "adapter")
    target = output(harness)

    events = forge(harness, "fuse", model=DISK, adapter=str(adapter), output_dir=target)

    assert events[-1]["type"] == "done", events[-1]
    with_adapter, tokenizer = load(disk, adapter)
    fused, _tokenizer = load(Path(target))
    base, _tokenizer = load(disk)
    ids = tokenizer.encode("固有値とは")
    assert np.allclose(logits(fused, ids), logits(with_adapter, ids), atol=1e-4)
    assert not np.allclose(logits(base, ids), logits(with_adapter, ids), atol=1e-3)


def test_fuse_can_dequantize(harness: Harness, disk: Path) -> None:
    del disk
    quantized = output(harness, "q8")
    forge(harness, "quantize", model=DISK, output_dir=quantized, bits=8, group_size=32)
    adapter = make_adapter(Path(quantized), harness.tmp_path / "adapter")

    kept = output(harness, "kept")
    plain = output(harness, "plain")
    forge(harness, "fuse", model=quantized, adapter=str(adapter), output_dir=kept)
    events = forge(
        harness, "fuse", model=quantized, adapter=str(adapter), output_dir=plain, dequantize=True
    )

    assert events[-1]["type"] == "done", events[-1]
    assert load(Path(kept))[0].layers[0].mlp.up_proj.bits == 8
    assert "quantization" not in json.loads((Path(plain) / "config.json").read_text())
    assert not hasattr(load(Path(plain))[0].layers[0].mlp.up_proj, "scales")


def test_fuse_needs_an_adapter(harness: Harness, disk: Path) -> None:
    del disk
    response = harness.client.post(
        "/forge/fuse",
        json={
            "model": DISK,
            "adapter": str(harness.tmp_path / "none"),
            "output_dir": output(harness),
        },
    )

    assert response.status_code == 404


# MARK: - 合成


def test_merge_linear(harness: Harness, disk: Path) -> None:
    other = harness.hub.add_disk_model("test/other", seed=1)
    target = output(harness)

    events = forge(
        harness, "merge", models=[DISK, "test/other"], output_dir=target, method="linear", t=0.25
    )

    assert events[-1]["type"] == "done", events[-1]
    assert {e["stage"] for e in events if e["type"] == "progress"} == {"merging", "saving"}
    assert [e["model"] for e in events if e["type"] == "loading"] == [DISK, "test/other"]
    left, right, merged = weights(disk), weights(other), weights(Path(target))
    for name, value in merged.items():
        assert np.allclose(value, 0.75 * left[name] + 0.25 * right[name], atol=2e-3)
    stored = mx.load(str(Path(target) / "model.safetensors"))
    assert isinstance(stored, dict)
    assert {value.dtype for value in stored.values()} == {mx.float16}
    load(Path(target))


def test_merge_slerp(harness: Harness, disk: Path) -> None:
    other = harness.hub.add_disk_model("test/other", seed=1)
    target = output(harness)

    events = forge(harness, "merge", models=[DISK, "test/other"], output_dir=target, t=0.5)

    assert events[-1]["type"] == "done", events[-1]
    name = "model.layers.0.mlp.up_proj.weight"
    a, b = weights(disk)[name].ravel(), weights(other)[name].ravel()
    omega = math.acos(float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b))))
    expected = (math.sin(0.5 * omega) * a + math.sin(0.5 * omega) * b) / math.sin(omega)
    assert np.allclose(weights(Path(target))[name].ravel(), expected, atol=2e-3)


def test_merge_math() -> None:
    a = mx.array([1.0, 0.0])
    b = mx.array([0.0, 1.0])

    assert np.allclose(to_float(lerp(a, b, 0.25)), [0.75, 0.25])
    halfway = to_float(slerp(a, b, 0.5))
    assert np.allclose(halfway, [math.sqrt(0.5), math.sqrt(0.5)])
    assert np.allclose(np.linalg.norm(halfway), 1.0)
    # ほぼ同じ向きなら、線形補間にする
    assert np.allclose(to_float(slerp(a, a * 2, 0.5)), [1.5, 0.0])


def test_merge_rejects_different_structures(harness: Harness, disk: Path) -> None:
    del disk
    harness.hub.add_disk_model("test/deeper", num_layers=3)

    response = harness.client.post(
        "/forge/merge",
        json={"models": [DISK, "test/deeper"], "output_dir": output(harness), "method": "linear"},
    )

    assert response.status_code == 422
    assert "num_hidden_layers" in response.json()["detail"]


def test_merge_needs_two_models(harness: Harness, disk: Path) -> None:
    del disk
    response = harness.client.post(
        "/forge/merge", json={"models": [DISK], "output_dir": output(harness)}
    )

    assert response.status_code == 400


# MARK: - 枝刈り


def test_prune_drops_layers_and_zeroes_heads(harness: Harness) -> None:
    source = harness.hub.add_disk_model(DISK, num_layers=3)
    target = output(harness)

    events = forge(
        harness,
        "prune",
        model=DISK,
        output_dir=target,
        drop_layers=[1],
        drop_heads=[{"layer": 0, "head": 1}, {"layer": 1, "head": 0}],
    )

    done = events[-1]
    assert done["type"] == "done", done
    assert done["num_layers"] == 2
    config = json.loads((Path(target) / "config.json").read_text())
    assert config["num_hidden_layers"] == 2
    before, after = weights(source), weights(Path(target))
    assert np.array_equal(
        after["model.layers.1.mlp.up_proj.weight"], before["model.layers.2.mlp.up_proj.weight"]
    )
    projection = after["model.layers.0.self_attn.o_proj.weight"]
    original = before["model.layers.0.self_attn.o_proj.weight"]
    head_dim = 16
    assert np.all(projection[:, head_dim : 2 * head_dim] == 0)
    assert np.array_equal(projection[:, :head_dim], original[:, :head_dim])
    assert np.array_equal(projection[:, 2 * head_dim :], original[:, 2 * head_dim :])
    model, _tokenizer = load(Path(target))
    assert len(model.layers) == 2


@pytest.mark.parametrize(("head_dim", "group_size"), [(32, 32), (16, 32)])
def test_prune_heads_of_quantized_models(harness: Harness, head_dim: int, group_size: int) -> None:
    harness.hub.add_disk_model(DISK, num_layers=3, head_dim=head_dim)
    quantized = output(harness, "q")
    forge(harness, "quantize", model=DISK, output_dir=quantized, bits=8, group_size=group_size)
    target = output(harness)

    events = forge(
        harness,
        "prune",
        model=quantized,
        output_dir=target,
        drop_layers=[0],
        drop_heads=[{"layer": 1, "head": 2}],
    )

    assert events[-1]["type"] == "done", events[-1]
    model, _tokenizer = load(Path(target))
    reference, _tokenizer = load(Path(quantized))
    config = json.loads((Path(target) / "config.json").read_text())
    assert config["num_hidden_layers"] == 2

    def dequantized(module: Any) -> np.ndarray[Any, Any]:
        return np.asarray(
            mx.dequantize(
                module.weight,
                module.scales,
                module.biases,
                group_size=module.group_size,
                bits=module.bits,
            )
        )

    projection = model.layers[0].self_attn.o_proj
    if head_dim % group_size == 0:
        # グループの目盛りを 0 にするだけなので、量子化したまま
        pruned = dequantized(projection)
    else:
        # 0 をちょうど表せないので、その層だけ量子化しないで持つ
        assert not hasattr(projection, "scales")
        assert config["quantization"]["model.layers.0.self_attn.o_proj"] is False
        pruned = np.asarray(projection.weight.astype(mx.float32))
    original = dequantized(reference.layers[1].self_attn.o_proj)
    assert np.all(pruned[:, 2 * head_dim : 3 * head_dim] == 0)
    assert np.array_equal(pruned[:, : 2 * head_dim], original[:, : 2 * head_dim])
    assert model.layers[0].self_attn.q_proj.bits == 8


@pytest.mark.parametrize(
    "fields",
    [
        {"drop_layers": [5]},
        {"drop_layers": [0, 1]},
        {"drop_heads": [{"layer": 0, "head": 4}]},
        {"drop_heads": [{"layer": 9, "head": 0}]},
    ],
)
def test_prune_rejects_bad_numbers(harness: Harness, disk: Path, fields: dict[str, object]) -> None:
    del disk
    response = harness.client.post(
        "/forge/prune", json={"model": DISK, "output_dir": output(harness)} | fields
    )

    assert response.status_code == 400, response.text


def test_models_lists_forged_folders(harness: Harness, disk: Path) -> None:
    from fastapi.testclient import TestClient

    from sundesk_engine.app import create_app
    from sundesk_engine.engine import Engine
    from sundesk_engine.runtime.hub import HuggingFaceHub

    del disk
    forge(
        harness,
        "quantize",
        model=DISK,
        output_dir=output(harness, "qwen-3bit"),
        bits=3,
        group_size=32,
    )
    hub = HuggingFaceHub(harness.tmp_path / "cache", models_dir=harness.tmp_path / "Forged")
    client = TestClient(create_app(engine=Engine(hub=hub, models=harness.engine.models)))

    models = client.get("/models").json()["models"]

    assert models == [
        {
            "id": output(harness, "qwen-3bit"),
            "kind": "llm",
            "size_bytes": models[0]["size_bytes"],
            "path": output(harness, "qwen-3bit"),
            "name": "qwen-3bit",
            "source": "local",
        }
    ]
    assert models[0]["size_bytes"] > 0
