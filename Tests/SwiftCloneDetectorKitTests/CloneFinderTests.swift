//
//  CloneFinderTests.swift
//  SwiftCloneDetectorKitTests
//
//  Covers the Type-1/2 distinction, the min-mass floor, and subsumption.
//

import Testing
@testable import SwiftCloneDetectorKit

@Suite("CloneFinder")
struct CloneFinderTests {

    private func source(_ path: String, _ text: String) -> SourceInput {
        SourceInput(path: path, text: text)
    }

    @Test("detects an exact duplicated function (Type-1)")
    func exactDuplicate() {
        let body = """
        func compute(_ values: [Int]) -> Int {
            var total = 0
            for value in values {
                total += value * 2
            }
            return total
        }
        """
        let finder = CloneFinder(normalization: .type1, minMass: 10)
        let classes = finder.find(in: [source("a.swift", body), source("b.swift", body)])
        #expect(classes.contains { $0.instances.count == 2 })
    }

    @Test("Type-2 matches renamed identifiers; Type-1 does not")
    func renamedIdentifiers() {
        let original = """
        func a() -> Int {
            var total = 0
            for value in [1, 2, 3] {
                total += value
            }
            return total
        }
        """
        let renamed = """
        func b() -> Int {
            var sum = 0
            for item in [1, 2, 3] {
                sum += item
            }
            return sum
        }
        """
        let inputs = [source("a.swift", original), source("b.swift", renamed)]

        let type2 = CloneFinder(normalization: .type2, minMass: 10).find(in: inputs)
        #expect(type2.contains { $0.instances.count >= 2 })

        let type1 = CloneFinder(normalization: .type1, minMass: 10).find(in: inputs)
        #expect(type1.isEmpty)
    }

    @Test("ignores fragments below the min-mass floor")
    func belowThreshold() {
        let tiny = "let x = 1\n"
        let finder = CloneFinder(normalization: .type2, minMass: 50)
        let classes = finder.find(in: [source("a.swift", tiny), source("b.swift", tiny)])
        #expect(classes.isEmpty)
    }

    @Test("reports the enclosing clone once, not every nested sub-clone")
    func subsumption() {
        let body = """
        func handle(_ values: [Int]) -> Int {
            var total = 0
            for value in values {
                if value > 0 {
                    total += value
                }
            }
            return total
        }
        """
        let finder = CloneFinder(normalization: .type2, minMass: 10)
        let classes = finder.find(in: [source("a.swift", body), source("b.swift", body)])
        // The whole function, its loop, and its `if` all match — but only the
        // outermost (largest) clone should survive subsumption.
        #expect(classes.count == 1)
        #expect(classes.first?.instances.count == 2)
    }
}
