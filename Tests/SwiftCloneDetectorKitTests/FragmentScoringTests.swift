//
//  FragmentScoringTests.swift
//  SwiftCloneDetectorKitTests
//
//  How much distinguishing structure a fragment carries, and when that number
//  means nothing at all.
//

@testable import SwiftCloneDetectorKit
import SwiftSyntax
import Testing

@Suite("FragmentScoring.distinctiveness")
struct FragmentScoringTests {
    private func vector(_ kinds: [SyntaxKind: Int]) -> CharacteristicVector {
        var built = CharacteristicVector()
        for (kind, count) in kinds {
            for _ in 0..<count {
                built.add(kind)
            }
        }
        return built
    }

    // The measure the trivial-structure gate rests on: a fragment built only from
    // constructs every other fragment also uses says nothing by matching.
    @Test("a fragment of only ubiquitous kinds scores 1")
    func ubiquitousScoresOne() {
        let common = vector([.functionCallExpr: 6, .memberAccessExpr: 6])
        let corpus = Array(repeating: common, count: 12)
        let scoring = FragmentScoring(vectors: corpus, useRarityWeighting: true)
        #expect(abs(scoring.distinctiveness(0) - 1.0) < 0.0001)
    }

    @Test("a fragment using a rare construct scores higher")
    func rareScoresHigher() {
        let plain = vector([.functionCallExpr: 6, .memberAccessExpr: 6])
        let unusual = vector([.functionCallExpr: 6, .whileStmt: 6])
        let corpus = [unusual] + Array(repeating: plain, count: 20)
        let scoring = FragmentScoring(vectors: corpus, useRarityWeighting: true)
        #expect(scoring.distinctiveness(0) > scoring.distinctiveness(1))
        #expect(scoring.distinctiveness(1) < 1.05)
    }

    @Test("uniform weighting makes every fragment equally distinctive")
    func uniformIsFlat() {
        let corpus = [vector([.functionCallExpr: 6]), vector([.whileStmt: 6])]
        let scoring = FragmentScoring(vectors: corpus, useRarityWeighting: false)
        #expect(scoring.distinctiveness(0) == scoring.distinctiveness(1))
    }

    @Test("an empty fragment is not distinctive")
    func emptyScoresZero() {
        let scoring = FragmentScoring(vectors: [CharacteristicVector()], useRarityWeighting: true)
        #expect(scoring.distinctiveness(0) == 0)
    }

    // The floor rests on "rare in this codebase", and a handful of fragments is
    // not a codebase. Without this guard the default floor silenced every run
    // over a small input — the complete-linkage tests caught it.
    @Test("rarity says nothing about a corpus too small to have a shape")
    func smallCorpusIsNotMeaningful() {
        let three = Array(repeating: vector([.functionCallExpr: 6]), count: 3)
        #expect(FragmentScoring(vectors: three, useRarityWeighting: true).rarityIsMeaningful == false)
    }

    // Under uniform weighting every fragment scores exactly 1, so any floor above
    // that would suppress the entire run rather than its least distinctive part.
    @Test("rarity says nothing when weighting is uniform")
    func uniformIsNotMeaningful() {
        let many = Array(repeating: vector([.functionCallExpr: 6]), count: 60)
        #expect(FragmentScoring(vectors: many, useRarityWeighting: false).rarityIsMeaningful == false)
        #expect(FragmentScoring(vectors: many, useRarityWeighting: true).rarityIsMeaningful)
    }
}
