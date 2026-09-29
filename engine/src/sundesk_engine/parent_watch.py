"""親プロセス（sundesk アプリ）が消えたら、エンジンも終了する。

アプリが強制終了やクラッシュで終わると、終了処理でエンジンを止められない。
そのままではエンジンが取り残されるので、エンジン側でも親の生存を確かめる。
"""

import os
import signal
import threading

PARENT_PID_ENV = "SUNDESK_PARENT_PID"


def is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # 存在はしているが、シグナルを送る権限がない
        return True
    return True


def watch_parent(pid: int, interval: float = 1.0) -> threading.Thread:
    """`pid` のプロセスが消えたら、自分に SIGTERM を送る別スレッドを始める。

    SIGTERM を受けた uvicorn は、処理中のリクエストを終えてから止まる。
    """

    def run() -> None:
        stop = threading.Event()
        while not stop.wait(interval):
            if not is_alive(pid):
                os.kill(os.getpid(), signal.SIGTERM)
                return

    thread = threading.Thread(target=run, name="parent-watch", daemon=True)
    thread.start()
    return thread


def parent_pid_from_env() -> int | None:
    value = os.environ.get(PARENT_PID_ENV)
    if value is None or not value.isdigit():
        return None
    return int(value)
