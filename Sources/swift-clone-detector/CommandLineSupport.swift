//
//  CommandLineSupport.swift
//  swift-clone-detector
//
//  File discovery, help text, and the console reporter. Kept out of main.swift
//  so the entry point stays a thin argument-parsing shell.
//

import Foundation
import SwiftCloneDetectorKit

let kUsage = """
swift-clone-detector — Type-1/2/3 Swift clone detector

USAGE:
  swift-clone-detector [options] [paths...]

OPTIONS:
  --type1            exact clones only (no identifier/literal normalization)
  --type2            also match renamed identifiers and literals (default)
  --type3, --near    near-miss clones (inserted/removed/changed statements)
  --similarity N     near-miss threshold in [0, 1] (default: 0.85)
  --min-mass N       minimum subtree size in AST nodes (default: 20)
  --cross-project    only report clones spanning two or more project roots
  --shared PATH      mark a project root as the shared package (repeatable)
  -h, --help         show this help

Type-1/2 match identical structure; --type3 finds copies that have drifted by a
few statements. Paths may be files or directories (searched recursively), and
default to the current directory. Exit code is 2 when clones are found.

In --cross-project mode, each positional path is a consumer project and each
--shared path is the library they depend on. Clones confined to one project are
dropped; the rest are flagged either as hoist candidates (duplicated across
consumers — extract into the shared package) or as duplicated-from-shared (a
consumer re-copied shared code — import it instead). Example:

  swift-clone-detector --cross-project --shared ../LintStudioUI \\
    ../SwiftLintRuleStudio ../SwiftProjectLint ../SwiftFormatLint
"""

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

func loadSwiftFiles(paths: [String]) -> [SourceInput] {
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
                swiftFilePaths.append((path as NSString).appendingPathComponent(item))
            }
        } else if path.hasSuffix(".swift") {
            swiftFilePaths.append(path)
        }
    }

    return swiftFilePaths.compactMap { path in
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return SourceInput(path: path, text: text)
    }
}

func report(_ classes: [CloneClass], fileCount: Int, nearMiss: Bool) {
    let label = nearMiss ? "Type-3 near-miss" : "Type-1/2"

    guard !classes.isEmpty else {
        print("No \(label) clones found across \(fileCount) file(s).")
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

        print("")
        print("\(headline):")
        for instance in cloneClass.instances {
            print("  \(instance.path):\(instance.startLine)-\(instance.endLine)")
        }
    }

    print("")
    print("Found \(classes.count) \(label) clone class(es) across \(fileCount) file(s); "
        + "~\(duplicatedLines) duplicated line(s).")
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
