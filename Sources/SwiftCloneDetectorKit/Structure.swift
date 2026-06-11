//
//  Structure.swift
//  SwiftCloneDetectorKit
//
//  Shared structural-digest helpers: a blind hash (fast bucketing) and a
//  consistent-renaming signature (match confirmation). Used by the sequence
//  finder to hash and confirm statement runs, and by CloneFinder to confirm
//  exact matches — the same scheme, in one place.
//

import SwiftSyntax

/// Structural digests over a syntax subtree.
enum Structure {
    /// The blind structural hash and node mass of `node`. Leaf tokens fold
    /// through the normalization's canonical (blind) form, so the hash is fast
    /// and order-independent — the right pre-filter for bucketing.
    static func hash(of node: Syntax, normalization: Normalization) -> (hash: UInt64, mass: Int) {
        if let token = node.as(TokenSyntax.self) {
            var hasher = FNV64()
            hasher.combine("T:")
            hasher.combine(normalization.canonicalText(for: token))
            return (hasher.value, 1)
        }

        var hasher = FNV64()
        hasher.combine("N:\(node.kind)")
        var mass = 1
        for child in node.children(viewMode: .sourceAccurate) {
            let result = hash(of: child, normalization: normalization)
            hasher.combine(result.hash)
            mass += result.mass
        }
        return (hasher.value, mass)
    }

    /// Append `node`'s consistent-renaming signature to `parts`. `mapping` is
    /// threaded by the caller, so passing it across several sibling nodes makes
    /// identifier reuse consistent over a whole run, not just one node.
    static func appendSignature(
        of node: Syntax,
        normalization: Normalization,
        into parts: inout [String],
        mapping: inout [String: Int]
    ) {
        if let token = node.as(TokenSyntax.self) {
            parts.append(normalization.consistentText(for: token, mapping: &mapping))
            return
        }
        parts.append("(\(node.kind)")
        for child in node.children(viewMode: .sourceAccurate) {
            appendSignature(of: child, normalization: normalization, into: &parts, mapping: &mapping)
        }
        parts.append(")")
    }
}
