//
//  CrossProjectKind.swift
//  SwiftCloneDetectorKit
//
//  Why a cross-project clone matters — and what to do about it.
//

/// Why a cross-project clone matters — and what to do about it.
public enum CrossProjectKind: Sendable, Equatable {
    /// Present in the shared package and re-copied into a consumer. Delete the
    /// copy and import the shared package's version instead.
    case duplicatedFromShared
    /// Duplicated across two or more consumers, absent from the shared package.
    /// Hoist it into the shared package and import it everywhere.
    case hoistCandidate
}
