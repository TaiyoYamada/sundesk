# 0004. DI に Factory を使い、登録は Composition Root モジュールにまとめる

- 状態: 採用
- 日付: 2026-09-29

## 背景

実務に近い形にするため、DI には手書きではなくライブラリを使う。一方で、Clean Architecture の
内側の層（Domain）はライブラリに依存させたくない。

## 決定

- DI コンテナに [Factory](https://github.com/hmlongco/Factory) 3 系を使う
- コンテナへの登録は `SundeskComposition` モジュールにまとめる。すべての層を知っているのは
  このモジュールだけ
- Domain、Data、Presentation は Factory を import しない。依存はコンストラクタで受け取る
- アプリ本体（View）は `@InjectedObservable` などで ViewModel を受け取る。
  `SundeskComposition` が `FactoryKit` を再公開している

## 検討した選択肢

| 選択肢 | 良い点 | 悪い点 |
|---|---|---|
| 手書きのコンストラクタ注入 | 依存が増えない | 組み立てのコードが増え、テストでの差し替えも手作業 |
| **Factory** | 定番の DI コンテナ。Swift 6 と Swift Testing に対応。活発に保守されている | コンテナの外で依存を解決しないよう、書き方の規律が要る |
| swift-dependencies | テストで差し替え忘れを検出できる | TCA 系の設計と組み合わせる前提の作り |
| Swinject | 昔からの定番 | 1 年以上更新がない |

## 結果

- Composition Root 自体を `swift test` でテストできる（シングルトンの共有、差し替え）
- テストでは `@Suite(.container)` で、テストごとに新しいコンテナを使う
