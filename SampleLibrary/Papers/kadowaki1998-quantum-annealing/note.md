---
type: paper
title: "Quantum annealing in the transverse Ising model"
authors: [Tadashi Kadowaki, Hidetoshi Nishimori]
year: 1998
venue: Physical Review E
doi: "10.1103/PhysRevE.58.5355"
url: "https://doi.org/10.1103/PhysRevE.58.5355"
status: 読書中
tags: [量子アニーリング, イジング模型, 組合せ最適化]
added: 2026-09-01
---
# Quantum annealing in the transverse Ising model

## 要点

- 熱ゆらぎの代わりに量子ゆらぎ（横磁場 $\Gamma \sum_i \sigma_i^x$）で状態空間を探り、$\Gamma$ を 0 へ下げていく。量子アニーリングの提案
- 小さな系で時間依存のシュレーディンガー方程式を直接解き、同じ条件の SA（熱アニーリング）より基底状態に届く確率が高いことを示した
- 横磁場の下げ方（スケジュール）によって結果が大きく変わる

## メモ

- 論文は厳密な時間発展。自分が回しているのは経路積分モンテカルロによる SQA なので、同じものではない。
  SQA は量子アニーリングの平衡の性質は真似られるが、トンネルの力学までは真似られない、という点に注意
- SQA と SA を、スピン更新の回数をそろえて比べた → [[SQA と SA の比較（Max-Cut 30 頂点、スピン更新の回数をそろえる）|SQA と SA]]。
  スライス 1 枚で見ると SA に負け、16 枚の最良で見ると短い計算では勝つ。どちらで数えるのが公平かは議論が要る
- SA のスケジュールの比較は [[SA の温度スケジュールの比較（Max-Cut 30 頂点）|スケジュールの実験]]
- 数値実験の設定（スピンの数、スケジュール）を読み終えたら、ここに追記する
