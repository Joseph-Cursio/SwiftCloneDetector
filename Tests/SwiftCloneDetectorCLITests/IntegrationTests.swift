//
//  IntegrationTests.swift
//  SwiftCloneDetectorCLITests
//
//  End-to-end tests that run the command over real temp-directory fixtures,
//  exercising the orchestration (run/runCrossProject/findClones/applyBaseline/
//  emit), file discovery, the console reporters and baseline disk I/O — the
//  paths the in-process parser tests don't reach.
//
//  Serialized because each test captures the process-global stdout; running them
//  concurrently would let one test's redirect swallow another's output.
//

import ArgumentParser
import Foundation
@testable import swift_clone_detector
import SwiftCloneDetectorKit
import Testing

// Fixture functions, each large enough to clear the default 20-node min-mass.
// File-scoped so they don't count against the suite's type-body length.
private let kDupOne = """
func scale(_ value: Int) -> Int {
    let doubled = value * 2
    let shifted = doubled + 100
    let clamped = max(0, min(shifted, 9999))
    return clamped
}
"""

private let kDupTwo = """
func combine(_ items: [String]) -> String {
    var result = ""
    for item in items {
        result += item
        result += ","
    }
    return result
}
"""

@Suite("Integration", .serialized)
struct IntegrationTests {
    // MARK: Fixture + capture helpers

