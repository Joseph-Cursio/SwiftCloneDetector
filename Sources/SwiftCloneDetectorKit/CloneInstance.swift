//
//  CloneInstance.swift
//  SwiftCloneDetectorKit
//
//  One occurrence of a clone: a source range identified by file path and
//  start/end line and column.
//

/// A single source location belonging to a clone class — one of the two-or-more
/// structurally identical fragments the detector found.
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
