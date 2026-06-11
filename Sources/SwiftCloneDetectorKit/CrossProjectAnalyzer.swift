//
//  CrossProjectAnalyzer.swift
//  SwiftCloneDetectorKit
//
//  A layer over the clone engine for the multi-project case: several apps that
//  share a library. It takes the clone classes the finder already produced and
//  keeps only those whose instances span two or more projects — the duplication
//  worth acting on when the question is "what belongs in the shared package?"
//
//  Each surviving class is classified:
//    • hoistCandidate       — duplicated across ≥2 consumers, not in the shared
//                             package → extract it into the shared package.
//    • duplicatedFromShared — also present in the shared package; a consumer
//                             re-copied shared code → replace the copy with an
//                             import of the shared package.
//
//  File → project mapping is by path prefix: a file belongs to the most specific
//  project root that is a path-component prefix of its path.
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

/// Why a cross-project clone matters — and what to do about it.
public enum CrossProjectKind: Sendable, Equatable {
    /// Duplicated across two or more consumers, absent from the shared package.
    /// Hoist it into the shared package and import it everywhere.
    case hoistCandidate
    /// Present in the shared package and re-copied into a consumer. Delete the
    /// copy and import the shared package's version instead.
    case duplicatedFromShared
}

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

public struct CrossProjectAnalyzer: Sendable {
    public let roots: [ProjectRoot]

    public init(roots: [ProjectRoot]) {
        self.roots = roots
    }

    /// The project that owns a file: the root whose path components are the
    /// longest prefix of the file's components. `nil` if no root contains it.
    public func project(for path: String) -> ProjectRoot? {
        let fileComponents = Self.components(of: path)
        var best: ProjectRoot?
        var bestLength = -1
        for root in roots {
            let rootComponents = Self.components(of: root.path)
            guard rootComponents.count <= fileComponents.count else { continue }
            guard Array(fileComponents.prefix(rootComponents.count)) == rootComponents else { continue }
            if rootComponents.count > bestLength {
                best = root
                bestLength = rootComponents.count
            }
        }
        return best
    }

    /// Keep only clone classes that span two or more projects, each tagged with
    /// its projects and kind. Intra-project duplication is dropped.
    public func analyze(_ classes: [CloneClass]) -> [CrossProjectClone] {
        var result: [CrossProjectClone] = []
        for cloneClass in classes {
            var owners: [String: ProjectRoot] = [:]
            for instance in cloneClass.instances {
                guard let root = project(for: instance.path) else { continue }
                owners[root.name] = root
            }
            guard owners.count >= 2 else { continue }

            let involvesShared = owners.values.contains { $0.isShared }
            let kind: CrossProjectKind = involvesShared ? .duplicatedFromShared : .hoistCandidate
            result.append(CrossProjectClone(
                cloneClass: cloneClass,
                projects: owners.keys.sorted(),
                kind: kind
            ))
        }
        return result
    }

    // Path components, ignoring empty segments so leading/trailing/duplicate
    // slashes don't affect prefix matching.
    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
