//
//  EngineClientTests.swift
//  SundeskEngineClientTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskEngineClient
import Testing

@Suite("EngineClient")
struct EngineClientTests {
    @Test("health はトークンを付けて呼び、snake_case の応答を読む")
    func healthDecodesResponseAndSendsToken() async throws {
        let stub = StubServer { request in
            #expect(request.url?.path == "/health")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            return (200, #"{"status":"ok","version":"0.1.0","python_version":"3.13.7"}"#)
        }

        let health = try await stub.client(token: "secret").health()

        #expect(health == EngineHealth(status: "ok", version: "0.1.0", pythonVersion: "3.13.7"))
    }

    @Test("2xx 以外は unexpectedStatus になる", arguments: [401, 404, 500])
    func nonSuccessStatusThrows(statusCode: Int) async {
        let stub = StubServer { _ in (statusCode, "{}") }

        await #expect(throws: EngineClientError.unexpectedStatus(statusCode)) {
            try await stub.client().health()
        }
    }

    @Test("形の合わない応答は decoding になる")
    func malformedBodyThrowsDecoding() async {
        let stub = StubServer { _ in (200, #"{"status":"ok"}"#) }

        await #expect {
            try await stub.client().health()
        } throws: { error in
            guard case EngineClientError.decoding = error else { return false }
            return true
        }
    }
}

@Suite("EngineClient の JSON と NDJSON")
struct EngineClientJSONTests {
    private struct Request: Encodable {
        let noteTitle: String
    }

    private struct Response: Decodable, Equatable {
        let conceptCount: Int
    }

    private struct Event: Decodable, Equatable, Sendable {
        let type: String
        let text: String?
    }

    /// URLProtocol に届いた本文（httpBody か httpBodyStream のどちらかに入る）。
    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(bytes: data, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("POST は本文を snake_case の JSON にし、応答も snake_case で読む")
    func postEncodesSnakeCase() async throws {
        let stub = StubServer { request in
            #expect(request.httpMethod == "POST")
            #expect(Self.body(of: request) == #"{"note_title":"固有値"}"#)
            return (200, #"{"concept_count":3}"#)
        }

        let response = try await stub.client().post("graph/build", body: Request(noteTitle: "固有値"), as: Response.self)

        #expect(response == Response(conceptCount: 3))
    }

    @Test("失敗の応答は、エンジンのメッセージを返す")
    func serverErrorCarriesDetail() async {
        let stub = StubServer { _ in (422, #"{"detail":"このモデルの構造には対応していません"}"#) }

        await #expect(throws: EngineClientError.server(status: 422, message: "このモデルの構造には対応していません")) {
            try await stub.client().post("lab/attention", body: Request(noteTitle: ""), as: Response.self)
        }
    }

    @Test("NDJSON を 1 行ずつ読み、error の行で失敗にする")
    func streamsLines() async throws {
        let stub = StubServer { _ in
            let lines = [
                #"{"type":"token","text":"固有"}"#, "", #"{"type":"token","text":"値"}"#,
                #"{"type":"error","message":"メモリが足りません"}"#,
            ]
            return (200, lines.joined(separator: "\n") + "\n")
        }
        var events: [Event] = []

        await #expect(throws: EngineClientError.stream("メモリが足りません")) {
            for try await event in stub.client().stream("chat", body: Request(noteTitle: ""), as: Event.self) {
                events.append(event)
            }
        }
        #expect(events == [Event(type: "token", text: "固有"), Event(type: "token", text: "値")])
    }
}

@Suite("EngineLocator")
struct EngineLocatorTests {
    @Test("既定のエンジンのフォルダは、リポジトリの engine/ を指す")
    func defaultEngineDirectoryPointsToRepository() {
        let url = EngineLocator.defaultEngineDirectory(
            sourceFile:
                "/repo/sundesk/Packages/SundeskKit/Sources/Infrastructure/SundeskEngineClient/EngineConfiguration.swift"
        )
        #expect(url.path == "/repo/sundesk/engine")
    }

    @Test("どこから呼んでも、既定のエンジンのフォルダはこのリポジトリの engine/ になる")
    func defaultEngineDirectoryDoesNotDependOnCaller() {
        let url = EngineLocator.defaultEngineDirectory()
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "pyproject.toml").path))
    }

    @Test("決まった場所になければ PATH から uv を探す")
    func findUVSearchesPath() throws {
        let directory = try makeDirectoryWithExecutable(named: "uv")
        defer { try? FileManager.default.removeItem(at: directory) }

        let found = EngineLocator.findUV(
            wellKnownLocations: [URL(filePath: "/nonexistent/uv")],
            environment: ["PATH": "/nonexistent:\(directory.path)"]
        )

        #expect(found == directory.appending(path: "uv"))
    }

    @Test("決まった場所にあれば、PATH より優先する")
    func findUVPrefersWellKnownLocations() throws {
        let wellKnown = try makeDirectoryWithExecutable(named: "uv")
        let onPath = try makeDirectoryWithExecutable(named: "uv")
        defer {
            try? FileManager.default.removeItem(at: wellKnown)
            try? FileManager.default.removeItem(at: onPath)
        }

        let found = EngineLocator.findUV(
            wellKnownLocations: [wellKnown.appending(path: "uv")],
            environment: ["PATH": onPath.path]
        )

        #expect(found == wellKnown.appending(path: "uv"))
    }

    @Test("どこにもなければ nil")
    func findUVReturnsNilWhenMissing() {
        #expect(EngineLocator.findUV(wellKnownLocations: [], environment: ["PATH": "/nonexistent"]) == nil)
    }

    private func makeDirectoryWithExecutable(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: directory.appending(path: name).path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )
        return directory
    }
}
