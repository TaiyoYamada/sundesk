//
//  EngineProcess.swift
//  SundeskEngine
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import OSLog
import Subprocess
import System

public enum EngineProcessError: Error, Sendable, Equatable {
    case uvNotFound(path: String)
    case engineDirectoryNotFound(path: String)
    case portUnavailable
    case launchFailed(String)
    /// 起動中、または稼働中にプロセスが終了した。`detail` は終了コードと標準エラーの末尾。
    case terminated(detail: String)
    case timedOut
}

/// Python エンジンのプロセスを起動し、止まるまで見守る。
///
/// エンジンは `uv run` で起動する。uv が仮想環境の作成と依存関係の同期を済ませてから
/// エンジンを立ち上げるので、アプリ側で Python の環境を気にする必要がない。
public actor EngineProcess {
    public enum State: Sendable, Equatable {
        case stopped
        case starting
        case running(EngineHealth)
        case failed(EngineProcessError)
    }

    public private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            for continuation in observers.values { continuation.yield(state) }
        }
    }

    /// 起動しているときだけ値がある。
    public private(set) var client: EngineClient?

    private let configuration: @Sendable () -> EngineConfiguration
    private var runTask: Task<Void, Never>?
    private var isStopping = false
    private var observers: [UUID: AsyncStream<State>.Continuation] = [:]

    /// - Parameter configuration: 起動のたびに呼ぶ。設定の変更は次の起動から反映される。
    public init(configuration: @escaping @Sendable () -> EngineConfiguration) {
        self.configuration = configuration
    }

    /// 現在の状態を最初に流し、その後は変化するたびに流す。
    public func states() -> AsyncStream<State> {
        let (stream, continuation) = AsyncStream.makeStream(of: State.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    public func start() async throws(EngineProcessError) {
        switch state {
        case .running, .starting: return
        case .stopped, .failed: break
        }

        let configuration = configuration()
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: configuration.uvExecutable.path) else {
            throw fail(.uvNotFound(path: configuration.uvExecutable.path))
        }
        guard fileManager.fileExists(atPath: configuration.engineDirectory.appending(path: "pyproject.toml").path)
        else {
            throw fail(.engineDirectoryNotFound(path: configuration.engineDirectory.path))
        }
        guard let port = PortAllocator.freeLoopbackPort() else { throw fail(.portUnavailable) }

        state = .starting
        let token = UUID().uuidString
        let client = EngineClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!, token: token)

        let signpostID = Log.signposter.makeSignpostID()
        let interval = Log.signposter.beginInterval("エンジンの起動", id: signpostID)
        defer { Log.signposter.endInterval("エンジンの起動", interval) }
        Log.process.info("エンジンを起動する: port=\(port, privacy: .public)")

        runTask = Task {
            let outcome = await Self.run(configuration: configuration, port: port, token: token)
            self.processDidExit(outcome)
        }

        let deadline = ContinuousClock.now + configuration.startupTimeout
        while ContinuousClock.now < deadline {
            if case .failed(let error) = state { throw error }
            guard case .starting = state else { return }  // 起動中に stop() された

            if let health = try? await client.health() {
                self.client = client
                state = .running(health)
                Log.process.info("エンジンが応答した: version=\(health.version, privacy: .public)")
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        await stop()
        throw fail(.timedOut)
    }

    public func stop() async {
        guard let runTask else {
            state = .stopped
            return
        }
        isStopping = true
        Log.process.info("エンジンを停止する")
        runTask.cancel()
        await runTask.value
        self.runTask = nil
        client = nil
        isStopping = false
        state = .stopped
    }

    // MARK: - 内部

    private func fail(_ error: EngineProcessError) -> EngineProcessError {
        state = .failed(error)
        Log.process.error("エンジンを起動できない: \(String(describing: error), privacy: .public)")
        return error
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func processDidExit(_ outcome: Outcome) {
        runTask = nil
        client = nil
        guard !isStopping else { return }

        switch outcome {
        case .exited(let status, let stderrTail):
            let detail = ([status] + stderrTail.suffix(5)).joined(separator: "\n")
            Log.process.error("エンジンが終了した: \(detail, privacy: .public)")
            state = .failed(.terminated(detail: detail))
        case .launchFailed(let message):
            Log.process.error("エンジンを起動できない: \(message, privacy: .public)")
            state = .failed(.launchFailed(message))
        case .cancelled:
            state = .stopped
        }
    }

    private enum Outcome: Sendable {
        case exited(status: String, stderrTail: [String])
        case launchFailed(String)
        case cancelled
    }

    /// プロセスを起動し、終了するまで出力をログに流す。
    ///
    /// 呼び出し元のタスクがキャンセルされると、Subprocess が SIGTERM を送り、
    /// 5 秒たっても終わらなければ強制終了する。
    @concurrent
    private static func run(configuration: EngineConfiguration, port: Int, token: String) async -> Outcome {
        var options = PlatformOptions()
        options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(5))]

        do {
            let result = try await Subprocess.run(
                .path(FilePath(configuration.uvExecutable.path)),
                arguments: [
                    "run", "--project", configuration.engineDirectory.path,
                    "sundesk-engine", "--host", "127.0.0.1", "--port", String(port),
                ],
                environment: .inherit.updating([
                    "SUNDESK_ENGINE_TOKEN": token,
                    // アプリが強制終了されても、エンジンがこれを見て自分で終了する
                    "SUNDESK_PARENT_PID": String(ProcessInfo.processInfo.processIdentifier),
                    "PYTHONUNBUFFERED": "1",
                ]),
                workingDirectory: FilePath(configuration.engineDirectory.path),
                platformOptions: options,
                input: .none,
                output: .sequence,
                error: .sequence
            ) { execution in
                async let stdout: Void = {
                    for try await line in execution.standardOutput.strings() {
                        Log.output.info("\(line, privacy: .public)")
                    }
                }()
                var tail: [String] = []
                for try await line in execution.standardError.strings() {
                    Log.output.notice("\(line, privacy: .public)")
                    tail.append(line)
                    if tail.count > 20 { tail.removeFirst() }
                }
                try await stdout
                return tail
            }
            if Task.isCancelled { return .cancelled }
            return .exited(status: "終了コード: \(result.terminationStatus)", stderrTail: result.closureResult)
        } catch {
            if Task.isCancelled || error is CancellationError { return .cancelled }
            return .launchFailed(error.localizedDescription)
        }
    }
}
