---
type: paper
title: "Optimization by Simulated Annealing"
authors: [S. Kirkpatrick, C. D. Gelatt Jr., M. P. Vecchi]
year: 1983
venue: Science
doi: "10.1126/science.220.4598.671"
url: "https://doi.org/10.1126/science.220.4598.671"
status: 読了
tags: [SA, 組合せ最適化, 統計力学]
added: 2026-08-28
---
# Optimization by Simulated Annealing

## 要点

- 組合せ最適化を統計力学の系とみなし、コストをエネルギー、温度を制御の変数にして、メトロポリス法で徐々に冷やす
- 高温で大まかな構造を決め、低温で細部を詰める。急に冷やす（クエンチ）と局所解で凍る
- 回路の配置配線や巡回セールスマン問題で効果を示した

## メモ

- 同じ評価の回数なら、Max-Cut では GA と PSO よりはっきり強かった → [[SA で重みつき Max-Cut（30 頂点、GA と PSO と同じ評価の回数）|SA の実験]]。
  1 回の反転の差分が $O(\text{次数})$ で計算できるのも大きい
- スケジュールの形で成功確率が変わる。短いときは線形、長いときは等比がよかった → [[SA の温度スケジュールの比較（Max-Cut 30 頂点）|スケジュールの実験]]
- 3000 スイープでも成功確率が 0.7 ほどで頭打ちになるのが気になる。始めの温度を変えて確かめている
- 量子版は [[Quantum annealing in the transverse Ising model|Kadowaki & Nishimori 1998]]
