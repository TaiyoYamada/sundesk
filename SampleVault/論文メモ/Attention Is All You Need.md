---
title: Attention Is All You Need
status: 読了
tags: [論文, 機械学習]
source: NeurIPS 2017
---

# Attention Is All You Need

Vaswani et al., 2017. 再帰も畳み込みも使わず、[[Attention]] だけで系列変換を行う Transformer を提案。

## 要点

1. **Self-Attention** で、系列内の任意の 2 点を 1 ステップで結ぶ
2. **Multi-Head** で、異なる部分空間の関係を並列に見る
3. **位置エンコーディング** で順序の情報を足す

$$
PE_{(pos, 2i)} = \sin\!\left(\frac{pos}{10000^{2i/d}}\right)
$$

## 感想

> 行列積に落ちるので GPU と相性がよい。これが後の大規模化の鍵だったと思う。
