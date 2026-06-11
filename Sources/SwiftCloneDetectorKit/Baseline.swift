//
//  Baseline.swift
//  SwiftCloneDetectorKit
//
//  The on-disk baseline: the set of clones a codebase has already accepted, so
//  a CI gate can fail only on clones that are new since it was recorded.
//

/// The on-disk baseline: the set of clones a codebase has already accepted.
public struct Baseline: Codable, Sendable, Equatable {
    /// Bumped if the fingerprint scheme ever changes, so a stale baseline is
    /// detectable rather than silently mismatching every clone.
    public static let currentVersion = 1

    public let version: Int
    public let clones: [BaselineEntry]

    /// The fingerprints to match freshly detected clones against.
    public var fingerprintSet: Set<String> {
        Set(clones.map(\.fingerprint))
    }

    public init(clones: [BaselineEntry], version: Int = Self.currentVersion) {
        self.version = version
        self.clones = clones
    }

    /// Build a baseline from detected clones, sorted by fingerprint for stable,
    /// review-friendly diffs.
    public init(classes: [CloneClass]) {
        self.version = Self.currentVersion
        self.clones = classes
            .map(BaselineEntry.init(cloneClass:))
            .sorted { $0.fingerprint < $1.fingerprint }
    }
}
