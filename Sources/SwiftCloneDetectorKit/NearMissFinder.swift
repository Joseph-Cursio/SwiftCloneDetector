//
//  NearMissFinder.swift
//  SwiftCloneDetectorKit
//
//  Type-3 (near-miss) detection: copies with a few inserted, removed, or changed
//  statements. Each significant subtree is reduced to a characteristic vector of
//  node-kind counts; subtrees whose vectors are similar enough (Sørensen–Dice ≥
//  threshold) are clustered into near-miss clone classes.
//
//  Exact copies are deliberately excluded — a pair with identical structural
//  signatures is a Type-1/2 clone and belongs to `CloneFinder`. This pass reports
//  only the *near*, not the identical.
//

import SwiftSyntax
import SwiftParser

public struct NearMissFinder {
    /// Minimum subtree size (in AST nodes) to consider.
    public let minMass: Int
    /// Sørensen–Dice similarity threshold in [0, 1] for two subtrees to be
    /// considered near-miss clones.
    public let similarityThreshold: Double

    public init(minMass: Int = 30, similarityThreshold: Double = 0.85) {
        self.minMass = minMass
        self.similarityThreshold = similarityThreshold
    }

    // Type-3 distinguishes structure, not token text, so signatures normalize
    // identifiers/literals away — the same basis the Type-2 pass uses.
    private let normalization = Normalization.type2

    private struct Fragment {
        let fileIndex: Int
        let node: Syntax
        let mass: Int
        let startOffset: Int
        let endOffset: Int
        let vector: CharacteristicVector
        let signature: String
    }

    public func find(in sources: [SourceInput]) -> [CloneClass] {
        var fragments: [Fragment] = []
        var converters: [SourceLocationConverter] = []

        for (index, source) in sources.enumerated() {
            let tree = Parser.parse(source: source.text)
            converters.append(SourceLocationConverter(fileName: source.path, tree: tree))
            collect(Syntax(tree), fileIndex: index, into: &fragments)
        }

        let clusters = cluster(fragments)
        return report(clusters, fragments: fragments, sources: sources, converters: converters)
    }

    // MARK: - Walk + vector

    private func collect(_ root: Syntax, fileIndex: Int, into fragments: inout [Fragment]) {
        // Tokens count toward `mass` (size) but not the vector, which stays a
        // purely structural fingerprint of composite node kinds.
        func walk(_ node: Syntax) -> (vector: CharacteristicVector, mass: Int) {
            if node.is(TokenSyntax.self) {
                return (CharacteristicVector(), 1)
            }

            var vector = CharacteristicVector()
            vector.add(node.kind)
            var mass = 1
            for child in node.children(viewMode: .sourceAccurate) {
                let result = walk(child)
                vector.merge(result.vector)
                mass += result.mass
            }

            if mass >= minMass, anchorKinds.contains(node.kind) {
                fragments.append(Fragment(
                    fileIndex: fileIndex,
                    node: node,
                    mass: mass,
                    startOffset: node.positionAfterSkippingLeadingTrivia.utf8Offset,
                    endOffset: node.endPositionBeforeTrailingTrivia.utf8Offset,
                    vector: vector,
                    signature: signature(of: node)
                ))
            }
            return (vector, mass)
        }
        walk(root)
    }

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

    // MARK: - Clustering

    private func cluster(_ fragments: [Fragment]) -> [[Int]] {
        let count = fragments.count
        var parent = Array(0..<count)

        func find(_ value: Int) -> Int {
            var root = value
            while parent[root] != root {
                parent[root] = parent[parent[root]]
                root = parent[root]
            }
            return root
        }
        func union(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = find(lhs)
            let rhsRoot = find(rhs)
            if lhsRoot != rhsRoot { parent[lhsRoot] = rhsRoot }
        }

        // Compare only within the same anchor kind. A near-miss clone shares its
        // root construct (a copied function is still a function); comparing across
        // kinds only matches a parent to the very child nested inside it.
        var byKind: [SyntaxKind: [Int]] = [:]
        for index in 0..<count {
            byKind[fragments[index].node.kind, default: []].append(index)
        }

        // Size prune: for Dice ≥ t the smaller vector must be at least
        // t / (2 - t) of the larger, else the score can't reach the threshold.
        let sizeRatio = similarityThreshold / (2 - similarityThreshold)

        for indices in byKind.values where indices.count >= 2 {
            for outer in 0..<indices.count {
                for inner in (outer + 1)..<indices.count {
                    let lhsIndex = indices[outer]
                    let rhsIndex = indices[inner]
                    let left = fragments[lhsIndex]
                    let right = fragments[rhsIndex]

                    let smaller = Double(min(left.vector.total, right.vector.total))
                    let larger = Double(max(left.vector.total, right.vector.total))
                    if larger == 0 || smaller / larger < sizeRatio { continue }

                    // Exact (Type-1/2) copies belong to CloneFinder, not here.
                    if left.signature == right.signature { continue }

                    if left.vector.similarity(to: right.vector) >= similarityThreshold {
                        union(lhsIndex, rhsIndex)
                    }
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in 0..<count {
            groups[find(index), default: []].append(index)
        }
        return groups.values.filter { $0.count >= 2 }
    }

    // MARK: - Report + subsumption

    private func report(
        _ clusters: [[Int]],
        fragments: [Fragment],
        sources: [SourceInput],
        converters: [SourceLocationConverter]
    ) -> [CloneClass] {
        // Largest clones first, so nested sub-clones get subsumed.
        let ordered = clusters.sorted { lhs, rhs in
            (lhs.map { fragments[$0].mass }.max() ?? 0) > (rhs.map { fragments[$0].mass }.max() ?? 0)
        }

        var claimed: [Int: [(start: Int, end: Int)]] = [:]
        var result: [CloneClass] = []

        func isInsideClaimedRange(_ fragment: Fragment) -> Bool {
            guard let ranges = claimed[fragment.fileIndex] else { return false }
            return ranges.contains { fragment.startOffset >= $0.start && fragment.endOffset <= $0.end }
        }

        for cluster in ordered {
            let members = cluster.map { fragments[$0] }
            if members.allSatisfy(isInsideClaimedRange) { continue }

            for member in members {
                claimed[member.fileIndex, default: []].append((member.startOffset, member.endOffset))
            }

            let instances = members.map { member -> CloneInstance in
                let converter = converters[member.fileIndex]
                let start = converter.location(for: member.node.positionAfterSkippingLeadingTrivia)
                let end = converter.location(for: member.node.endPositionBeforeTrailingTrivia)
                return CloneInstance(
                    path: sources[member.fileIndex].path,
                    startLine: start.line,
                    startColumn: start.column,
                    endLine: end.line,
                    endColumn: end.column
                )
            }

            result.append(CloneClass(
                mass: members.map(\.mass).max() ?? 0,
                instances: instances,
                similarity: minimumPairwiseSimilarity(members)
            ))
        }
        return result
    }

    private func minimumPairwiseSimilarity(_ members: [Fragment]) -> Double {
        var minimum = 1.0
        for outer in 0..<members.count {
            for inner in (outer + 1)..<members.count {
                minimum = min(minimum, members[outer].vector.similarity(to: members[inner].vector))
            }
        }
        return minimum
    }
}