    private func withTree(_ files: [String: String], _ body: (URL) throws -> Void) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try write(files, under: root)
        try body(root)
    }

    private func write(_ files: [String: String], under root: URL) throws {
        let manager = FileManager.default
        for (relativePath, contents) in files {
            let fileURL = root.appendingPathComponent(relativePath)
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // Redirect stdout to a temp file for the duration of `body`, returning what
    // was printed.
    private func captureStdout(_ body: () throws -> Void) rethrows -> String {
        let ownerReadWrite: mode_t = 0o600
        fflush(stdout)
        let saved = dup(STDOUT_FILENO)
        let path = NSTemporaryDirectory() + UUID().uuidString
        let descriptor = open(path, O_RDWR | O_CREAT | O_TRUNC, ownerReadWrite)
        dup2(descriptor, STDOUT_FILENO)
        defer {
            fflush(stdout)
            dup2(saved, STDOUT_FILENO)
            close(saved)
            close(descriptor)
            try? FileManager.default.removeItem(atPath: path)
        }
        try body()
        fflush(stdout)
        let data = FileManager.default.contents(atPath: path) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    // Parse + run, capturing stdout and the ExitCode (nil = clean exit).
    private func run(_ arguments: [String]) throws -> (exit: Int32?, output: String) {
        let command = try CloneDetectorCommand.parse(arguments)
        var exitCode: Int32?
        let output = try captureStdout {
            do {
                try command.run()
            } catch let code as ExitCode {
                exitCode = code.rawValue
            }
        }
        return (exitCode, output)
    }

    // The message ArgumentParser would print for an error thrown by run().
    private func runErrorMessage(_ arguments: [String]) -> String? {
        do {
            _ = try run(arguments)
            return nil
        } catch {
            return CloneDetectorCommand.message(for: error)
        }
    }

    // MARK: Core run()

    @Test("reports a planted clone and exits 2")
    func findsClone() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let result = try run([root.path])
            #expect(result.exit == 2)
            #expect(result.output.contains("Found 1 Type-1/2 clone class"))
        }
    }

    @Test("a clean tree exits 0")
    func cleanTree() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupTwo]) { root in
            let result = try run([root.path])
            #expect(result.exit == nil)
            #expect(result.output.contains("No Type-1/2 clones found"))
        }
    }

    @Test("a directory with no Swift files is a usage error")
    func noSwiftFiles() throws {
        try withTree(["readme.txt": "nothing here"]) { root in
            #expect(runErrorMessage([root.path])?.contains("no .swift files found") == true)
        }
    }

    @Test("a single file path is scanned, not just directories")
    func singleFilePath() throws {
        // Two identical functions in one file form a clone within that file.
        try withTree(["pair.swift": kDupOne + "\n" + kDupOne]) { root in
            let result = try run([root.appendingPathComponent("pair.swift").path])
            #expect(result.exit == 2)
        }
    }

    // MARK: Output formats end-to-end

    @Test("--format json emits a parseable document")
    func jsonFormat() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let result = try run(["--format", "json", root.path])
            #expect(result.exit == 2)
            let parsed = try JSONSerialization.jsonObject(with: Data(result.output.utf8))
            let object = try #require(parsed as? [String: Any])
            #expect((object["cloneCount"] as? Int ?? 0) >= 1)
        }
    }

    @Test("--format sarif emits a 2.1.0 log")
    func sarifFormat() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let result = try run(["--format", "sarif", root.path])
            let parsed = try JSONSerialization.jsonObject(with: Data(result.output.utf8))
            let object = try #require(parsed as? [String: Any])
            #expect(object["version"] as? String == "2.1.0")
        }
    }

    // MARK: Baseline I/O

    @Test("--write-baseline writes a decodable baseline")
    func writeBaseline() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let baselinePath = root.appendingPathComponent("baseline.json").path
            let result = try run(["--write-baseline", baselinePath, root.path])
            #expect(result.exit == nil)
            #expect(result.output.contains("Wrote baseline"))
            let baseline = try loadBaseline(at: baselinePath)
            #expect(baseline.version == Baseline.currentVersion)
            #expect(baseline.clones.isEmpty == false)
        }
    }

    @Test("a baseline suppresses its known clones")
    func baselineSuppresses() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let baselinePath = root.appendingPathComponent("baseline.json").path
            _ = try run(["--write-baseline", baselinePath, root.path])
            let result = try run(["--baseline", baselinePath, root.path])
            #expect(result.exit == nil)
            #expect(result.output.contains("suppressed by baseline"))
        }
    }

    @Test("a baseline still surfaces a new clone")
    func baselineSurfacesNew() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let baselinePath = root.appendingPathComponent("baseline.json").path
            _ = try run(["--write-baseline", baselinePath, root.path])
            // Introduce a second, distinct clone class not in the baseline.
            try write(["c.swift": kDupTwo, "d.swift": kDupTwo], under: root)
            let result = try run(["--baseline", baselinePath, root.path])
            #expect(result.exit == 2)
        }
    }

    @Test("a missing baseline file is a usage error")
    func missingBaseline() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne]) { root in
            let message = runErrorMessage(["--baseline", root.appendingPathComponent("nope.json").path, root.path])
            #expect(message?.contains("could not read baseline file") == true)
        }
    }

    @Test("a corrupt baseline file is a usage error")
    func corruptBaseline() throws {
        try withTree(["a.swift": kDupOne, "b.swift": kDupOne, "bad.json": "not json"]) { root in
            let message = runErrorMessage([
                "--baseline", root.appendingPathComponent("bad.json").path, root.path
            ])
            #expect(message?.contains("not a valid baseline") == true)
        }
    }

    // MARK: Cross-project

    @Test("cross-project flags a hoist candidate and exits 2")
    func crossProjectHoist() throws {
        try withTree([
            "appA/File.swift": kDupOne,
            "appB/File.swift": kDupOne,
            "lib/Lib.swift": kDupTwo
        ]) { root in
            let result = try run([
                "--cross-project",
                "--shared", root.appendingPathComponent("lib").path,
                root.appendingPathComponent("appA").path,
                root.appendingPathComponent("appB").path
            ])
            #expect(result.exit == 2)
            #expect(result.output.contains("HOIST CANDIDATES"))
        }
    }

    @Test("cross-project with a single root is a usage error")
    func crossProjectTooFewRoots() throws {
        try withTree(["appA/File.swift": kDupOne]) { root in
            let message = runErrorMessage(["--cross-project", root.appendingPathComponent("appA").path])
            #expect(message?.contains("at least two project roots") == true)
        }
    }

    // MARK: Exclude globs

    private func basename(_ source: SourceInput) -> String {
        URL(fileURLWithPath: source.path).lastPathComponent
    }

    @Test("discovery skips build artifacts and honours a name glob")
    func excludeByName() throws {
        try withTree([
            "Foo.swift": kDupOne,
            "FooTests.swift": kDupOne,
            "Generated/Gen.swift": kDupTwo,
            ".build/Vendor.swift": kDupOne
        ]) { root in
            // Build artifacts are always skipped, with or without --exclude.
            let all = loadSwiftFiles(paths: [root.path], excluding: [])
            #expect(all.map(basename).sorted() == ["Foo.swift", "FooTests.swift", "Gen.swift"])

            let kept = loadSwiftFiles(paths: [root.path], excluding: ["*Tests.swift"])
            #expect(kept.map(basename).sorted() == ["Foo.swift", "Gen.swift"])
        }
    }

    @Test("a path glob excludes a whole directory")
    func excludeByPath() throws {
        try withTree(["Foo.swift": kDupOne, "Generated/Gen.swift": kDupTwo]) { root in
            let kept = loadSwiftFiles(paths: [root.path], excluding: ["*/Generated/*"])
            #expect(kept.map(basename) == ["Foo.swift"])
        }
    }

    @Test("--exclude removes a clone end-to-end")
    func excludeEndToEnd() throws {
        try withTree(["Foo.swift": kDupOne, "FooTests.swift": kDupOne]) { root in
            let withAll = try run([root.path])
            #expect(withAll.exit == 2)
            let filtered = try run(["--exclude", "*Tests.swift", root.path])
            #expect(filtered.exit == nil)
        }
    }

    // MARK: Sequence clones

    @Test("--sequence detects a statement run the subtree pass misses")
    func sequenceFindsRun() throws {
        let runSource = """
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
        try withTree(["pair.swift": runSource]) { root in
            // The subtree pass finds nothing at this floor — the run isn't a node.
            let subtree = try run(["--min-mass", "20", root.path])
            #expect(subtree.exit == nil)
            // The sequence pass catches the shared run of statements.
            let sequence = try run(["--sequence", "--min-mass", "20", root.path])
            #expect(sequence.exit == 2)
            #expect(sequence.output.contains("Found 1 Type-1/2 clone class"))
        }
    }
}
