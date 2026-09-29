---
title: Attention
status: 下書き
tags: [機械学習, 線形代数]
---

# Attention

クエリ $Q$、キー $K$、値 $V$ から、重み付きの和を作る。

$$
\mathrm{Attention}(Q, K, V) = \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right) V
$$

## 行列で見る

- $QK^\top$ は、すべてのクエリとキーの[[ベクトル|内積]]を一度に計算した行列
- $\sqrt{d_k}$ で割るのは、内積の分散を 1 に保つため
- softmax は行ごとに確率分布へ変換する

実装: `scripts/attention.py`

## 覗いてみたいこと

- [ ] 層ごと・ヘッドごとの注意の行列をヒートマップで見る
- [ ] logit lens で途中の層の予測を読む

参考: [[論文メモ/Attention Is All You Need]]
