//
//  ExperimentHeadlineTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskDomain
import Testing

@Suite("一覧に出す実験の指標")
struct ExperimentHeadlineTests {
    private func experiment(metrics: [String: Double], objective: String? = nil) -> ResearchExperiment {
        ResearchExperiment(
            key: "k", title: "t", algorithm: "SA", problem: "p", status: .done, created: nil, finished: nil, tags: [],
            parameters: [:], seeds: [],
            objective: objective.map { Objective(name: $0, minimizes: false, reference: nil) },
            metrics: metrics, series: [], attachments: [], links: [])
    }

    @Test("目的の名前を含む指標を選ぶ")
    func prefersObjective() {
        let metrics: [String: Double] = ["time_seconds": 1, "best_cut": 671, "success_rate": 1]
        #expect(experiment(metrics: metrics, objective: "success").headlineMetric?.name == "success_rate")
    }

    @Test("目的がなければ best で始まる指標、それもなければ所要時間以外を選ぶ")
    func fallsBack() {
        #expect(experiment(metrics: ["time_seconds": 1, "best_cut": 671]).headlineMetric?.name == "best_cut")
        #expect(experiment(metrics: ["time_seconds": 1, "mean_cut": 660]).headlineMetric?.name == "mean_cut")
        #expect(experiment(metrics: ["time_seconds": 1]).headlineMetric?.name == "time_seconds")
        #expect(experiment(metrics: [:]).headlineMetric == nil)
    }

    @Test("同じ優先度なら名前の順に決める（毎回同じものを選ぶ）")
    func isStable() {
        let metrics: [String: Double] = ["b_metric": 2, "a_metric": 1, "time_seconds": 3]
        for _ in 0..<20 {
            #expect(experiment(metrics: metrics).headlineMetric?.name == "a_metric")
        }
    }
}
