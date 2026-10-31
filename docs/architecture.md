# sundesk アーキテクチャ

- 最終更新: 2026-11-01
- 要件は [requirements.md](requirements.md)、個々の判断の理由は [ADR](adr/README.md) を参照

## 1. 方針

- **Clean Architecture + MVVM**
  - アプリ全体は Clean Architecture の層に分け、依存は常に内側（Domain）へ向ける
  - 画面は MVVM で作る。ViewModel が UseCase を呼び、戻り値（または `AsyncSequence`）を受け取って表示用の状態に整える
- **依存のルールはコンパイラに守らせる。** 機能と層ごとに Swift Package のモジュールを分け、許した向きにしか import できないようにする（[ADR 0011](adr/0011-feature-based-multi-module.md)）
- **Swift だけで作る。** 書誌情報は URLSession、PDF は PDFKit、要約は Foundation Models（[ADR 0017](adr/0017-reference-manager.md)）
- Xcode 27 / Swift 6.4、Swift 6 言語モード、厳密な並行性チェック。対象は macOS 27

## 2. 層

```
┌─ Presentation ─────────────────────────────────────────┐
│  View（SwiftUI）、ViewModel（@Observable）                  │
├─ Domain（中心。どこにも依存しない）───────────────────────┤
│  Entity（Sendable な struct）                             │
│  UseCase（protocol と実装）                                │
│  Repository、外部の仕組み（protocol のみ）                  │
├─ Data ─────────────────────────────────────────────────┤
│  SwiftData の @Model と Mapper、Repository の実装          │
│  doi.org・arXiv・Open Library、PDFKit、Foundation Models   │
├─ Infrastructure / UI ───────────────────────────────────┤
│  Markdown の解析、コードの色づけ、メモのエディタ               │
└────────────────────────────────────────────────────────┘

依存の向き: Presentation → Domain ← Data
組み立て: AppFeature（Composition Root）が全部をつなぐ
```

| 層 | 知ってよいもの | 知ってはいけないもの |
|---|---|---|
| Domain | Swift 標準ライブラリ、Foundation の基本型 | SwiftUI、AppKit、SwiftData、PDFKit、FoundationModels |
| Presentation | Domain、SwiftUI、AppKit、PDFKit、メモのエディタ | SwiftData、Data 層の型 |
| Data | Domain、SwiftData、PDFKit、FoundationModels | SwiftUI、ViewModel |

### 約束事

