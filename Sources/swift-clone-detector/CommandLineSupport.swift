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
swift-clone-detector — Type-1/Type-2 Swift clone detector

USAGE:
  swift-clone-detector [options] [paths...]

OPTIONS:
  --type1            exact clones only (no identifier/literal normalization)
  --type2            also match renamed identifiers and literals (default)
  --min-mass N       minimum subtree size in AST nodes (default: 20)
  -h, --help         show this help

Paths may be files or directories; directories are searched recursively.
Defaults to the current directory. Exit code is 2 when clones are found.
"""

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
                if item.hasPrefix(".build/") || item.contains("/.build/") { continue }
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

func report(_ classes: [CloneClass], fileCount: Int) {
    guard !classes.isEmpty else {
        print("No Type-1/2 clones found across \(fileCount) file(s).")
        return
    }

    var duplicatedLines = 0
    for (index, cloneClass) in classes.enumerated() {
        let first = cloneClass.instances[0]
        let lineSpan = first.endLine - first.startLine + 1
        duplicatedLines += lineSpan * (cloneClass.instances.count - 1)

        print("")
        print("Clone #\(index + 1) — \(cloneClass.instances.count) instances, "
            + "\(cloneClass.mass) nodes (~\(lineSpan) lines):")
        for instance in cloneClass.instances {
            print("  \(instance.path):\(instance.startLine)-\(instance.endLine)")
        }
    }

    print("")
    print("Found \(classes.count) clone class(es) across \(fileCount) file(s); "
        + "~\(duplicatedLines) duplicated line(s).")
}
