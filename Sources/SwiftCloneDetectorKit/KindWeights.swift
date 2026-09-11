//
//  KindWeights.swift
//  SwiftCloneDetectorKit
//
//  How much each node kind is allowed to say about whether two fragments are
//  copies of each other.
//

import Foundation
import SwiftSyntax

/// Per-kind weights for characteristic-vector similarity.
///
/// Unweighted, every node kind counts the same, and that is what makes Type-3
/// unable to tell two SwiftUI bodies apart. A declarative view body is built from
/// a handful of kinds — `FunctionCallExpr`, `MemberAccessExpr`, `ClosureExpr`,
/// `StringLiteralExpr` — that appear in nearly every other body too, so two views
/// rendering completely different things score alike on the only evidence the
/// vector carries. Two fragments read by hand and judged unrelated,
/// `rulesSection` (governed rules and annotation buttons) and `reviewSection`
/// (approve and reject), scored 85%.
///
/// The same fault appears away from SwiftUI: two entire actors, an LSP subprocess
/// connection and an MLX inference backend, matched at 87% because a large type
/// is a large type.
///
/// Rarity weighting is the standard answer — a kind that appears in every
/// fragment distinguishes nothing, one that appears in a few distinguishes a lot.
/// The weight is **damped**, `1 + ln(N / df)`, rather than plain inverse document
/// frequency: a ubiquitous kind keeps a weight of 1 instead of falling to 0, so
/// rarity *adds* discrimination rather than becoming the only evidence. Undamped,
/// a fragment built entirely from common kinds would have a weighted magnitude of
/// zero and no honest similarity to anything, including its own exact copy.
struct KindWeights {
    // Sørensen-Dice weights the shared elements by two.
    private static let diceOverlapFactor = 2.0
    // A kind present in every fragment keeps this weight rather than falling to
    // zero. See the damping note above.
    private static let ubiquitousWeight = 1.0

    /// Every kind weighted 1 — the original, unweighted behaviour.
    static let uniform = Self(weights: [:])

    private let weights: [SyntaxKind: Double]

    /// Weights derived from how many of `vectors` each kind appears in.
    ///
    /// Document frequency is counted per fragment, not per occurrence: a kind
    /// used forty times inside one fragment is still evidence about one fragment.
    static func rarity(over vectors: [CharacteristicVector]) -> Self {
        let count = vectors.count
        guard count > 0 else {
            return .uniform
        }

        var documentFrequency: [SyntaxKind: Int] = [:]
        for vector in vectors {
            for kind in vector.counts.keys {
                documentFrequency[kind, default: 0] += 1
            }
        }

        let total = Double(count)
        return Self(weights: documentFrequency.mapValues { frequency in
            ubiquitousWeight + log(total / Double(frequency))
        })
    }

    func weight(_ kind: SyntaxKind) -> Double {
        weights[kind] ?? Self.ubiquitousWeight
    }

    /// A vector's weighted magnitude — the denominator half of weighted Dice.
    func magnitude(of vector: CharacteristicVector) -> Double {
        var terms: [Double] = []
        terms.reserveCapacity(vector.counts.count)
        for (kind, count) in vector.counts {
            terms.append(weight(kind) * Double(count))
        }
        return Self.canonicalSum(&terms)
    }

    /// Weighted Sørensen–Dice: `2 · Σ w·min(a, b) / (‖a‖ + ‖b‖)`, in [0, 1].
    ///
    /// Magnitudes are passed in because the caller computes each fragment's once
    /// and this runs for every pair.
    func similarity(
        _ lhs: CharacteristicVector,
        _ rhs: CharacteristicVector,
        magnitude lhsMagnitude: Double,
        _ rhsMagnitude: Double
    ) -> Double {
        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            return 0
        }

        // Walk the smaller map and intersect against the larger.
        let (smaller, larger) = lhs.counts.count <= rhs.counts.count
            ? (lhs.counts, rhs.counts)
            : (rhs.counts, lhs.counts)

        var terms: [Double] = []
        terms.reserveCapacity(smaller.count)
        for (kind, count) in smaller {
            if let otherCount = larger[kind] {
                terms.append(weight(kind) * Double(min(count, otherCount)))
            }
        }
        let intersection = Self.canonicalSum(&terms)
        return Self.diceOverlapFactor * intersection / (lhsMagnitude + rhsMagnitude)
    }

    /// Sum `terms` in an order derived from the values themselves, so the result
    /// does not depend on the order they were produced in.
    ///
    /// Both sums here accumulate `Double`s while walking a `[SyntaxKind: Int]`,
    /// and Swift reseeds dictionary hashing per process — so two runs over
    /// identical input walk the kinds in different orders. Floating-point
    /// addition is not associative, so the sums disagreed in the last bits: 32 of
    /// 33 near-miss classes reported a `similarity` that drifted by up to ~3 ULP
    /// between runs, making a JSON or SARIF report differ byte-for-byte each time
    /// it was produced.
    ///
    /// Sorting the addends settles it. The *multiset* of terms is a function of
    /// the input alone, so any order canonical in that multiset is reproducible.
    /// Ascending is the useful choice: adding small terms first is also the more
    /// accurate way to sum, since it defers the rounding loss of a small term
    /// added to a large running total.
    static func canonicalSum(_ terms: inout [Double]) -> Double {
        terms.sort()
        var sum = 0.0
        for term in terms {
            sum += term
        }
        return sum
    }
}
