//
//  CloneOrder.swift
//  SwiftCloneDetectorKit
//
//  A total order on clone classes, so a run is reproducible.
//
//  Every pass gathers its classes by iterating `Dictionary.values`, and Swift
//  reseeds dictionary hashing per process — so the order classes arrive in
//  differs between two runs over identical input. Sorting by mass alone doesn't
//  settle it: `sort` is not stable, so equal-mass classes stay arbitrary.
//
//  That is not only cosmetic. Subsumption claims byte ranges in report order, so
//  when two equal-mass classes overlap, whichever is visited first is reported
//  and the other is dropped as a sub-clone. Without a tie-break the *set* of
//  reported clones can shift between runs, not just its order.
//

/// Where a clone class sorts in a report: largest mass first, ties broken by the
/// earliest source position the class covers.
///
/// The tie-break is a total order because passes partition fragments — each
/// fragment belongs to exactly one class — so no two classes share an earliest
/// position.
struct CloneOrder: Comparable {
    /// Size of the class in AST nodes; the primary, descending key.
    let mass: Int
    /// The earliest range any member covers; the ascending tie-break.
    let earliest: SourceRange

    /// The order of a class covering `ranges`. `ranges` is never empty in
    /// practice; an empty class sorts last.
    init(mass: Int, ranges: some Sequence<SourceRange>) {
        self.mass = mass
        self.earliest = ranges.min()
            ?? SourceRange(fileIndex: .max, startOffset: .max, endOffset: .max)
    }

    /// The order of a class made of `spans`.
    init(mass: Int, spans: some Sequence<FragmentSpan>) {
        self.init(mass: mass, ranges: spans.map(\.range))
    }

    /// The order of a single span, for ranking fragments the same way classes of
    /// them are ranked.
    init(_ span: FragmentSpan) {
        self.init(mass: span.mass, ranges: CollectionOfOne(span.range))
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        // Mass descends (biggest clone first); the positional tie-break ascends.
        if lhs.mass != rhs.mass {
            return lhs.mass > rhs.mass
        }
        return lhs.earliest < rhs.earliest
    }
}
