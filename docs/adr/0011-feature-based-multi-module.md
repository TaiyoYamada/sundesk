# 0011. 機能ごとのマルチモジュールにし、アプリのターゲットは起動だけにする

- 状態: 採用
- 日付: 2026-09-29

## 背景

フェーズ 0 では、層ごとに 5 つのモジュール（Domain、Engine、Data、Presentation、Composition）を作り、
View はアプリのターゲットに置いていた。今後、知識グラフ、RAG、LLM 実験室、画像生成と機能が増える。
大きくなっても見通しよく開発できる構成に、今のうちに移したい。

また、アーキテクチャを点検したところ、次のずれがあった。

- View が Domain の型や設定を直接触っている
- 描画の判断（何で描くか）が View にある
- ViewModel が UseCase を組み合わせている（UseCase の役目）
- typed throws が一部だけ
- 監視の仕組み（`ResultsObserver`）の記述が実装と合っていない

## 決定

ローカルの Swift Package（`Packages/SundeskKit`）の中を、5 つのグループに分ける。

| グループ | モジュール | 役目 |
|---|---|---|
| App | AppFeature | 画面全体の組み立てと DI（Composition Root）。全モジュールを知る唯一の場所 |
| Features | WorkspaceFeature、NotesFeature、EngineFeature、SettingsFeature | 機能ごとの Presentation 層（ViewModel と View） |
| Core | SundeskDomain、SundeskData、SundeskDesignSystem | Entity と UseCase、Repository の実装、共通の画面部品 |
| Infrastructure | SundeskEngineClient、SundeskMarkdown、SundeskCodeHighlight | 外部の技術を包む |
| UI | SundeskEditorUI、SundeskWebView | 機能をまたいで使う画面の部品 |

- アプリのターゲットは `@main` だけにし、`AppFeature` の `SundeskScenes` を表示する
- Features どうしは依存しない。ただし WorkspaceFeature は、ウインドウに並べるために NotesFeature と EngineFeature を使う
- Features は Data と Infrastructure と FactoryKit を import しない。必要なものは `WorkspaceDependencies` やコンストラクタで受け取る
- 画面のモジュールは既定で MainActor（`.defaultIsolation(MainActor.self)`）、Core と Infrastructure は既定で nonisolated
- 依存の向きはコンパイラ（Package.swift）が守る。同じモジュールの中の決まりは SwiftLint の独自ルールで守る
  - `view_imports_domain`: `Views/` の下のファイルは SundeskDomain を import しない
  - `domain_imports_framework`: Domain は SwiftUI、AppKit、SwiftData、WebKit、Combine を import しない
  - `feature_imports_data`: Features は Data、Infrastructure、FactoryKit を import しない

## 検討した選択肢

| 選択肢 | 良い点 | 悪い点 |
|---|---|---|
| **機能ごとのマルチモジュール（この決定）** | 機能を足しても影響が閉じる。ビルドが速い。依存をコンパイラが守る | モジュールの数が多い。`public` を付ける手間 |
| 層ごとの 5 モジュール（フェーズ 0） | 数が少なく分かりやすい | Presentation と View が機能の数だけ太る |
| アプリのターゲット 1 つの中でフォルダを分ける | 手軽 | 依存のルールを守らせる仕組みがない |

## 結果

- [ADR 0001](0001-clean-architecture-mvvm.md) の「View はアプリのターゲットに置く」と、
  [ADR 0004](0004-factory-composition-root.md) の「登録は SundeskComposition にまとめる」は、それぞれ
  「View は機能のモジュールに置く」「登録は AppFeature にまとめる」に読み替える
- Xcode では、ナビゲータの SundeskKit の下にグループごとのフォルダとして見える
