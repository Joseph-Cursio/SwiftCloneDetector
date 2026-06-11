//
//  ProjectRoot.swift
//  SwiftCloneDetectorKit
//
//  One project in the multi-project (cross-project) set: a consumer app or the
//  shared package they depend on.
//

/// One project in the multi-project set — a consumer app or the shared package.
public struct ProjectRoot: Sendable, Equatable {
    public let name: String
    public let path: String
    /// True for the shared package (e.g. LintStudioUI) that consumers depend on.
    public let isShared: Bool

    public init(name: String, path: String, isShared: Bool = false) {
        self.name = name
        self.path = path
        self.isShared = isShared
    }
}
