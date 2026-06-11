//
//  CommandParsingTests.swift
//  SwiftCloneDetectorCLITests
//
//  Exercises the swift-argument-parser command in-process: that options, flags
//  and positional paths decode as expected, and that the validate() bounds and
//  the framework's own type/option errors reject bad input with clear messages.
//

import ArgumentParser
@testable import swift_clone_detector
import Testing

@Suite("CommandParsing")
struct CommandParsingTests {
    private func parse(_ arguments: [String]) throws -> CloneDetectorCommand {
        try CloneDetectorCommand.parse(arguments)
    }

    // Returns the message ArgumentParser would print for a failed parse, or nil
    // if parsing unexpectedly succeeded.
    private func failureMessage(_ arguments: [String]) -> String? {
        do {
            _ = try CloneDetectorCommand.parse(arguments)
            return nil
        } catch {
            return CloneDetectorCommand.message(for: error)
        }
    }

    // MARK: Successful parses

    @Test("uses the documented defaults")
    func defaults() throws {
        let command = try parse(["Sources"])
        #expect(command.minMass == 20)
        #expect(command.minDistinctIdentifiers == 0)
        #expect(command.similarity == 0.85)
        #expect(command.format == .text)
        #expect(command.nearMiss == false)
        #expect(command.type1 == false)
        #expect(command.crossProject == false)
        #expect(command.sharedPaths.isEmpty)
        #expect(command.excludePatterns.isEmpty)
        #expect(command.baselinePath == nil)
        #expect(command.writeBaselinePath == nil)
        #expect(command.paths == ["Sources"])
    }

    @Test("no positional paths parses to an empty list")
    func noPaths() throws {
        #expect(try parse([]).paths.isEmpty)
    }

    @Test("parses tuning and output options")
    func parsesOptions() throws {
        let command = try parse([
            "--min-mass", "45",
            "--min-distinct-identifiers", "3",
            "--similarity", "0.7",
            "--format", "sarif",
            "--baseline", "base.json",
            "--write-baseline", "out.json",
            "Sources", "More"
        ])
        #expect(command.minMass == 45)
        #expect(command.minDistinctIdentifiers == 3)
        #expect(command.similarity == 0.7)
        #expect(command.format == .sarif)
        #expect(command.baselinePath == "base.json")
        #expect(command.writeBaselinePath == "out.json")
        #expect(command.paths == ["Sources", "More"])
    }

    @Test("parses flags including the --near alias")
    func parsesFlags() throws {
        let typed = try parse(["--type1", "--cross-project", "Sources"])
        #expect(typed.type1)
        #expect(typed.crossProject)
        #expect(try parse(["--near", "Sources"]).nearMiss)
        #expect(try parse(["--type3", "Sources"]).nearMiss)
        #expect(try parse(["--sequence", "Sources"]).sequence)
    }

    @Test("--shared is repeatable")
    func repeatableShared() throws {
        let command = try parse(["--cross-project", "--shared", "Lib", "--shared", "Lib2", "App"])
        #expect(command.sharedPaths == ["Lib", "Lib2"])
    }

    @Test("--exclude is repeatable")
    func repeatableExclude() throws {
        let command = try parse(["--exclude", "*Tests.swift", "--exclude", "Generated/*", "Sources"])
        #expect(command.excludePatterns == ["*Tests.swift", "Generated/*"])
    }

    @Test("accepts every output format value", arguments: OutputFormat.allCases)
    func acceptsFormats(_ format: OutputFormat) throws {
        #expect(try parse(["--format", format.rawValue, "Sources"]).format == format)
    }

    // MARK: Rejected input

    @Test("rejects a min-mass below the floor")
    func rejectsMinMassFloor() {
        #expect(failureMessage(["--min-mass", "0", "Sources"])?.contains("--min-mass must be at least 1") == true)
    }

    @Test("rejects an out-of-range similarity")
    func rejectsSimilarityRange() {
        #expect(failureMessage(["--similarity", "1.5", "Sources"])?.contains("--similarity must be within") == true)
    }

    @Test("rejects a negative min-distinct-identifiers")
    func rejectsNegativeDistinct() {
        let message = failureMessage(["--min-distinct-identifiers=-1", "Sources"])
        #expect(message?.contains("--min-distinct-identifiers must be at least 0") == true)
    }

    @Test("rejects a non-integer numeric value")
    func rejectsNonInteger() {
        let message = failureMessage(["--min-mass", "abc", "Sources"])
        #expect(message?.contains("abc") == true)
        #expect(message?.contains("min-mass") == true)
    }

    @Test("rejects an unknown format and lists the valid choices")
    func rejectsUnknownFormat() {
        let message = failureMessage(["--format", "xml", "Sources"])
        #expect(message?.contains("xml") == true)
        #expect(message?.contains("json") == true)
    }

    @Test("rejects an unknown option")
    func rejectsUnknownOption() {
        #expect(failureMessage(["--bogus", "Sources"])?.contains("--bogus") == true)
    }
}
