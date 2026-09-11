//
//  ClaimedRanges.swift
//  SwiftCloneDetectorKit
//
//  Sub-clone subsumption, shared by every pass. Each detector reports its clone
//  classes largest first and claims the byte ranges it just reported; a later,
//  smaller class whose every instance already sits inside a claimed range is a
//  sub-clone of something the caller has been told about, so it is dropped.
//

/// Byte ranges already covered by a reported clone, bucketed by file.
///
/// Passes differ in what they match on but agree on this bookkeeping, so it
/// lives here rather than being restated in each `subsume` step.
struct ClaimedRanges {
    private var byFile: [Int: [SourceRange]] = [:]

    /// Whether `range` lies wholly inside a range that has already been claimed.
    func covers(_ range: SourceRange) -> Bool {
        guard let ranges = byFile[range.fileIndex] else {
            return false
        }
        return ranges.contains { range.isContained(in: $0) }
    }

    /// Record `range` as reported, so anything nested inside it is treated as a
    /// sub-clone from here on.
    mutating func claim(_ range: SourceRange) {
        byFile[range.fileIndex, default: []].append(range)
    }

    /// Whether `span` lies wholly inside an already-claimed range.
    func covers(_ span: FragmentSpan) -> Bool {
        covers(span.range)
    }

    /// Record `span`'s byte range as reported.
    mutating func claim(_ span: FragmentSpan) {
        claim(span.range)
    }
}
