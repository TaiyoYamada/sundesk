"""テストの共通の準備。"""

from collections.abc import Generator
from pathlib import Path

import mlx.core as mx
import pytest
from fakes import FakeHub, FakeImageBackend, FakeLLMBackend, make_engine
from fastapi.testclient import TestClient

from sundesk_engine.app import create_app
from sundesk_engine.engine import Engine

# GPU のない環境（CI の仮想マシンなど）でも同じ結果になるように、CPU で計算する
mx.set_default_device(mx.cpu)


class Harness:
    """偽物の部品で組んだエンジンと、それにつないだクライアント。"""

    engine: Engine
    hub: FakeHub
    llm: FakeLLMBackend
    image: FakeImageBackend

    def __init__(self, tmp_path: Path) -> None:
        self.engine, self.hub, self.llm, self.image = make_engine(tmp_path / "models")
        self.tmp_path = tmp_path
        self.client = TestClient(create_app(engine=self.engine))


@pytest.fixture
def harness(tmp_path: Path) -> Generator[Harness]:
    harness = Harness(tmp_path)
    yield harness
    harness.engine.shutdown()


@pytest.fixture
def engine(harness: Harness) -> Engine:
    return harness.engine


@pytest.fixture
def client(harness: Harness) -> TestClient:
    return harness.client
