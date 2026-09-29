"""Python のスクラッチ。ノートブックのように、同じセッションの中では変数が残る。

利用者の書いたコードは、MLX 用のワーカースレッドで動かす（ほかの MLX の計算とぶつからないように）。
受け手が接続を切ったら、そのスレッドに非同期の例外を投げ込んで止める。
C の中の長い計算（MLX の eval など）の途中では止まらず、Python に戻ったところで止まる。

名前空間に最初から入れておくもの:

- `model`、`tokenizer`: 要求で `model` を渡したときに載せたもの（実行が終わると外す）
- `mx`、`nn`、`np`、`plt`: `mlx.core`、`mlx.nn`、`numpy`、`matplotlib.pyplot`（画面に出さない Agg）
- `generate(prompt, **kwargs)`: 載せたモデルで生成した文字列を返す
- `show(x)`: 図、表、画像を出力に出す
"""

import ast
import ctypes
import linecache
import threading
import time
import traceback
from collections import OrderedDict
from collections.abc import Callable, Generator
from contextlib import contextmanager
from dataclasses import dataclass, field
from importlib import import_module
from typing import Any

from sundesk_engine.runtime.manager import LoadedLLM
from sundesk_engine.scratch.capture import OutputBuffer, capture_output
from sundesk_engine.streaming import Emit, Event, StreamCancelledError

MAX_SESSIONS = 16
"""覚えておくセッションの数。超えたら、いちばん長く使っていないものから消す"""
CELL_PREFIX = "<scratch-"


class ScratchInterruptError(BaseException):
    """受け手が接続を切ったので、利用者のコードを止める。

    利用者のコードの `except Exception` で握りつぶされないよう、`BaseException` から作る。
    """


