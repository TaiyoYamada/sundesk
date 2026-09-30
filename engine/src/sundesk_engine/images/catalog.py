"""使える画像生成モデルの一覧。

生成は mflux で行う。ダウンロードする範囲は、mflux が読むファイルだけにする
（同じ重みの別形式まで落とすと、容量が倍になる）。
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class ImageModelSpec:
    id: str
    """エンジンの中での名前（mflux の名前と同じ）"""
    name: str
    repo: str
    """Hugging Face の ID"""
    default_steps: int
    default_width: int
    default_height: int
    download_patterns: tuple[str, ...]
    required_files: tuple[str, ...]
    """ダウンロード済みとみなすために揃っているべきファイル（グロブ）"""


_REQUIRED = (
    "transformer/*.safetensors",
    "vae/*.safetensors",
    "text_encoder/*.safetensors",
    "tokenizer/*",
)

IMAGE_MODELS: tuple[ImageModelSpec, ...] = (
    ImageModelSpec(
        id="z-image-turbo",
        name="Z-Image Turbo",
        repo="Tongyi-MAI/Z-Image-Turbo",
        default_steps=9,
        default_width=1024,
        default_height=1024,
        download_patterns=(
            "vae/*.safetensors",
            "vae/*.json",
            "transformer/*.safetensors",
            "transformer/*.json",
            "text_encoder/*.safetensors",
            "text_encoder/*.json",
            "tokenizer/*",
        ),
        required_files=_REQUIRED,
    ),
    ImageModelSpec(
        id="flux2-klein-4b",
        name="FLUX.2 klein 4B",
        repo="black-forest-labs/FLUX.2-klein-4B",
        default_steps=4,
        default_width=1024,
        default_height=1024,
        download_patterns=(
            "vae/*.safetensors",
            "vae/*.json",
            "transformer/*.safetensors",
            "transformer/*.json",
            "text_encoder/*.safetensors",
            "text_encoder/*.json",
            "tokenizer/**",
            "added_tokens.json",
            "chat_template.jinja",
        ),
        required_files=_REQUIRED,
    ),
)


def find_image_model(model_id: str) -> ImageModelSpec | None:
    return next((spec for spec in IMAGE_MODELS if spec.id == model_id), None)


def find_image_repo(repo: str) -> ImageModelSpec | None:
    return next((spec for spec in IMAGE_MODELS if spec.repo == repo), None)
