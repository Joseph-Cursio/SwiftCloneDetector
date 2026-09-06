//
//  CommandLineSupport.swift
//  swift-clone-detector
//
//  File discovery and the console reporter. Kept out of the command definition
//  so it stays a thin argument-parsing shell.
//

import Foundation
import SwiftCloneDetectorKit

/// Build the project-root set: each consumer path plus each shared path, named
/// by its last path component.
func projectRoots(consumers: [String], shared: [String]) -> [ProjectRoot] {
    consumers.map { ProjectRoot(name: projectName(for: $0), path: $0) }
        + shared.map { ProjectRoot(name: projectName(for: $0), path: $0, isShared: true) }
}

private func projectName(for path: String) -> String {
    let components = path.split(separator: "/", omittingEmptySubsequences: true)
    return components.last.map(String.init) ?? path
}

// Skip generated/derived trees: SwiftPM build dirs (.build, .build-coverage,
// index-build), Xcode DerivedData, .swiftpm, and .git. Crucially this drops the
// dependency *checkouts* nested under .build*, which are vendored copies of
// other packages — not duplication the user wrote.
private let kExcludedDirectoryNames: Set<String> = [".swiftpm", "DerivedData", ".git"]

private func isInBuildArtifact(_ relativePath: String) -> Bool {
    relativePath.split(separator: "/").contains { component in
        component.hasPrefix(".build") || kExcludedDirectoryNames.contains(String(component))
    }
}

// A file is excluded when any `--exclude` glob matches its full path or its bare
// file name. `fnmatch` runs without FNM_PATHNAME, so `*` spans directories —
// `*Tests.swift` and `*/Generated/*` both work.
private func isExcluded(_ path: String, patterns: [String]) -> Bool {
    guard !patterns.isEmpty else {
        return false
    }
    let noFlags: Int32 = 0
    let matched: Int32 = 0
    let basename = URL(fileURLWithPath: path).lastPathComponent
    return patterns.contains { pattern in
        fnmatch(pattern, path, noFlags) == matched || fnmatch(pattern, basename, noFlags) == matched
    }
}

func loadSwiftFiles(paths: [String], excluding patterns: [String]) -> [SourceInput] {
    let fileManager = FileManager.default
    var swiftFilePaths: [String] = []

    for path in paths {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }

        if isDirectory.boolValue {
            let enumerator = fileManager.enumerator(atPath: path)
            while let item = enumerator?.nextObject() as? String {
                guard item.hasSuffix(".swift") else { continue }
                if isInBuildArtifact(item) { continue }
                let separator = path.hasSuffix("/") ? "" : "/"
                let fullPath = path + separator + item
                if isExcluded(fullPath, patterns: patterns) { continue }
                swiftFilePaths.append(fullPath)
            }
        } else if path.hasSuffix(".swift"), !isExcluded(path, patterns: patterns) {
            swiftFilePaths.append(path)
        }
    }

    return swiftFilePaths.compactMap { path in
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return SourceInput(path: path, text: text)
    }
}

/// Say how many machine-written files were left unscanned, and how to include them.
/// Silent when there were none, so an ordinary run gains no line.
func reportSkippedGenerated(_ count: Int) {
    guard count > 0 else {
        return
    }
    print("(\(count) generated file(s) skipped; pass --include-generated to scan them.)")
}

func report(_ classes: [CloneClass], fileCount: Int, nearMiss: Bool) {
    let mixedPasses = Set(classes.map(\.pass)).count > 1
    // A single-pass run keeps its established wording; a mixed one has no one type.
    let label = mixedPasses ? "" : (nearMiss ? "Type-3 near-miss " : "Type-1/2 ")

    guard !classes.isEmpty else {
        print("No \(label)clones found across \(fileCount) file(s).")
        return
    }

    var duplicatedLines = 0
    for (index, cloneClass) in classes.enumerated() {
        let first = cloneClass.instances[0]
        let lineSpan = first.endLine - first.startLine + 1
        duplicatedLines += lineSpan * (cloneClass.instances.count - 1)

        var headline = "Clone #\(index + 1) — \(cloneClass.instances.count) instances, "
            + "\(cloneClass.mass) nodes (~\(lineSpan) lines)"
        if let similarity = cloneClass.similarity {
            headline += ", \(Int((similarity * 100).rounded()))% similar"
        }
        // Only when passes ran together: otherwise the run's own header says it.
        if mixedPasses {
            headline += " [\(cloneClass.pass.label)]"
        }

        print("")
        print("\(headline):")
        for instance in cloneClass.instances {
            print("  \(instance.path):\(instance.startLine)-\(instance.endLine)")
        }
    }

    print("")
    print("Found \(classes.count) \(label)clone class(es) across \(fileCount) file(s); "
        + "~\(duplicatedLines) duplicated line(s).")
    if mixedPasses {
        let byPass = DetectionPass.allCases
            .map { pass in (pass, classes.filter { $0.pass == pass }.count) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \($0.0.label)" }
        print("  " + byPass.joined(separator: ", ") + " — each pass sees shapes the others cannot.")
    }
}

func reportCrossProject(
    _ clones: [CrossProjectClone],
    roots: [ProjectRoot],
    fileCount: Int,
    nearMiss: Bool
) {
    let label = nearMiss ? "Type-3 near-miss" : "Type-1/2"
    let sharedNames = roots.filter(\.isShared).map(\.name)
    let sharedLabel = sharedNames.isEmpty ? "the shared package" : sharedNames.joined(separator: ", ")

    guard !clones.isEmpty else {
        print("No cross-project \(label) clones found across \(fileCount) file(s) "
            + "in \(roots.count) project(s).")
        return
    }

    let hoist = clones.filter { $0.kind == .hoistCandidate }
    let copied = clones.filter { $0.kind == .duplicatedFromShared }

    if !hoist.isEmpty {
        print("")
        print("HOIST CANDIDATES — duplicated across consumers, extract into \(sharedLabel):")
        printGroup(hoist)
    }

    if !copied.isEmpty {
        print("")
        print("DUPLICATED FROM SHARED — a consumer re-copied \(sharedLabel); import it instead:")
        printGroup(copied)
    }

    print("")
    print("Found \(clones.count) cross-project \(label) clone class(es): "
        + "\(hoist.count) to hoist, \(copied.count) re-copied from shared.")
}

private func printGroup(_ clones: [CrossProjectClone]) {
    for (offset, clone) in clones.enumerated() {
        let cloneClass = clone.cloneClass
        let first = cloneClass.instances[0]
        let lineSpan = first.endLine - first.startLine + 1
        var headline = "  #\(offset + 1) — \(cloneClass.instances.count) instances, "
            + "\(cloneClass.mass) nodes (~\(lineSpan) lines), in \(clone.projects.joined(separator: " + "))"
        if let similarity = cloneClass.similarity {
            headline += ", \(Int((similarity * 100).rounded()))% similar"
        }
        print(headline)
        for instance in cloneClass.instances {
            print("      \(instance.path):\(instance.startLine)-\(instance.endLine)")
        }
    }
}
