"""mflux による画像生成。mflux には型の情報がないので、呼び出しはこのモジュールに閉じ込める。"""

from collections.abc import Callable
from importlib import import_module
from pathlib import Path
from typing import Any

from sundesk_engine.errors import UnsupportedError
from sundesk_engine.images.catalog import ImageModelSpec
from sundesk_engine.runtime.manager import ImageGenerator


class _ProgressRelay:
    """mflux の段ごとの呼び出しを受けて、今の生成の `on_step` に渡す。"""

    def __init__(self) -> None:
        self.target: Callable[[int, int], None] | None = None

    def call_in_loop(self, t: int, config: Any, **_kwargs: Any) -> None:
        if self.target is not None:
            total = int(config.num_inference_steps)
            self.target(t + 1, total)


class MfluxGenerator:
    def __init__(self, spec: ImageModelSpec, model: Any) -> None:
        self._spec = spec
        self._model = model
        self._relay = _ProgressRelay()
        model.callbacks.register(self._relay)

    def generate(
        self,
        *,
        prompt: str,
        width: int,
        height: int,
        steps: int,
        seed: int,
        output_path: Path,
        on_step: Callable[[int, int], None],
    ) -> None:
        self._relay.target = on_step
        try:
            options: dict[str, Any] = {
                "seed": seed,
                "prompt": prompt,
                "num_inference_steps": steps,
                "width": width,
                "height": height,
            }
            if self._spec.id.startswith("flux2-klein"):
                # 蒸留済みの klein は guidance 1.0 でしか動かない
                options["guidance"] = 1.0
            image = self._model.generate_image(**options)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path=output_path, overwrite=True)
        finally:
            self._relay.target = None


class MfluxBackend:
    def load(self, spec: ImageModelSpec, path: Path, quantize: int | None) -> ImageGenerator:
        # mflux には型の情報がないので、モジュールを Any として読み込む
        config: Any = import_module("mflux.models.common.config.model_config")
        if spec.id == "z-image-turbo":
            variant: Any = import_module("mflux.models.z_image.variants.z_image")
            model: Any = variant.ZImage(
                quantize=quantize,
                model_path=str(path),
                model_config=config.ModelConfig.z_image_turbo(),
            )
        elif spec.id == "flux2-klein-4b":
            variant = import_module("mflux.models.flux2.variants.txt2img.flux2_klein")
            model = variant.Flux2Klein(
                quantize=quantize,
                model_path=str(path),
                model_config=config.ModelConfig.flux2_klein_4b(),
            )
        else:
            raise UnsupportedError(f"この画像モデルには対応していません: {spec.id}")
        return MfluxGenerator(spec, model)
