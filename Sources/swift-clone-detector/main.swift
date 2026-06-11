//
//  main.swift
//  swift-clone-detector
//
//  Entry point: parse arguments, load sources, run the finder, print results.
//

import Foundation
import SwiftCloneDetectorKit

// Apply a value-taking option (one that consumes the next argument). Returns
// false if `argument` is not a value option, leaving it for `applyFlag`.
private func applyValueOption(
    _ argument: String,
    _ rawArguments: [String],
    _ index: inout Int,
    _ options: inout Options
) -> Bool {
    func nextValue() -> String? {
        guard index + 1 < rawArguments.count else {
            return nil
        }
        index += 1
        return rawArguments[index]
    }
    switch argument {
    case "--min-mass":
        if let value = nextValue(), let parsed = Int(value) { options.minMass = parsed }

    case "--min-distinct-identifiers":
        if let value = nextValue(), let parsed = Int(value) { options.minDistinctIdentifiers = parsed }

    case "--similarity":
        if let value = nextValue(), let parsed = Double(value) { options.similarityThreshold = parsed }

    case "--shared":
        if let value = nextValue() { options.sharedPaths.append(value) }

    default:
        return false
    }
    return true
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
    reportCrossProject(cross, roots: roots, fileCount: sources.count, nearMiss: options.nearMiss)
    exit(cross.isEmpty ? 0 : Options.clonesFoundExitCode)
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
    report(classes, fileCount: sources.count, nearMiss: options.nearMiss)
    exit(classes.isEmpty ? 0 : Options.clonesFoundExitCode)
}

run()