class Interrupter:
    """利用者のコードを動かしているスレッドに、非同期の例外を投げ込んで止める係。

    コードを動かしている間（`running` の中）だけ投げ込む。終わったあとのスレッドは
    ほかの処理に使い回されるので、そこへ投げ込まないように、ロックで守る。
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._thread: int | None = None
        self.interrupted = False

    @contextmanager
    def running(self) -> Generator[None]:
        with self._lock:
            if self.interrupted:
                raise ScratchInterruptError
            self._thread = threading.get_ident()
        try:
            yield
        finally:
            with self._lock:
                self._thread = None

    def interrupt(self) -> None:
        with self._lock:
            self.interrupted = True
            if self._thread is not None:
                ctypes.pythonapi.PyThreadState_SetAsyncExc(
                    ctypes.c_ulong(self._thread), ctypes.py_object(ScratchInterruptError)
                )


@dataclass
class ScratchSession:
    namespace: dict[str, Any] = field(default_factory=dict[str, Any])
    send: Callable[[Event], None] | None = None
    """いま動いている実行の出力先。`show` がここに流す"""
    llm: LoadedLLM | None = None
    cells: int = 0


class ScratchSessions:
    """セッションごとの名前空間を持つ。"""

    def __init__(self, limit: int = MAX_SESSIONS) -> None:
        self._limit = limit
        self._lock = threading.Lock()
        self._sessions: OrderedDict[str, ScratchSession] = OrderedDict()

    def session(self, name: str) -> ScratchSession:
        with self._lock:
            session = self._sessions.get(name)
            if session is None:
                session = ScratchSession()
                _install_builtins(session)
                self._sessions[name] = session
                while len(self._sessions) > self._limit:
                    self._sessions.popitem(last=False)
            self._sessions.move_to_end(name)
            return session

    def reset(self, name: str) -> bool:
        with self._lock:
            return self._sessions.pop(name, None) is not None

    def __contains__(self, name: object) -> bool:
        with self._lock:
            return name in self._sessions


# MARK: - 名前空間


def _pyplot() -> Any:
    """画面に出さない描き方（Agg）で matplotlib.pyplot を読み込む。"""
    import matplotlib

    matplotlib.use("Agg", force=True)
    import matplotlib.pyplot as plt

    return plt


def _install_builtins(session: ScratchSession) -> None:
    import mlx.core as mx
    import numpy as np

    nn: Any = import_module("mlx.nn")

    def show(value: object) -> None:
        """図（matplotlib）、表（dict の list か 2 次元の配列）、画像を出力に出す。"""
        from matplotlib.figure import Figure

        from sundesk_engine.scratch.display import to_events

        send = session.send
        if send is None:
            raise RuntimeError("show() は実行の中でだけ使えます")
        for event in to_events(value):
            send(event)
        if isinstance(value, Figure):
            _pyplot().close(value)

    def generate(
        prompt: str,
        max_tokens: int = 128,
        temperature: float = 0.0,
        top_p: float = 1.0,
        top_k: int = 0,
        seed: int | None = None,
        chat_template: bool = False,
    ) -> str:
        """載せたモデルで、`prompt` の続きを生成して返す。"""
        from sundesk_engine.lab.generation import generate_text
        from sundesk_engine.lab.sampling import SamplingOptions
        from sundesk_engine.lab.tokens import encode_prompt

        llm = session.llm
        if llm is None:
            raise RuntimeError("モデルが載っていません。model を指定して実行してください")
        ids = encode_prompt(llm.tokenizer, prompt, chat_template, limit=None)
        return generate_text(
            llm.model,
            llm.tokenizer,
            ids,
            max_tokens=max_tokens,
            options=SamplingOptions(temperature=temperature, top_p=top_p, top_k=top_k),
            seed=seed if seed is not None else time.time_ns() % (2**32),
        )

    session.namespace.update(
        {
            "__name__": "__scratch__",
            "mx": mx,
            "nn": nn,
            "np": np,
            "plt": _pyplot(),
            "show": show,
            "generate": generate,
            "model": None,
            "tokenizer": None,
        }
    )


# MARK: - 実行


def execute(code: str, namespace: dict[str, Any], filename: str) -> object:
    """コードを実行し、最後の文が式ならその値を返す（そうでなければ None）。"""
    tree = ast.parse(code, filename, "exec")
    last: ast.Expression | None = None
    if tree.body and isinstance(tree.body[-1], ast.Expr):
        expression = tree.body.pop()
        assert isinstance(expression, ast.Expr)  # noqa: S101 - 直前で確かめた
        last = ast.Expression(expression.value)
    # 例外の表示で、利用者のコードの行を見せられるようにする
    linecache.cache[filename] = (len(code), None, code.splitlines(keepends=True), filename)
    exec(compile(tree, filename, "exec"), namespace)  # noqa: S102 - 手元の利用者が書いたコードを動かすための機能
    if last is None:
        return None
    return eval(compile(last, filename, "eval"), namespace)  # noqa: S307 - 同上


def describe_error(error: BaseException) -> Event:
    """例外を `error` の行にする。トレースバックは、利用者のコードの部分から見せる。"""
    summary = traceback.TracebackException.from_exception(error)
    frames = list(summary.stack)
    first = next(
        (index for index, frame in enumerate(frames) if frame.filename.startswith(CELL_PREFIX)),
        None,
    )
    summary.stack = traceback.StackSummary.from_list(frames[first:] if first is not None else [])
    text = str(error)
    message = f"{type(error).__name__}: {text}" if text else type(error).__name__
    return {"type": "error", "message": message, "traceback": "".join(summary.format())}


def run_cell(
    session: ScratchSession,
    code: str,
    llm: LoadedLLM | None,
    emit: Emit,
    interrupter: Interrupter,
) -> None:
    """コードを 1 回動かし、出力を行にして流す。最後に `done` か `error` を流す。"""
    from matplotlib.figure import Figure

    from sundesk_engine.scratch.display import figure_event, value_event

    plt = _pyplot()
    started = time.perf_counter()
    output = OutputBuffer(emit)

    def send(event: Event) -> None:
        output.flush()
        emit(event)

    session.cells += 1
    filename = f"{CELL_PREFIX}{session.cells}>"
    session.send = send
    session.llm = llm
    session.namespace["model"] = llm.model if llm else None
    session.namespace["tokenizer"] = llm.tokenizer if llm else None
    failure: BaseException | None = None
    value: object = None
    try:
        with capture_output(output.write), interrupter.running():
            value = execute(code, session.namespace, filename)
    except ScratchInterruptError as error:
        raise StreamCancelledError from error
    except StreamCancelledError:
        raise
    except BaseException as error:
        failure = error
    finally:
        session.send = None
        session.llm = None
        # 載せたモデルを持ち続けないように外す（次の実行でまた渡す）
        session.namespace["model"] = None
        session.namespace["tokenizer"] = None

    output.flush()
    # 開いたままの図は、画像にして閉じる
    for number in plt.get_fignums():
        emit(figure_event(plt.figure(number)))
    plt.close("all")
    if failure is not None:
        emit(describe_error(failure))
        return
    if value is not None and not isinstance(value, Figure):
        try:
            emit(value_event(value))
        except Exception as error:
            emit(describe_error(error))
            return
    emit({"type": "done", "seconds": round(time.perf_counter() - started, 3)})
