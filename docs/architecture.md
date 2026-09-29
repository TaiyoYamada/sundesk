# sundesk アーキテクチャ

- 状態: フェーズ 1 の実装（ネイティブ描画、編集、マルチモジュール）を反映済み
- 最終更新: 2026-09-29
- 要件は [requirements.md](requirements.md)、個々の判断の理由は [ADR](adr/README.md) を参照

## 1. 方針

- **Clean Architecture + MVVM**
  - アプリ全体は Clean Architecture の層に分け、依存は常に内側（Domain）へ向ける
  - 画面は MVVM で作る。ViewModel が UseCase を呼び、戻り値（または `AsyncSequence`）を受け取って表示用の状態に整える
- **依存のルールはコンパイラに守らせる。** 機能と層ごとに Swift Package のモジュールを分け、許した向きにしか import できないようにする（[ADR 0011](adr/0011-feature-based-multi-module.md)）
- **最新の Swift を使う。** Xcode 27 / Swift 6.4、Swift 6 言語モード、厳密な並行性チェック
- **対象は macOS 27**
- Apple のフレームワークと低レイヤー（Metal、Accelerate など）を積極的に使う

## 2. 層

```
┌─ Presentation ─────────────────────────────────────────┐
│  View（SwiftUI）、ViewModel（@Observable）                  │
├─ Domain（中心。どこにも依存しない）───────────────────────┤
│  Entity（Sendable な struct）                             │
│  UseCase（protocol と実装）                                │
│  Repository（protocol のみ）                               │
├─ Data ─────────────────────────────────────────────────┤
│  Repository の実装、SwiftData の @Model、Mapper             │
│  DataSource: ファイル、SwiftData、AI エンジン                │
├─ Infrastructure（フレームワークとドライバ）─────────────────┤
│  エンジンのプロセス管理、Markdown の解析、コードの色づけ       │
└────────────────────────────────────────────────────────┘

依存の向き: Presentation → Domain ← Data → Infrastructure
組み立て: AppFeature（Composition Root）が全部をつなぐ
```

| 層 | 知ってよいもの | 知ってはいけないもの |
|---|---|---|
| Domain | Swift 標準ライブラリ、Foundation の基本型 | SwiftUI、SwiftData、Metal、エンジン |
| Presentation | Domain | SwiftData、エンジン、Data 層の型 |
| Data | Domain、SwiftData、Infrastructure | SwiftUI、ViewModel |
| Infrastructure | Subprocess、swift-markdown、tree-sitter など | Domain 以外のアプリの型 |

### 約束事

- **SwiftData の `@Model` は Data 層の外に出さない。** 境界で Mapper を通して Domain の Entity（`Sendable` な struct）に変換する
- **View は `@Query` を使わない。** データの変化は Repository が `AsyncSequence` として流す
  - 今の索引（`SwiftDataNoteIndex`）は、書き込んだあとに自分で変更を知らせている
  - 画面に大量の一覧を出すときには、`ResultsObserver`（macOS 27 の SwiftData）で監視する形に広げる
