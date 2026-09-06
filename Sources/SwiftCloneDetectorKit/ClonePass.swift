//
//  ClonePass.swift
//  SwiftCloneDetectorKit
//
//  What the three finders have in common, so a caller can run them together.
//

/// A search for clones over a set of sources.
///
/// The three finders were only ever used one at a time, so nothing named the
/// shape they share. Running them together needs it.
public protocol ClonePass {
    /// Every clone class this pass finds across `sources`.
    func find(in sources: [SourceInput]) -> [CloneClass]
}

extension CloneFinder: ClonePass {}
extension NearMissFinder: ClonePass {}
extension SequenceCloneFinder: ClonePass {}
