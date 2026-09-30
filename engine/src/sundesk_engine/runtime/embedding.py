"""sentence-transformers による埋め込み。torch の読み込みは重いので、使うときまで遅らせる。"""

from collections.abc import Sequence
from pathlib import Path
from typing import Any

import numpy as np
from numpy.typing import NDArray

from sundesk_engine.runtime.manager import Embedder

# ruri-v3 の決まり。前に付ける文字列で、埋め込みの使い道を伝える
QUERY_PREFIX = "検索クエリ: "
DOCUMENT_PREFIX = "検索文書: "
TOPIC_PREFIX = "トピック: "
"""概念の名前どうしの近さを測るときに使う"""


class SentenceTransformerEmbedder:
    def __init__(self, model: Any) -> None:
        self._model = model

    @property
    def dimension(self) -> int:
        return int(self._model.get_embedding_dimension())

    def encode(self, texts: Sequence[str]) -> NDArray[np.float32]:
        if not texts:
            return np.zeros((0, self.dimension), dtype=np.float32)
        vectors = self._model.encode(
            list(texts),
            batch_size=32,
            convert_to_numpy=True,
            normalize_embeddings=True,
            show_progress_bar=False,
        )
        return np.asarray(vectors, dtype=np.float32)


class SentenceTransformerBackend:
    def load(self, path: Path) -> Embedder:
        import torch
        from sentence_transformers import SentenceTransformer

        device = "mps" if torch.backends.mps.is_available() else "cpu"
        model = SentenceTransformer(str(path), device=device, local_files_only=True)
        return SentenceTransformerEmbedder(model)