- **SwiftData の `@Model` は Data 層の外に出さない。** 境界で `RecordMapper` を通して Domain の Entity（`Sendable` な struct）に変換する
- **View は `@Query` を使わない。** Repository が書き換えのたびに `changes()` で知らせ、ViewModel が読み直す
- **UseCase は機能ごとにまとめる。** ライブラリの操作は `ManageLibraryUseCase`、要約は `SummarizePaperUseCase`（`callAsFunction`）
- **DI は [Factory](https://github.com/hmlongco/Factory) を使う**（[ADR 0004](adr/0004-factory-composition-root.md)）
  - Domain、Data、Features は Factory を import しない。依存はコンストラクタで受け取る
  - コンテナへの登録は `AppFeature` モジュールにまとめる。全モジュールを知っているのはここだけ
  - 画面に要るものは `LibraryDependencies` にまとめて渡し、View はそこから ViewModel を作る
- **View は Domain を import しない。** ViewModel が表示用の型（`ReferenceRow`、`ReferenceDraft`、`HighlightDisplay` など）に変換して渡す
- **エラーは層ごとに型を決める。** typed throws（`LibraryError`、`SummaryError`）を使う

## 3. モジュール構成

```
sundesk/
├── sundesk.xcodeproj
├── sundesk/App/sundeskApp.swift  アプリのターゲット（@main だけ。AppFeature の画面を出す）
├── Packages/SundeskKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── App/AppFeature/              Composition Root（Factory への登録）、ウインドウ、メニュー
│   │   ├── Features/
│   │   │   ├── LibraryFeature/          ライブラリのウインドウ、文献の詳細、PDF を読むウインドウ
│   │   │   └── SettingsFeature/         設定の画面（外観、保存先）
│   │   ├── Core/
│   │   │   ├── SundeskDomain/           Entity、UseCase、Repository の protocol、BibTeX、要約の区切り方
│   │   │   ├── SundeskData/             SwiftData、PDF の置き場、書誌情報の取得、PDFKit、Foundation Models
│   │   │   └── SundeskDesignSystem/     共通の画面部品（帯、インスペクタの節、流し込みの並べ方）
│   │   ├── Infrastructure/
│   │   │   ├── SundeskMarkdown/         swift-markdown での解析（エディタ用、閲覧用）
│   │   │   ├── SundeskCodeHighlight/    tree-sitter でのコードの色づけ
│   │   │   └── TreeSitterScanners/      文法パッケージから漏れる scanner.c（C）
│   │   └── UI/
│   │       └── SundeskEditorUI/         メモのエディタ（TextKit 2）と閲覧の View
│   └── Tests/                           モジュールごとのテスト（Sources と同じグループ分け）
├── Configurations/                      xcconfig（バンドル ID、対象 OS、Swift の設定）
├── scripts/                             補助スクリプト（カバレッジの集計）
└── docs/                                要件、アーキテクチャ、ADR
```

- モジュール名に `Data` を単独で使わない（Foundation の `Data` 型と衝突するため）
- 画面のモジュール（App、Features、UI、DesignSystem）は既定で MainActor、それ以外は既定で nonisolated

| モジュール | 依存先 |
|---|---|
| AppFeature | LibraryFeature、SettingsFeature、SundeskDomain、SundeskData、SundeskDesignSystem、FactoryKit |
| LibraryFeature | SundeskDomain、SundeskDesignSystem、SundeskEditorUI |
| SettingsFeature | SundeskDesignSystem |
| SundeskDomain | なし |
| SundeskData | SundeskDomain |
| SundeskMarkdown | swift-markdown |
| SundeskCodeHighlight | swift-tree-sitter、14 言語の文法、TreeSitterScanners |
| SundeskEditorUI | SundeskMarkdown、SundeskCodeHighlight、SundeskDesignSystem、SwiftMath |

同じモジュールの中の決まり（View は Domain を import しない、など）は SwiftLint の独自ルールで守る（[ADR 0011](adr/0011-feature-based-multi-module.md)）。

## 4. 画面

| ウインドウ | 中身 |
|---|---|
| ライブラリ（`Window`、1 つだけ） | 左: すべての文献、未整理、コレクション（入れ子）、タグ。中: 文献の一覧（`Table`）。右: 選んだ文献の情報、メモ、要約 |
| PDF を読む（`WindowGroup(for: UUID.self)`、文献ごと） | PDFView と、右のインスペクタ（注釈、メモ、要約） |
| 設定 | 外観、保存先の場所 |

- 一覧に PDF をドロップすると取り込む。行をサイドバーのコレクションへドラッグすると、そこに入れる（選んでいる行の 1 つなら、選んでいる行すべて）
- 一覧の行をダブルクリックすると、PDF を読むウインドウを開く
- 文献を足す操作と BibTeX の書き出しは「ファイル」メニューにある（`LibraryCommands`。`@FocusedValue` でライブラリの ViewModel を受け取る）
- 編集は `ReferenceDetailViewModel` が 0.6 秒待ってから保存する。保存を待っている間に変更の知らせが来ても、画面の値を残す。
  画面を閉じるときは待たずに保存する（`flush()`）
- ハイライトは `PDFReaderController` が PDFView の上に `PDFAnnotation` として描く（`userName` に注釈の ID を入れ、自分で足したものだけを描き直す）。
  PDF のファイルには保存しない

## 5. 文献の登録

```
識別子（DOI / arXiv / ISBN） ─ ReferenceIdentifier(parsing:) ─┐
                                                            ├→ LibraryInteractor → SwiftDataReferenceRepository
PDF ─ PDFKitReader（最初の 3 ページの DOI / arXiv の ID）──┘          └→ FileAttachmentStore（Storage/<ID>/）
                                     │
                         OnlineBibliography（通信するのはここだけ）
                         ├ DOI   → doi.org（Accept: application/vnd.citationstyles.csl+json）→ CSLItem
                         │         arXiv の DOI（10.48550/arXiv.*）は arXiv の API に回す
                         ├ arXiv → export.arxiv.org の API（Atom）→ ArxivFeed、PDF は arxiv.org/pdf
                         └ ISBN  → Open Library の Books API → OpenLibraryBook
```

- doi.org は、Crossref の DOI には Crossref の種類の名前（`journal-article` など）を返し、値の型も揺れる（題名が文字列か配列か、巻が文字列か数か）。
  `ReferenceType(csl:)` と `FlexibleText` で、どちらでも読む
- 引用キーは `CitationKey.make` が付ける。保存するときに空なら付け直す

## 6. 要約

`SummarizePaperInteractor` が、Domain だけで流れを決める。モデルとのやり取りは `PaperSummarizer`（実装は `FoundationModelsSummarizer`）。

1. PDF のページの文字を読み、`PaperText.body` で参考文献の節より後ろを落とす
2. `PaperText.parts` で、`tokenCount(for:)` で測りながらページを順に詰める。上限は `contextSize` から指示と答えの分（1,400 トークン）を引いた長さ。
   1 ページで超えるときは行で、改行がなければ文字で、半分に分ける
3. 区切りごとに、要点の箇条書きを作る（`LanguageModelSession.respond`）
4. 要点を合わせても上限を超えるときは、要点をさらに区切ってまとめる
5. `@Generable` の `GeneratedSummary`（目的、手法、結果、限界）にまとめ、文献に保存する（保存の前に読み直し、要約している間の編集を消さない）

進み具合は `AsyncThrowingStream<SummaryProgress>` で画面に流す。

## 7. 並行処理

| 担当 | 実行する場所 |
|---|---|
| View、ViewModel | `@MainActor` |
| UseCase | `nonisolated` の struct |
| SwiftData | `@ModelActor`（`SwiftDataReferenceRepository`） |
| 変更の知らせ | Repository が持つ `AsyncStream` の一覧に、保存のたびに流す |

## 8. テスト

- **実装した後に書く**（TDD にはしない）。Swift Testing を基本にし、UI テストだけ XCTest を使う

| 対象 | 内容 |
|---|---|
| Domain | 識別子の読み取り、著者の名前、引用キー、BibTeX、絞り込み、要約の区切り方。UseCase は Repository などを偽物に差し替えて流れを確かめる |
| Data | SwiftData はメモリ上の DB で実際に動かす。doi.org、arXiv、Open Library の応答の読み取り。PDF の置き場は一時フォルダで |
| ViewModel | メモリ上の SwiftData と本物の `LibraryInteractor` を使い、通信と PDF だけ偽物にする |
| Markdown の解析とエディタ | 日本語を含む入力で、位置のずれと記号の隠し方を確かめる。エディタは本物の `NSTextView` で |
| 画面 | 一時フォルダのライブラリ（起動引数 `-library.directory`）で起動し、主な操作を確かめる。通信する操作は確かめない |

- `make test` でパッケージとアプリのテスト、`make test-ui` で UI テスト
- CI（GitHub Actions）はプルリクエストごとに、lint とテストを行う。Swift のカバレッジは手元で `make coverage` で見る

## 9. 未決事項

- [ ] 引用の書式（CSL）。citeproc-js を JavaScriptCore で動かす案を、ライセンスを確かめてから
- [ ] CodeQL の Swift 対応（CodeQL が Swift 6.4 に対応したら加える）
