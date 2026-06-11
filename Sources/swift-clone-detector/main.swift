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

    case "--type1":
        normalization = .type1

    case "--type2":
        normalization = .type2

    case "-h", "--help":
        print(kUsage)
        exit(0)

    default:
        paths.append(argument)
    }
    index += 1
}

if paths.isEmpty {
    paths = ["."]
}

let sources = loadSwiftFiles(paths: paths)
if sources.isEmpty {
    FileHandle.standardError.write(Data("swift-clone-detector: no .swift files found\n".utf8))
    exit(1)
}

let finder = CloneFinder(normalization: normalization, minMass: minMass)
let classes = finder.find(in: sources)
report(classes, fileCount: sources.count)
exit(classes.isEmpty ? 0 : 2)
