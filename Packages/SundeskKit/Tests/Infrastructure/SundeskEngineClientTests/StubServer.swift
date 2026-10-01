//
//  StubServer.swift
//  SundeskEngineClientTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskEngineClient
import Synchronization

/// URLProtocol を使って、ネットワークに出ずに HTTP の応答を返す。
///
/// テストは並列に走るので、テストごとに別のポート番号を割り当て、
/// そのポートへのリクエストだけに応答する。
struct StubServer {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: String)

    let port: Int

    init(handler: @escaping Handler) {
        port = StubURLProtocol.register(handler)
    }

    func client(token: String = "token") -> EngineClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return EngineClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            token: token,
            session: URLSession(configuration: configuration)
        )
    }
}

final class StubURLProtocol: URLProtocol {
    private static let handlers = Mutex<[Int: StubServer.Handler]>([:])
    private static let nextPort = Atomic<Int>(20_000)

    static func register(_ handler: @escaping StubServer.Handler) -> Int {
        let port = nextPort.add(1, ordering: .relaxed).newValue
        handlers.withLock { $0[port] = handler }
        return port
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let port = request.url?.port ?? -1
        guard let handler = Self.handlers.withLock({ $0[port] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
