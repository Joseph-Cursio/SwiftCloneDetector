//
//  BaselineFile.swift
//  swift-clone-detector
//
//  Reading and writing the baseline file. Failures surface as ValidationError so
//  ArgumentParser reports them and exits with its usage status. Encoding reuses
//  the reporter's key-sorting encoder so a written baseline is reproducible.
//

import ArgumentParser
import Foundation
import SwiftCloneDetectorKit

/// Load a baseline file, or throw a usage error if it can't be read/parsed.
func loadBaseline(at path: String) throws -> Baseline {
    guard let data = FileManager.default.contents(atPath: path) else {
        throw ValidationError("could not read baseline file at \(path)")
    }
    guard let baseline = try? JSONDecoder().decode(Baseline.self, from: data) else {
        throw ValidationError("baseline file at \(path) is not a valid baseline")
    }
    guard baseline.version == Baseline.currentVersion else {
        throw ValidationError("baseline at \(path) is version \(baseline.version); "
            + "this tool writes version \(Baseline.currentVersion). Regenerate it with --write-baseline.")
    }
    return baseline
}

/// Write a baseline built from the given clones, or throw a usage error.
func writeBaseline(_ classes: [CloneClass], to path: String) throws {
    let baseline = Baseline(classes: classes)
    guard let data = try? makeEncoder().encode(baseline) else {
        throw ValidationError("could not encode baseline")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        throw ValidationError("could not write baseline to \(path): \(error.localizedDescription)")
    }
    print("Wrote baseline with \(classes.count) clone(s) to \(path).")
}