- **UseCase は 1 つの操作につき 1 つ。** `callAsFunction` で呼べるようにする
- **DI は [Factory](https://github.com/hmlongco/Factory) を使う**（[ADR 0004](adr/0004-factory-composition-root.md)）
  - Domain、Data、Features は Factory を import しない。依存はコンストラクタで受け取る
  - コンテナへの登録は `AppFeature` モジュールにまとめる。全モジュールを知っているのはここだけ
  - ウインドウに要るものは `WorkspaceDependencies` にまとめて WorkspaceFeature に渡す
- **View は Domain を import しない。** ViewModel が表示用の型（`DocumentDisplay`、`OutlineItem` など）に変換して渡す
- **エラーは層ごとに型を決める。** typed throws を使い、層の境界で変換する

## 3. モジュール構成

```
sundesk/
├── sundesk.xcodeproj
├── sundesk/App/sundeskApp.swift  アプリのターゲット（@main だけ。AppFeature の画面を出す）
├── Packages/SundeskKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── App/AppFeature/                 Composition Root（Factory への登録）、ウインドウ、メニュー、AppDelegate
│   │   ├── Features/
│   │   │   ├── WorkspaceFeature/           ウインドウ（ナビゲータ、タブ、インスペクタ）
│   │   │   ├── NotesFeature/               ファイルの木、検索、タグ、ファイルの表示と編集、インスペクタ
│   │   │   ├── EngineFeature/              エンジンの状態と設定
│   │   │   └── SettingsFeature/            Vault の設定
│   │   ├── Core/
│   │   │   ├── SundeskDomain/              Entity、UseCase、Repository の protocol
│   │   │   ├── SundeskData/                Repository の実装、SwiftData のスキーマ、設定の保存
│   │   │   └── SundeskDesignSystem/        共通の画面部品（インスペクタの節、流し込みの並べ方）
│   │   ├── Infrastructure/
│   │   │   ├── SundeskEngineClient/        エンジンのプロセス管理と HTTP クライアント
│   │   │   ├── SundeskMarkdown/            swift-markdown での解析（索引用、閲覧用、エディタ用）
│   │   │   ├── SundeskCodeHighlight/       tree-sitter でのコードの色づけ
│   │   │   └── TreeSitterScanners/         文法パッケージから漏れる scanner.c（C）
│   │   └── UI/
│   │       ├── SundeskEditorUI/            閲覧の View（SwiftUI）とエディタ（TextKit 2）
│   │       └── SundeskWebView/             HTML ファイルの表示（WebKit）
│   └── Tests/                              モジュールごとのテスト（Sources と同じグループ分け）
├── engine/                       Python エンジン（uv で管理。LLM、画像生成、埋め込み、NLP、グラフ計算）
├── SampleVault/                  モックの Vault（既定で開くノート）
├── Configurations/               xcconfig（バンドル ID、対象 OS、Swift の設定）
├── scripts/                      補助スクリプト（カバレッジの集計など）
└── docs/                         要件、アーキテクチャ、ADR

フェーズ 2 で、知識グラフの機能（GraphFeature）と Metal の描画モジュール（UI/SundeskGraphRenderer）を加える。
```

- モジュール名に `Data` を単独で使わない（Foundation の `Data` 型と衝突するため）
- 画面のモジュール（App、Features、UI、DesignSystem）は既定で MainActor、それ以外は既定で nonisolated

| モジュール | 依存先 |
|---|---|
| AppFeature | すべての Features、SundeskDomain、SundeskData、SundeskDesignSystem、SundeskEngineClient、SundeskMarkdown、FactoryKit |
| WorkspaceFeature | NotesFeature、EngineFeature、SundeskDomain、SundeskDesignSystem |
| NotesFeature | SundeskDomain、SundeskDesignSystem、SundeskEditorUI、SundeskWebView |
| EngineFeature、SettingsFeature | SundeskDomain、SundeskDesignSystem |
| SundeskDomain | なし |
| SundeskData | SundeskDomain、SundeskEngineClient |
| SundeskEngineClient | swift-subprocess |
| SundeskMarkdown | SundeskDomain、swift-markdown |
| SundeskCodeHighlight | swift-tree-sitter、14 言語の文法、TreeSitterScanners |
| SundeskEditorUI | SundeskMarkdown、SundeskCodeHighlight、SundeskDesignSystem、SwiftMath |
| SundeskWebView | WebKit |

同じモジュールの中の決まり（View は Domain を import しない、など）は SwiftLint の独自ルールで守る（[ADR 0011](adr/0011-feature-based-multi-module.md)）。

## 4. 画面（MVVM）の書き方

```swift
// Domain
public protocol AskQuestionUseCase: Sendable {
    func callAsFunction(_ question: String) -> AsyncThrowingStream<AnswerEvent, any Error>
}

// Presentation
@MainActor @Observable
public final class ChatViewModel {
    public private(set) var answer = ""
    public private(set) var citations: [CitationItem] = []
    private let askQuestion: any AskQuestionUseCase

    public func send(_ question: String) async {
        do {
            for try await event in askQuestion(question) {
                switch event {
                case .token(let text): answer += text
                case .citations(let items): citations = items.map(CitationItem.init)
                }
            }
        } catch { /* 表示用のエラー状態へ */ }
    }
}
```

## 5. 並行処理

| 担当 | 実行する場所 |
|---|---|
| View、ViewModel | `@MainActor` |
| UseCase | `nonisolated`。重い計算は `@concurrent` |
| SwiftData への大量の書き込み | `@ModelActor`（バックグラウンド） |
| エンジンのプロセス管理（`EngineProcess`）、ジョブ管理 | `actor` |
| エンジンの起動（子プロセスの実行） | `@concurrent` |
| 逐次の通知（トークン、進捗） | `AsyncSequence` と `ProgressManager` |
| 後始末（モデルの解放など） | `withTaskCancellationShield` |

## 6. AI エンジンとの連携

- 通信: `127.0.0.1` の空いているポートで HTTP。起動ごとにトークンを発行し、`Authorization` ヘッダーで確かめる（[ADR 0006](adr/0006-engine-http-over-loopback.md)）
- 起動: `uv run --project engine sundesk-engine`。swift-subprocess で起動し、`GET /health` が応答したら稼働中とみなす
- 停止: SIGTERM を送り、5 秒で終わらなければ強制終了する。アプリは終了前にエンジンを止め終える
- 取り残し対策: アプリのプロセス ID を渡し、エンジンは親がいなくなったら自分で終了する（[ADR 0007](adr/0007-engine-process-lifecycle.md)）
- 設定: エンジンのフォルダと uv の場所は設定画面で変えられる。既定はリポジトリの `engine/` と、Homebrew などの決まった場所
- ログ: OSLog のサブシステム `com.taiyou.sundesk`。エンジン自身の出力はカテゴリ `engine.output` に流す。起動にかかった時間は signpost で Instruments に出る

## 7. ノートの表示、編集、索引（フェーズ 1）

画面の構成は [ADR 0009](adr/0009-workspace-layout.md)、描画と編集の技術は [ADR 0010](adr/0010-native-rendering-and-editing.md) を参照。

| 種類 | モード | 描き方 |
|---|---|---|
| Markdown | ライブプレビュー（既定）、ソース | TextKit 2 のエディタ。記法を `MarkdownSyntax` で色づけし、ライブプレビューではカーソルのない段落の記号を隠す |
| Markdown | 閲覧 | `MarkdownDocumentParser` のブロックの木を SwiftUI で描く。数式は SwiftMath、コードは tree-sitter |
| HTML | 閲覧 | WebKit（`sundesk-vault:` のスキームで Vault の中だけを読む） |
| HTML | ソース | エディタ（tree-sitter で色づけ、行番号つき） |
| テキスト、コード | ソースだけ | エディタ（tree-sitter で色づけ、行番号つき） |
| 画像 | — | SwiftUI（拡大・縮小） |
| PDF | — | PDFKit |
| その他 | — | Quick Look |

- ⌘E で編集と閲覧を切り替える（編集に戻るときは、前に使っていた編集のモード）
- 編集すると `AnalyzeNoteUseCase` で解析し直し、インスペクタの目次、タグ、プロパティをすぐ更新する
- 自動保存: 最後の編集から 1 秒後に `SaveDocumentUseCase` で書く。保存は 1 つずつ順に行う
  - タブを閉じるとき、⌘S、アプリの終了時（`OpenDocumentRegistry`）は待たずに保存する
  - 保存していない編集があるタブには点を出す。保存に失敗したら、エディタの上に帯を出す
- ファイルが外で書き換えられたら読み直す。ただし保存していない編集があれば、画面の本文を残す
- エディタ（`TextEditorSession`）はファイルごとに作って使い回し、タブを切り替えても取り消しの履歴とスクロール位置を残す

索引の流れ:

1. `FileSystemVaultRepository` が Vault の木を読む（隠しファイルと node_modules などは除く）
2. `IndexVaultInteractor` が、更新日時と大きさの変わった Markdown だけを読み直す
   - ファイルが増えたり消えたりしたときは、リンク先が変わりうるので、すべて読み直す
3. `SwiftMarkdownParser` が、フロントマター、タイトル、タグ、リンク、見出しを取り出す（コードと数式の中は除く）
4. `LinkResolver` が、Obsidian と同じ順（完全なパス → 末尾の一致 → ファイル名）でリンク先を決める
5. `SwiftDataNoteIndex` に保存する（ノート、リンク、メタデータの 3 つのモデル。Vault ごとに別のファイル）
6. Vault の変更は FSEvents で見張り、変わるたびに 1〜5 をくり返す

## 8. 知識グラフの描画（Metal）

- `MTKView` を SwiftUI に埋め込んで描く
- 点と線はインスタンス描画でまとめて描く（数万規模を想定）
- レイアウト（力学モデル）の計算は、Metal のコンピュートシェーダーで行う。反発力の計算は、Barnes-Hut 法かグリッド分割で近似する
- クリックした点の判定、ズーム、パン
- 文字ラベルは、重要な点（PageRank の上位など）だけに付ける
  - 描き方（グリフのアトラスを作って Metal で描くか、SwiftUI を重ねるか）は試作して決める
- テストでは、シェーダーの計算結果を CPU の参照実装と比べる

## 9. テスト

- **実装した後に書く**（TDD にはしない）。ただし、層ごとに漏れなく書く
- Swift Testing を基本にする。UI テストだけ XCTest を使う

| 対象 | 内容 |
|---|---|
| Domain | 純粋なロジック（正規化、スコア計算、グラフのアルゴリズム）。パラメータ化テストを多用する |
| UseCase | Repository を偽物に差し替え、処理の流れを検証する |
| ViewModel | UseCase を偽物に差し替え、状態の変化を検証する |
| Data | SwiftData はメモリ上の DB で実際に動かす。Mapper の往復変換も検証する |
| Metal | シェーダーと CPU の参照実装の結果が一致するかを検証する |
| Markdown の解析 | 索引用、閲覧用、エディタ用の 3 つの解析を、日本語を含む入力で検証する（位置のずれ、数式とコードの保護） |
| エディタ | 本物の `NSTextView` で、ライブプレビューの記号の隠し方、色づけ、リンクの属性を検証する |
| WebKit | 本物の `WebPage` で Vault の HTML ファイルを開く |
| エンジン | API の約束事を Swift と Python の両側から検証する |
| 画面 | スナップショットテストと、主要な操作の UI テスト |

- `make test` でパッケージ、アプリ、Python のテストをまとめて走らせる。`make test-ui` で UI テスト
- 本物のエンジンを起動する結合テストは、`SUNDESK_INTEGRATION=1` のときだけ走る（`make test-integration`、CI では常に走らせる）
- CI（GitHub Actions）はプルリクエストごとに、lint、テスト、カバレッジの集計を行う

## 10. 未決事項

- [ ] ライブプレビューで数式を画像にして見せるか（今は色を変えたソースのまま）
- [ ] 大きなテンソル（Attention の行列など）の転送形式（フェーズ 4）
- [ ] CodeQL の Swift 対応（CodeQL が Swift 6.4 に対応したら加える）
