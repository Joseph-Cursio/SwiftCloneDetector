//
//  SourceRange.swift
//  SwiftCloneDetectorKit
//
//  The byte range a clone occupies in one input file. Subsumption asks whether
//  one range sits inside another; reporting asks which range comes first. Both
//  questions live here so the passes don't answer them from loose Int triples.
//

/// A half-open UTF-8 byte range within a single input file.
struct SourceRange: Comparable {
    /// Index of the source this range falls in, into the pass's input array.
    let fileIndex: Int
    /// UTF-8 offset of the first byte.
    let startOffset: Int
    /// UTF-8 offset one past the last byte.
    let endOffset: Int

    /// Source order: by file, then by position within it.
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.fileIndex != rhs.fileIndex {
            return lhs.fileIndex < rhs.fileIndex
        }
        if lhs.startOffset != rhs.startOffset {
            return lhs.startOffset < rhs.startOffset
        }
        return lhs.endOffset < rhs.endOffset
    }

    /// Whether this range lies wholly inside `other` — the sub-clone test.
    ///
    /// Ranges in different files never contain one another, so the file check
    /// comes first; callers that already bucket by file get the same answer.
    func isContained(in other: Self) -> Bool {
        fileIndex == other.fileIndex && startOffset >= other.startOffset && endOffset <= other.endOffset
    }

    /// Whether this range lies inside `other` and is strictly smaller than it.
    ///
    /// The self-overlap filter needs this rather than `isContained(in:)`: two
    /// members of one cluster with identical ranges each contain the other, so a
    /// non-strict test would discard both and leave the cluster empty.
    func isStrictlyContained(in other: Self) -> Bool {
        isContained(in: other) && (startOffset > other.startOffset || endOffset < other.endOffset)
    }
}
