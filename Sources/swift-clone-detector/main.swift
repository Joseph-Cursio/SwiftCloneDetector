//
//  main.swift
//  swift-clone-detector
//
//  Entry point: parse arguments, load sources, run the finder, print results.
//

import Foundation
import SwiftCloneDetectorKit

// The options that consume the following argument as their value.
private let kValueOptionNames: Set<String> = [
    "--min-mass", "--min-distinct-identifiers", "--similarity",
    "--shared", "--format", "--baseline", "--write-baseline"
]

// Validation bounds for numeric options.
private let kMinMassFloor = 1
private let kMinDistinctFloor = 0
private let kSimilarityRange = 0.0...1.0

// Parse an integer option value, or exit with a usage error if it is not a
// valid integer at or above `minimum`.
private func intValue(_ value: String, for option: String, minimum: Int) -> Int {
    guard let parsed = Int(value) else {
        failUsage("option '\(option)' expects an integer, got '\(value)'")
    }
    guard parsed >= minimum else {
        failUsage("option '\(option)' must be at least \(minimum), got \(parsed)")
    }
    return parsed
}

// Parse a floating-point option value, or exit with a usage error if it is not
// a valid number within `range`.
private func doubleValue(_ value: String, for option: String, range: ClosedRange<Double>) -> Double {
    guard let parsed = Double(value) else {
        failUsage("option '\(option)' expects a number, got '\(value)'")
    }
    guard range.contains(parsed) else {
        failUsage("option '\(option)' must be within \(range.lowerBound)...\(range.upperBound), got \(parsed)")
    }
    return parsed
}

// Apply a value-taking option (one that consumes the next argument). Returns
// false if `argument` is not a value option, leaving it for `applyFlag`.
private func applyValueOption(
    _ argument: String,
    _ rawArguments: [String],
    _ index: inout Int,
    _ options: inout Options
) -> Bool {
    guard kValueOptionNames.contains(argument) else {
        return false
    }
    guard index + 1 < rawArguments.count else {
        failUsage("option '\(argument)' requires a value")
    }
    let value = rawArguments[index + 1]
    guard !value.hasPrefix("-") else {
        failUsage("option '\(argument)' requires a value, but found the option '\(value)'")
    }
    index += 1
    if !applyTuningOption(argument, value, &options) {
        applyOutputOption(argument, value, &options)
    }
    return true
}

// Apply an analysis-tuning value option. Returns false if `argument` is not one.
private func applyTuningOption(_ argument: String, _ value: String, _ options: inout Options) -> Bool {
    switch argument {
    case "--min-mass":
        options.minMass = intValue(value, for: argument, minimum: kMinMassFloor)

    case "--min-distinct-identifiers":
        options.minDistinctIdentifiers = intValue(value, for: argument, minimum: kMinDistinctFloor)

    case "--similarity":
        options.similarityThreshold = doubleValue(value, for: argument, range: kSimilarityRange)

    case "--shared":
        options.sharedPaths.append(value)

    default:
        return false
    }
    return true
}

// Apply an output value option (format, baseline, write-baseline).
private func applyOutputOption(_ argument: String, _ value: String, _ options: inout Options) {
    switch argument {
    case "--format":
        guard let format = OutputFormat(rawValue: value) else {
            failUsage("unknown --format '\(value)' (expected: text, json, or sarif)")
        }
        options.format = format

    case "--baseline":
        options.baselinePath = value

    default:
        options.writeBaselinePath = value
    }
}

// Apply a boolean flag (or fall through to treating the argument as a path).
private func applyFlag(_ argument: String, _ options: inout Options) {
    switch argument {
    case "--type1":
        options.normalization = .type1

    case "--type2":
        options.normalization = .type2

    case "--type3", "--near":
        options.nearMiss = true

    case "--cross-project":
        options.crossProject = true

    case "-h", "--help":
        print(kUsage)
        exit(0)

    default:
        if argument.hasPrefix("-") {
            failUsage("unknown option '\(argument)' (see --help)")
        }
        options.paths.append(argument)
    }
}

private func parseOptions(_ rawArguments: [String]) -> Options {
    var options = Options()
    var index = 0
    while index < rawArguments.count {
        let argument = rawArguments[index]
        if !applyValueOption(argument, rawArguments, &index, &options) {
            applyFlag(argument, &options)
        }
        index += 1
    }
    return options
}

