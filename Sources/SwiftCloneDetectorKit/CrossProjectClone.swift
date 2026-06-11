//
//  CrossProjectClone.swift
//  SwiftCloneDetectorKit
//
//  A clone class whose instances span more than one project, annotated with the
//  projects it touches and what to do about it.
//

/// A clone class whose instances span more than one project, annotated with the
/// projects it touches and what to do about it.
public struct CrossProjectClone: Sendable {
    public let cloneClass: CloneClass
    /// Distinct project names the clone spans, sorted.
    public let projects: [String]
    public let kind: CrossProjectKind

    public init(cloneClass: CloneClass, projects: [String], kind: CrossProjectKind) {
        self.cloneClass = cloneClass
        self.projects = projects
        self.kind = kind
    }
}
