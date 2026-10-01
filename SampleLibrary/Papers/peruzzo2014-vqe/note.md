---
type: paper
title: "A variational eigenvalue solver on a photonic quantum processor"
authors: [Alberto Peruzzo, Jarrod McClean, Peter Shadbolt, Man-Hong Yung, Xiao-Qi Zhou, Peter J. Love, Alán Aspuru-Guzik, Jeremy L. O'Brien]
year: 2014
venue: Nature Communications
arxiv: "1304.3061"
doi: "10.1038/ncomms5213"
url: "https://arxiv.org/abs/1304.3061"
status: 読了
tags: [VQE, 量子化学, 変分法]
added: 2026-08-24
---
# A variational eigenvalue solver on a photonic quantum processor

## 要点

- VQE の原論文。状態の準備と期待値の測定だけを量子計算機にやらせ、パラメータの更新は古典の最適化に任せる
- エネルギーをパウリ演算子の和 $H = \sum_i h_i P_i$ に分け、項ごとに測って足す。位相推定のような長いコヒーレンス時間はいらない
- 光量子プロセッサで HeH⁺ の基底エネルギーを求めた。最適化には Nelder-Mead を使っている
- 変分原理 $\langle \psi(\theta) | H | \psi(\theta) \rangle \ge E_0$ があるので、どこで止めても上界になる

## メモ

- 自分の研究の出発点。「古典の最適化の部分をどう設計するか」がそのまま研究の問いになる
- 測定の回数（ショット）が有限だと、最適化は雑音のある関数を相手にすることになる。
  ここを進化計算で扱うのが今の方針 → [[VQE で H2（ショット 1024、SPSA と CMA-ES）|ショットありの比較]]
- 手元の H2 は、STO-3G の積分から自分で作ったハミルトニアンで再現した（`Data/molecules/h2-sto3g-0.735.json`）。
  FCI は -1.137306 Ha で、文献の値と合う
- 仮説はこの論文では UCC。実機向けの浅い回路は [[Hardware-efficient variational quantum eigensolver for small molecules and quantum magnets|Kandala 2017]]
