"""Hugging Face のキャッシュ（`~/.cache/huggingface/hub`）と、手元のフォルダにあるモデルの管理。

キャッシュの構造は次のとおり。

    models--<org>--<name>/
        blobs/<etag>                ← 実体
        refs/main                   ← 最新のコミット
        snapshots/<commit>/<file>   ← blobs への symlink

アプリが作ったモデル（量子化や蒸留の結果）は、環境変数 `SUNDESK_MODELS_DIR` のフォルダの直下に
1 つずつフォルダとして置く。これらは絶対パスを ID にして一覧に加える。
"""

import json
import os
import shutil
import threading
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any, Literal, Protocol

from sundesk_engine.errors import BadRequestError, InternalError, NotFoundError

type ModelKind = Literal["llm", "embedding", "image", "other"]
type ModelSource = Literal["hub", "local"]

MODELS_DIR_ENV = "SUNDESK_MODELS_DIR"

# 同じ重みの別形式（PyTorch、ONNX など）は落とさない
DEFAULT_IGNORE_PATTERNS = [
    "*.bin",
    "*.pt",
    "*.pth",
    "*.ckpt",
    "*.onnx",
    "*.onnx_data",
    "*.h5",
    "*.msgpack",
    "*.gguf",
    "*.ot",
    "onnx/*",
    "openvino/*",
    "coreml/*",
]


@dataclass(frozen=True)
class LocalModel:
    id: str
    kind: ModelKind
    size_bytes: int
    path: str
    name: str
    """表示名。キャッシュならリポジトリ名、手元のフォルダならフォルダ名"""
    source: ModelSource


@dataclass(frozen=True)
class RemoteFile:
    filename: str
    size: int
    etag: str | None


@dataclass(frozen=True)
class DownloadPlan:
    model_id: str
    revision: str | None
    files: tuple[RemoteFile, ...]
    allow_patterns: tuple[str, ...] | None
    ignore_patterns: tuple[str, ...] | None

    @property
    def total_bytes(self) -> int:
        return sum(file.size for file in self.files)


class Hub(Protocol):
    """モデルの置き場。テストでは偽物に差し替える。"""

    def resolve(self, model_id: str) -> Path:
        """手元にあるモデルのディレクトリを返す。なければ `NotFoundError`。"""
        ...

    def is_cached(self, model_id: str, required: Sequence[str] = ()) -> bool: ...

    def list_models(self) -> list[LocalModel]: ...

    def delete(self, model_id: str) -> bool: ...

    def plan_download(
        self,
        model_id: str,
        allow_patterns: Sequence[str] | None,
        ignore_patterns: Sequence[str] | None,
    ) -> DownloadPlan: ...

    def download(self, plan: DownloadPlan, on_progress: Callable[[int], None]) -> Path: ...


def default_cache_dir() -> Path:
    from huggingface_hub import constants

    return Path(constants.HF_HUB_CACHE)


def models_dir_from_env() -> Path | None:
    """アプリが渡す、作ったモデルの置き場（絶対パスのときだけ使う）。"""
    value = os.environ.get(MODELS_DIR_ENV, "").strip()
    if not value:
        return None
    path = Path(value).expanduser()
    return path if path.is_absolute() else None


def directory_size(path: Path) -> int:
    """フォルダの中のファイルの大きさの合計。symlink はリンク先の大きさを数える。"""
    total = 0
    for root, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += (Path(root) / name).stat().st_size
            except OSError:
                continue
    return total


def list_local_models(models_dir: Path, image_repos: Sequence[str] = ()) -> list[LocalModel]:
    """`models_dir` の直下にある、`config.json` を持つフォルダをモデルとして返す。

    名前が `.` で始まるフォルダ（作っている途中のものなど）は数えない。
    """
    if not models_dir.is_dir():
        return []
    models: list[LocalModel] = []
    for folder in sorted(models_dir.iterdir()):
        if folder.name.startswith(".") or not folder.is_dir():
            continue
        if not (folder / "config.json").is_file():
            continue
        path = str(folder)
        models.append(
            LocalModel(
                id=path,
                kind=classify(path, folder, image_repos),
                size_bytes=directory_size(folder),
                path=path,
                name=folder.name,
                source="local",
            )
        )
    return models


def repo_folder_name(model_id: str) -> str:
    return "models--" + model_id.replace("/", "--")


def validate_model_id(model_id: str) -> None:
    parts = model_id.split("/")
    if len(parts) != 2 or not all(parts) or any(part in {".", ".."} for part in parts):
        raise BadRequestError(f"モデルの ID の形が正しくありません: {model_id}")


