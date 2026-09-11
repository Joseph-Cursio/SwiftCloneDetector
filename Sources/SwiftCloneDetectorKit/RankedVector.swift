//
//  RankedVector.swift
//  SwiftCloneDetectorKit
//
//  A characteristic vector prepared for scoring: its kinds in a fixed order,
//  each one's weight already resolved, and its weighted magnitude already summed.
//

/// A characteristic vector flattened into rank-ordered entries.
///
/// Two things come out of holding the kinds in ``KindRanking`` order rather than
/// in a dictionary.
///
/// It is **reproducible**. Every `Double` sum below accumulates in ascending rank
/// order, which is a function of the corpus and not of this process's dictionary
/// hash seed. Summing in dictionary order instead made 32 of 33 near-miss classes
/// report a `similarity` that drifted by a few ULP between runs, so a JSON or
/// SARIF report differed byte-for-byte each time it was produced.
///
/// It is also **faster**, which is why the order is fixed here once per fragment
/// rather than per comparison. Intersecting two sorted runs is a merge, so the
/// quadratic pass over fragment pairs walks two contiguous arrays instead of
/// hashing every kind of the smaller vector into the larger one.
struct RankedVector {
    /// One kind's contribution: where it sorts, how often it occurs, and what a
    /// single occurrence is worth.
    struct Entry {
        let rank: Int
        let count: Int
        let weight: Double
    }

    // Sørensen–Dice weights the shared elements by two.
    private static let diceOverlapFactor = 2.0

    /// The vector's kinds, ascending by rank.
    let entries: [Entry]
    /// Number of nodes counted, the unweighted L1 magnitude.
    let total: Int
    /// `Σ weight · count`, summed in rank order — the denominator half of
    /// weighted Dice.
    let magnitude: Double

    init(entries: [Entry], total: Int) {
        self.entries = entries
        self.total = total

        var magnitude = 0.0
        for entry in entries {
            magnitude += entry.weight * Double(entry.count)
        }
        self.magnitude = magnitude
    }

    /// Weighted Sørensen–Dice: `2 · Σ w·min(a, b) / (‖a‖ + ‖b‖)`, in [0, 1].
    ///
    /// Both operands are ascending by rank, so the shared kinds are found by
    /// advancing whichever side is behind — and the intersection accumulates in
    /// rank order, which makes the result identical between runs and identical
    /// whichever way round the two are passed.
    static func similarity(_ lhs: Self, _ rhs: Self) -> Double {
        guard lhs.magnitude > 0, rhs.magnitude > 0 else {
            return 0
        }

        var intersection = 0.0
        var left = lhs.entries.startIndex
        var right = rhs.entries.startIndex

        while left < lhs.entries.endIndex, right < rhs.entries.endIndex {
            let lhsEntry = lhs.entries[left]
            let rhsEntry = rhs.entries[right]

            if lhsEntry.rank < rhsEntry.rank {
                left += 1
            } else if lhsEntry.rank > rhsEntry.rank {
                right += 1
            } else {
                // Same kind, so the same weight on both sides.
                intersection += lhsEntry.weight * Double(min(lhsEntry.count, rhsEntry.count))
                left += 1
                right += 1
            }
        }

        return Self.diceOverlapFactor * intersection / (lhs.magnitude + rhs.magnitude)
    }
}
