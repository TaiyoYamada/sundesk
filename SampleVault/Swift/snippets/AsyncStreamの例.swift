import Foundation

/// 1 秒ごとに現在時刻を流す AsyncStream。
func ticks(count: Int) -> AsyncStream<Date> {
    AsyncStream { continuation in
        let task = Task {
            for _ in 0..<count {
                continuation.yield(.now)
                try? await Task.sleep(for: .seconds(1))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

for await date in ticks(count: 3) {
    print(date.formatted(date: .omitted, time: .standard))
}
