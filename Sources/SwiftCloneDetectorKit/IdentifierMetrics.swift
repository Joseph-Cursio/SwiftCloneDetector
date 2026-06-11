//
//  IdentifierMetrics.swift
//  SwiftCloneDetectorKit
//
//  Shared metric behind the --min-distinct-identifiers floor, used by both the
//  exact (CloneFinder) and near-miss (NearMissFinder) passes.
//

import SwiftSyntax

/// Number of distinct identifier tokens in a subtree — a proxy for how much
/// unique naming a fragment carries. Large but repetitive structure (a long
/// switch, a chained builder) scores low even when its node count is high, so a
/// distinct-identifier floor filters those out where `--min-mass` cannot.
func distinctIdentifierCount(in node: Syntax) -> Int {
    var seen: Set<String> = []
    func walk(_ node: Syntax) {
        if let token = node.as(TokenSyntax.self) {
            if case .identifier = token.tokenKind {
                seen.insert(token.text)
            }
            return
        }
        for child in node.children(viewMode: .sourceAccurate) {
            walk(child)
        }
    }
    walk(node)
    return seen.count
}
