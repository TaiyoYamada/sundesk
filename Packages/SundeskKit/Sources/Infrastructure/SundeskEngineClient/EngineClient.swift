//
//  EngineClient.swift
//  SundeskEngineClient
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// `GET /health` の応答。
public struct EngineHealth: Decodable, Sendable, Equatable {
    public let status: String
    public let version: String
    public let pythonVersion: String

    public init(status: String, version: String, pythonVersion: String) {
        self.status = status
        self.version = version
        self.pythonVersion = pythonVersion
    }
}

public enum EngineClientError: Error, Sendable, Equatable {
    case transport(String)
    case unexpectedStatus(Int)
    /// エンジンが失敗を返した（`detail` の日本語のメッセージ）。
    case server(status: Int, message: String)
    case decoding(String)
    /// NDJSON の途中で `{"type": "error"}` が届いた。
    case stream(String)

    /// 利用者に見せるメッセージ。
    public var message: String {
        switch self {
        case .transport(let detail): "エンジンに接続できません: \(detail)"
        case .unexpectedStatus(let status): "エンジンが予期しない応答を返しました（\(status)）"
        case .server(_, let message), .stream(let message): message
        case .decoding(let detail): "エンジンの応答を読めません: \(detail)"
        }
    }
}

/// エンジンの HTTP API を呼ぶ。
///
/// エンジンは 127.0.0.1 の空いているポートで待ち受け、起動ごとに発行したトークンで
/// 呼び出し元を確かめる（ADR 0006）。
public struct EngineClient: Sendable {
    public let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func health() async throws(EngineClientError) -> EngineHealth {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 2
        return try await send(request, as: EngineHealth.self)
    }

    /// `GET` して JSON を読む。
    public func get<Response: Decodable>(
        _ path: String, as type: Response.Type, timeout: TimeInterval = 60
    ) async throws(EngineClientError) -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = timeout
        return try await send(request, as: type)
    }

    /// `DELETE` して JSON を読む。
    public func delete<Response: Decodable>(
        _ path: String, as type: Response.Type
    ) async throws(EngineClientError) -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "DELETE"
        return try await send(request, as: type)
    }

    /// JSON を `POST` して、JSON を読む。
    public func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, as type: Response.Type, timeout: TimeInterval = 600
    ) async throws(EngineClientError) -> Response {
        try await send(try jsonRequest(path, body: body, timeout: timeout), as: type)
    }

    /// JSON を `POST` して、NDJSON（1 行に 1 つの JSON）を 1 行ずつ読む。
    ///
    /// `{"type": "error"}` の行が届いたら、`EngineClientError.stream` で終える
    /// （`passesErrorLines` が true なら、ほかの行と同じく `Event` として渡す）。
    public func stream<Body: Encodable, Event: Decodable & Sendable>(
        _ path: String, body: Body, as type: Event.Type, passesErrorLines: Bool = false
    ) -> AsyncThrowingStream<Event, any Error> {
        let session = session
        let request: URLRequest
        do {
            request = try jsonRequest(path, body: body, timeout: 3600)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw EngineClientError.unexpectedStatus(-1) }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.failure(status: http.statusCode, data: data)
                    }
                    for try await line in bytes.lines where !line.isEmpty {
                        let data = Data(line.utf8)
                        if !passesErrorLines, let failure = try? Self.decoder.decode(StreamError.self, from: data),
                            failure.type == "error"
                        {
                            throw EngineClientError.stream(failure.message)
                        }
                        do {
                            continuation.yield(try Self.decoder.decode(Event.self, from: data))
                        } catch {
                            throw EngineClientError.decoding(String(describing: error))
                        }
                    }
                    continuation.finish()
                } catch let error as EngineClientError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: EngineClientError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct StreamError: Decodable {
        let type: String
        let message: String
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }

    private func jsonRequest<Body: Encodable>(
        _ path: String, body: Body, timeout: TimeInterval
    ) throws(EngineClientError) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try Self.encoder.encode(body)
        } catch {
            throw .decoding(String(describing: error))
        }
        return request
    }

    private static func failure(status: Int, data: Data) -> EngineClientError {
        if let body = try? decoder.decode(ErrorBody.self, from: data) {
            return .server(status: status, message: body.detail)
        }
        return .unexpectedStatus(status)
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        as type: Response.Type
    ) async throws(EngineClientError) -> Response {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw .unexpectedStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw Self.failure(status: http.statusCode, data: data) }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
