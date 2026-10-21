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

    // A `while` whose body is one big statement: the switch, the while and the func
    // are three near-identical fragments nested inside each other, and near-miss
    // similarity is loose enough to put all three in one cluster. They are one region
    // matched against itself at three granularities, not a copy of anything.
    private let nested = """
    func drain(_ buffer: inout [Int], into sink: inout [String]) {
        while !buffer.isEmpty {
            switch buffer.removeFirst() {
            case 0:
                let label = "zero"
                sink.append(label)
                sink.append("zero-trailing")
            case 1:
                let label = "one"
                sink.append(label)
                sink.append("one-trailing")
            case 2:
                let label = "two"
                sink.append(label)
                sink.append("two-trailing")
            default:
                let label = "many"
                sink.append(label)
                sink.append("many-trailing")
            }
        }
    }
    """

    // Two unrelated models built the same way: stored properties and a memberwise
    // init. The node-kind vector sees one shape; only the names say they are not
    // copies of each other.
    private let invoice = """
    struct Invoice {
        let number: String
        let amount: Double
        let dueDate: Date
        let customer: String
        init(number: String, amount: Double, dueDate: Date, customer: String) {
            self.number = number
            self.amount = amount
            self.dueDate = dueDate
            self.customer = customer
        }
    }
    """
    private let satellite = """
    struct Satellite {
        let callSign: String
        let altitude: Float
        let launched: Bool
        init(callSign: String, altitude: Float, launched: Bool) {
            self.callSign = callSign
            self.altitude = altitude
            self.launched = launched
        }
    }
    """

    // Three functions in a line. `bravo` is a *blend* of `alpha` and `charlie`,
    // not their union — Dice penalises a size difference hard enough that a
    // double-length middle scores worse against each end than the ends do
    // against each other, which is the opposite of a chain.
    //
    // Measured: alpha~bravo 0.83, bravo~charlie 0.85, alpha~charlie 0.68. At a
    // 0.75 threshold the first two clear it and the third does not, which is
    // exactly what single-linkage clustering merges into one class and complete
    // linkage must not.
    private var chained: String {
        [
            wrapped("alpha", ifChain(1, 13)),
            wrapped("bravo", ifChain(1, 7) + "\n" + switchChain(7, 13)),
            wrapped("charlie", switchChain(1, 13))
        ].joined(separator: "\n\n")
    }

    private func source(_ path: String, _ text: String) -> SourceInput {
        SourceInput(path: path, text: text)
    }

    private func ifChain(_ from: Int, _ upTo: Int) -> String {
        let lines = (from..<upTo).map { index in
            "    if items.count > \(index) { total += \(index) }"
        }
        return lines.joined(separator: "\n")
    }

    private func switchChain(_ from: Int, _ upTo: Int) -> String {
        let cases = (from..<upTo).map { index in
            """
                switch items.count {
                case \(index): total += \(index)
                default: total -= \(index)
                }
            """
        }
        return cases.joined(separator: "\n")
    }

    private func wrapped(_ name: String, _ body: String) -> String {
        """
        func \(name)(_ items: [Int]) -> Int {
            var total = 0
        \(body)
            return total
        }
        """
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

    @Test("never reports a fragment against a fragment that contains it")
    func dropsSelfOverlappingInstances() {
        let finder = NearMissFinder(minMass: 20, similarityThreshold: 0.85)
        let classes = finder.find(in: [source("a.swift", nested)])
        for cloneClass in classes {
            let instances = cloneClass.instances
            for outer in instances.indices {
                for inner in instances.indices where inner != outer {
                    let containing = instances[outer]
                    let contained = instances[inner]
                    let isNested = contained.path == containing.path
                        && contained.startLine >= containing.startLine
                        && contained.endLine <= containing.endLine
                    #expect(
                        !isNested,
                        """
                        \(containing.startLine)-\(containing.endLine) contains \
                        \(contained.startLine)-\(contained.endLine) in one clone class
                        """
                    )
                }
            }
        }
    }

    // Dropping the self-overlap is not only noise removal: the bogus whole-function
    // class used to claim the range and subsume what was actually duplicated here.
    @Test("unmasks the real duplication the self-overlap was hiding")
    func reportsTheCaseArmsInstead() {
        let finder = NearMissFinder(minMass: 20, similarityThreshold: 0.85)
        let classes = finder.find(in: [source("a.swift", nested)])
        #expect(classes.contains { $0.instances.count == 4 })
    }

    // The guarantee a clone class makes: every member is a near copy of every
    // other. Union-find gives single linkage, where A joins B and B joins C and
    // A and C land together however unlike they are — over the corpus that
    // produced a class of 34,942 fragments whose least-similar pair scored 3%.
    @Test("never reports a class whose least-similar pair is below the threshold")
    func neverReportsBelowThreshold() {
        let threshold = 0.75
        let finder = NearMissFinder(minMass: 100, similarityThreshold: threshold)
        let classes = finder.find(in: [source("chain.swift", chained)])
        #expect(classes.isEmpty == false)
        for cloneClass in classes {
            #expect(
                (cloneClass.similarity ?? 1.0) >= threshold,
                "reported a class at \(cloneClass.similarity ?? 1.0), below the \(threshold) threshold"
            )
        }
    }

    // Breaking the chain must not cost the pair that was genuinely alike.
    @Test("keeps the pair either side of the broken chain")
    func keepsTheGenuinePair() {
        let finder = NearMissFinder(minMass: 100, similarityThreshold: 0.75)
        let classes = finder.find(in: [source("chain.swift", chained)])
        #expect(classes.contains { $0.instances.count == 2 })
    }

    @Test("does not cluster unrelated code that only shares a shape")
    func gatesOnSharedNaming() {
        let inputs = [source("a.swift", invoice), source("b.swift", satellite)]
        let ungated = NearMissFinder(minMass: 15, similarityThreshold: 0.8, minIdentifierOverlap: 0)
        #expect(ungated.find(in: inputs).isEmpty == false)
        let gated = NearMissFinder(minMass: 15, similarityThreshold: 0.8)
        #expect(gated.find(in: inputs).isEmpty)
    }

    @Test("a tighter threshold rejects a loose match")
    func thresholdGates() {
        let inputs = [source("a.swift", base), source("b.swift", variant)]
        let strict = NearMissFinder(minMass: 15, similarityThreshold: 0.99).find(in: inputs)
        #expect(strict.isEmpty)
    }
}
