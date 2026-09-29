//
//  EngineClientTests.swift
//  SundeskEngineTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskEngine
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

@Suite("EngineLocator")
struct EngineLocatorTests {
    @Test("既定のエンジンのフォルダは、リポジトリの engine/ を指す")
    func defaultEngineDirectoryPointsToRepository() {
        let url = EngineLocator.defaultEngineDirectory(
            sourceFile: "/repo/sundesk/Packages/SundeskKit/Sources/SundeskEngine/EngineConfiguration.swift"
        )
        #expect(url.path == "/repo/sundesk/engine")
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
