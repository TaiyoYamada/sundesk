//
//  EngineMapper.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import SundeskEngine

/// Infrastructure 層の型を Domain の Entity に変換する。
enum EngineMapper {
    static func status(from state: EngineProcess.State) -> EngineStatus {
        switch state {
        case .stopped:
            .stopped
        case .starting:
            .starting
        case .running(let health):
            .running(EngineInfo(version: health.version, pythonVersion: health.pythonVersion))
        case .failed(let error):
            .failed(failure(from: error))
        }
    }

    static func failure(from error: EngineProcessError) -> EngineFailure {
        let message =
            switch error {
            case .uvNotFound(let path):
                "uv が見つかりません（\(path)）。`brew install uv` で入れるか、設定で場所を指定してください。"
            case .engineDirectoryNotFound(let path):
                "エンジンのフォルダに pyproject.toml がありません（\(path)）。設定でフォルダを指定してください。"
            case .portUnavailable:
                "空いているポートを確保できませんでした。"
            case .launchFailed(let reason):
                "エンジンを起動できませんでした: \(reason)"
            case .terminated(let detail):
                "エンジンが終了しました。\n\(detail)"
            case .timedOut:
                "エンジンが時間内に応答しませんでした。初回は依存関係の取得に時間がかかることがあります。"
            }
        return EngineFailure(message: message)
    }
}
