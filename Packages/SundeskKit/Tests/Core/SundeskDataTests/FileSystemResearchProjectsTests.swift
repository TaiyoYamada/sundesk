//
//  FileSystemResearchProjectsTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain
import Testing

@testable import SundeskData

@Suite("~/Research の実験を見つける")
struct FileSystemResearchProjectsTests {
    @Test("config.json か CSV のあるフォルダを 1 回の実行とみなし、その下は実行の一部にする")
    func findsRuns() async throws {
        let research = try TemporaryVault(files: [
            "experiment/demo/README.md": "# 最適化器の比較\n\n小さな問題で最適化器を比べる。\n\n## 構成\n",
            "experiment/demo/docs/design.md": "# 設計",
            "experiment/demo/notebooks/run.ipynb": "{}",
            "experiment/demo/notebooks/out.csv": "a\n1",
            "experiment/demo/results/runs/2026-01-02_030405/config.json":
                #"{"sizes": [4, 8], "repeats": 5, "noisy": true, "step": {"a": 0.1}}"#,
            "experiment/demo/results/runs/2026-01-02_030405/history.csv": "function,seed,evals,best\nsphere,1,1,3.0",
            "experiment/demo/results/runs/2026-01-02_030405/tables/t.csv": "x\n1",
            "experiment/demo/results/runs/2026-01-02_030405/figures/box.png": "",
            "experiment/demo/results/runs/2026-01-02_030405/figures/box.pdf": "",
            "experiment/demo/results/runs/2026-01-02_030405/comments.md": "# 所見",
            "experiment/demo/results/trials/t1/results.csv": "a\n1",
            "experiment/notes-only/README.md": "# 資料集",
        ])
        defer { research.remove() }
        let repository = FileSystemResearchProjects(mounts: {
            [VaultMount(name: "Research", url: research.url)]
        })

        let projects = await repository.projects()

        #expect(projects.map(\.name) == ["demo", "notes-only"])
        let demo = try #require(projects.first)
        #expect(demo.title == "最適化器の比較")
        #expect(demo.summary == "小さな問題で最適化器を比べる。")
        #expect(demo.documents == ["Research/experiment/demo/README.md", "Research/experiment/demo/docs/design.md"])
        // 名前に日時がない実行は更新日時（今）になるので、新しい順では先に来る
        #expect(demo.runs.map(\.relativePath) == ["results/trials/t1", "results/runs/2026-01-02_030405"])
        let run = try #require(demo.runs.first { $0.relativePath.hasPrefix("results/runs") })
        #expect(run.path == "Research/experiment/demo/results/runs/2026-01-02_030405")
        #expect(run.tables.map(\.name) == ["history.csv", "tables/t.csv"])
        #expect(run.figures == ["Research/experiment/demo/results/runs/2026-01-02_030405/figures/box.png"])
        #expect(run.notes == ["Research/experiment/demo/results/runs/2026-01-02_030405/comments.md"])
        #expect(run.parameters["sizes"] == .text("4, 8"))
        #expect(run.parameters["repeats"] == .number(5))
        #expect(run.parameters["noisy"] == .flag(true))
        #expect(run.parameters["step.a"] == .number(0.1))
        let date = try #require(run.date)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(
            [components.year, components.month, components.day, components.hour, components.minute]
                == [2026, 1, 2, 3, 4])
    }

    @Test(
        "フォルダ名から日時を読む",
        arguments: [
            ("2026-01-02_0304", "2026-01-02 03:04"), ("20260102_030405_small_run", "2026-01-02 03:04"),
            ("2026-01-02_trial", "2026-01-02 00:00"), ("round3_check", nil),
        ])
    func parsesFolderDates(name: String, expected: String?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        #expect(FileSystemResearchProjects.date(fromFolderName: name).map(formatter.string) == expected)
    }
}
