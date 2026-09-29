"""コマンドライン引数のテスト。"""

import pytest

from sundesk_engine.cli import DEFAULT_PORT, parse_args


def test_defaults_listen_on_loopback() -> None:
    args = parse_args([])

    assert args.host == "127.0.0.1"
    assert args.port == DEFAULT_PORT
    assert args.log_level == "info"


def test_port_and_host_can_be_overridden() -> None:
    args = parse_args(["--host", "0.0.0.0", "--port", "9000"])  # noqa: S104

    assert args.host == "0.0.0.0"  # noqa: S104
    assert args.port == 9000


def test_rejects_unknown_log_level() -> None:
    with pytest.raises(SystemExit):
        parse_args(["--log-level", "verbose"])
