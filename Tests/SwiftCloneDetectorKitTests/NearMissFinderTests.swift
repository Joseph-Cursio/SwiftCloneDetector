//
//  NearMissFinderTests.swift
//  SwiftCloneDetectorKitTests
//
//  Covers Type-3 detection: copies that drift by a few statements should
//  cluster, exact copies should not (they belong to CloneFinder), and
//  unrelated code should stay apart.
//

@testable import SwiftCloneDetectorKit
import Testing

@Suite("NearMissFinder")
struct NearMissFinderTests {
    // Same shape, with an extra `if` inserted in the variant — the canonical
    // Type-3 case an exact hash would miss.
    private let base = """
    func process(_ items: [Int]) -> Int {
        var total = 0
        for item in items {
            total += item
        }
        return total
    }
    """
    private let variant = """
    func process(_ items: [Int]) -> Int {
        var total = 0
        for item in items {
            if item > 0 {
                total += item
            }
        }
        return total
    }
    """

    private func source(_ path: String, _ text: String) -> SourceInput {
        SourceInput(path: path, text: text)
    }

    @Test("clusters a near-miss copy that drifted by one inserted statement")
    func detectsNearMiss() {
        let finder = NearMissFinder(minMass: 15, similarityThreshold: 0.8)
        let classes = finder.find(in: [source("a.swift", base), source("b.swift", variant)])
        #expect(classes.contains { $0.instances.count == 2 })
        // It is *near*, not exact.
        if let similarity = classes.first?.similarity {
            #expect(similarity < 1.0)
            #expect(similarity >= 0.8)
        }
    }

    @Test("does not report exact copies — those are CloneFinder's job")
    func ignoresExactCopies() {
        let finder = NearMissFinder(minMass: 15, similarityThreshold: 0.8)
        let classes = finder.find(in: [source("a.swift", base), source("b.swift", base)])
        #expect(classes.isEmpty)
    }

    @Test("keeps unrelated functions apart")
    func ignoresUnrelated() {
        let other = """
        func greet(_ name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                return "Hello, stranger"
            }
            return "Hello, " + trimmed + "!"
        }
        """
        let finder = NearMissFinder(minMass: 15, similarityThreshold: 0.85)
        let classes = finder.find(in: [source("a.swift", base), source("b.swift", other)])
        #expect(classes.isEmpty)
    }

    @Test("a tighter threshold rejects a loose match")
    func thresholdGates() {
        let inputs = [source("a.swift", base), source("b.swift", variant)]
        let strict = NearMissFinder(minMass: 15, similarityThreshold: 0.99).find(in: inputs)
        #expect(strict.isEmpty)
    }
}
