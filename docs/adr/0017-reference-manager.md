# 0017. sundesk を、Swift だけで動く文献管理アプリに作り直す

- 状態: 採用（[0002](0002-swift-app-with-python-engine.md)、[0003](0003-swiftdata-single-source-of-truth.md)、[0005](0005-metal-knowledge-graph.md)、[0006](0006-engine-http-over-loopback.md)、[0007](0007-engine-process-lifecycle.md)、[0009](0009-workspace-layout.md)、[0012](0012-knowledge-and-rag.md)、[0013](0013-lab-and-image-generation.md)、[0014](0014-forge-and-scratch.md)、[0015](0015-research-library.md)、[0016](0016-read-research-in-place.md) を置き換える）
- 日付: 2026-11-01

## 背景

これまでの sundesk は、ノート、知識グラフ、RAG、LLM の実験室、画像生成をまとめた「ローカル AI の実験場」だった。
機能が広がりすぎ、Python のエンジンの起動と通信が一番重い部分になっていた。
研究で毎日要るのは、論文を集めて整理し、読んで書き込み、LaTeX から引くことなので、Zotero のような文献管理のアプリに作り直す。
Zotero のコードは使わない（AGPL-3.0 なので、移すとこのアプリも縛られる）。考え方だけを参考にし、Swift と SwiftUI で書く。

## 決定

- **Python のエンジンをなくし、Swift だけにする。** 書誌情報の取得は URLSession、PDF は PDFKit、要約は Foundation Models で足りる
- **機能**: 文献の登録（DOI、arXiv の ID、ISBN、PDF のドロップ、手での入力）、コレクション（入れ子にできる）とタグと検索、
  PDF を読む画面とハイライト・コメント・メモ、BibTeX の書き出し、オンデバイスのモデルでの要約
- **保存**: 書誌情報、コレクション、タグ、メモ、注釈、要約は SwiftData に置き、これを正とする。
  PDF はデータフォルダの `Storage/<文献の ID>/` に写す（元の場所を指すだけにはしない）。
  ハイライトは PDF のファイルに書き込まない（元の PDF を変えず、要約や検索にもそのまま使えるように）
- **書誌情報**: 項目は CSL JSON に合わせる。DOI は doi.org に `Accept: application/vnd.citationstyles.csl+json` で聞く
  （Crossref と DataCite の両方に効く）。arXiv は arXiv の API、ISBN は Open Library の Books API を使う
- **引用の書式**: まずは BibTeX だけにする。Swift で動く CSL の処理系は見当たらず
  （CiteprocRsKit は 2021 年から止まっている）、CSL の書式は citeproc-js を JavaScriptCore で動かす案を、ライセンスを確かめてから考える
- **要約**: オンデバイスのモデルは一度に読める長さが短い（`SystemLanguageModel.contextSize`）。
  参考文献の節より後ろを落とし、`tokenCount(for:)` で測りながらページを詰めて区切り、区切りごとに要点のメモを作ってから、
  `@Generable` の型（目的、手法、結果、限界）にまとめる
- **残すもの**: Clean Architecture と MVVM（[0001](0001-clean-architecture-mvvm.md)）、Factory（[0004](0004-factory-composition-root.md)）、
  マルチモジュール（[0011](0011-feature-based-multi-module.md)）、Markdown のエディタ（[0010](0010-native-rendering-and-editing.md)。メモに使う）

## 検討した選択肢

| 選択肢 | 良い点 | 悪い点 |
|---|---|---|
| **作り直す（Swift だけ）** | エンジンの起動と通信がなくなり、構成が単純になる | AI の実験の機能はすべてなくなる |
| 今のアプリに文献管理を足す | 実験室や知識グラフも残る | 重い部分がそのまま残り、画面も散らかる |
| PDF の置き場をファイルの正にする（これまでのライブラリの形） | Finder からも中身が分かる | コレクションやタグのような多対多の関係をファイルで持つと、読み書きと作り直しの処理が膨らむ |
| ハイライトを PDF に書き込む | ほかの PDF のアプリでも見える | 元の PDF が変わる。書き込みに失敗すると PDF を壊す |

## 結果

- 外と通信するのは、書誌情報と arXiv の PDF を取るところ（`OnlineBibliography`）だけ
- データは `~/Library/Application Support/com.taiyou.sundesk/Library/`（`library.store` と `Storage/`）にまとまり、Time Machine に入る
- 引用の書式（CSL）、ブラウザからの登録、同期は、まだない
