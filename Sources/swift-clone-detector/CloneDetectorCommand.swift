//
//  CloneDetectorCommand.swift
//  swift-clone-detector
//
//  The command-line interface, built on swift-argument-parser. Parses options,
//  loads sources, runs the finder and renders results. Exit code is 2 when
//  clones are found, 0 when clean, and ArgumentParser's usage status otherwise.
//

import ArgumentParser
import Foundation
import SwiftCloneDetectorKit

// Defaults and bounds, named so they are not magic numbers and can be shared
// between option declarations and validation.
private let kDefaultMinMass = 20
private let kDefaultMinDistinctIdentifiers = 0
private let kDefaultSimilarity = 0.85
private let kMinMassFloor = 1
private let kMinDistinctFloor = 0
private let kSimilarityRange = 0.0...1.0
private let kMinimumProjectRoots = 2
private let kClonesFoundExitCode: Int32 = 2

@main
struct CloneDetectorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: ToolInfo.name,
        abstract: "A Type-1/2/3 Swift clone detector built on SwiftSyntax.",
        discussion: """
        Type-1/2 match identical structure; --type3 finds copies that have \
        drifted by a few statements. Paths may be files or directories \
        (searched recursively) and default to the current directory. The exit \
        code is 2 when clones are found and 0 when clean.

        In --cross-project mode each positional path is a consumer project and \
        each --shared path is a library they depend on. Clones confined to one \
        project are dropped; the rest are flagged as hoist candidates \
        (duplicated across consumers — extract into the shared package) or as \
        duplicated-from-shared (a consumer re-copied shared code — import it \
        instead).
        """,
        version: ToolInfo.version
    )

    @Flag(name: .customLong("type1"), help: "Match exact clones only; do not normalize identifiers or literals.")
    var type1 = false

    @Flag(name: .customLong("type2"), help: "Also match renamed identifiers and literals (the default).")
    var type2 = false

    @Flag(
        name: [.customLong("type3"), .customLong("near")],
        help: "Near-miss clones: copies that drifted by inserted, removed or changed statements."
    )
    var nearMiss = false

    @Flag(name: .customLong("cross-project"), help: "Only report clones spanning two or more project roots.")
    var crossProject = false

    @Option(name: .customLong("min-mass"), help: "Minimum subtree size in AST nodes.")
    var minMass = kDefaultMinMass

    @Option(
        name: .customLong("min-distinct-identifiers"),
        help: "Drop fragments with fewer than this many distinct identifier tokens (0 = off)."
    )
    var minDistinctIdentifiers = kDefaultMinDistinctIdentifiers

    @Option(name: .customLong("similarity"), help: "Near-miss similarity threshold in [0, 1].")
    var similarity = kDefaultSimilarity

    @Option(
        name: .customLong("shared"),
        help: ArgumentHelp("Mark a project root as the shared package (repeatable).", valueName: "path")
    )
    var sharedPaths: [String] = []

    @Option(
        name: .customLong("exclude"),
        help: ArgumentHelp(
            "Skip files whose path or name matches this glob, e.g. '*Tests.swift' (repeatable).",
            valueName: "glob"
        )
    )
    var excludePatterns: [String] = []

    @Option(name: .customLong("format"), help: "Output format: text, json, or sarif.")
    var format: OutputFormat = .text

    @Option(
        name: .customLong("baseline"),
        help: ArgumentHelp("Only report clones absent from this baseline file.", valueName: "path")
    )
    var baselinePath: String?

    @Option(
        name: .customLong("write-baseline"),
        help: ArgumentHelp("Write the current clones to this path as a baseline and exit.", valueName: "path")
    )
    var writeBaselinePath: String?

    @Argument(help: ArgumentHelp("Files or directories to scan.", valueName: "path"))
    var paths: [String] = []

    // type1 wins if both type flags are given; type2 is the implicit default.
    private var normalization: Normalization {
        type1 ? .type1 : .type2
    }

    func validate() throws {
        guard minMass >= kMinMassFloor else {
            throw ValidationError("--min-mass must be at least \(kMinMassFloor).")
        }
        guard minDistinctIdentifiers >= kMinDistinctFloor else {
            throw ValidationError("--min-distinct-identifiers must be at least \(kMinDistinctFloor).")
        }
        guard kSimilarityRange.contains(similarity) else {
            throw ValidationError(
                "--similarity must be within \(kSimilarityRange.lowerBound)...\(kSimilarityRange.upperBound)."
            )
        }
    }

    func run() throws {
        if crossProject {
            try runCrossProject()
            return
        }

        let scanPaths = paths.isEmpty ? ["."] : paths
        let sources = loadSwiftFiles(paths: scanPaths, excluding: excludePatterns)
        guard !sources.isEmpty else {
            throw ValidationError("no .swift files found")
        }

        let classes = findClones(in: sources)
        if let path = writeBaselinePath {
            try writeBaseline(classes, to: path)
            return
        }

        let outcome = try applyBaseline(classes)
        emit(outcome.reported, fileCount: sources.count, suppressed: outcome.suppressed)
        if !outcome.reported.isEmpty {
            throw ExitCode(kClonesFoundExitCode)
        }
    }

    private func runCrossProject() throws {
        let roots = projectRoots(consumers: paths, shared: sharedPaths)
        guard roots.count >= kMinimumProjectRoots else {
            throw ValidationError("--cross-project needs at least two project roots "
                + "(pass consumer paths and optionally --shared)")
        }

        let sources = loadSwiftFiles(paths: paths + sharedPaths, excluding: excludePatterns)
        guard !sources.isEmpty else {
            throw ValidationError("no .swift files found")
        }

        let classes = findClones(in: sources)
        let cross = CrossProjectAnalyzer(roots: roots).analyze(classes)
        if let path = writeBaselinePath {
            try writeBaseline(cross.map(\.cloneClass), to: path)
            return
        }

        let outcome = try applyBaselineCross(cross)
        emitCrossProject(outcome.reported, roots: roots, fileCount: sources.count, suppressed: outcome.suppressed)
        if !outcome.reported.isEmpty {
            throw ExitCode(kClonesFoundExitCode)
        }
    }

    private func findClones(in sources: [SourceInput]) -> [CloneClass] {
        if nearMiss {
            return NearMissFinder(
                minMass: minMass,
                similarityThreshold: similarity,
                minDistinctIdentifiers: minDistinctIdentifiers
            ).find(in: sources)
        }
        return CloneFinder(
            normalization: normalization,
            minMass: minMass,
            minDistinctIdentifiers: minDistinctIdentifiers
        ).find(in: sources)
    }

    // Filter detected clones through a baseline, if one was given. Returns the
    // clones to report and how many were suppressed as already-known.
    private func applyBaseline(
        _ classes: [CloneClass]
    ) throws -> (reported: [CloneClass], suppressed: Int) {
        guard let path = baselinePath else {
            return (classes, 0)
        }
        let fingerprints = try loadBaseline(at: path).fingerprintSet
        let split = partitionClasses(classes, baseline: fingerprints)
        return (split.new, split.known.count)
    }

    private func applyBaselineCross(
        _ clones: [CrossProjectClone]
    ) throws -> (reported: [CrossProjectClone], suppressed: Int) {
        guard let path = baselinePath else {
            return (clones, 0)
        }
        let fingerprints = try loadBaseline(at: path).fingerprintSet
        let reported = clones.filter { !fingerprints.contains(cloneFingerprint(for: $0.cloneClass)) }
        return (reported, clones.count - reported.count)
    }

    // Render results in the requested format, with a baseline note for text output.
    private func emit(_ classes: [CloneClass], fileCount: Int, suppressed: Int) {
        switch format {
        case .text:
            report(classes, fileCount: fileCount, nearMiss: nearMiss)
            if suppressed > 0 {
                print("(\(suppressed) known clone(s) suppressed by baseline.)")
            }
        case .json:
            print(jsonReport(classes, fileCount: fileCount, nearMiss: nearMiss))
        case .sarif:
            print(sarifReport(classes, nearMiss: nearMiss))
        }
    }

    private func emitCrossProject(
        _ clones: [CrossProjectClone],
        roots: [ProjectRoot],
        fileCount: Int,
        suppressed: Int
    ) {
        switch format {
        case .text:
            reportCrossProject(clones, roots: roots, fileCount: fileCount, nearMiss: nearMiss)
            if suppressed > 0 {
                print("(\(suppressed) known clone(s) suppressed by baseline.)")
            }
        case .json:
            print(jsonReportCrossProject(clones, fileCount: fileCount))
        case .sarif:
            print(sarifReportCrossProject(clones))
        }
    }
}
