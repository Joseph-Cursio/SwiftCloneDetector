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

    @Test("consistent renaming separates structs whose field types reuse differently")
    func consistentRenamingSeparatesByTypePattern() {
        // Same shape (4 fields + memberwise init), but one is all-Int and the other
        // mixes String/Int. Blind Type-2 folds every type name to one placeholder
        // and wrongly matches them; consistent renaming keeps the reuse patterns
        // (Int,Int,Int,Int vs String,Int,String,String) distinct.
        let allInts = """
        struct Summary {
            let totalIssues: Int
            let errorCount: Int
            let warningCount: Int
            let infoCount: Int
            init(totalIssues: Int, errorCount: Int, warningCount: Int, infoCount: Int) {
                self.totalIssues = totalIssues
                self.errorCount = errorCount
                self.warningCount = warningCount
                self.infoCount = infoCount
            }
        }
        """
        let mixedTypes = """
        struct Finding {
            let filePath: String
            let line: Int
            let ruleID: String
            let reason: String
            init(filePath: String, line: Int, ruleID: String, reason: String) {
                self.filePath = filePath
                self.line = line
                self.ruleID = ruleID
                self.reason = reason
            }
        }
        """
        let finder = CloneFinder(normalization: .type2, minMass: 20)
        let classes = finder.find(in: [source("a.swift", allInts), source("b.swift", mixedTypes)])
        #expect(classes.isEmpty)
    }

    @Test("consistent renaming still matches a faithfully renamed copy")
    func consistentRenamingMatchesTrueRename() {
        // Identical field types (Int, Int) and reuse pattern, only the names differ —
        // a genuine Type-2 clone that consistent renaming must still catch.
        let original = """
        struct Box {
            let alpha: Int
            let beta: Int
            init(alpha: Int, beta: Int) {
                self.alpha = alpha
                self.beta = beta
            }
        }
        """
        let renamed = """
        struct Crate {
            let first: Int
            let second: Int
            init(first: Int, second: Int) {
                self.first = first
                self.second = second
            }
        }
        """
        let finder = CloneFinder(normalization: .type2, minMass: 20)
        let classes = finder.find(in: [source("a.swift", original), source("b.swift", renamed)])
        #expect(classes.contains { $0.instances.count >= 2 })
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
