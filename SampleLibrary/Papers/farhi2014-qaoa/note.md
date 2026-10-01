---
type: paper
title: "A Quantum Approximate Optimization Algorithm"
authors: [Edward Farhi, Jeffrey Goldstone, Sam Gutmann]
year: 2014
arxiv: "1411.4028"
url: "https://arxiv.org/abs/1411.4028"
status: 未読
tags: [QAOA, 組合せ最適化, Max-Cut]
added: 2026-09-20
---
# A Quantum Approximate Optimization Algorithm

## 要点

- 問題のハミルトニアン $C$ と混ぜるハミルトニアン $B = \sum_j X_j$ を $p$ 回交互にかける回路 $U(B, \beta_p) U(C, \gamma_p) \cdots U(B, \beta_1) U(C, \gamma_1) |+\rangle^{\otimes n}$
- $p \to \infty$ で断熱的な量子計算に近づく。$p$ が小さくても、近似比に保証がつく場合がある
- 3 正則グラフの Max-Cut で、$p = 1$ の近似比が 0.6924 以上になることを示した（アブストラクトより）

## メモ

- まだ本文は読んでいない。アブストラクトと図だけ
- [[Quantum annealing in the transverse Ising model|量子アニーリング]] を離散化したものとして見ると、SQA の結果と並べて考えやすい
- 次の実験の候補 → [[QAOA で小さな Max-Cut（p = 1〜3）|QAOA の計画]]。パラメータ $(\gamma, \beta)$ の最適化に CMA-ES を試したい
