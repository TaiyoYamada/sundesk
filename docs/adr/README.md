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
| [0008](0008-webkit-renderer.md) | ノートの描画は WebKit の中で markdown-it、KaTeX、Shiki を使う | 置き換え済み（0010） |
| [0009](0009-workspace-layout.md) | 画面は Xcode と Obsidian を合わせた構成にする | 採用 |
| [0010](0010-native-rendering-and-editing.md) | ノートの描画と編集は Swift で行い、WebKit は HTML ファイルだけに使う | 採用 |
| [0011](0011-feature-based-multi-module.md) | 機能ごとのマルチモジュールにし、アプリのターゲットは起動だけにする | 採用 |
| [0012](0012-knowledge-and-rag.md) | 知識は毎回まとめて作り直し、RAG は 3 つの検索を順位で組み合わせる | 採用 |
| [0013](0013-lab-and-image-generation.md) | 実験室は mlx-lm の計算を差し替えて覗き、画像生成は mflux を使う | 採用 |
| [0014](0014-forge-and-scratch.md) | 実験室に工房と Python のスクラッチを置く | 採用 |

新しく書くときは [template.md](template.md) を写して使う。
