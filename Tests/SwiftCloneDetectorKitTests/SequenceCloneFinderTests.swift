//
//  SequenceCloneFinderTests.swift
//  SwiftCloneDetectorKitTests
//
//  Covers sequence (statement-run) detection: matched runs across lists, the
//  minItems/minMass floors, consistent renaming, maximality, and that a lone
//  shared statement is not a run.
//
//  Fixtures bound the intended run with statements of a *different shape*, not
//  just different names — under Type-2 two same-shaped calls like `a()` and
//  `b()` are structurally identical and a run legitimately extends through them.
//

@testable import SwiftCloneDetectorKit
import Testing

@Suite("SequenceCloneFinder")
struct SequenceCloneFinderTests {
    private func source(_ path: String, _ text: String) -> SourceInput {
        SourceInput(path: path, text: text)
    }

    // Each instance as a [startLine, endLine] pair, sorted by start.
    private func instanceLines(_ cloneClass: CloneClass) -> [[Int]] {
        cloneClass.instances
            .map { [$0.startLine, $0.endLine] }
            .sorted { $0[0] < $1[0] }
    }

    @Test("detects a statement run shared by two functions with different surroundings")
    func detectsSharedRun() {
        let text = """
        func alpha() {
            guard ready else { return }
            let total = base + offset
            cache[key] = total
            notify(total, observer)
            for item in items { drop(item) }
        }
        func beta() {
            counter += 1
            let total = base + offset
            cache[key] = total
            notify(total, observer)
            print("done")
        }
        """
        let classes = SequenceCloneFinder(minMass: 10, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.count == 1)
        #expect(instanceLines(classes[0]) == [[3, 5], [10, 12]])
    }

    @Test("a single shared statement is not a run")
    func singleStatementIsNotARun() {
        let text = """
        func alpha() {
            counter += 1
            persist(record, store)
            return result
        }
        func beta() {
            toggle.flip()
            persist(record, store)
            cache[key] = value
        }
        """
        let classes = SequenceCloneFinder(minMass: 1, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.isEmpty)
    }

    @Test("matches a run with consistent identifier renaming (Type-2)")
    func matchesConsistentRenaming() {
        let text = """
        func alpha() {
            guard live else { return }
            let value = wrap(input)
            let scaled = value + value
            return scaled
        }
        func beta() {
            counter += 1
            let amount = wrap(input)
            let scaled = amount + amount
            cache[key] = scaled
        }
        """
        let classes = SequenceCloneFinder(minMass: 8, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.count == 1)
        #expect(classes[0].instances.count == 2)
    }

    @Test("does not match runs whose identifier reuse differs")
    func rejectsInconsistentRenaming() {
        let text = """
        func alpha() {
            let value = wrap(input)
            let scaled = value + value
        }
        func beta() {
            let amount = wrap(input)
            let scaled = amount + other
        }
        """
        let classes = SequenceCloneFinder(minMass: 5, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.isEmpty)
    }

    @Test("reports a run in all three places it appears")
    func reportsThreeInstances() {
        let text = """
        func alpha() {
            counter += 1
            let total = base + offset
            persist(total, store)
            return done
        }
        func beta() {
            toggle.flip()
            let total = base + offset
            persist(total, store)
            cache[key] = total
        }
        func gamma() {
            guard ok else { return }
            let total = base + offset
            persist(total, store)
            for value in values { use(value) }
        }
        """
        let classes = SequenceCloneFinder(minMass: 10, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.count == 1)
        #expect(classes[0].instances.count == 3)
    }

    @Test("reports the maximal run, not its sub-runs")
    func reportsMaximalRun() {
        let text = """
        func alpha() {
            guard ready else { return }
            let total = base + offset
            cache[key] = total
            notify(total, observer)
            history.append(total)
            counter += 1
        }
        func beta() {
            toggle.flip()
            let total = base + offset
            cache[key] = total
            notify(total, observer)
            history.append(total)
            return total
        }
        """
        let classes = SequenceCloneFinder(minMass: 10, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.count == 1)
        // Four statements per run: lines 3–6 and 11–14.
        #expect(instanceLines(classes[0]) == [[3, 6], [11, 14]])
    }

    @Test("a run below the mass floor is ignored")
    func respectsMassFloor() {
        let text = """
        func alpha() {
            guard a else { return }
            foo()
            bar.baz()
            return z
        }
        func beta() {
            counter += 1
            foo()
            bar.baz()
            cache[key] = value
        }
        """
        let classes = SequenceCloneFinder(minMass: 100, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.isEmpty)
    }

    @Test("unrelated functions produce no sequence clones")
    func noFalsePositives() {
        let text = """
        func alpha() {
            let sum = numbers.reduce(0, +)
            print(sum)
        }
        func beta() {
            guard let handle = open(path) else { return }
            handle.close()
        }
        """
        let classes = SequenceCloneFinder(minMass: 8, minItems: 2).find(in: [source("a.swift", text)])
        #expect(classes.isEmpty)
    }
}
