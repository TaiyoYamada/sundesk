---
type: paper
title: "Particle swarm optimization"
authors: [James Kennedy, Russell Eberhart]
year: 1995
venue: "Proceedings of ICNN'95 - International Conference on Neural Networks"
doi: "10.1109/ICNN.1995.488968"
url: "https://doi.org/10.1109/ICNN.1995.488968"
status: 読了
tags: [PSO, 群知能, 連続最適化]
added: 2026-08-29
---
# Particle swarm optimization

## 要点

- 鳥の群れのシミュレーションから生まれた連続最適化の手法。各粒子は速度を持ち、自分の最良（pbest）と群れの最良（gbest）に引かれて動く
- $v \leftarrow v + c_1 r_1 (p - x) + c_2 r_2 (g - x)$、$x \leftarrow x + v$。慣性の重み $w$ は後の論文で入った
- ニューラルネットの重みの学習や、ベンチマークの関数で試している

## メモ

- 原論文は連続版。Max-Cut では、速度をシグモイドで確率に直す二値 PSO（同じ著者の 1997 年の論文）を使った
- 二値 PSO は 10 個の種のどれも最適値に届かず、GA より悪かった → [[二値 PSO で重みつき Max-Cut（30 頂点）|PSO の実験]]。
  速度が上限に張りつくと、ビットがほぼ固定されて動かなくなるのが原因だと思う
- 連続の問題、たとえば VQE の角度の最適化なら、本来の強みが出るはず。CMA-ES と並べて試す候補
