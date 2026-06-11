//
//  Options.swift
//  swift-clone-detector
//
//  Parsed command-line options, plus the CLI's fixed defaults and exit codes.
//

import SwiftCloneDetectorKit

/// Parsed command-line options and the CLI's fixed defaults/exit codes.
struct Options {
    static let toolName = "swift-clone-detector"
    static let toolVersion = "0.1.0"
    static let informationURI = "https://github.com/Joseph-Cursio/SwiftCloneDetector"

    static let defaultMinMass = 20
    static let defaultMinDistinctIdentifiers = 0
    static let defaultSimilarityThreshold = 0.85
    /// Cross-project mode is meaningless below this many project roots.
    static let minimumProjectRoots = 2
    /// Non-zero status doubles as a CI signal that duplication is present.
    static let clonesFoundExitCode: Int32 = 2
    static let usageErrorExitCode: Int32 = 1

    var minMass = Self.defaultMinMass
    var minDistinctIdentifiers = Self.defaultMinDistinctIdentifiers
    var normalization = Normalization.type2
    var nearMiss = false
    var similarityThreshold = Self.defaultSimilarityThreshold
    var crossProject = false
    var sharedPaths: [String] = []
    var paths: [String] = []
    var format = OutputFormat.text
    /// When set, only clones absent from this baseline are reported and gate CI.
    var baselinePath: String?
    /// When set, write the current clones to this path as a baseline and exit.
    var writeBaselinePath: String?
}
