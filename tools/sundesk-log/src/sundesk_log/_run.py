"""実行の記録（`Run`）と、収束などの曲線（`Trace`）。

書く形は docs/library-format.md の「取り込み箱」に従う。
"""

from __future__ import annotations

import json
import math
import numbers
import os
import re
import secrets
import shutil
from collections.abc import Mapping, Sequence
from datetime import datetime
from pathlib import Path
from types import TracebackType
from typing import Any, Literal, Protocol, TypeAlias

INBOX_ENV = "SUNDESK_INBOX"
"""取り込み箱の場所を変える環境変数の名前。"""

Scalar: TypeAlias = "str | int | float | bool"
Direction: TypeAlias = Literal["minimize", "maximize"]

# figures/ に入れるファイルの拡張子。ほかは results/ に入れる
FIGURE_SUFFIXES = frozenset(
    {".png", ".jpg", ".jpeg", ".gif", ".svg", ".pdf", ".webp", ".tif", ".tiff", ".heic"}
)
_NAME = re.compile(r"^[A-Za-z0-9_.-]+$")


class SavesFigure(Protocol):
    """`savefig` を持つもの（matplotlib の Figure など）。"""

    def savefig(self, fname: Any, /, **kwargs: Any) -> Any: ...


def default_inbox() -> Path:
    """取り込み箱の場所。環境変数 `SUNDESK_INBOX` があればそれを使う。"""
    value = os.environ.get(INBOX_ENV)
    if value:
        return Path(value).expanduser()
    return Path.home() / "Library/Application Support/com.taiyou.sundesk/Library/Inbox"


def _now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _number(name: str, value: object) -> int | float:
    """数だけを通す。真偽は 0 と 1 にする。numpy の数も受け取る。"""
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, numbers.Integral):
        return int(value)
    if isinstance(value, numbers.Real):
        return float(value)
    raise TypeError(f"{name} には数を渡す（{type(value).__name__} が渡された）")


def _finite(name: str, value: object) -> int | float:
    number = _number(name, value)
    if isinstance(number, float) and not math.isfinite(number):
        raise ValueError(f"{name} は有限の数にする（JSON に書けない）: {number}")
    return number


def _scalar(name: str, value: object) -> Scalar:
    """パラメータの値。文字、数、真偽のどれか。入れ子は受け付けない。"""
    if isinstance(value, (str, bool)):
        return value
    if isinstance(value, numbers.Real):
        return _finite(name, value)
    raise TypeError(
        f"パラメータ {name} の値は文字、数、真偽のどれかにする（{type(value).__name__} が渡された）"
    )


def _cell(value: int | float | None) -> str:
    if value is None:
        return ""
    return repr(value)


def _write_text(path: Path, text: str) -> None:
    """途中で止まっても半端なファイルが残らないように、別名で書いてから置き換える。"""
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


class Trace:
    """`results/<名前>.csv` に 1 行ずつ書く曲線。

    最初に渡した列が横軸（x）になる。新しい列が出てきたら、見出しを増やして書き直す。
    """

    def __init__(self, path: Path, *, x: str | None = None, y: Sequence[str] | None = None) -> None:
        self.path = path
        self._x = x
        self._y = list(y) if y is not None else None
        self._columns: list[str] = [x] if x is not None else []
        self._rows: list[dict[str, int | float | None]] = []

    @property
    def columns(self) -> list[str]:
        return list(self._columns)

    @property
    def x(self) -> str | None:
        return self._x if self._x is not None else (self._columns[0] if self._columns else None)

    @property
    def y(self) -> list[str]:
        if self._y is not None:
            return list(self._y)
        return [column for column in self._columns if column != self.x]

    def __len__(self) -> int:
        return len(self._rows)

    def log(self, **values: float | None) -> None:
        """1 行を足す。値は数か None（空欄）。"""
        if not values:
            raise ValueError("列を 1 つ以上渡す")
        row = {
            name: None if value is None else _number(name, value) for name, value in values.items()
        }
        new_columns = [name for name in row if name not in self._columns]
        self._rows.append(row)
        if new_columns or len(self._rows) == 1:
            self._columns.extend(new_columns)
            self._rewrite()
        else:
            with self.path.open("a", encoding="utf-8", newline="") as file:
                file.write(self._line(row))
                file.flush()

    def _line(self, row: Mapping[str, int | float | None]) -> str:
        return ",".join(_cell(row.get(column)) for column in self._columns) + "\n"

    def _rewrite(self) -> None:
        text = ",".join(self._columns) + "\n" + "".join(self._line(row) for row in self._rows)
        _write_text(self.path, text)

    def series(self, root: Path) -> dict[str, Any]:
        return {"file": self.path.relative_to(root).as_posix(), "x": self.x, "y": self.y}


