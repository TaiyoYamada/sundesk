---
type: paper
title: "Ising formulations of many NP problems"
authors: [Andrew Lucas]
year: 2014
venue: Frontiers in Physics
arxiv: "1302.5843"
doi: "10.3389/fphy.2014.00005"
url: "https://arxiv.org/abs/1302.5843"
status: 読了
tags: [QUBO, イジング模型, 組合せ最適化, 量子アニーリング]
added: 2026-08-30
---
# Ising formulations of many NP problems

## 要点

- Karp の 21 問題を中心に、多くの NP 完全・NP 困難な問題をイジング模型（QUBO）の基底状態を求める問題に書き直した一覧
- 分割問題、Max-Cut、グラフ彩色、クリーク、巡回セールスマンなど。制約はペナルティ項 $A(\cdot)^2$ で入れる
- 量子アニーリング機に載せるときのスピンの数（何倍に増えるか）も見積もっている

## メモ

- Max-Cut は制約がなく、ペナルティ係数を決めなくてよいので、最初のベンチマークにちょうどよい。
  $s_i \in \{\pm 1\}$ で $E = \sum_{i<j} w_{ij} s_i s_j$ を最小にすれば、カットは $(W - E)/2$
- QUBO の形は `Data/instances/maxcut-w30-qubo.json` に置いた（$x^\top Q x = -\mathrm{cut}(x)$）
- 制約つきの問題（巡回セールスマンなど）に進むと、ペナルティ係数の決め方が問題になる → [[QUBO のペナルティ係数]]
- 同じインスタンスで GA、PSO、SA を比べた → [[2026-09-17]]
