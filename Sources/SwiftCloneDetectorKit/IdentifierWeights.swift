//
//  IdentifierWeights.swift
//  SwiftCloneDetectorKit
//
//  How much each identifier is allowed to say about whether two fragments are
//  copies, for the --min-identifier-overlap gate.
//

import Foundation
import SwiftSyntax

/// How much each name is allowed to say about whether two fragments are copies.
///
/// Unweighted, the names every model carries — `String`, `Int`, `id`, `Hashable`
/// — are shared evidence like any other, and a pair of unrelated data types can
/// clear the overlap gate on those alone. Splitting a near-miss class into pairs
/// that each pass the gate made that worse, not better: the 88%-alike models it
/// was meant to drop came back two at a time. A name used in most files says
/// nothing about any two of them; one used in a handful says a great deal.
///
/// The weight is the same damped rarity ``KindWeights`` gives node kinds,
/// `1 + ln(N / df)`, counted over files: a name in every file keeps a weight of 1
/// rather than falling to 0, so two fragments built only from common names still
/// have an overlap to measure.
struct IdentifierWeights {
    // A name present in every file keeps this weight. See the damping note above.
    private static let ubiquitousWeight = 1.0

    /// Every name weighted 1 — a plain Jaccard index.
    static let uniform = Self(weights: [:])

    private let weights: [String: Double]

    /// Weights derived from how many of `files` name each identifier.
    static func rarity(over files: [Syntax]) -> Self {
        guard !files.isEmpty else {
            return .uniform
        }
        var documentFrequency: [String: Int] = [:]
        for file in files {
            var names: Set<String> = []
            collectIdentifiers(in: file, into: &names)
            for name in names {
                documentFrequency[name, default: 0] += 1
            }
        }
        let total = Double(files.count)
        return Self(weights: documentFrequency.mapValues { frequency in
            ubiquitousWeight + log(total / Double(frequency))
        })
    }

    func weight(_ name: String) -> Double {
        weights[name] ?? Self.ubiquitousWeight
    }
}
