//
//  RankedVectorTests.swift
//  SwiftCloneDetectorKitTests
//
//  The fixed kind order behind reproducible scoring, and the merge that
//  intersects two vectors held in it.
//

@testable import SwiftCloneDetectorKit
import SwiftSyntax
import Testing

@Suite("RankedVector")
struct RankedVectorTests {
    private func vector(_ kinds: [SyntaxKind: Int]) -> CharacteristicVector {
        var built = CharacteristicVector()
        for (kind, count) in kinds {
            for _ in 0..<count {
                built.add(kind)
            }
        }
        return built
    }

    private func ranked(_ vectors: [CharacteristicVector], _ weights: KindWeights = .uniform) -> [RankedVector] {
        let ranking = KindRanking(over: vectors)
        return vectors.map { ranking.ranked($0, weights: weights) }
    }

    // Why the order is derived from the case name: it is the only identity
    // `SyntaxKind` exposes that is stable across processes. Hash values are not —
    // Swift reseeds dictionary hashing per run, which is what made scoring
    // irreproducible in the first place.
    @Test("kinds rank by case name, so the order is the same in every process")
    func ranksFollowCaseName() {
        let corpus = [vector([.whileStmt: 1, .functionCallExpr: 1, .guardStmt: 1])]
        let entries = ranked(corpus)[0].entries

        #expect(entries.map(\.rank) == [0, 1, 2])
        // functionCallExpr < guardStmt < whileStmt, alphabetically.
        let names = [SyntaxKind.functionCallExpr, .guardStmt, .whileStmt].map { String(describing: $0) }
        #expect(names == names.sorted())
    }

    @Test("entries come out ascending by rank, which is what the merge relies on")
    func entriesAreSorted() {
        let corpus = [vector([.whileStmt: 3, .functionCallExpr: 2, .guardStmt: 1, .memberAccessExpr: 4])]
        let ranks = ranked(corpus)[0].entries.map(\.rank)
        #expect(ranks == ranks.sorted())
        #expect(ranks.count == 4)
    }

    // The merge walks both operands in rank order regardless of which is passed
    // first, so the two directions agree bit for bit. The dictionary version it
    // replaced walked whichever vector had fewer kinds, so it had no such
    // guarantee.
    @Test("similarity is exactly symmetric")
    func similarityIsSymmetric() {
        let lhs = vector([.functionCallExpr: 7, .whileStmt: 3, .guardStmt: 1])
        let rhs = vector([.functionCallExpr: 4, .memberAccessExpr: 9, .whileStmt: 1])
        let corpus = ranked([lhs, rhs], KindWeights.rarity(over: [lhs, rhs]))

        #expect(RankedVector.similarity(corpus[0], corpus[1])
            == RankedVector.similarity(corpus[1], corpus[0]))
    }

    @Test("a vector is identical to itself and disjoint vectors score zero")
    func boundsHold() {
        let lhs = vector([.functionCallExpr: 3, .whileStmt: 2])
        let rhs = vector([.guardStmt: 4])
        let corpus = ranked([lhs, rhs])

        #expect(RankedVector.similarity(corpus[0], corpus[0]) == 1.0)
        #expect(RankedVector.similarity(corpus[0], corpus[1]) == 0.0)
    }

    // Guards the merge against silently dropping or double-counting a shared
    // kind: under uniform weights the result must equal plain Sørensen–Dice,
    // 2·|A ∩ B| / (|A| + |B|), worked out by hand.
    @Test("the merge reproduces Sørensen–Dice computed by hand")
    func matchesHandComputedDice() {
        // Shared: functionCallExpr min(4, 2) = 2, whileStmt min(1, 3) = 1.
        // Totals: 5 and 9. So 2·3 / 14.
        let lhs = vector([.functionCallExpr: 4, .whileStmt: 1])
        let rhs = vector([.functionCallExpr: 2, .whileStmt: 3, .guardStmt: 4])
        let corpus = ranked([lhs, rhs])

        #expect(abs(RankedVector.similarity(corpus[0], corpus[1]) - (6.0 / 14.0)) < 1e-12)
        #expect(abs(RankedVector.similarity(corpus[0], corpus[1]) - lhs.similarity(to: rhs)) < 1e-12)
    }

    @Test("an empty vector scores zero rather than dividing by zero")
    func emptyVectorScoresZero() {
        let corpus = ranked([CharacteristicVector(), vector([.functionCallExpr: 2])])
        #expect(RankedVector.similarity(corpus[0], corpus[1]) == 0)
        #expect(RankedVector.similarity(corpus[0], corpus[0]) == 0)
    }
}
