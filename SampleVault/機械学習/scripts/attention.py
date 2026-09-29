"""Scaled dot-product attention を NumPy だけで書いたもの。"""

import numpy as np


def softmax(x: np.ndarray, axis: int = -1) -> np.ndarray:
    x = x - x.max(axis=axis, keepdims=True)
    e = np.exp(x)
    return e / e.sum(axis=axis, keepdims=True)


def attention(q: np.ndarray, k: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    d_k = q.shape[-1]
    weights = softmax(q @ k.T / np.sqrt(d_k))
    return weights @ v, weights


if __name__ == "__main__":
    rng = np.random.default_rng(0)
    q, k, v = (rng.normal(size=(4, 8)) for _ in range(3))
    out, w = attention(q, k, v)
    print(w.round(2))
