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

/// Filters and classifies clone classes for the multi-project case, keeping only
/// duplication that spans two or more project roots.
public struct CrossProjectAnalyzer: Sendable {
    // A clone must touch at least this many projects to count as cross-project.
    private static let minimumProjectSpan = 2

    public let roots: [ProjectRoot]

    public init(roots: [ProjectRoot]) {
        self.roots = roots
    }

    // Path components, ignoring empty segments so leading/trailing/duplicate
    // slashes don't affect prefix matching.
    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
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
            guard owners.count >= Self.minimumProjectSpan else { continue }

            let involvesShared = owners.values.contains(where: \.isShared)
            let kind: CrossProjectKind = involvesShared ? .duplicatedFromShared : .hoistCandidate
            result.append(CrossProjectClone(
                cloneClass: cloneClass,
                projects: owners.keys.sorted(),
                kind: kind
            ))
        }
        return result
    }
}
