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
    /// Collapse all identifiers to one placeholder, so `total` ≡ `sum`.
    public var renameIdentifiers: Bool
    /// Collapse numeric/string literals, so `42` ≡ `99` and `"a"` ≡ `"b"`.
    public var renameLiterals: Bool

    /// Exact copy-paste only (modulo whitespace/comments — trivia isn't hashed).
    public static let type1 = Normalization(renameIdentifiers: false, renameLiterals: false)
    /// Copy-paste with renamed variables and changed constants.
    public static let type2 = Normalization(renameIdentifiers: true, renameLiterals: true)

    public init(renameIdentifiers: Bool, renameLiterals: Bool) {
        self.renameIdentifiers = renameIdentifiers
        self.renameLiterals = renameLiterals
    }

    /// The canonical text used for a leaf token under this normalization. Keywords,
    /// operators, and punctuation are always kept verbatim — they carry structure.
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
}
