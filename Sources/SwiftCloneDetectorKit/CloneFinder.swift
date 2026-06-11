//
//  CloneFinder.swift
//  SwiftCloneDetectorKit
//
//  The Type-1/2 clone engine: parse → hash every significant subtree →
//  bucket by hash → confirm exact matches → drop subsumed sub-clones.
//

import SwiftParser
import SwiftSyntax

/// The Type-1/2 exact clone detector: structurally identical subtrees, optionally
/// modulo renamed identifiers and literals.
public struct CloneFinder {
    // A significant subtree recorded during the walk.
    private struct Fragment {
        let fileIndex: Int
        let node: Syntax
        let mass: Int
        let startOffset: Int
        let endOffset: Int
        let hash: UInt64
    }

    // A clone class needs at least this many matching instances.
    private static let minimumInstances = 2

    /// Which clone type to catch: `.type1` (exact) or `.type2` (renamed).
    public let normalization: Normalization
    /// Minimum subtree size (in AST nodes) to consider. Filters out trivial
    /// fragments that would otherwise be reported as noise.
    public let minMass: Int
    /// Minimum count of distinct identifier tokens a fragment must carry to be
    /// considered. Drops large-but-repetitive structure (a long switch, a builder
    /// chain) that passes `minMass` yet has little unique naming. 0 disables it.
    public let minDistinctIdentifiers: Int

    /// Create a finder. `minMass` is the smallest subtree (in AST nodes) worth
    /// reporting; `minDistinctIdentifiers` is the distinct-naming floor (0 = off).
    public init(normalization: Normalization = .type2, minMass: Int = 20, minDistinctIdentifiers: Int = 0) {
        self.normalization = normalization
        self.minMass = minMass
        self.minDistinctIdentifiers = minDistinctIdentifiers
    }

    /// Find all Type-1/2 clone classes across the given sources, largest first
    /// and with sub-clones subsumed by the larger clones that contain them.
    public func find(in sources: [SourceInput]) -> [CloneClass] {
        var fragments: [Fragment] = []
        var converters: [SourceLocationConverter] = []

        for (index, source) in sources.enumerated() {
            let tree = Parser.parse(source: source.text)
            converters.append(SourceLocationConverter(fileName: source.path, tree: tree))
            collect(Syntax(tree), fileIndex: index, into: &fragments)
        }

        // Bucket by structural hash (fast), then confirm exact matches within
        // each bucket via a canonical signature (guards against hash collisions).
        var buckets: [UInt64: [Fragment]] = [:]
        for fragment in fragments {
            buckets[fragment.hash, default: []].append(fragment)
        }

        var classes: [[Fragment]] = []
        for bucket in buckets.values where bucket.count >= Self.minimumInstances {
            var bySignature: [String: [Fragment]] = [:]
            for fragment in bucket {
                bySignature[signature(of: fragment.node), default: []].append(fragment)
            }
            for group in bySignature.values where group.count >= Self.minimumInstances {
                classes.append(group)
            }
        }

        // Report the largest clones first and drop sub-clones already covered
        // by a larger reported clone.
        classes.sort { $0[0].mass > $1[0].mass }
        return subsume(classes, sources: sources, converters: converters)
    }

    // MARK: - Walk + hash

    private func collect(_ root: Syntax, fileIndex: Int, into fragments: inout [Fragment]) {
        @discardableResult
        func walk(_ node: Syntax) -> (hash: UInt64, mass: Int) {
            if let token = node.as(TokenSyntax.self) {
                var hasher = FNV64()
                hasher.combine("T:")
                hasher.combine(normalization.canonicalText(for: token))
                return (hasher.value, 1)
            }

            var hasher = FNV64()
            hasher.combine("N:\(node.kind)")
            var mass = 1
            for child in node.children(viewMode: .sourceAccurate) {
                let result = walk(child)
                hasher.combine(result.hash)
                mass += result.mass
            }

            if mass >= minMass, AnchorKinds.all.contains(node.kind), passesIdentifierFloor(node) {
                fragments.append(Fragment(
                    fileIndex: fileIndex,
                    node: node,
                    mass: mass,
                    startOffset: node.positionAfterSkippingLeadingTrivia.utf8Offset,
                    endOffset: node.endPositionBeforeTrailingTrivia.utf8Offset,
                    hash: hasher.value
                ))
            }
            return (hasher.value, mass)
        }
        walk(root)
    }

    // Whether a fragment carries enough distinct naming to clear the floor. The
    // count walk only runs when the floor is enabled.
    private func passesIdentifierFloor(_ node: Syntax) -> Bool {
        minDistinctIdentifiers == 0 || distinctIdentifierCount(in: node) >= minDistinctIdentifiers
    }

    // A full structural signature used to confirm a bucket is a true match.
    // Encodes node kinds and consistently-renamed leaf tokens, so equal signatures
    // are genuinely equal subtrees that also reuse identifiers in the same pattern.
    // The blind hash that fed this bucket only approximates that — two fragments
    // with the same shape but different identifier-reuse patterns share a hash yet
    // produce different signatures here, and so are correctly split apart.
    private func signature(of node: Syntax) -> String {
        var parts: [String] = []
        var mapping: [String: Int] = [:]
        Structure.appendSignature(of: node, normalization: normalization, into: &parts, mapping: &mapping)
        return parts.joined(separator: " ")
    }

    // MARK: - Subsumption

    private func subsume(
        _ classes: [[Fragment]],
        sources: [SourceInput],
        converters: [SourceLocationConverter]
    ) -> [CloneClass] {
        var claimed: [Int: [(start: Int, end: Int)]] = [:]
        var result: [CloneClass] = []

        func isInsideClaimedRange(_ fragment: Fragment) -> Bool {
            guard let ranges = claimed[fragment.fileIndex] else {
                return false
            }
            return ranges.contains { fragment.startOffset >= $0.start && fragment.endOffset <= $0.end }
        }

        for group in classes {
            // If every instance sits inside an already-reported (larger) clone,
            // this is a sub-clone — skip it.
            if group.allSatisfy(isInsideClaimedRange) { continue }

            for fragment in group {
                claimed[fragment.fileIndex, default: []].append((fragment.startOffset, fragment.endOffset))
            }

            let instances = group.map { fragment -> CloneInstance in
                let converter = converters[fragment.fileIndex]
                let start = converter.location(for: fragment.node.positionAfterSkippingLeadingTrivia)
                let end = converter.location(for: fragment.node.endPositionBeforeTrailingTrivia)
                return CloneInstance(
                    path: sources[fragment.fileIndex].path,
                    startLine: start.line,
                    startColumn: start.column,
                    endLine: end.line,
                    endColumn: end.column
                )
            }
            result.append(CloneClass(mass: group[0].mass, instances: instances))
        }
        return result
    }
}
