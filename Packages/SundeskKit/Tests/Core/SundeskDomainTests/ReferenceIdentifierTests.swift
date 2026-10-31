//
//  ReferenceIdentifierTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Testing

@testable import SundeskDomain

@Suite("識別子の読み取り")
struct ReferenceIdentifierTests {
    @Test(
        "DOI",
        arguments: [
            ("10.1038/ncomms5213", "10.1038/ncomms5213"),
            ("doi:10.1038/ncomms5213", "10.1038/ncomms5213"),
            ("https://doi.org/10.1145/3292500.3330701", "10.1145/3292500.3330701"),
            ("  https://dx.doi.org/10.1038/ncomms5213.  ", "10.1038/ncomms5213"),
        ])
    func doi(input: String, expected: String) {
        #expect(ReferenceIdentifier(parsing: input) == .doi(expected))
    }

    @Test(
        "arXiv の ID（版の番号は落とす）",
        arguments: [
            ("1304.3061", "1304.3061"),
            ("arXiv:2101.00001v2", "2101.00001"),
            ("https://arxiv.org/abs/2101.00001", "2101.00001"),
            ("https://arxiv.org/pdf/2101.00001v3.pdf", "2101.00001"),
            ("quant-ph/0101001", "quant-ph/0101001"),
            ("math.GT/0309136v1", "math.GT/0309136"),
        ])
    func arxiv(input: String, expected: String) {
        #expect(ReferenceIdentifier(parsing: input) == .arxiv(expected))
    }

    @Test(
        "ISBN（検査の数字が合うものだけ）",
        arguments: [
            ("978-0-262-03561-3", "9780262035613"),
            ("ISBN 0262035618", "0262035618"),
            ("ISBN: 0-8044-2957-X", "080442957X"),
        ])
    func isbn(input: String, expected: String) {
        #expect(ReferenceIdentifier(parsing: input) == .isbn(expected))
    }

    @Test("読めないもの", arguments: ["", "量子アニーリング", "978-0-262-03561-4", "12345"])
    func invalid(input: String) {
        #expect(ReferenceIdentifier(parsing: input) == nil)
    }
}
