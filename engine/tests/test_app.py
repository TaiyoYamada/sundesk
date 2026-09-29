"""HTTP API のテスト。"""

import platform

import pytest
from fastapi.testclient import TestClient

from sundesk_engine import __version__
from sundesk_engine.app import create_app


def test_health_returns_version_and_python() -> None:
    client = TestClient(create_app())

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": __version__,
        "python_version": platform.python_version(),
    }


def test_token_is_required_when_configured() -> None:
    client = TestClient(create_app(token="secret"))

    assert client.get("/health").status_code == 401
    assert client.get("/health", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/health", headers={"Authorization": "Bearer secret"}).status_code == 200


@pytest.mark.parametrize("path", ["/docs", "/redoc"])
def test_interactive_docs_are_disabled(path: str) -> None:
    client = TestClient(create_app())

    assert client.get(path).status_code == 404