@MainActor
private func findClones(in sources: [SourceInput], options: Options) -> [CloneClass] {
    if options.nearMiss {
        return NearMissFinder(
            minMass: options.minMass,
            similarityThreshold: options.similarityThreshold,
            minDistinctIdentifiers: options.minDistinctIdentifiers
        ).find(in: sources)
    }
    return CloneFinder(
        normalization: options.normalization,
        minMass: options.minMass,
        minDistinctIdentifiers: options.minDistinctIdentifiers
    ).find(in: sources)
}

@MainActor
private func runCrossProject(_ options: Options) -> Never {
    let roots = projectRoots(consumers: options.paths, shared: options.sharedPaths)
    if roots.count < Options.minimumProjectRoots {
        let message = "swift-clone-detector: --cross-project needs at least two project roots "
            + "(pass consumer paths and optionally --shared)\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(Options.usageErrorExitCode)
    }

    let sources = loadSwiftFiles(paths: options.paths + options.sharedPaths)
    if sources.isEmpty {
        FileHandle.standardError.write(Data("swift-clone-detector: no .swift files found\n".utf8))
        exit(Options.usageErrorExitCode)
    }

    let classes = findClones(in: sources, options: options)
    let cross = CrossProjectAnalyzer(roots: roots).analyze(classes)

    if let path = options.writeBaselinePath {
        writeBaseline(cross.map(\.cloneClass), to: path)
        exit(0)
    }

    let (reported, knownCount) = applyBaselineCross(cross, options: options)
    emitCrossProject(reported, roots: roots, fileCount: sources.count, options: options, suppressed: knownCount)
    exit(reported.isEmpty ? 0 : Options.clonesFoundExitCode)
}

@MainActor
private func run() -> Never {
    var options = parseOptions(Array(CommandLine.arguments.dropFirst()))

    if options.crossProject {
        runCrossProject(options)
    }

    if options.paths.isEmpty {
        options.paths = ["."]
    }

    let sources = loadSwiftFiles(paths: options.paths)
    if sources.isEmpty {
        FileHandle.standardError.write(Data("swift-clone-detector: no .swift files found\n".utf8))
        exit(Options.usageErrorExitCode)
    }

    let classes = findClones(in: sources, options: options)

    if let path = options.writeBaselinePath {
        writeBaseline(classes, to: path)
        exit(0)
    }

    let (reported, knownCount) = applyBaseline(classes, options: options)
    emit(reported, fileCount: sources.count, options: options, suppressed: knownCount)
    exit(reported.isEmpty ? 0 : Options.clonesFoundExitCode)
}

// Filter detected clones through a baseline, if one was given. Returns the
// clones to report and how many were suppressed as already-known.
@MainActor
private func applyBaseline(
    _ classes: [CloneClass],
    options: Options
) -> (reported: [CloneClass], suppressed: Int) {
    guard let path = options.baselinePath else {
        return (classes, 0)
    }
    let fingerprints = loadBaseline(at: path).fingerprintSet
    let split = partitionClasses(classes, baseline: fingerprints)
    return (split.new, split.known.count)
}

@MainActor
private func applyBaselineCross(
    _ clones: [CrossProjectClone],
    options: Options
) -> (reported: [CrossProjectClone], suppressed: Int) {
    guard let path = options.baselinePath else {
        return (clones, 0)
    }
    let fingerprints = loadBaseline(at: path).fingerprintSet
    let reported = clones.filter { !fingerprints.contains(cloneFingerprint(for: $0.cloneClass)) }
    return (reported, clones.count - reported.count)
}

// Render results in the requested format, with a baseline note for text output.
@MainActor
private func emit(_ classes: [CloneClass], fileCount: Int, options: Options, suppressed: Int) {
    switch options.format {
    case .text:
        report(classes, fileCount: fileCount, nearMiss: options.nearMiss)
        if suppressed > 0 {
            print("(\(suppressed) known clone(s) suppressed by baseline.)")
        }
    case .json:
        print(jsonReport(classes, fileCount: fileCount, nearMiss: options.nearMiss))
    case .sarif:
        print(sarifReport(classes, nearMiss: options.nearMiss))
    }
}

@MainActor
private func emitCrossProject(
    _ clones: [CrossProjectClone],
    roots: [ProjectRoot],
    fileCount: Int,
    options: Options,
    suppressed: Int
) {
    switch options.format {
    case .text:
        reportCrossProject(clones, roots: roots, fileCount: fileCount, nearMiss: options.nearMiss)
        if suppressed > 0 {
            print("(\(suppressed) known clone(s) suppressed by baseline.)")
        }
    case .json:
        print(jsonReportCrossProject(clones, fileCount: fileCount))
    case .sarif:
        print(sarifReportCrossProject(clones))
    }
}

run()
