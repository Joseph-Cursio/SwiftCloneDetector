//
//  LineSpan.swift
//  SwiftCloneDetectorKit
//
//  How many lines a fragment occupies — the floor `minMass` cannot express.
//

import SwiftSyntax

/// Lines a fragment occupies, 1 when it begins and ends on the same line.
///
/// `minMass` counts AST nodes, and twenty nodes fit comfortably inside one line
/// of Swift, so a mass floor alone admits fragments no reader can act on. Across
/// the corpus that was 20% of near-miss classes and 55-64% of Type-1/2 classes —
/// in one case a class of 59 instances, every one of them a single line.
///
/// A line count is the unit the report already speaks in and the one a reader
/// judges an extraction by, so it is the honest place to put the floor.
func lineSpan(
    from start: AbsolutePosition,
    to end: AbsolutePosition,
    in converter: SourceLocationConverter
) -> Int {
    converter.location(for: end).line - converter.location(for: start).line + 1
}

/// Lines `node` occupies, ignoring its leading and trailing trivia.
func lineSpan(of node: Syntax, in converter: SourceLocationConverter) -> Int {
    lineSpan(
        from: node.positionAfterSkippingLeadingTrivia,
        to: node.endPositionBeforeTrailingTrivia,
        in: converter
    )
}
