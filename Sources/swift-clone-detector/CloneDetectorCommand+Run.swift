//
//  CloneDetectorCommand+Run.swift
//  swift-clone-detector
//
//  What the command does once its arguments are parsed. Split from the option
//  declarations so neither half has to be read to change the other.
//

import ArgumentParser
import Foundation
import SwiftCloneDetectorKit

extension CloneDetectorCommand {
    func run() throws {
        if crossProject {
            try runCrossProject()
            return
        }

        let scanPaths = paths.isEmpty ? ["."] : paths
        let discovered = loadSwiftFiles(paths: scanPaths, excluding: excludePatterns)
        let sources = scannable(discovered)
        guard !sources.isEmpty else {
            throw ValidationError("no .swift files found")
        }

        let classes = findClones(in: sources)
        if let path = writeBaselinePath {
            try writeBaseline(classes, to: path)
            return
        }

        let outcome = try applyBaseline(classes)
        emit(
            outcome.reported,
            fileCount: sources.count,
            suppressed: outcome.suppressed,
            skippedGenerated: discovered.count - sources.count
        )
        if !outcome.reported.isEmpty {
            throw ExitCode(kClonesFoundExitCode)
        }
    }

    /// The discovered files this run will actually parse.
    func scannable(_ discovered: [SourceInput]) -> [SourceInput] {
        includeGenerated ? discovered : discovered.filter { !$0.isGenerated }
    }

    func runCrossProject() throws {
        let roots = projectRoots(consumers: paths, shared: sharedPaths)
        guard roots.count >= kMinimumProjectRoots else {
            throw ValidationError("--cross-project needs at least two project roots "
                + "(pass consumer paths and optionally --shared)")
        }

        let discovered = loadSwiftFiles(paths: paths + sharedPaths, excluding: excludePatterns)
        let sources = scannable(discovered)
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
        emitCrossProject(
            outcome.reported,
            roots: roots,
            fileCount: sources.count,
            suppressed: outcome.suppressed,
            skippedGenerated: discovered.count - sources.count
        )
        if !outcome.reported.isEmpty {
            throw ExitCode(kClonesFoundExitCode)
        }
    }

    func findClones(in sources: [SourceInput]) -> [CloneClass] {
        let found = passes.flatMap { pass in
            finder(for: pass).find(in: sources)
        }
        return passes.count > 1 ? CloneClass.merged(found) : found
    }

    private func finder(for pass: DetectionPass) -> any ClonePass {
        switch pass {
        case .subtree:
            return CloneFinder(
                normalization: normalization,
                minMass: minMass,
                minDistinctIdentifiers: minDistinctIdentifiers,
                minLines: minLines
            )
        case .nearMiss:
            return NearMissFinder(
                minMass: minMass,
                similarityThreshold: similarity,
                minDistinctIdentifiers: minDistinctIdentifiers,
                minLines: minLines,
                useRarityWeighting: !uniformWeighting,
                minDistinctiveness: minDistinctiveness,
                minIdentifierOverlap: minIdentifierOverlap
            )
        case .sequence:
            return SequenceCloneFinder(
                normalization: normalization,
                minMass: minMass,
                minDistinctIdentifiers: minDistinctIdentifiers,
                minLines: minLines,
                minIdentifierOverlap: minIdentifierOverlap
            )
        }
    }

    // Filter detected clones through a baseline, if one was given. Returns the
    // clones to report and how many were suppressed as already-known.
    func applyBaseline(
        _ classes: [CloneClass]
    ) throws -> (reported: [CloneClass], suppressed: Int) {
        guard let path = baselinePath else {
            return (classes, 0)
        }
        let fingerprints = try loadBaseline(at: path).fingerprintSet
        let split = partitionClasses(classes, baseline: fingerprints)
        return (split.new, split.known.count)
    }

    func applyBaselineCross(
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
    func emit(_ classes: [CloneClass], fileCount: Int, suppressed: Int, skippedGenerated: Int) {
        switch format {
        case .text:
            report(classes, fileCount: fileCount, nearMiss: reportsNearMiss)
            if suppressed > 0 {
                print("(\(suppressed) known clone(s) suppressed by baseline.)")
            }
            reportSkippedGenerated(skippedGenerated)
        case .json:
            print(jsonReport(classes, fileCount: fileCount, nearMiss: reportsNearMiss))
        case .sarif:
            print(sarifReport(classes, nearMiss: reportsNearMiss))
        }
    }

    func emitCrossProject(
        _ clones: [CrossProjectClone],
        roots: [ProjectRoot],
        fileCount: Int,
        suppressed: Int,
        skippedGenerated: Int
    ) {
        switch format {
        case .text:
            reportCrossProject(clones, roots: roots, fileCount: fileCount, nearMiss: reportsNearMiss)
            if suppressed > 0 {
                print("(\(suppressed) known clone(s) suppressed by baseline.)")
            }
            reportSkippedGenerated(skippedGenerated)
        case .json:
            print(jsonReportCrossProject(clones, fileCount: fileCount))
        case .sarif:
            print(sarifReportCrossProject(clones))
        }
    }
}
