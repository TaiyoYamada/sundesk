# 0001. Clean Architecture と MVVM を採用する

- 状態: 採用
- 日付: 2026-09-29

## 背景

sundesk は、ノートの取り込み、知識グラフ、RAG、LLM の実験、画像生成と機能が多く、
AI エンジンのように差し替えたくなる部品も抱える。名前の決まった、広く使われている
設計にしたい、という要望もあった。

## 決定

- アプリ全体を Clean Architecture の層（Presentation、Domain、Data、Infrastructure）に分け、
  依存は常に内側（Domain）へ向ける
- 画面は MVVM で作る。ViewModel が UseCase を呼び、戻り値や `AsyncSequence` を受け取って
  表示用の状態に整える
- 層ごとに Swift Package のモジュールを分け、依存の向きをコンパイラに守らせる
- SwiftData の `@Model` は Data 層から出さず、Domain は `Sendable` な struct だけを扱う

## 検討した選択肢

| 選択肢 | 良い点 | 悪い点 |
|---|---|---|
| 原典どおりの Clean Architecture（Presenter と Output Port を使う） | 役割の分離が最も徹底する | 1 機能あたりの型が多い |
| **Clean Architecture + MVVM** | 広く使われている。async/await と相性がよい | ViewModel の責務がやや大きくなる |
| TCA | 設計の縛りが強く、テストしやすい | 独自の状態管理が中心で、SwiftData と噛み合いにくい |
| MV（Apple のサンプルの流儀） | コードが短い | 規模が大きくなると崩れやすい |

## 結果

- 内側から外側を import するとビルドが通らないので、依存のルールが崩れにくい
- Domain と ViewModel は UI もデータベースも無しでテストできる
- View で `@Query` を使えないので、データの変化は Repository から流す必要がある
