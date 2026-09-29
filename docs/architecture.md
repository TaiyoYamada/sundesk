# sundesk アーキテクチャ

- 状態: フェーズ 0〜6 の実装を反映済み
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
│   │   │   ├── LibraryFeature/             研究ライブラリ（種類ごとの一覧、論文、実験、比べる画面）
│   │   │   ├── GraphFeature/               知識グラフ
│   │   │   ├── ChatFeature/                ノートを根拠に答えるチャット
│   │   │   ├── LabFeature/                 LLM の実験室（覗く・いじる）と、モデルの管理
│   │   │   ├── ImagesFeature/              画像生成
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
│   │       ├── SundeskGraphRenderer/       知識グラフの描画（Metal）
│   │       └── SundeskWebView/             HTML ファイルの表示（WebKit）
│   └── Tests/                              モジュールごとのテスト（Sources と同じグループ分け）
├── engine/                       Python エンジン（uv で管理。LLM、画像生成、埋め込み、NLP、グラフ計算）
├── SampleLibrary/                研究向けの見本のライブラリ（開発とテスト用）
├── tools/sundesk-log/            実験のコードから結果を送る Python の記録用ライブラリ
├── Configurations/               xcconfig（バンドル ID、対象 OS、Swift の設定）
├── scripts/                      補助スクリプト（カバレッジの集計など）
└── docs/                         要件、アーキテクチャ、ADR
```

- モジュール名に `Data` を単独で使わない（Foundation の `Data` 型と衝突するため）
- 画面のモジュール（App、Features、UI、DesignSystem）は既定で MainActor、それ以外は既定で nonisolated

| モジュール | 依存先 |
|---|---|
| AppFeature | すべての Features、SundeskDomain、SundeskData、SundeskDesignSystem、SundeskEngineClient、SundeskMarkdown、FactoryKit |
| WorkspaceFeature | ほかの Features、SundeskDomain、SundeskDesignSystem |
| NotesFeature | SundeskDomain、SundeskDesignSystem、SundeskEditorUI、SundeskWebView |
| GraphFeature | SundeskDomain、SundeskDesignSystem、SundeskGraphRenderer |
| ChatFeature、LabFeature、ImagesFeature | SundeskDomain、SundeskDesignSystem |
| EngineFeature、SettingsFeature | SundeskDomain、SundeskDesignSystem |
| SundeskDomain | なし |
| SundeskData | SundeskDomain、SundeskEngineClient |
| SundeskEngineClient | swift-subprocess |
| SundeskMarkdown | SundeskDomain、swift-markdown |
| SundeskCodeHighlight | swift-tree-sitter、14 言語の文法、TreeSitterScanners |
| SundeskEditorUI | SundeskMarkdown、SundeskCodeHighlight、SundeskDesignSystem、SwiftMath |
| SundeskGraphRenderer | Metal、MetalKit |
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

## 7.5. 研究ライブラリ

形式は [library-format.md](library-format.md)、判断の理由は [ADR 0015](adr/0015-research-library.md)。

- ライブラリはアプリのデータフォルダの中のふつうのファイル。ノート、論文、実験、データ、資料、取り込み箱のフォルダに分ける
- 左のナビゲータ（⌘1）は種類ごとの一覧。論文は読んだ状態で絞り込み、題名や年で並べ替える。実験は複数選ぶと比べられる
- 論文のタブ: PDF（PDFKit）、書誌情報、論文メモ（エディタ）。arXiv の ID か DOI から書誌情報を取る（`OnlineBibliography`。アプリで唯一の通信）
- 実験のタブ: 設定、指標、収束の曲線（Swift Charts。最適値の線つき）、図、仮説と考察のメモ。CSV や画像をドロップすると取り込む
- 比べるタブ: 収束の曲線を重ね（最適値との差を対数で見ることもできる）、指標の最もよい値と、値の違うパラメータを表にする
- 取り込み箱: 記録用ライブラリが `Inbox/<ID>/` に書き、`.complete` を置く。ライブラリの変化を見張っていて、見つけたら `Experiments/` に移す

## 8. 知識グラフ（フェーズ 2）

作り方と更新の仕方は [ADR 0012](adr/0012-knowledge-and-rag.md)、描画は [ADR 0005](adr/0005-metal-knowledge-graph.md) を参照。

1. `MarkdownChunker` がノートを見出しで区切る（見出しの階層、行番号、数式とコードを除いた本文を持つ）
2. エンジンの `/graph/build` が、SudachiPy で用語を抜き出し（C-value）、関係を作る
   - 共起（PMI）、見出しの階層、「A とは B」「A は B の一種」、ノートのリンク、複合語の包含、埋め込みの類似
   - networkx で PageRank とコミュニティ（Louvain 法）を計算する
3. アプリが `KnowledgeStore`（Vault ごとの SwiftData）に保存する
4. 描画（`SundeskGraphRenderer`）
   - 重要な概念から上位 N 個（100〜3000）を描く。点の大きさは PageRank、色はコミュニティ
   - 配置は Fruchterman-Reingold 法を Metal のコンピュートシェーダーで計算する。温度を下げていき、落ち着いたら止める
   - 点はインスタンス描画の円（フラグメントシェーダーで縁をなめらかにする）、線は線分でまとめて描く
   - ラベルは、大きい点と、選んだ点とその隣だけを SwiftUI の Canvas で重ねる
   - ドラッグで移動、スクロールやピンチで拡大・縮小、点のドラッグで動かす
   - テストでは、GPU の計算結果を CPU の参照実装と突き合わせる
5. インスペクタに、つながる概念（関係の種類つき）と、概念が出てくるノートの節を出す。押すとその節を開く

## 9. RAG（フェーズ 3）

1. 質問を、意味（ruri-v3 の埋め込みとベクトル検索）、語（bigram）、知識グラフの 3 つで探し、Reciprocal Rank Fusion でまとめる
2. 上位 6 節に番号を付けてシステムの指示に入れ、前の会話と一緒にモデルへ渡す
3. 答えは少しずつ画面に出す。答えの中の `[1]` を出典として残し、押すとその節を開く
4. 会話は `KnowledgeStore` に残し、あとから見返せる
5. モデルは、Apple のオンデバイスモデル（Foundation Models）か、エンジンの MLX のモデル（既定は Qwen3-4B-Instruct の 4bit）

## 10. 実験室と画像生成（フェーズ 4〜6）

詳しくは [ADR 0013](adr/0013-lab-and-image-generation.md) を参照。

| 画面 | できること |
|---|---|
| モデル | 手元のモデルの一覧、Hugging Face からの取り込み、削除、メモリから外す |
| 実験室: トークン | プロンプトの区切られ方と ID |
| 実験室: 次のトークン | 上位 20 個の確率（温度を変えると分布の形が変わる）とエントロピー |
| 実験室: 生成 | 1 トークンずつ、選ばれた確率で色を付ける。押すと他の候補が見える。LoRA を選んで生成できる |
| 実験室: Attention | 層・ヘッドごとの注目の行列 |
| 実験室: Logit lens | 途中の層の状態を出力層に通したときの予測 |
| 実験室: 活性 | 各層・各トークンの残差ストリームの大きさ |
| 実験室: LoRA | Vault のフォルダのノートで学習し、損失の変化を描く |
| 実験室: Steering | 2 組の文の活性の差を足して、生成の向きを変える（足さない生成と並べて比べる） |
| 実験室: 蒸留 | 先生の確率分布を生徒に学ばせる（生徒に LoRA を付けるか、全体を学習する） |
| 実験室: 量子化 | MLX の 2〜8 ビット、層ごとの配分、重みごとの上書き。好きなビット数や 3 値（1.58 ビット）を真似る量子化 |
| 実験室: 変換と合成 | Hugging Face のモデルを MLX に変換、LoRA の焼き込み、2 つのモデルを混ぜる（linear、slerp） |
| 実験室: 枝刈り | 層を取り除く、ヘッドの出力を 0 にする |
| 実験室: 評価 | いくつかのモデルを、同じノートのパープレキシティと、同じプロンプトの生成で比べる |
| 実験室: スクリプト | エンジンの中で Python を書いて実行する。載せたモデルを直接触れ、出力、表、図を見られる（[ADR 0014](adr/0014-forge-and-scratch.md)） |
| 実験室: 記録 | 実行するたびに残した、モデル、プロンプト、設定、結果の要約 |
| 画像生成 | mflux（FLUX.2 klein 4B、Z-Image Turbo）で生成し、履歴を一覧する。同じ設定でもう一度作れる |

## 11. テスト

- **実装した後に書く**（TDD にはしない）。ただし、層ごとに漏れなく書く
- Swift Testing を基本にする。UI テストだけ XCTest を使う

| 対象 | 内容 |
|---|---|
| Domain | 純粋なロジック（正規化、スコア計算、グラフのアルゴリズム）。パラメータ化テストを多用する |
| UseCase | Repository を偽物に差し替え、処理の流れを検証する |
| ViewModel | UseCase を偽物に差し替え、状態の変化を検証する |
| Data | SwiftData はメモリ上の DB で実際に動かす。Mapper の往復変換も検証する |
| Metal | レイアウトのシェーダーと CPU の参照実装の結果が一致するかを検証する |
| Markdown の解析 | 索引用、閲覧用、エディタ用の 3 つの解析を、日本語を含む入力で検証する（位置のずれ、数式とコードの保護） |
| エディタ | 本物の `NSTextView` で、ライブプレビューの記号の隠し方、色づけ、リンクの属性を検証する |
| WebKit | 本物の `WebPage` で Vault の HTML ファイルを開く |
| エンジン | API の約束事を Swift と Python の両側から検証する |
| 画面 | スナップショットテストと、主要な操作の UI テスト |

- `make test` でパッケージ、アプリ、Python のテストをまとめて走らせる。`make test-ui` で UI テスト
- 本物のエンジンを起動する結合テストは、`SUNDESK_INTEGRATION=1` のときだけ走る（`make test-integration`、CI では常に走らせる）
- CI（GitHub Actions）はプルリクエストごとに、lint、テスト、カバレッジの集計を行う

## 12. 未決事項

- [ ] ライブプレビューで数式を画像にして見せるか（今は色を変えたソースのまま）
- [ ] 大きなテンソル（Attention の行列など）の転送形式（フェーズ 4）
- [ ] CodeQL の Swift 対応（CodeQL が Swift 6.4 に対応したら加える）
