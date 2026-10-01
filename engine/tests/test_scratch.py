"""Python のスクラッチのテスト。"""

import asyncio
import base64
import sys
import threading
import time
from typing import Any

import pytest
from conftest import Harness
from fakes import LLM_ID, NUM_LAYERS, ndjson
from fastapi.testclient import TestClient

from sundesk_engine.scratch.capture import OutputBuffer, capture_output

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def run(
    client: TestClient, code: str, session: str = "s1", **fields: object
) -> list[dict[str, Any]]:
    return ndjson(client.post("/scratch/run", json={"session": session, "code": code} | fields))


def test_variables_persist_within_a_session(client: TestClient) -> None:
    first = run(client, "x = 20\ny = x + 1")
    second = run(client, "x + y")
    other = run(client, "x", session="s2")

    assert first == [first[0]]
    assert first[0]["type"] == "done"
    assert isinstance(first[0]["seconds"], float)
    assert second[0] == {"type": "value", "repr": "41"}
    assert second[-1]["type"] == "done"
    assert other[0]["type"] == "error"
    assert other[0]["message"] == "NameError: name 'x' is not defined"


def test_stdout_and_stderr(client: TestClient) -> None:
    events = run(
        client,
        "import sys\nprint('こんにちは')\nprint(1, 2)\nprint('警告', file=sys.stderr)\n"
        "print('途中', end='')\nNone",
    )

    assert events == [
        {"type": "stdout", "text": "こんにちは\n"},
        {"type": "stdout", "text": "1 2\n"},
        {"type": "stderr", "text": "警告\n"},
        {"type": "stdout", "text": "途中"},
        events[-1],
    ]
    assert events[-1]["type"] == "done"


def test_flush_sends_partial_lines(client: TestClient) -> None:
    events = run(client, "print('読み込み中', end='', flush=True)\nprint('…完了')")

    assert events[:2] == [
        {"type": "stdout", "text": "読み込み中"},
        {"type": "stdout", "text": "…完了\n"},
    ]


def test_last_expression_value(client: TestClient) -> None:
    events = run(client, "for i in range(3):\n    pass\n{'a': [1, 2]}")

    assert events[0] == {"type": "value", "repr": "{'a': [1, 2]}"}


def test_errors_have_a_traceback(client: TestClient) -> None:
    events = run(client, "def f():\n    return 1 / 0\n\nprint('前')\nf()")

    assert events[0] == {"type": "stdout", "text": "前\n"}
    error = events[-1]
    assert error["type"] == "error"
    assert error["message"] == "ZeroDivisionError: division by zero"
    assert "<scratch-" in error["traceback"]
    assert "return 1 / 0" in error["traceback"]
    assert "sundesk_engine" not in error["traceback"]


def test_syntax_errors(client: TestClient) -> None:
    events = run(client, "x = (")

    assert events[-1]["type"] == "error"
    assert events[-1]["message"].startswith("SyntaxError")


def test_plots_become_images(client: TestClient) -> None:
    code = (
        "fig, ax = plt.subplots()\nax.plot([1, 2, 3])\nshow(fig)\n"
        "plt.figure()\nplt.bar(['a', 'b'], [1, 2])\nprint('描いた')"
    )

    events = run(client, code)

    types = [event["type"] for event in events]
    assert types == ["image", "stdout", "image", "done"]
    for event in (events[0], events[2]):
        assert base64.b64decode(event["png_base64"]).startswith(PNG_SIGNATURE)
    # 図は閉じてあるので、次の実行には残らない
    assert run(client, "len(plt.get_fignums())")[0] == {"type": "value", "repr": "0"}


def test_tables(client: TestClient) -> None:
    events = run(
        client,
        "show([{'層': 0, 'ノルム': 1.25}, {'層': 1, 'ノルム': float('nan')}])\n"
        "show(np.array([[1, 2], [3, 4]]))\nshow(mx.arange(3))",
    )

    assert events[0] == {
        "type": "table",
        "columns": ["層", "ノルム"],
        "rows": [[0, 1.25], [1, None]],
    }
    assert events[1] == {"type": "table", "columns": ["0", "1"], "rows": [[1, 2], [3, 4]]}
    assert events[2] == {"type": "table", "columns": ["値"], "rows": [[0], [1], [2]]}


