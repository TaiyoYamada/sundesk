"""スクラッチの実行中に `print` などで書かれた文字を受け取る。

`sys.stdout` と `sys.stderr` はプロセス全体で 1 つなので、そのまま差し替えると、
ほかのスレッド（サーバーのログなど）の出力まで拾ってしまう。
そこで、書いたスレッドを見て振り分ける代わりの出力先を置く。
"""

import sys
import threading
from collections.abc import Callable, Generator
from contextlib import contextmanager
from typing import Any, Literal, TextIO

type StreamName = Literal["stdout", "stderr"]
type Sink = Callable[[StreamName, str], None]
"""書かれた文字を受け取る。文字が空なら、たまっている分を流せという合図（`flush()`）"""

_local = threading.local()


class _ThreadRouter:
    """いまのスレッドに受け手がいればそこへ、いなければもとの出力先へ書く。"""

    def __init__(self, name: StreamName, original: TextIO) -> None:
        self.name: StreamName = name
        self.original = original

    def write(self, text: str) -> int:
        sink: Sink | None = getattr(_local, "sink", None)
        if sink is None:
            return self.original.write(text)
        sink(self.name, text)
        return len(text)

    def flush(self) -> None:
        sink: Sink | None = getattr(_local, "sink", None)
        if sink is None:
            self.original.flush()
        else:
            sink(self.name, "")

    def isatty(self) -> bool:
        return False

    def __getattr__(self, name: str) -> Any:
        return getattr(self.original, name)


@contextmanager
def capture_output(sink: Sink) -> Generator[None]:
    """`with` の中で、このスレッドが書いた文字を `sink(名前, 文字)` に渡す。"""
    routers: list[_ThreadRouter] = []
    for name in ("stdout", "stderr"):
        current: Any = getattr(sys, name)
        if not isinstance(current, _ThreadRouter):
            router = _ThreadRouter(name, current)
            setattr(sys, name, router)
            routers.append(router)
    previous: Sink | None = getattr(_local, "sink", None)
    _local.sink = sink
    try:
        yield
    finally:
        _local.sink = previous
        for router in routers:
            # ほかの誰かが差し替えていなければ、もとに戻す
            if getattr(sys, router.name) is router:
                setattr(sys, router.name, router.original)


class OutputBuffer:
    """書かれた文字を、行の区切りでまとめてから流す。

    `print` は本文と改行を別々に書くので、1 回ずつ流すと行が細切れになる。
    stdout と stderr が入れ替わるときと、図や表を流す前には、たまっている分を先に流す。
    """

    LIMIT = 8192

    def __init__(self, emit: Callable[[dict[str, Any]], None]) -> None:
        self._emit = emit
        self._name: StreamName | None = None
        self._pending: list[str] = []
        self._size = 0

    def write(self, name: StreamName, text: str) -> None:
        if not text:
            # `print(..., flush=True)` などで、利用者が流すように頼んだ
            if name == self._name:
                self.flush()
            return
        if self._name is not None and self._name != name:
            self.flush()
        self._name = name
        self._pending.append(text)
        self._size += len(text)
        if self._size >= self.LIMIT:
            self.flush()
        elif "\n" in text:
            joined = "".join(self._pending)
            cut = joined.rindex("\n") + 1
            self._send(name, joined[:cut])
            rest = joined[cut:]
            self._pending = [rest] if rest else []
            self._size = len(rest)

    def flush(self) -> None:
        if self._name is not None and self._pending:
            self._send(self._name, "".join(self._pending))
        self._pending = []
        self._size = 0

    def _send(self, name: StreamName, text: str) -> None:
        if text:
            self._emit({"type": name, "text": text})
