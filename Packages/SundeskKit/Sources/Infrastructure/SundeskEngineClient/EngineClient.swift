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
    case decoding(String)
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
        guard (200..<300).contains(http.statusCode) else { throw .unexpectedStatus(http.statusCode) }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
