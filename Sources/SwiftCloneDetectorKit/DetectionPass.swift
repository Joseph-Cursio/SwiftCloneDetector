//
//  DetectionPass.swift
//  SwiftCloneDetectorKit
//
//  Which of the three searches found a clone. They look for different shapes,
//  and until they could run together a caller had to guess which one to ask.
//

/// The search that produced a clone class.
///
/// The three passes are not settings on one algorithm; they look for genuinely
/// different shapes, and each is blind to the others':
///
/// - ``subtree`` anchors on one AST subtree and matches it exactly, modulo the
///   active normalization.
/// - ``nearMiss`` compares subtrees by node-kind distribution, so a copy that
///   drifted by a few statements still matches — and deliberately *excludes*
///   exact matches, which belong to ``subtree``.
/// - ``sequence`` matches runs of consecutive statements or members, which is
///   the only pass that can see duplication spanning more than one declaration.
///
/// Scored against hand-judged cases, no single pass finds everything: two
/// byte-identical 46-line runs of members are invisible to both ``subtree`` and
/// ``nearMiss``, because neither is one subtree. See `Evaluation/README.md`.
/// The search that produced a clone class.
public enum DetectionPass: String, Sendable, Codable, CaseIterable {
    case nearMiss = "near-miss"
    case sequence
    case subtree

    // Strongest claim first — see `specificity`.
    private static let claimStrength: [Self] = [.subtree, .sequence, .nearMiss]

    /// How strong a claim the pass makes about a range, strongest first.
    ///
    /// When two passes report the same region, the report should keep the one
    /// that says the most: "these are identical" beats "these are one run of
    /// identical statements", which beats "these are 87% alike".
    var specificity: Int {
        // Strongest claim first: "identical" outranks "one run of identical
        // statements", which outranks "87% alike".
        Self.claimStrength.firstIndex(of: self) ?? Self.claimStrength.count
    }

    /// How the pass names itself in a report.
    public var label: String {
        switch self {
        case .subtree:
            return "exact"
        case .nearMiss:
            return "near-miss"
        case .sequence:
            return "sequence"
        }
    }
}
