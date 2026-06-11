//
//  CharacteristicVector.swift
//  SwiftCloneDetectorKit
//
//  A multiset of SyntaxKind occurrences within a subtree — the feature vector
//  behind Type-3 (near-miss) detection. Where an exact hash shatters the moment
//  a single statement is inserted, a characteristic vector only shifts slightly,
//  so structurally-similar-but-not-identical subtrees still cluster together.
//

import SwiftSyntax

struct CharacteristicVector {
    private(set) var counts: [SyntaxKind: Int] = [:]
    /// Number of (composite) nodes counted — the vector's L1 magnitude.
    private(set) var total = 0

    mutating func add(_ kind: SyntaxKind) {
        counts[kind, default: 0] += 1
        total += 1
    }

    mutating func merge(_ other: CharacteristicVector) {
        for (kind, count) in other.counts {
            counts[kind, default: 0] += count
        }
        total += other.total
    }

    /// Sørensen–Dice similarity over the two multisets, in [0, 1]. 1.0 means an
    /// identical kind distribution; a handful of inserted/removed nodes drops it
    /// only a little, which is exactly the Type-3 signal.
    func similarity(to other: CharacteristicVector) -> Double {
        guard total > 0, other.total > 0 else { return 0 }

        // Walk the smaller map and intersect against the larger.
        let (smaller, larger) = counts.count <= other.counts.count
            ? (counts, other.counts)
            : (other.counts, counts)

        var intersection = 0
        for (kind, count) in smaller {
            if let otherCount = larger[kind] {
                intersection += min(count, otherCount)
            }
        }
        return 2.0 * Double(intersection) / Double(total + other.total)
    }
}
