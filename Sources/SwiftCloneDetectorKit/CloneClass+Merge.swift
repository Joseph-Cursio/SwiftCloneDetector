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
// which outranks "87% alike".
// 
// **A weaker claim never hides a stronger one.** A class is dropped only when
// the class covering it speaks at least as precisely. Subsuming on size alone
// cost two true positives the first time this was measured: a near-miss class
// matching two whole types at 87% — itself a false positive — swallowed the
// byte-identical run of members inside one of them, which is the only real
// finding either instance contained. Losing a fact to a guess that happens to
// be bigger is the wrong trade in every direction.
public extension CloneClass {
    /// Merge clone classes found by different passes into one report, dropping a
    /// class whose every instance already sits inside a larger reported one.
    static func merged(_ classes: [CloneClass]) -> [CloneClass] {
        let ordered = classes.sorted { lhs, rhs in
            if lhs.mass != rhs.mass {
                return lhs.mass > rhs.mass
            }
            return lhs.pass.specificity < rhs.pass.specificity
        }

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
