"""mflux とのつなぎ目のテスト。重みは読まず、mflux の呼び出しの形だけを確かめる。"""

import inspect
from dataclasses import replace
from importlib import import_module
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

from sundesk_engine.errors import UnsupportedError
from sundesk_engine.images.catalog import IMAGE_MODELS, find_image_model, find_image_repo
from sundesk_engine.images.mflux_backend import MfluxBackend, MfluxGenerator


class FakeMfluxModel:
    """mflux のモデルと同じく、`callbacks` に登録した処理を段ごとに呼ぶ。"""

    def __init__(self) -> None:
        registry: Any = import_module("mflux.callbacks.callback_registry")
        self.callbacks = registry.CallbackRegistry()
        self.calls: list[dict[str, Any]] = []

    def generate_image(self, **options: Any) -> Any:
        self.calls.append(options)
        steps = int(options["num_inference_steps"])
        config = SimpleNamespace(num_inference_steps=steps, time_steps=range(steps))
        context = self.callbacks.start(
            seed=options["seed"], prompt=options["prompt"], config=config
        )
        for t in range(steps):
            context.in_loop(t, latents=None)
        saved: list[Path] = []

        class Image:
            def save(self, *, path: Path, overwrite: bool) -> None:
                assert overwrite
                path.write_bytes(b"png")
                saved.append(path)

        return Image()


def test_generator_relays_progress_and_saves(tmp_path: Path) -> None:
    spec = find_image_model("flux2-klein-4b")
    assert spec is not None
    model = FakeMfluxModel()
    generator = MfluxGenerator(spec, model)
    steps: list[tuple[int, int]] = []
    output = tmp_path / "nested" / "image.png"

    generator.generate(
        prompt="猫",
        width=512,
        height=512,
        steps=3,
        seed=1,
        output_path=output,
        on_step=lambda step, total: steps.append((step, total)),
    )

    assert steps == [(1, 3), (2, 3), (3, 3)]
    assert output.read_bytes() == b"png"
    assert model.calls[0]["guidance"] == 1.0
    assert model.calls[0]["num_inference_steps"] == 3


@pytest.mark.parametrize(
    ("module", "name"),
    [
        ("mflux.models.z_image.variants.z_image", "ZImage"),
        ("mflux.models.flux2.variants.txt2img.flux2_klein", "Flux2Klein"),
    ],
)
def test_mflux_api_matches_what_the_backend_calls(module: str, name: str) -> None:
    cls: Any = getattr(import_module(module), name)

    init = inspect.signature(cls.__init__).parameters
    generate = inspect.signature(cls.generate_image).parameters

    assert {"quantize", "model_path", "model_config"} <= set(init)
    assert {"seed", "prompt", "num_inference_steps", "width", "height", "guidance"} <= set(generate)


def test_mflux_knows_the_catalog_models() -> None:
    config: Any = import_module("mflux.models.common.config.model_config").ModelConfig

    repos = {spec.id: spec.repo for spec in IMAGE_MODELS}

    assert config.z_image_turbo().model_name == repos["z-image-turbo"]
    assert config.flux2_klein_4b().model_name == repos["flux2-klein-4b"]
    assert all(find_image_repo(spec.repo) is spec for spec in IMAGE_MODELS)


def test_backend_rejects_unknown_models(tmp_path: Path) -> None:
    spec = IMAGE_MODELS[0]
    unknown = replace(spec, id="other")

    with pytest.raises(UnsupportedError):
        MfluxBackend().load(unknown, tmp_path, None)
