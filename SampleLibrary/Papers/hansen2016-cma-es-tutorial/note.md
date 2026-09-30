---
type: paper
title: "The CMA Evolution Strategy: A Tutorial"
authors: [Nikolaus Hansen]
year: 2016
arxiv: "1604.00772"
url: "https://arxiv.org/abs/1604.00772"
status: 読書中
tags: [CMA-ES, 進化計算, 連続最適化]
added: 2026-09-09
---
# The CMA Evolution Strategy: A Tutorial

## 要点

- 多変量正規分布 $\mathcal{N}(m, \sigma^2 C)$ から候補を $\lambda$ 個作り、よい $\mu$ 個で平均 $m$、共分散 $C$、ステップ幅 $\sigma$ を更新する
- $C$ の更新は rank-one（進化の経路 $p_c$）と rank-$\mu$ の組み合わせ。$\sigma$ は累積のステップ長（CSA）で調整する
- 順位だけを使うので、目的関数の単調な変換に対して不変。付録に、既定のパラメータつきのアルゴリズムのまとめと、短いコードがある

## メモ

- 付録のまとめをそのまま numpy で書いた（`Data/code/vqe.py` の `CMAES`）。$n = 4$ で $\lambda = 8$
- 順位しか使わないので、ショット雑音で値が少しずれても、順位が入れ替わらない限り影響しない。VQE と相性がよいと思った理由
- ショット 1024 の H2 で SPSA と比べると、平均の誤差は半分ほどで、種ごとのばらつきも小さかった
  → [[VQE で H2（ショット 1024、SPSA と CMA-ES）|ショットありの比較]]
- 雑音があると $\sigma$ が縮みきらず、最後は化学精度のまわりをうろうろする。雑音への対策（評価の再サンプリング、UH-CMA-ES など）は別の論文なので、あとで調べる
