//
//  IdentifierMetricsTests.swift
//  SwiftCloneDetectorKitTests
//
//  Covers the identifier-overlap metric behind --min-identifier-overlap, and the
//  rarity weights that keep names every file uses from deciding it.
//

@testable import SwiftCloneDetectorKit
import SwiftParser
import SwiftSyntax
import Testing

@Suite("IdentifierMetrics")
struct IdentifierMetricsTests {
    @Test("the same names overlap fully")
    func identicalSets() {
        #expect(identifierOverlap(["total", "items"], ["items", "total"], weights: .uniform) == 1)
    }

    @Test("disjoint names do not overlap at all")
    func disjointSets() {
        #expect(identifierOverlap(["total", "items"], ["name", "trimmed"], weights: .uniform) == 0)
    }

    @Test("overlap is shared names over all names")
    func partialOverlap() {
        // Shared: wrap, input, scaled. All: value, amount, wrap, input, scaled.
        let lhs: Set = ["value", "wrap", "input", "scaled"]
        let rhs: Set = ["amount", "wrap", "input", "scaled"]
        #expect(identifierOverlap(lhs, rhs, weights: .uniform) == 0.6)
    }

    @Test("two fragments that name nothing have no naming to disagree on")
    func emptySets() {
        #expect(identifierOverlap([], [], weights: .uniform) == 1)
    }

    // `String` is in every file, so sharing it says little; the two fragments'
    // own names are each in one file.
    @Test("a name every file uses counts for less than a rare one")
    func commonNamesWeighLess() {
        let files = [
            "let invoice: String = number",
            "let satellite: String = callSign",
            "let label: String = title"
        ].map { Syntax(Parser.parse(source: $0)) }
        let weights = IdentifierWeights.rarity(over: files)
        #expect(weights.weight("String") < weights.weight("invoice"))

        let lhs: Set = ["String", "invoice", "number"]
        let rhs: Set = ["String", "satellite", "callSign"]
        #expect(identifierOverlap(lhs, rhs, weights: weights) < identifierOverlap(lhs, rhs, weights: .uniform))
    }
}
