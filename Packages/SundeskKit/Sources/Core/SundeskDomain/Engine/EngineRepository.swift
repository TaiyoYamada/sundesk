//
//  EngineRepository.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

/// AI エンジンの起動と停止、状態の監視を担う。
///
/// 実装は Data 層にある。Domain はエンジンが Python で書かれていることを知らない。
public protocol EngineRepository: Sendable {
    /// エンジンを起動し、応答が返るまで待つ。すでに起動していれば何もしない。
    func start() async throws(EngineFailure)

    /// エンジンを止める。止まっていれば何もしない。
    func stop() async

    /// 現在の状態を最初に流し、その後は変化するたびに流す。
    func statusUpdates() async -> AsyncStream<EngineStatus>
}
