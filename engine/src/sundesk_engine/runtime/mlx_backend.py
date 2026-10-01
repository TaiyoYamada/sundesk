"""mlx-lm による LLM の読み込み。mlx-lm の読み込みは重いので、使うときまで遅らせる。"""

import json
from pathlib import Path
from typing import Any

from sundesk_engine.errors import UnsupportedError


def _eos_token_ids(path: Path) -> Any:
    try:
        config = json.loads((path / "config.json").read_text())
    except (OSError, ValueError):
        return None
    return config.get("eos_token_id") if isinstance(config, dict) else None  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType]


class MlxLmBackend:
    def load(self, path: Path, adapter: Path | None) -> tuple[Any, Any]:
        from mlx_lm.utils import load

        try:
            loaded: Any = load(
                str(path),
                adapter_path=str(adapter) if adapter else None,
            )
        except ValueError as error:
            # 対応していない model_type など
            raise UnsupportedError(f"このモデルは読み込めません: {error}") from error
        model, tokenizer = loaded
        return model, tokenizer

    def load_tokenizer(self, path: Path) -> Any:
        from mlx_lm.utils import load_tokenizer  # pyright: ignore[reportUnknownVariableType]

        return load_tokenizer(path, eos_token_ids=_eos_token_ids(path))
