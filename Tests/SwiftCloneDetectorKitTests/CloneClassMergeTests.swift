//
//  CloneClassMergeTests.swift
//  SwiftCloneDetectorKitTests
//
//  Folding three passes into one report, without a weaker claim hiding a
//  stronger one.
//

@testable import SwiftCloneDetectorKit
import Testing

@Suite("CloneClass.merged")
struct CloneClassMergeTests {
    private struct Range {
        let path: String
        let start: Int
        let end: Int
    }

    private func cloneClass(_ pass: DetectionPass, mass: Int, _ ranges: [Range]) -> CloneClass {
        CloneClass(
            mass: mass,
            instances: ranges.map { range in
                CloneInstance(
                    path: range.path,
                    startLine: range.start,
                    startColumn: 1,
                    endLine: range.end,
                    endColumn: 1
                )
            },
            pass: pass
        )
    }

    private func range(_ path: String, _ start: Int, _ end: Int) -> Range {
        Range(path: path, start: start, end: end)
    }

    @Test("a class every instance of which sits inside a larger one is dropped")
    func dropsContained() {
        let outer = cloneClass(.subtree, mass: 400, [range("a.swift", 10, 90), range("b.swift", 10, 90)])
        let inner = cloneClass(.nearMiss, mass: 100, [range("a.swift", 20, 40), range("b.swift", 20, 40)])
        let merged = CloneClass.merged([inner, outer])
        #expect(merged.count == 1)
        #expect(merged.first?.pass == .subtree)
    }

    // The regression this exists for. A near-miss class matching two whole types
    // at 87% — itself a false positive — swallowed the byte-identical run of
    // members inside one of them, which was the only real finding present.
    @Test("a weaker claim never hides a stronger one")
    func weakDoesNotHideStrong() {
        let vague = cloneClass(.nearMiss, mass: 900, [range("a.swift", 1, 300), range("b.swift", 1, 300)])
        let exact = cloneClass(.subtree, mass: 200, [range("a.swift", 40, 90), range("b.swift", 40, 90)])
        let run = cloneClass(.sequence, mass: 150, [range("a.swift", 120, 170), range("b.swift", 120, 170)])
        let merged = CloneClass.merged([vague, exact, run])
        #expect(merged.count == 3)
        #expect(Set(merged.map(\.pass)) == [.nearMiss, .subtree, .sequence])
    }

    @Test("a class is kept when only some of its instances are covered")
    func keepsPartiallyCovered() {
        let outer = cloneClass(.subtree, mass: 400, [range("a.swift", 10, 90)])
        let straddling = cloneClass(.subtree, mass: 100, [range("a.swift", 20, 40), range("c.swift", 5, 25)])
        let merged = CloneClass.merged([outer, straddling])
        #expect(merged.count == 2)
    }

    @Test("equal mass is broken by how precisely the pass speaks")
    func strongerPassLeadsAtEqualMass() {
        let vague = cloneClass(.nearMiss, mass: 100, [range("a.swift", 1, 50), range("b.swift", 1, 50)])
        let exact = cloneClass(.subtree, mass: 100, [range("a.swift", 1, 50), range("b.swift", 1, 50)])
        let merged = CloneClass.merged([vague, exact])
        #expect(merged.first?.pass == .subtree)
        #expect(merged.count == 1)
    }

    @Test("nothing to merge is left alone")
    func passesThroughDisjoint() {
        let first = cloneClass(.subtree, mass: 100, [range("a.swift", 1, 20), range("b.swift", 1, 20)])
        let second = cloneClass(.sequence, mass: 90, [range("c.swift", 1, 20), range("d.swift", 1, 20)])
        #expect(CloneClass.merged([first, second]).count == 2)
    }

    @Test("equal-mass classes from one pass are ordered by position, not by input order")
    func ordersEqualMassByPosition() {
        // Same pass, same mass — only position separates them, so the merge has
        // to fall through to the positional tie-break.
        let early = cloneClass(.subtree, mass: 200, [range("a.swift", 10, 20), range("b.swift", 10, 20)])
        let late = cloneClass(.subtree, mass: 200, [range("a.swift", 80, 90), range("b.swift", 80, 90)])

        // Whichever order they arrive in, the earlier one is reported first.
        let forward = CloneClass.merged([early, late])
        let backward = CloneClass.merged([late, early])

        #expect(forward.map(\.instances[0].startLine) == [10, 80])
        #expect(backward.map(\.instances[0].startLine) == [10, 80])
    }

    @Test("two equal-mass overlapping classes resolve the same way whatever order they arrive in")
    func subsumptionIsIndependentOfInputOrder() {
        // `outer` contains `inner` and they are the same mass and pass, so which
        // one survives is decided purely by which the merge visits first. Before
        // the positional tie-break that was whichever the input happened to list
        // first, so the *set* of reported clones depended on input order.
        let outer = cloneClass(.subtree, mass: 200, [range("a.swift", 10, 90), range("b.swift", 10, 90)])
        let inner = cloneClass(.subtree, mass: 200, [range("a.swift", 20, 40), range("b.swift", 20, 40)])

        let forward = CloneClass.merged([outer, inner])
        let backward = CloneClass.merged([inner, outer])

        #expect(forward.count == backward.count)
        #expect(forward.map(\.instances[0].startLine) == backward.map(\.instances[0].startLine))
    }
}
