# sundesk アーキテクチャ

- 状態: ドラフト（話し合いながら更新中）
- 最終更新: 2026-09-29
- 要件は [requirements.md](requirements.md) を参照

## 1. 方針

- **Clean Architecture + MVVM**
  - アプリ全体は Clean Architecture の層に分け、依存は常に内側（Domain）へ向ける
  - 画面は MVVM で作る。ViewModel が UseCase を呼び、戻り値（または `AsyncSequence`）を受け取って表示用の状態に整える
- **依存のルールはコンパイラに守らせる。** 層ごとに Swift Package のモジュールを分け、内側から外側を import できないようにする
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
│  Metal レンダラ、エンジンのプロセス管理、ファイル監視          │
└────────────────────────────────────────────────────────┘

依存の向き: Presentation → Domain ← Data → Infrastructure
組み立て: App ターゲット（Composition Root）が全部をつなぐ
```

| 層 | 知ってよいもの | 知ってはいけないもの |
|---|---|---|
| Domain | Swift 標準ライブラリ、Foundation の基本型 | SwiftUI、SwiftData、Metal、エンジン |
| Presentation | Domain | SwiftData、エンジン、Data 層の型 |
| Data | Domain、SwiftData、Infrastructure | SwiftUI、ViewModel |
| Infrastructure | Metal、Subprocess、FSEvents など | Domain 以外のアプリの型 |

### 約束事

- **SwiftData の `@Model` は Data 層の外に出さない。** 境界で Mapper を通して Domain の Entity（`Sendable` な struct）に変換する
- **View は `@Query` を使わない。** データの変化は Data 層で `ResultsObserver` を使って監視し、Repository が `AsyncSequence` として流す
- **UseCase は 1 つの操作につき 1 つ。** `callAsFunction` で呼べるようにする
- **DI は手書きのコンストラクタ注入。** DI コンテナのライブラリは入れない。組み立ては App ターゲットの Composition Root で一か所にまとめる
- **エラーは層ごとに型を決める。** typed throws を使い、層の境界で変換する

## 3. モジュール構成

```
sundesk/
├── sundesk.xcodeproj
├── sundesk/                      App ターゲット
│   ├── App/                      @main、Composition Root、ウインドウ、メニュー
│   └── Views/                    SwiftUI の View（機能ごとのフォルダ）
├── Packages/SundeskKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── SundeskDomain/        Entity、UseCase、Repository の protocol
│   │   ├── SundeskPresentation/  ViewModel（UI に依存しないのでテストしやすい）
│   │   ├── SundeskData/          Repository の実装、SwiftData のスキーマ、Mapper
│   │   ├── SundeskEngine/        AI エンジンとの接続（DataSource）
│   │   └── SundeskGraphRenderer/ Metal による知識グラフの描画
│   └── Tests/                    モジュールごとのテスト
├── engine/                       Python エンジン（プロセス構成が B 案になった場合）
└── docs/
```

- モジュール名に `Data` を単独で使わない（Foundation の `Data` 型と衝突するため）。すべて `Sundesk` の接頭辞を付ける
- View は App ターゲットに置き、ViewModel は `SundeskPresentation` に置く。こうすると ViewModel を UI 抜きでテストできる

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
| エンジンとの通信、ジョブ管理 | `actor` |
| 逐次の通知（トークン、進捗） | `AsyncSequence` と `ProgressManager` |
| 後始末（モデルの解放など） | `withTaskCancellationShield` |

## 6. 知識グラフの描画（Metal）

- `MTKView` を SwiftUI に埋め込んで描く
- 点と線はインスタンス描画でまとめて描く（数万規模を想定）
- レイアウト（力学モデル）の計算は、Metal のコンピュートシェーダーで行う。反発力の計算は、Barnes-Hut 法かグリッド分割で近似する
- クリックした点の判定、ズーム、パン
- 文字ラベルは、重要な点（PageRank の上位など）だけに付ける
  - 描き方（グリフのアトラスを作って Metal で描くか、SwiftUI を重ねるか）は試作して決める
- テストでは、シェーダーの計算結果を CPU の参照実装と比べる

## 7. テスト

- **実装した後に書く**（TDD にはしない）。ただし、層ごとに漏れなく書く
- Swift Testing を基本にする。UI テストだけ XCTest を使う

| 対象 | 内容 |
|---|---|
| Domain | 純粋なロジック（正規化、スコア計算、グラフのアルゴリズム）。パラメータ化テストを多用する |
| UseCase | Repository を偽物に差し替え、処理の流れを検証する |
| ViewModel | UseCase を偽物に差し替え、状態の変化を検証する |
| Data | SwiftData はメモリ上の DB で実際に動かす。Mapper の往復変換も検証する |
| Metal | シェーダーと CPU の参照実装の結果が一致するかを検証する |
| エンジン | API の約束事を Swift と Python の両側から検証する |
| 画面 | スナップショットテストと、主要な操作の UI テスト |

## 8. 未決事項

- [ ] プロセス構成（Swift のみか Swift + Python か）。決まれば `SundeskEngine` と `engine/` の中身が決まる
- [ ] 画面の構成（ウインドウは一つか、複数か）
- [ ] ノートを sundesk で編集するか、読むだけか
- [ ] MVP の範囲と作る順番
