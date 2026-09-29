"""`sundesk-engine` コマンドの入口。"""

import argparse
import os
from collections.abc import Sequence

import uvicorn

from sundesk_engine.app import TOKEN_ENV, create_app
from sundesk_engine.parent_watch import parent_pid_from_env, watch_parent

DEFAULT_PORT = 8765


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="sundesk-engine", description="sundesk の AI エンジン")
    parser.add_argument("--host", default="127.0.0.1", help="待ち受けるアドレス（既定: 127.0.0.1）")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="待ち受けるポート")
    parser.add_argument(
        "--log-level",
        default="info",
        choices=["critical", "error", "warning", "info", "debug"],
        help="ログの詳しさ",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> None:
    args = parse_args(argv)
    app = create_app(token=os.environ.get(TOKEN_ENV))
    if (parent_pid := parent_pid_from_env()) is not None:
        watch_parent(parent_pid)
    # SIGTERM を受けると、uvicorn が処理中のリクエストを終えてから止まる
    uvicorn.run(app, host=args.host, port=args.port, log_level=args.log_level)


if __name__ == "__main__":
    main()