def classify(model_id: str, snapshot: Path, image_repos: Sequence[str] = ()) -> ModelKind:
    """スナップショットの中身から、モデルの種類を推し量る。"""
    if (snapshot / "modules.json").exists() or (
        snapshot / "config_sentence_transformers.json"
    ).exists():
        return "embedding"
    if (
        model_id in image_repos
        or (snapshot / "model_index.json").exists()
        or ((snapshot / "transformer").is_dir() and (snapshot / "vae").is_dir())
    ):
        return "image"
    config_path = snapshot / "config.json"
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
        except (OSError, ValueError):
            return "other"
        if isinstance(config, dict):
            architectures = config.get("architectures")  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType]
            if isinstance(architectures, list) and any(
                isinstance(name, str) and name.endswith(("ForCausalLM", "LMHeadModel"))
                for name in architectures  # pyright: ignore[reportUnknownVariableType]
            ):
                return "llm"
    return "other"


def _blobs_size(path: Path) -> int:
    """リポジトリの blobs の合計。新しいキャッシュでは、blobs はキャッシュ全体で共有する
    実体（`<cache>/blobs/<2 桁>/<ハッシュ>`）への symlink なので、リンク先の大きさを数える。"""
    if not path.is_dir():
        return 0
    total = 0
    for file in path.iterdir():
        if file.name.endswith(".incomplete"):
            continue
        try:
            total += file.stat().st_size
        except OSError:
            continue
    return total


class _ByteCounter:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._value = 0

    def add(self, amount: int) -> None:
        with self._lock:
            self._value += amount

    @property
    def value(self) -> int:
        with self._lock:
            return self._value


_WRITTEN_PROGRESS = "huggingface_hub.snapshot_download"
"""snapshot_download が、ディスクに書いたバイト数の進捗表示に付ける名前"""
_TRANSFER_PROGRESS = "huggingface_hub.snapshot_download.transfer"
"""受け取ったバイト数の進捗表示の名前。Xet ではファイルを最後にまとめて書くので、途中はこれで測る"""


def _progress_class(written: _ByteCounter, received: _ByteCounter) -> Any:
    """snapshot_download の進捗表示に差し込み、書いた・受け取ったバイト数を数える。"""
    base: Any = import_module("huggingface_hub.utils").tqdm
    counters = {_WRITTEN_PROGRESS: written, _TRANSFER_PROGRESS: received}

    class Progress(base):
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            self._counter = counters.get(str(kwargs.get("name")))
            super().__init__(*args, **kwargs)  # pyright: ignore[reportUnknownMemberType]

        def update(self, n: float | None = 1) -> Any:
            if self._counter is not None and n:
                self._counter.add(int(n))
            return super().update(n)  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType]

    return Progress


