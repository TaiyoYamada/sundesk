---
type: paper
title: "Hardware-efficient variational quantum eigensolver for small molecules and quantum magnets"
authors: [Abhinav Kandala, Antonio Mezzacapo, Kristan Temme, Maika Takita, Markus Brink, Jerry M. Chow, Jay M. Gambetta]
year: 2017
venue: Nature
arxiv: "1704.05018"
doi: "10.1038/nature23879"
url: "https://arxiv.org/abs/1704.05018"
status: 読了
tags: [VQE, HEA, 量子化学, SPSA]
added: 2026-08-26
---
# Hardware-efficient variational quantum eigensolver for small molecules and quantum magnets

## 要点

- 化学の知識から回路を組む（UCC）のではなく、実機で素直に作れるゲート（1 量子ビットの回転と、決まった形のもつれ）を層にして重ねる仮説を使う
- 超伝導量子ビット 6 個まで使い、H2、LiH、BeH2 の解離曲線と、量子磁性のモデルを計算した
- 最適化は SPSA。1 回の更新で 2 回しか評価しないので、測定の多い VQE で使いやすい
- 誤差の多くは、ゲートの誤りとデコヒーレンスから来ていると分析している

## メモ

- 自分の実験の仮説（RY の層と CNOT）は、この HEA を実数の振幅に絞ったもの
- H2 は 2 量子ビットに縮めれば、深さ 1 で FCI に届く → [[VQE で H2（HEA、パラメータシフトの勾配法、深さ 1 と 2）|勾配法の実験]]
- SPSA は種によって当たり外れが大きかった → [[VQE で H2（HEA 深さ 1、SPSA、ショットなし）|SPSA の実験]]。
  論文では、この揺れを何回かの試行と較正で抑えているように読める
- 解離曲線は自分でも描いた → [[H2 の解離曲線（HF、VQE、FCI）|解離曲線]]
- 層を深くすると barren plateau が気になる。H2 の規模では関係ないが、4 量子ビット以上に広げるときに確かめる
