---
title: Actor
status: 執筆済
tags: [Swift, 並行処理]
---

# Actor

可変状態を守る参照型。外から触るときは `await` が要る。

```swift
actor Counter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
```

## 再入可能性

`await` の前後で状態が変わりうる。**`await` をまたいで前提を持ち越さない。**

関連: [[並行処理]]
