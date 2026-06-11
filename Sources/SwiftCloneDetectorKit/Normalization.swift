//
//  Normalization.swift
//  SwiftCloneDetectorKit
//
//  The single knob that selects which clone type the detector catches. Hashing
//  folds over `(node.kind, children)`; what we do with the leaf tokens here is
//  the whole difference between Type-1 and Type-2 matching.
//

import SwiftSyntax

public struct Normalization: Sendable {
    /// Exact copy-paste only (modulo whitespace/comments — trivia isn't hashed).
    public static let type1 = Self(renameIdentifiers: false, renameLiterals: false)
    /// Copy-paste with renamed variables and changed constants.
    public static let type2 = Self(renameIdentifiers: true, renameLiterals: true)

    /// Collapse all identifiers to one placeholder, so `total` ≡ `sum`.
    public var renameIdentifiers: Bool
    /// Collapse numeric/string literals, so `42` ≡ `99` and `"a"` ≡ `"b"`.
    public var renameLiterals: Bool

    public init(renameIdentifiers: Bool, renameLiterals: Bool) {
        self.renameIdentifiers = renameIdentifiers
        self.renameLiterals = renameLiterals
    }

    /// The canonical text used for a leaf token under this normalization. Keywords,
    /// operators, and punctuation are always kept verbatim — they carry structure.
    ///
    /// This is the *blind* form (every identifier folds to one `$ID`). It is fast
    /// and order-independent, which makes it the right pre-filter for hashing, but
    /// it over-matches: it can't tell `Int, Int, Int` from `String, Int, String`.
    /// Match confirmation uses `consistentText(for:mapping:)` instead.
    func canonicalText(for token: TokenSyntax) -> String {
        switch token.tokenKind {
        case .identifier:
            return renameIdentifiers ? "$ID" : token.text

        case .integerLiteral, .floatLiteral:
            return renameLiterals ? "$NUM" : token.text

        case .stringSegment:
            return renameLiterals ? "$STR" : token.text

        default:
            return token.text
        }
    }

    /// Canonical text for *confirming* a match, using consistent 1:1 renaming: the
    /// first distinct identifier seen in a fragment becomes `$ID0`, the next `$ID1`,
    /// and so on, with reuse preserved. Two fragments confirm as a clone only if
    /// they reuse identifiers (and literals) in the same pattern — so blind
    /// look-alikes such as a four-`Int` struct and a `String, Int, String, String`
    /// struct no longer collapse together. `mapping` holds the per-fragment
    /// assignment and must start empty for each fragment.
    func consistentText(for token: TokenSyntax, mapping: inout [String: Int]) -> String {
        switch token.tokenKind {
        case .identifier:
            return renameIdentifiers ? placeholder("ID", token.text, &mapping) : token.text

        case .integerLiteral, .floatLiteral:
            return renameLiterals ? placeholder("NUM", token.text, &mapping) : token.text

        case .stringSegment:
            return renameLiterals ? placeholder("STR", token.text, &mapping) : token.text

        default:
            return token.text
        }
    }

    // Assign a stable, fragment-relative index to each distinct (category, text)
    // pair by order of first appearance. The category prefix keeps an identifier
    // and a literal that happen to share text from colliding.
    private func placeholder(_ category: String, _ text: String, _ mapping: inout [String: Int]) -> String {
        let key = "\(category):\(text)"
        if let index = mapping[key] {
            return "$\(category)\(index)"
        }
        let index = mapping.count
        mapping[key] = index
        return "$\(category)\(index)"
    }
}
