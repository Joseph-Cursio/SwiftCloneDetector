//
//  KindWeightsTests.swift
//  SwiftCloneDetectorKitTests
//
//  Rarity weighting: a node kind every fragment carries must stop deciding
//  whether two fragments are copies of each other.
//

@testable import SwiftCloneDetectorKit
import SwiftSyntax
import Testing

@Suite("KindWeights")
struct KindWeightsTests {
    private func vector(_ kinds: [SyntaxKind: Int]) -> CharacteristicVector {
        var built = CharacteristicVector()
        for (kind, count) in kinds {
            for _ in 0..<count {
                built.add(kind)
            }
        }
        return built
    }

    @Test("an unseen kind weighs 1, so nothing is silently discounted")
    func unseenKindWeighsOne() {
        let weights = KindWeights.rarity(over: [vector([.functionCallExpr: 1])])
        #expect(weights.weight(.whileStmt) == 1.0)
    }

    @Test("a kind in every fragment weighs 1; a rarer one weighs more")
    func rarityOrdersWeights() {
        // `functionCallExpr` in all four, `whileStmt` in one.
        let corpus = [
            vector([.functionCallExpr: 3, .whileStmt: 1]),
            vector([.functionCallExpr: 3]),
            vector([.functionCallExpr: 3]),
            vector([.functionCallExpr: 3])
        ]
        let weights = KindWeights.rarity(over: corpus)
        #expect(weights.weight(.functionCallExpr) == 1.0)
        #expect(weights.weight(.whileStmt) > weights.weight(.functionCallExpr))
    }

    // The damping is the reason a ubiquitous kind weighs 1 rather than 0. Without
    // it a fragment built only from common kinds has zero weighted magnitude and
    // no honest similarity to anything — including an exact copy of itself.
    @Test("a fragment of only-common kinds still matches its own copy")
    func commonOnlyFragmentStillMatchesItself() {
        let common = vector([.functionCallExpr: 5, .memberAccessExpr: 5])
        let corpus = Array(repeating: common, count: 10)
        let weights = KindWeights.rarity(over: corpus)
        let magnitude = weights.magnitude(of: common)
        #expect(magnitude > 0)
        #expect(weights.similarity(common, common, magnitude: magnitude, magnitude) == 1.0)
    }

    // The fault this exists to fix: two fragments alike only in the constructs
    // every fragment carries should score lower once those stop counting for
    // full value, while two alike in a rare construct should not.
    @Test("shared common structure counts for less than shared rare structure")
    func rareAgreementOutweighsCommonAgreement() {
        let corpus = [
            vector([.functionCallExpr: 10, .whileStmt: 2]),
            vector([.functionCallExpr: 10, .whileStmt: 2])
        ] + Array(repeating: vector([.functionCallExpr: 10]), count: 20)
        let weights = KindWeights.rarity(over: corpus)

        let commonOnly = vector([.functionCallExpr: 10])
        let withRare = vector([.functionCallExpr: 10, .whileStmt: 2])
        let commonMagnitude = weights.magnitude(of: commonOnly)
        let rareMagnitude = weights.magnitude(of: withRare)

        let mixed = weights.similarity(commonOnly, withRare, magnitude: commonMagnitude, rareMagnitude)
        let bothRare = weights.similarity(withRare, withRare, magnitude: rareMagnitude, rareMagnitude)
        #expect(mixed < bothRare)
        // Unweighted, the same pair scores higher — the common part carried it.
        #expect(mixed < commonOnly.similarity(to: withRare))
    }

    @Test("uniform weighting reproduces plain Sørensen–Dice")
    func uniformMatchesUnweighted() {
        let lhs = vector([.functionCallExpr: 4, .whileStmt: 1])
        let rhs = vector([.functionCallExpr: 4, .guardStmt: 1])
        let weights = KindWeights.uniform
        let weighted = weights.similarity(
            lhs, rhs, magnitude: weights.magnitude(of: lhs), weights.magnitude(of: rhs)
        )
        #expect(abs(weighted - lhs.similarity(to: rhs)) < 0.0001)
    }

    // The drift this prevents: `magnitude` and `similarity` accumulate `Double`s
    // while walking a `[SyntaxKind: Int]`, and Swift reseeds dictionary hashing
    // per process, so two runs walked the kinds in different orders. Floating-
    // point addition is not associative, so the totals disagreed in the last bits
    // and every near-miss clone reported a `similarity` that changed between runs.
    //
    // Hash seeding cannot be varied inside one process, so this pins the property
    // that fixes it rather than the symptom: the sum must not depend on the order
    // the addends arrive in.
    @Test("summation does not depend on the order the addends arrive in")
    func summationIsOrderIndependent() {
        // One dominant term and several an order below its ULP: added after it,
        // each rounds away; added together first, they survive. Plain
        // left-to-right summation over these yields three different totals
        // depending on the order.
        let terms = [1.0, 1e-16, 1e-16, 1e-16, 1e-16]

        var canonical = terms
        let expected = KindWeights.canonicalSum(&canonical)

        var sawNaiveDisagreement = false
        for _ in 0..<200 {
            var permuted = terms.shuffled()
            #expect(KindWeights.canonicalSum(&permuted) == expected)

            if permuted.reduce(0, +) != terms.reduce(0, +) {
                sawNaiveDisagreement = true
            }
        }

        // Guard against the test passing vacuously on addends too well-behaved to
        // expose the hazard: plain left-to-right summation must actually differ.
        #expect(sawNaiveDisagreement)
    }
}
