"""親プロセスの見張りのテスト。"""

import os
import subprocess
import sys

import pytest

from sundesk_engine.parent_watch import PARENT_PID_ENV, is_alive, parent_pid_from_env


def test_current_process_is_alive() -> None:
    assert is_alive(os.getpid())


def test_finished_process_is_not_alive() -> None:
    child = subprocess.Popen([sys.executable, "-c", "pass"])
    child.wait()

    assert not is_alive(child.pid)


@pytest.mark.parametrize(
    ("value", "expected"),
    [("1234", 1234), ("", None), ("abc", None), (None, None)],
)
def test_parent_pid_from_env(
    monkeypatch: pytest.MonkeyPatch, value: str | None, expected: int | None
) -> None:
    if value is None:
        monkeypatch.delenv(PARENT_PID_ENV, raising=False)
    else:
        monkeypatch.setenv(PARENT_PID_ENV, value)

    assert parent_pid_from_env() == expected


def test_process_exits_when_parent_disappears() -> None:
    """見張っている親が消えると、子は SIGTERM で終了する。"""
    parent = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(0.3)"])
    code = (
        "import time\n"
        "from sundesk_engine.parent_watch import watch_parent\n"
        f"watch_parent({parent.pid}, interval=0.1)\n"
        "time.sleep(10)\n"
    )
    watcher = subprocess.Popen([sys.executable, "-c", code])  # noqa: S603
    parent.wait()

    assert watcher.wait(timeout=5) != 0
