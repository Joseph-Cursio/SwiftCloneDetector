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
private let kDefaultMinLines = 2
private let kMinLinesFloor = 1
let kSimilarityRange = 0.0...1.0
let kMinimumProjectRoots = 2
let kClonesFoundExitCode: Int32 = 2

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

    @Flag(
        name: .customLong("sequence"),
        help: "Detect duplicated runs of consecutive statements that aren't a single subtree."
    )
    var sequence = false

    @Flag(name: .customLong("cross-project"), help: "Only report clones spanning two or more project roots.")
    var crossProject = false

    @Option(name: .customLong("min-mass"), help: "Minimum subtree size in AST nodes.")
    var minMass = kDefaultMinMass

    @Option(
        name: .customLong("min-distinct-identifiers"),
        help: "Drop fragments with fewer than this many distinct identifier tokens (0 = off)."
    )
    var minDistinctIdentifiers = kDefaultMinDistinctIdentifiers

    @Option(
        name: .customLong("min-lines"),
        help: ArgumentHelp(
            "Minimum lines a fragment must span (1 = off). --min-mass counts AST nodes, and "
                + "twenty of them fit on one line."
        )
    )
    var minLines = kDefaultMinLines

    @Flag(
        name: .customLong("uniform-weighting"),
        help: ArgumentHelp(
            "Weight every node kind equally in near-miss scoring. The default weights a kind by "
                + "how rare it is, so constructs every fragment carries stop deciding the score."
        )
    )
    var uniformWeighting = false

    @Option(name: .customLong("similarity"), help: "Near-miss similarity threshold in [0, 1].")
    var similarity = kDefaultSimilarity

    @Option(
        name: .customLong("shared"),
        help: ArgumentHelp("Mark a project root as the shared package (repeatable).", valueName: "path")
    )
    var sharedPaths: [String] = []

    @Flag(
        name: .customLong("include-generated"),
        help: ArgumentHelp(
            "Also scan machine-written files. They are skipped by default: generated code is "
                + "duplicated by construction, and none of it is worth deduplicating."
        )
    )
    var includeGenerated = false

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
    var normalization: Normalization {
        type1 ? .type1 : .type2
    }

    // Sequence clones are exact/renamed duplications, so they report as Type-1/2
    // even if --type3 was also passed; --sequence selects the strategy.
    var reportsNearMiss: Bool {
        nearMiss && !sequence
    }

    func validate() throws {
        guard minMass >= kMinMassFloor else {
            throw ValidationError("--min-mass must be at least \(kMinMassFloor).")
        }
        guard minDistinctIdentifiers >= kMinDistinctFloor else {
            throw ValidationError("--min-distinct-identifiers must be at least \(kMinDistinctFloor).")
        }
        guard minLines >= kMinLinesFloor else {
            throw ValidationError("--min-lines must be at least \(kMinLinesFloor).")
        }
        guard kSimilarityRange.contains(similarity) else {
            throw ValidationError(
                "--similarity must be within \(kSimilarityRange.lowerBound)...\(kSimilarityRange.upperBound)."
            )
        }
    }
}