class Run:
    """1 回の実行。取り込み箱に `<実行の ID>/` を作って書く。

    `with` で使うと、抜けるときに `done`（例外なら `failed`）にして `.complete` を置く。
    例外はそのまま外へ投げ直す。
    """

    def __init__(
        self,
        title: str,
        *,
        algorithm: str,
        problem: str,
        parameters: Mapping[str, object] | None = None,
        seed: int | Sequence[int] | None = None,
        tags: Sequence[str] = (),
        objective: str | None = None,
        direction: Direction = "minimize",
        reference: float | None = None,
        links: Sequence[str] = (),
        inbox: str | os.PathLike[str] | None = None,
    ) -> None:
        if not title.strip():
            raise ValueError("題名を空にしない")
        if direction not in ("minimize", "maximize"):
            raise ValueError(f"direction は minimize か maximize にする: {direction}")
        if objective is None and reference is not None:
            raise ValueError("reference を渡すときは objective（目的関数の名前）も渡す")

        self.title = title
        self._data: dict[str, Any] = {
            "title": title,
            "algorithm": algorithm,
            "problem": problem,
            "status": "running",
            "created": _now(),
            "tags": list(tags),
            "parameters": {
                name: _scalar(name, value) for name, value in (parameters or {}).items()
            },
        }
        if isinstance(seed, Sequence):
            self._data["seeds"] = [int(value) for value in seed]
        elif seed is not None:
            self._data["seed"] = int(seed)
        if objective is not None:
            target: dict[str, Any] = {"name": objective, "direction": direction}
            if reference is not None:
                target["reference"] = _finite("reference", reference)
            self._data["objective"] = target
        self._data["metrics"] = {}
        self._attachments: list[str] = []
        self._links: list[str] = list(dict.fromkeys(links))
        self._traces: dict[str, Trace] = {}
        self._note: list[str] = []

        self.dir = self._make_dir(Path(inbox).expanduser() if inbox else default_inbox())
        (self.dir / "results").mkdir()
        (self.dir / "figures").mkdir()
        self._save()

    @staticmethod
    def _make_dir(inbox: Path) -> Path:
        inbox.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        while True:
            path = inbox / f"{stamp}-{secrets.token_hex(3)}"
            try:
                path.mkdir()
            except FileExistsError:
                continue
            return path

    # MARK: - 状態

    @property
    def id(self) -> str:
        """実行の ID（取り込み箱の中のフォルダ名）。"""
        return self.dir.name

    @property
    def status(self) -> str:
        return str(self._data["status"])

    @property
    def finished(self) -> bool:
        return self.status in ("done", "failed")

    def _check_open(self) -> None:
        if self.finished:
            raise RuntimeError(f"この実行はもう終わっている（{self.status}）")

    # MARK: - 記録

    def trace(
        self, name: str = "trace", *, x: str | None = None, y: Sequence[str] | None = None
    ) -> Trace:
        """`results/<name>.csv` の曲線を返す。はじめて呼んだときに作る。

        `x` と `y` を省くと、最初の列が横軸、残りの列がすべて縦軸になる。
        """
        self._check_open()
        if not _NAME.match(name):
            raise ValueError(f"曲線の名前には英数字、-、_、. だけを使う: {name}")
        trace = self._traces.get(name)
        if trace is None:
            trace = Trace(self.dir / "results" / f"{name}.csv", x=x, y=y)
            self._traces[name] = trace
        return trace

    def log(self, **values: float | None) -> None:
        """`results/trace.csv` に 1 行を足す。最初の列が横軸になる。"""
        self.trace().log(**values)

    def metrics(self, **values: float) -> None:
        """結果の要約を足す（同じ名前は上書き）。数だけを受け付ける。"""
        self._check_open()
        for name, value in values.items():
            self._data["metrics"][name] = _finite(name, value)
        self._save()

    def attach(self, path: str | os.PathLike[str], name: str | None = None) -> Path:
        """ファイルを写す。図は figures/、ほかは results/ に入れる。写した先を返す。"""
        self._check_open()
        source = Path(path)
        if not source.is_file():
            raise FileNotFoundError(source)
        target_name = name or source.name
        folder = "figures" if Path(target_name).suffix.lower() in FIGURE_SUFFIXES else "results"
        target = self.dir / folder / target_name
        if source.resolve() != target.resolve():
            shutil.copyfile(source, target)
        self._add_attachment(target)
        return target

    def figure(self, figure: SavesFigure, name: str = "figure.png", **kwargs: Any) -> Path:
        """matplotlib の図などを figures/ に保存する。`kwargs` は `savefig` に渡す。"""
        self._check_open()
        target = self.dir / "figures" / name
        figure.savefig(target, **kwargs)
        self._add_attachment(target)
        return target

    def _add_attachment(self, target: Path) -> None:
        relative = target.relative_to(self.dir).as_posix()
        if relative not in self._attachments:
            self._attachments.append(relative)
        self._save()

    def link(self, *paths: str) -> None:
        """関係する論文やデータ（ライブラリのルートからの相対パス）を足す。"""
        self._check_open()
        for path in paths:
            if path not in self._links:
                self._links.append(path)
        self._save()

    def note(self, text: str) -> None:
        """note.md の本文に文章を足す。アプリは note.md があればそれを使う。"""
        self._check_open()
        self._note.append(text.strip("\n"))
        self._write_note()

    def _write_note(self) -> None:
        header = (
            f"---\ntype: experiment\ntitle: {json.dumps(self.title, ensure_ascii=False)}\n---\n"
        )
        body = "\n\n".join([f"# {self.title}", *self._note])
        _write_text(self.dir / "note.md", header + body + "\n")

    # MARK: - 終わり

    def finish(self) -> None:
        """`done` にして `.complete` を置く。"""
        self._close("done")

    def fail(self, error: BaseException | None = None) -> None:
        """`failed` にして `.complete` を置く。`error` を渡すと note.md に残す。"""
        if error is not None and not self.finished:
            detail = str(error)
            message = f"{type(error).__name__}: {detail}" if detail else type(error).__name__
            self._note.append(f"## エラー\n\n```\n{message}\n```")
            self._write_note()
        self._close("failed")

    def _close(self, status: str) -> None:
        self._check_open()
        for trace in self._traces.values():
            if not trace.columns:
                continue
            # 行がまだない曲線でも、見出しだけの CSV を残す
            if len(trace) == 0:
                _write_text(trace.path, ",".join(trace.columns) + "\n")
        self._data["status"] = status
        self._data["finished"] = _now()
        self._save()
        # .complete は最後に置く。アプリはこれを見て取り込む
        (self.dir / ".complete").touch()

    def __enter__(self) -> Run:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        if self.finished:
            return
        if exc is None:
            self.finish()
        else:
            self.fail(exc)

    # MARK: - run.json

    def to_dict(self) -> dict[str, Any]:
        """run.json に書く中身。"""
        data = dict(self._data)
        keys = ["title", "algorithm", "problem", "status", "created", "finished", "tags"]
        ordered = {key: data.pop(key) for key in keys if key in data}
        ordered.update(
            {
                "parameters": data.pop("parameters"),
                **{key: data.pop(key) for key in ("seed", "seeds", "objective") if key in data},
                "metrics": dict(data.pop("metrics")),
                "series": [
                    trace.series(self.dir) for trace in self._traces.values() if trace.columns
                ],
                "attachments": list(self._attachments),
                "links": list(self._links),
            }
        )
        return ordered

    def _save(self) -> None:
        text = json.dumps(self.to_dict(), ensure_ascii=False, indent=2, allow_nan=False)
        _write_text(self.dir / "run.json", text + "\n")
