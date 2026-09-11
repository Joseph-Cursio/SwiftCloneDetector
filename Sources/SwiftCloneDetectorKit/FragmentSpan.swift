//
//  FragmentSpan.swift
//  SwiftCloneDetectorKit
//
//  The facts every detection pass records about a candidate fragment, in one
//  place. Each pass walks the tree looking for something different — a
//  structural hash, a characteristic vector, a per-item blind hash — but all
//  three note the same thing about *where* a fragment is: which file, which
//  node, how big, and what byte range it covers.
//

import SwiftSyntax

/// Where a candidate fragment sits: its file, its anchoring syntax node, its
/// size in AST nodes, and the UTF-8 byte range it spans.
///
/// A pass composes this with whatever matching key it needs — see
/// `CloneFinder.Fragment` (hash), `NearMissFinder.Fragment` (characteristic
/// vector), and `SequenceCloneFinder.Item` (per-item blind hash).
struct FragmentSpan {
    /// Index of the source this fragment came from, into the pass's input array.
    let fileIndex: Int
    /// The syntax node the fragment is anchored to.
    let node: Syntax
    /// Fragment size in AST nodes, the common floor for reporting.
    let mass: Int
    /// UTF-8 offset of the fragment's first non-trivia byte.
    let startOffset: Int
    /// UTF-8 offset one past the fragment's last non-trivia byte.
    let endOffset: Int

    /// The kind of construct this fragment is anchored to.
    var kind: SyntaxKind { node.kind }

    /// The byte range this fragment occupies.
    var range: SourceRange {
        SourceRange(fileIndex: fileIndex, startOffset: startOffset, endOffset: endOffset)
    }

    /// Record a span for `node`, deriving the byte range from the node itself.
    /// Trivia is excluded at both ends so a fragment's range covers its code and
    /// not the comments or whitespace around it.
    init(fileIndex: Int, node: Syntax, mass: Int) {
        self.fileIndex = fileIndex
        self.node = node
        self.mass = mass
        self.startOffset = node.positionAfterSkippingLeadingTrivia.utf8Offset
        self.endOffset = node.endPositionBeforeTrailingTrivia.utf8Offset
    }

    /// Resolve this span to a reportable clone instance, converting byte offsets
    /// to line/column via the converter built for its file.
    func cloneInstance(path: String, converter: SourceLocationConverter) -> CloneInstance {
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        return CloneInstance(
            path: path,
            startLine: start.line,
            startColumn: start.column,
            endLine: end.line,
            endColumn: end.column
        )
    }
}