def _latest_snapshot(repo_dir: Path) -> Path | None:
    snapshots = repo_dir / "snapshots"
    ref = repo_dir / "refs" / "main"
    if ref.is_file():
        candidate = snapshots / ref.read_text().strip()
        if candidate.is_dir():
            return candidate
    if not snapshots.is_dir():
        return None
    candidates = [path for path in snapshots.iterdir() if path.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


class HuggingFaceHub:
    """本物の Hugging Face のキャッシュを扱う。"""

    def __init__(
        self,
        cache_dir: Path | None = None,
        image_repos: Sequence[str] = (),
        poll_interval: float = 0.5,
        models_dir: Path | None = None,
    ) -> None:
        self.cache_dir = cache_dir or default_cache_dir()
        self.image_repos = tuple(image_repos)
        self.poll_interval = poll_interval
        self.models_dir = models_dir
        """アプリが作ったモデルの置き場。None なら手元のフォルダは一覧に出さない"""

    def _repo_dir(self, model_id: str) -> Path:
        validate_model_id(model_id)
        return self.cache_dir / repo_folder_name(model_id)

    def resolve(self, model_id: str) -> Path:
        local = Path(model_id).expanduser()
        if local.is_absolute():
            if local.is_dir():
                return local
            raise NotFoundError(f"モデルのディレクトリが見つかりません: {model_id}")
        snapshot = _latest_snapshot(self._repo_dir(model_id))
        if snapshot is None or not any(snapshot.iterdir()):
            raise NotFoundError(
                f"モデルが手元にありません。先にダウンロードしてください: {model_id}"
            )
        return snapshot

    def is_cached(self, model_id: str, required: Sequence[str] = ()) -> bool:
        """モデルが手元にあるか。`required` のグロブがどれも当たるなら揃っているとみなす。"""
        try:
            snapshot = self.resolve(model_id)
        except NotFoundError:
            return False
        return all(any(match.exists() for match in snapshot.glob(pattern)) for pattern in required)

    def list_models(self) -> list[LocalModel]:
        models = self._list_cached()
        if self.models_dir is not None:
            models.extend(list_local_models(self.models_dir, self.image_repos))
        return models

    def _list_cached(self) -> list[LocalModel]:
        if not self.cache_dir.is_dir():
            return []
        models: list[LocalModel] = []
        for repo_dir in sorted(self.cache_dir.glob("models--*")):
            model_id = repo_dir.name.removeprefix("models--").replace("--", "/", 1)
            snapshot = _latest_snapshot(repo_dir)
            if snapshot is None:
                continue
            models.append(
                LocalModel(
                    id=model_id,
                    kind=classify(model_id, snapshot, self.image_repos),
                    size_bytes=_blobs_size(repo_dir / "blobs"),
                    path=str(snapshot),
                    name=model_id.split("/", 1)[-1],
                    source="hub",
                )
            )
        return models

    def delete(self, model_id: str) -> bool:
        """キャッシュから消す。共有の実体の後始末は huggingface_hub に任せる。"""
        from huggingface_hub import scan_cache_dir

        repo_dir = self._repo_dir(model_id)
        if not repo_dir.is_dir():
            return False
        info = scan_cache_dir(self.cache_dir)
        for repo in info.repos:
            if repo.repo_type == "model" and repo.repo_id == model_id:
                hashes = [revision.commit_hash for revision in repo.revisions]
                if hashes:
                    info.delete_revisions(*hashes).execute()
        if repo_dir.exists():
            shutil.rmtree(repo_dir)
        return True

    def plan_download(
        self,
        model_id: str,
        allow_patterns: Sequence[str] | None,
        ignore_patterns: Sequence[str] | None,
    ) -> DownloadPlan:
        from huggingface_hub import HfApi
        from huggingface_hub.errors import (
            GatedRepoError,
            HfHubHTTPError,
            RepositoryNotFoundError,
        )
        from huggingface_hub.utils import filter_repo_objects

        validate_model_id(model_id)
        try:
            info = HfApi().model_info(model_id, files_metadata=True)
        except GatedRepoError as error:
            raise BadRequestError(
                f"このモデルは利用の同意が必要です。Hugging Face で許可を得てください: {model_id}"
            ) from error
        except RepositoryNotFoundError as error:
            raise NotFoundError(f"Hugging Face にモデルが見つかりません: {model_id}") from error
        except HfHubHTTPError as error:
            raise InternalError(f"Hugging Face に接続できませんでした: {error}") from error
        siblings = list(
            filter_repo_objects(
                info.siblings or [],
                allow_patterns=list(allow_patterns) if allow_patterns else None,
                ignore_patterns=list(ignore_patterns) if ignore_patterns else None,
                key=lambda sibling: sibling.rfilename,
            )
        )
        files = tuple(
            RemoteFile(
                filename=sibling.rfilename,
                size=(sibling.lfs.size if sibling.lfs else sibling.size) or 0,
                etag=sibling.lfs.sha256 if sibling.lfs else sibling.blob_id,
            )
            for sibling in siblings
        )
        return DownloadPlan(
            model_id=model_id,
            revision=info.sha,
            files=files,
            allow_patterns=tuple(allow_patterns) if allow_patterns else None,
            ignore_patterns=tuple(ignore_patterns) if ignore_patterns else None,
        )

    def _downloaded_bytes(self, plan: DownloadPlan) -> int:
        blobs = self._repo_dir(plan.model_id) / "blobs"
        if not blobs.is_dir():
            return 0
        total = 0
        for file in plan.files:
            if file.etag is None:
                continue
            sizes = [path.stat().st_size for path in blobs.glob(f"{file.etag}*") if path.is_file()]
            total += min(max(sizes, default=0), file.size)
        return total

    def download(self, plan: DownloadPlan, on_progress: Callable[[int], None]) -> Path:
        """ダウンロードしながら、落とし終えたバイト数を `on_progress` に渡す。

        進み具合は 2 通りで測り、大きいほうを使う。
        - キャッシュにできたファイル（途中のものを含む）の大きさ
        - huggingface_hub の進捗表示（Xet の転送はファイルが最後にまとめて書かれるため）
        """
        from huggingface_hub import snapshot_download  # pyright: ignore[reportUnknownVariableType]

        baseline = self._downloaded_bytes(plan)
        written = _ByteCounter()
        received = _ByteCounter()
        result: list[Path] = []
        failure: list[BaseException] = []

        def run() -> None:
            try:
                path = snapshot_download(
                    plan.model_id,
                    revision=plan.revision,
                    cache_dir=self.cache_dir,
                    allow_patterns=list(plan.allow_patterns) if plan.allow_patterns else None,
                    ignore_patterns=list(plan.ignore_patterns) if plan.ignore_patterns else None,
                    tqdm_class=_progress_class(written, received),
                )
                result.append(Path(str(path)))
            except BaseException as error:
                failure.append(error)

        thread = threading.Thread(target=run, name="hf-download", daemon=True)
        thread.start()
        last = -1
        while thread.is_alive():
            fetched = baseline + max(written.value, received.value)
            downloaded = min(max(self._downloaded_bytes(plan), fetched), plan.total_bytes)
            if downloaded > last:
                on_progress(downloaded)
                last = downloaded
            thread.join(self.poll_interval)
        if failure:
            raise InternalError(f"ダウンロードに失敗しました: {failure[0]}") from failure[0]
        on_progress(plan.total_bytes)
        return result[0]