def test_show_images_from_arrays(client: TestClient) -> None:
    events = run(client, "show(np.zeros((4, 5, 3), dtype=np.uint8))\nshow(object())")

    assert events[0]["type"] == "image"
    assert events[1]["type"] == "error"
    assert events[1]["message"].startswith("TypeError: show()")


def test_model_and_generate(harness: Harness) -> None:
    client = harness.client

    events = run(
        client,
        "text = generate('固有値', max_tokens=4)\n"
        "print(type(text).__name__)\n"
        "model.args.num_hidden_layers",
        model=LLM_ID,
    )

    assert events[0] == {"type": "stdout", "text": "str\n"}
    assert events[1] == {"type": "value", "repr": str(NUM_LAYERS)}
    assert harness.engine.models.loaded()["llm"] == LLM_ID
    # 次の実行で model を渡さなければ、model は空
    assert run(client, "model is None")[0] == {"type": "value", "repr": "True"}
    assert run(client, "generate('a')")[-1]["message"].startswith("RuntimeError")


def test_scratch_rejects_missing_models(client: TestClient) -> None:
    missing = client.post("/scratch/run", json={"session": "s", "code": "1", "model": "test/no"})
    adapter_only = client.post(
        "/scratch/run", json={"session": "s", "code": "1", "adapter": "/nowhere/adapter"}
    )

    assert missing.status_code == 404
    assert adapter_only.status_code == 400


def test_reset_forgets_variables(client: TestClient) -> None:
    run(client, "secret = 42")

    response = client.post("/scratch/reset", json={"session": "s1"})

    assert response.json() == {"reset": True}
    assert run(client, "secret")[-1]["message"] == "NameError: name 'secret' is not defined"
    assert client.post("/scratch/reset", json={"session": "unknown"}).json() == {"reset": True}


def test_output_of_other_threads_is_not_captured(capsys: pytest.CaptureFixture[str]) -> None:
    captured: list[tuple[str, str]] = []

    def elsewhere() -> None:
        print("ほかのスレッド")

    with capture_output(lambda name, text: captured.append((name, text))):
        print("ここ")
        thread = threading.Thread(target=elsewhere)
        thread.start()
        thread.join()
        sys.stderr.write("エラー\n")

    assert captured == [("stdout", "ここ"), ("stdout", "\n"), ("stderr", "エラー\n")]
    del captured[:]
    with capture_output(lambda name, text: captured.append((name, text))):
        print("途中", end="", flush=True)
    # print は空の end も書く。flush は空の文字で伝わる
    assert captured[0] == ("stdout", "途中")
    assert captured[-1] == ("stdout", "")
    assert "ほかのスレッド" in capsys.readouterr().out
    assert not type(sys.stdout).__name__.startswith("_ThreadRouter")


def test_output_buffer_joins_lines() -> None:
    events: list[dict[str, Any]] = []
    buffer = OutputBuffer(events.append)

    buffer.write("stdout", "a")
    buffer.write("stdout", "b\nc")
    buffer.write("stderr", "!")
    buffer.write("stdout", "")
    buffer.write("stderr", "")
    buffer.write("stdout", "x" * (OutputBuffer.LIMIT + 1))
    buffer.flush()

    assert events == [
        {"type": "stdout", "text": "ab\n"},
        {"type": "stdout", "text": "c"},
        {"type": "stderr", "text": "!"},
        {"type": "stdout", "text": "x" * (OutputBuffer.LIMIT + 1)},
    ]


def test_running_code_stops_when_the_client_leaves(harness: Harness) -> None:
    from sundesk_engine.api.scratch import RunRequest, post_run

    engine = harness.engine
    code = "print('始めた', flush=True)\ncount = 0\nwhile True:\n    count += 1"

    async def start_and_leave() -> None:
        response = await post_run(RunRequest(session="loop", code=code), engine)
        iterator: Any = response.body_iterator
        first = await anext(iterator)
        assert b"\\u59cb" in first or "始めた".encode() in first
        await iterator.aclose()

    asyncio.run(start_and_leave())

    # 止まれば、MLX のスレッドはほかの仕事を受けられる
    started = time.perf_counter()
    assert engine.mlx_executor.submit(lambda: "空いた").result(timeout=5) == "空いた"
    assert time.perf_counter() - started < 5
    # 止めるまでに動いた分の変数は残る
    events = run(harness.client, "count > 0", session="loop")
    assert events[0] == {"type": "value", "repr": "True"}
