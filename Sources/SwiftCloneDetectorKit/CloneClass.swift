//
//  CloneClass.swift
//  SwiftCloneDetectorKit
//
//  The public result type. A clone class is a set of two-or-more source
//  locations whose AST subtrees are structurally identical under the active
//  normalization.
//

/// A set of two-or-more source locations whose AST subtrees match under the
/// active normalization — one detected clone.
public struct CloneClass: Sendable {
    /// Size of the shared subtree in AST nodes — the significance metric.
    public let mass: Int
    /// The matching source locations, two or more.
    public let instances: [CloneInstance]
    /// For near-miss (Type-3) classes, the minimum pairwise structural
    /// similarity in [0, 1]. `nil` for exact (Type-1/2) classes.
    public let similarity: Double?
    /// Which search found this. Meaningful when passes run together, where a
    /// report otherwise cannot say why one finding is exact and the next is 87%.
    public let pass: DetectionPass

    public init(
        mass: Int,
        instances: [CloneInstance],
        similarity: Double? = nil,
        pass: DetectionPass = .subtree
    ) {
        self.mass = mass
        self.instances = instances
        self.similarity = similarity
        self.pass = pass
    }
}
