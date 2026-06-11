//
//  main.swift
//  swift-clone-detector
//
//  Entry point: parse arguments, load sources, run the finder, print results.
//

import Foundation
import SwiftCloneDetectorKit

var minMass = 20
var normalization = Normalization.type2
var nearMiss = false
var similarityThreshold = 0.85
var crossProject = false
var sharedPaths: [String] = []
var paths: [String] = []

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--min-mass":
        index += 1
        if index < arguments.count, let value = Int(arguments[index]) {
            minMass = value
        }

    case "--similarity":
        index += 1
        if index < arguments.count, let value = Double(arguments[index]) {
            similarityThreshold = value
        }

    case "--type1":
        normalization = .type1

    case "--type2":
        normalization = .type2

    case "--type3", "--near":
        nearMiss = true

    case "--cross-project":
        crossProject = true

    case "--shared":
        index += 1
        if index < arguments.count {
            sharedPaths.append(arguments[index])
        }

    case "-h", "--help":
        print(kUsage)
        exit(0)

    default:
        paths.append(argument)
    }
    index += 1
}

@MainActor
func findClones(in sources: [SourceInput]) -> [CloneClass] {
    if nearMiss {
        return NearMissFinder(minMass: minMass, similarityThreshold: similarityThreshold).find(in: sources)
    }
    return CloneFinder(normalization: normalization, minMass: minMass).find(in: sources)
}

if crossProject {
    let roots = projectRoots(consumers: paths, shared: sharedPaths)
    if roots.count < 2 {
        let message = "swift-clone-detector: --cross-project needs at least two project roots "
            + "(pass consumer paths and optionally --shared)\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }

    let sources = loadSwiftFiles(paths: paths + sharedPaths)
    if sources.isEmpty {
        FileHandle.standardError.write(Data("swift-clone-detector: no .swift files found\n".utf8))
        exit(1)
    }

    let classes = findClones(in: sources)
    let cross = CrossProjectAnalyzer(roots: roots).analyze(classes)
    reportCrossProject(cross, roots: roots, fileCount: sources.count, nearMiss: nearMiss)
    exit(cross.isEmpty ? 0 : 2)
}

if paths.isEmpty {
    paths = ["."]
}

let sources = loadSwiftFiles(paths: paths)
if sources.isEmpty {
    FileHandle.standardError.write(Data("swift-clone-detector: no .swift files found\n".utf8))
    exit(1)
}

let classes = findClones(in: sources)
report(classes, fileCount: sources.count, nearMiss: nearMiss)
exit(classes.isEmpty ? 0 : 2)
