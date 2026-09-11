//
//  CloneClass+Merge.swift
//  SwiftCloneDetectorKit
//
//  Folding the three passes' results into one report.
//

// Merge clone classes found by different passes into one report, dropping a
// class whose every instance already sits inside a larger reported one.
// 
// Each pass already subsumes nested clones within its own results. Across
// passes nothing did, because until now only one pass ran — so the same region
// would be reported up to three times, once as an exact match, once as a run of
// statements, and once at 94% similar.
// 
// Ordering is by mass, largest first, exactly as each pass orders its own
// output. Where two classes are the same size, the pass that makes the stronger
// claim goes first: "identical" outranks "one run of identical statements",
// which outranks "87% alike". Classes still tied after that are ordered by
// position — see `MergeOrder` for why that last key is not cosmetic.
// 
// **A weaker claim never hides a stronger one.** A class is dropped only when
// the class covering it speaks at least as precisely. Subsuming on size alone
// cost two true positives the first time this was measured: a near-miss class
// matching two whole types at 87% — itself a false positive — swallowed the
// byte-identical run of members inside one of them, which is the only real
// finding either instance contained. Losing a fact to a guess that happens to
// be bigger is the wrong trade in every direction.
// Where a class sorts in the merged report.
//
// Mass descends, then the pass making the stronger claim goes first. The third
// key is what makes the order *total*. `sorted` is not stable, so two classes of
// equal mass from the same pass would otherwise land in an arbitrary order — and
// because the subsumption below claims line ranges in report order, whichever
// came first would survive and the other be dropped as covered. That is the
// hazard `CloneOrder` settles inside a pass, restated over the public type this
// step works on, which carries paths and line numbers rather than byte offsets.
//
// It is a total order for the same reason: a pass partitions its fragments, so
// two classes from one pass cannot share an earliest instance, and two from
// different passes are already separated by specificity.
private struct MergeOrder: Comparable {
    /// Position of one instance in source order, the ascending tie-break.
    struct Position: Comparable {
        let path: String
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int

        init(_ instance: CloneInstance) {
            path = instance.path
            startLine = instance.startLine
            startColumn = instance.startColumn
            endLine = instance.endLine
            endColumn = instance.endColumn
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.path, lhs.startLine, lhs.startColumn, lhs.endLine, lhs.endColumn)
                < (rhs.path, rhs.startLine, rhs.startColumn, rhs.endLine, rhs.endColumn)
        }
    }

    let mass: Int
    let specificity: Int
    let earliest: Position?

    init(_ cloneClass: CloneClass) {
        mass = cloneClass.mass
        specificity = cloneClass.pass.specificity
        earliest = cloneClass.instances.map(Position.init).min()
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.mass != rhs.mass {
            return lhs.mass > rhs.mass
        }
        if lhs.specificity != rhs.specificity {
            return lhs.specificity < rhs.specificity
        }
        // A class with no instances never occurs in practice; sort it last.
        guard let lhsEarliest = lhs.earliest else {
            return false
        }
        guard let rhsEarliest = rhs.earliest else {
            return true
        }
        return lhsEarliest < rhsEarliest
    }
}

public extension CloneClass {
    /// Merge clone classes found by different passes into one report, dropping a
    /// class whose every instance already sits inside a larger reported one.
    static func merged(_ classes: [CloneClass]) -> [CloneClass] {
        let ordered = classes
            .map { (order: MergeOrder($0), cloneClass: $0) }
            .sorted { $0.order < $1.order }
            .map(\.cloneClass)

        // A range already reported, and how precisely the pass that took it spoke.
        struct Claim {
            let start: Int
            let end: Int
            let specificity: Int
        }

        var claimed: [String: [Claim]] = [:]
        var result: [CloneClass] = []

        for cloneClass in ordered {
            let isCovered = cloneClass.instances.allSatisfy { instance in
                (claimed[instance.path] ?? []).contains { claim in
                    instance.startLine >= claim.start
                        && instance.endLine <= claim.end
                        && claim.specificity <= cloneClass.pass.specificity
                }
            }
            if isCovered {
                continue
            }
            for instance in cloneClass.instances {
                claimed[instance.path, default: []].append(Claim(
                    start: instance.startLine,
                    end: instance.endLine,
                    specificity: cloneClass.pass.specificity
                ))
            }
            result.append(cloneClass)
        }
        return result
    }
}
