//
//  IdentifierMetrics.swift
//  SwiftCloneDetectorKit
//
//  Shared metrics behind the --min-distinct-identifiers floor, used by both the
//  exact (CloneFinder) and near-miss (NearMissFinder) passes, and the
//  --min-identifier-overlap gate, used by the near-miss and sequence passes.
//

import SwiftSyntax

/// Number of distinct identifier tokens in a subtree — a proxy for how much
/// unique naming a fragment carries. Large but repetitive structure (a long
/// switch, a chained builder) scores low even when its node count is high, so a
/// distinct-identifier floor filters those out where `--min-mass` cannot.
func distinctIdentifierCount(in node: Syntax) -> Int {
    var seen: Set<String> = []
    collectIdentifiers(in: node, into: &seen)
    return seen.count
}

/// Add every identifier token in `node` to `seen`. Shared so a caller can union
/// identifiers across several nodes — e.g. the items of a sequence-clone run.
func collectIdentifiers(in node: Syntax, into seen: inout Set<String>) {
    if let token = node.as(TokenSyntax.self) {
        if case .identifier = token.tokenKind {
            seen.insert(token.text)
        }
        return
    }
    for child in node.children(viewMode: .sourceAccurate) {
        collectIdentifiers(in: child, into: &seen)
    }
}

/// How much naming two fragments share: the Jaccard index of their distinct
/// identifiers, in [0, 1].
///
/// Structure alone cannot tell a copy from a coincidence. Two unrelated models,
/// each a run of stored properties and a memberwise init, are built from the same
/// node kinds in the same proportions, so the near-miss vector scores them 88%
/// alike; a 45-case enum is one shape repeated, so the sequence pass matches its
/// first twenty cases against its next twenty. What such pairs do not share is
/// names. Copy-paste keeps most of them — the callee, the types, the members it
/// reads — even when a few locals are renamed.
///
/// Each name counts by its weight in `weights`, so the overlap is a weighted
/// Jaccard index; see ``IdentifierWeights`` for why names are not all equal.
///
/// Two fragments that name nothing overlap fully: there is no naming for them to
/// disagree on, so the gate leaves them to the structural score.
func identifierOverlap(
    _ lhs: Set<String>,
    _ rhs: Set<String>,
    weights: IdentifierWeights
) -> Double {
    var shared = 0.0
    var all = 0.0
    // Summed in sorted order: a set's order follows the per-process hash seed, and
    // floating-point addition is not associative, so summing in set order lets a
    // pair at the threshold land either side of it from one run to the next.
    for name in lhs.union(rhs).sorted() {
        let weight = weights.weight(name)
        all += weight
        if lhs.contains(name), rhs.contains(name) {
            shared += weight
        }
    }
    guard all > 0 else {
        return 1
    }
    return shared / all
}
