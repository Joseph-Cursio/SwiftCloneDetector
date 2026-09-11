//
//  KindRanking.swift
//  SwiftCloneDetectorKit
//
//  A run-stable total order over the node kinds in one corpus, so the weighted
//  sums behind near-miss scoring can accumulate in the same order every run.
//

import SwiftSyntax

/// A total order over the node kinds appearing in one corpus of vectors.
///
/// Scoring needs its `Double` sums to accumulate in a fixed order, because
/// floating-point addition is not associative and a sum taken in two different
/// orders disagrees in the last bits. A `[SyntaxKind: Int]` cannot supply that
/// order — Swift reseeds dictionary hashing per process, so two runs walk the
/// same keys differently.
///
/// `SyntaxKind` offers nothing to sort on either: no raw value, no `Comparable`,
/// no `CaseIterable`. So the order is built here, once per run, from the only
/// stable identity the enum does expose — its case name. The names are resolved
/// once and sorted; ranking a kind afterwards is a single dictionary lookup.
///
/// A ranking covers exactly the kinds of the vectors it was built from. Ranking
/// one of those vectors therefore cannot meet an unranked kind, which is what
/// lets ``RankedVector`` hold a plain `Int` rank and compare on it.
struct KindRanking {
    private let ranks: [SyntaxKind: Int]

    /// The ranking over every kind appearing in `vectors`.
    init(over vectors: some Sequence<CharacteristicVector>) {
        var seen: Set<SyntaxKind> = []
        for vector in vectors {
            seen.formUnion(vector.counts.keys)
        }

        // Resolve each name once rather than inside the sort's comparisons:
        // `String(describing:)` goes through reflection and the sort would ask
        // for the same name O(log n) times.
        let byName = seen
            .map { (name: String(describing: $0), kind: $0) }
            .sorted { $0.name < $1.name }

        var ranks: [SyntaxKind: Int] = [:]
        ranks.reserveCapacity(byName.count)
        for (rank, entry) in byName.enumerated() {
            ranks[entry.kind] = rank
        }
        self.ranks = ranks
    }

    /// `vector` flattened into rank-ordered entries under `weights`.
    ///
    /// `vector` must be one this ranking was built over, so that every kind it
    /// carries has a rank.
    func ranked(_ vector: CharacteristicVector, weights: KindWeights) -> RankedVector {
        var entries: [RankedVector.Entry] = []
        entries.reserveCapacity(vector.counts.count)
        for (kind, count) in vector.counts {
            guard let rank = ranks[kind] else {
                preconditionFailure("ranking a vector against a ranking not built over it")
            }
            entries.append(
                RankedVector.Entry(rank: rank, count: count, weight: weights.weight(kind))
            )
        }
        entries.sort { $0.rank < $1.rank }
        return RankedVector(entries: entries, total: vector.total)
    }
}
