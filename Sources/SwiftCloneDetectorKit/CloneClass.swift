//
//  CloneClass.swift
//  SwiftCloneDetectorKit
//
//  The public result types. A clone class is a set of two-or-more source
//  locations whose AST subtrees are structurally identical under the active
//  normalization.
//

public struct CloneInstance: Sendable {
    public let path: String
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(path: String, startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
        self.path = path
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct CloneClass: Sendable {
    /// Size of the shared subtree in AST nodes — the significance metric.
    public let mass: Int
    public let instances: [CloneInstance]
    /// For near-miss (Type-3) classes, the minimum pairwise structural
    /// similarity in [0, 1]. `nil` for exact (Type-1/2) classes.
    public let similarity: Double?

    public init(mass: Int, instances: [CloneInstance], similarity: Double? = nil) {
        self.mass = mass
        self.instances = instances
        self.similarity = similarity
    }
}
