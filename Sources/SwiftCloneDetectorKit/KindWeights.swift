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
    ///
    /// A caller scoring a whole corpus should build one ``KindRanking`` over it
    /// and read ``RankedVector/magnitude`` instead; this ranks `vector` on its own
    /// each time, which is fine for a one-off but not inside a loop.
    func magnitude(of vector: CharacteristicVector) -> Double {
        KindRanking(over: [vector]).ranked(vector, weights: self).magnitude
    }

    /// Weighted Sørensen–Dice between two vectors, in [0, 1].
    ///
    /// A caller comparing many pairs should rank the corpus once and call
    /// ``RankedVector/similarity(_:_:)``, which is what this defers to; ranking
    /// per call would repeat that work a quadratic number of times.
    func similarity(_ lhs: CharacteristicVector, _ rhs: CharacteristicVector) -> Double {
        let ranking = KindRanking(over: [lhs, rhs])
        return RankedVector.similarity(
            ranking.ranked(lhs, weights: self),
            ranking.ranked(rhs, weights: self)
        )
    }
}
