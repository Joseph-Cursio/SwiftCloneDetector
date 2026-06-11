//
//  CloneFinder.swift
//  SwiftCloneDetectorKit
//
//  The Type-1/2 clone engine: parse → hash every significant subtree →
//  bucket by hash → confirm exact matches → drop subsumed sub-clones.
//

import SwiftSyntax
import SwiftParser

public struct SourceInput: Sendable {
    public let path: String
    public let text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct CloneFinder {
    public let normalization: Normalization
    /// Minimum subtree size (in AST nodes) to consider. Filters out trivial
    /// fragments that would otherwise be reported as noise.
    public let minMass: Int

    public init(normalization: Normalization = .type2, minMass: Int = 20) {
        self.normalization = normalization
        self.minMass = minMass
    }

    // A significant subtree recorded during the walk.
    private struct Fragment {
        let fileIndex: Int
        let node: Syntax
        let mass: Int
        let startOffset: Int
        let endOffset: Int
        let hash: UInt64
    }

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
        for bucket in buckets.values where bucket.count >= 2 {
            var bySignature: [String: [Fragment]] = [:]
            for fragment in bucket {
                bySignature[signature(of: fragment.node), default: []].append(fragment)
            }
            for group in bySignature.values where group.count >= 2 {
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

            if mass >= minMass, anchorKinds.contains(node.kind) {
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

    // A full structural signature used to confirm a bucket is a true match.
    // Encodes node kinds and normalized leaf tokens, so equal signatures are
    // genuinely equal subtrees under the active normalization.
    private func signature(of node: Syntax) -> String {
        var parts: [String] = []
        func emit(_ node: Syntax) {
            if let token = node.as(TokenSyntax.self) {
                parts.append(normalization.canonicalText(for: token))
                return
            }
            parts.append("(\(node.kind)")
            for child in node.children(viewMode: .sourceAccurate) {
                emit(child)
            }
            parts.append(")")
        }
        emit(node)
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
            guard let ranges = claimed[fragment.fileIndex] else { return false }
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
