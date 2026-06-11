//
//  BaselineEntry.swift
//  SwiftCloneDetectorKit
//
//  One recorded clone in a baseline file. The mass/instances/files fields are
//  carried purely so the file is reviewable in a pull request — only the
//  fingerprint participates in matching.
//

/// One recorded clone in a baseline file. Only `fingerprint` is used for
/// matching; the other fields exist so a baseline diff is human-reviewable.
public struct BaselineEntry: Codable, Sendable, Equatable {
    public let fingerprint: String
    public let mass: Int
    public let instances: Int
    public let files: [String]

    public init(fingerprint: String, mass: Int, instances: Int, files: [String]) {
        self.fingerprint = fingerprint
        self.mass = mass
        self.instances = instances
        self.files = files
    }

    public init(cloneClass: CloneClass) {
        self.fingerprint = cloneFingerprint(for: cloneClass)
        self.mass = cloneClass.mass
        self.instances = cloneClass.instances.count
        self.files = cloneClass.instances.map(\.path).sorted()
    }
}
