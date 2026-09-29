# ADR（Architecture Decision Record）

設計上の大きな判断を、理由と一緒に残す。一度決めた ADR は書き換えず、
判断を変えるときは新しい ADR を作り、古いほうの「状態」を「置き換え済み」にする。

| 番号 | タイトル | 状態 |
|---|---|---|
| [0001](0001-clean-architecture-mvvm.md) | Clean Architecture と MVVM を採用する | 採用 |
| [0002](0002-swift-app-with-python-engine.md) | 画面は Swift、AI と解析は Python のエンジンに分ける | 採用 |
| [0003](0003-swiftdata-single-source-of-truth.md) | SwiftData を唯一の DB にし、エンジンは状態を持たない | 採用 |
| [0004](0004-factory-composition-root.md) | DI に Factory を使い、登録は Composition Root モジュールにまとめる | 採用 |
| [0005](0005-metal-knowledge-graph.md) | 知識グラフは Metal で描く | 採用 |
| [0006](0006-engine-http-over-loopback.md) | エンジンとは 127.0.0.1 の HTTP で、起動ごとのトークンを付けて通信する | 採用 |
| [0007](0007-engine-process-lifecycle.md) | エンジンは uv で起動し、アプリと寿命をそろえる | 採用 |

新しく書くときは [template.md](template.md) を写して使う。
