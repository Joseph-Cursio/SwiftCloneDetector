//
//  BaselineFile.swift
//  swift-clone-detector
//
//  Reading and writing the baseline file, plus the usage-error exit shared by
//  argument parsing. Encoding reuses the reporter's key-sorting encoder so a
//  written baseline is reproducible.
//

import Foundation
import SwiftCloneDetectorKit

/// Load a baseline file, or exit with a usage error if it can't be read/parsed.
func loadBaseline(at path: String) -> Baseline {
    guard let data = FileManager.default.contents(atPath: path) else {
        failUsage("could not read baseline file at \(path)")
    }
    guard let baseline = try? JSONDecoder().decode(Baseline.self, from: data) else {
        failUsage("baseline file at \(path) is not a valid baseline")
    }
    if baseline.version != Baseline.currentVersion {
        failUsage("baseline at \(path) is version \(baseline.version); "
            + "this tool writes version \(Baseline.currentVersion). Regenerate it with --write-baseline.")
    }
    return baseline
}

/// Write a baseline built from the given clones, or exit on failure.
func writeBaseline(_ classes: [CloneClass], to path: String) {
    let baseline = Baseline(classes: classes)
    guard let data = try? makeEncoder().encode(baseline) else {
        failUsage("could not encode baseline")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        failUsage("could not write baseline to \(path): \(error.localizedDescription)")
    }
    print("Wrote baseline with \(classes.count) clone(s) to \(path).")
}

/// Print a usage error to stderr and exit with the usage-error status.
func failUsage(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(Options.toolName): \(message)\n".utf8))
    exit(Options.usageErrorExitCode)
}
