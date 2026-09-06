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

/// The Type-3 near-miss clone detector: copies that drifted by a few inserted,
/// removed, or changed statements, clustered by characteristic-vector similarity.
public struct NearMissFinder {
    struct Fragment {
        let fileIndex: Int
        let node: Syntax
        let mass: Int
        let startOffset: Int
        let endOffset: Int
        let vector: CharacteristicVector
        let signature: String
    }

    // A near-miss cluster needs at least this many members.
    static let minimumClusterSize = 2
    // Sørensen–Dice's overlap factor, reused in the size-prune ratio t / (2 - t).
    static let diceOverlapFactor = 2.0

    /// Minimum subtree size (in AST nodes) to consider.
    public let minMass: Int
    /// Sørensen–Dice similarity threshold in [0, 1] for two subtrees to be
    /// considered near-miss clones.
    public let similarityThreshold: Double
    /// Minimum count of distinct identifier tokens a fragment must carry to be
    /// considered. Drops large-but-repetitive structure with little unique
    /// naming. 0 disables it.
    public let minDistinctIdentifiers: Int
    /// Minimum lines a fragment must span. `minMass` counts AST nodes, and twenty
    /// of them fit on one line, so a mass floor alone reports single-line
    /// fragments nobody can act on. 1 disables it.
    public let minLines: Int
    /// Weight node kinds by how rare they are across this run's fragments, so a
    /// kind every fragment carries stops deciding whether two are copies.
    public let useRarityWeighting: Bool

    // Type-3 distinguishes structure, not token text, so signatures normalize
    // identifiers/literals away — the same basis the Type-2 pass uses.
    private let normalization = Normalization.type2

    /// Create a finder. `minMass` is the smallest subtree (in AST nodes) worth
    /// reporting; `similarityThreshold` is the Sørensen–Dice cutoff in [0, 1];
    /// `minDistinctIdentifiers` is the distinct-naming floor (0 = off).
    public init(
        minMass: Int = 30,
        similarityThreshold: Double = 0.85,
        minDistinctIdentifiers: Int = 0,
        minLines: Int = 2,
        useRarityWeighting: Bool = true
    ) {
        self.minMass = minMass
        self.similarityThreshold = similarityThreshold
        self.minDistinctIdentifiers = minDistinctIdentifiers
        self.minLines = minLines
        self.useRarityWeighting = useRarityWeighting
    }

    /// Find all Type-3 near-miss clone classes across the given sources, largest
    /// first and with nested sub-clones subsumed.
    public func find(in sources: [SourceInput]) -> [CloneClass] {
        let parsed = parseSources(sources)
        let converters = parsed.map(\.converter)
        var fragments: [Fragment] = []
        for source in parsed {
            collect(
                Syntax(source.tree),
                fileIndex: source.index,
                converter: source.converter,
                into: &fragments
            )
        }

        let scoring = FragmentScoring(
            vectors: fragments.map(\.vector),
            useRarityWeighting: useRarityWeighting
        )
        let clusters = cluster(fragments, scoring: scoring)
        return report(
            clusters,
            fragments: fragments,
            sources: sources,
            converters: converters,
            scoring: scoring
        )
    }

    // MARK: - Walk + vector

    private func collect(
        _ root: Syntax,
        fileIndex: Int,
        converter: SourceLocationConverter,
        into fragments: inout [Fragment]
    ) {
        // Tokens count toward `mass` (size) but not the vector, which stays a
        // purely structural fingerprint of composite node kinds.
        @discardableResult
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

            if mass >= minMass, AnchorKinds.all.contains(node.kind),
               minDistinctIdentifiers == 0 || distinctIdentifierCount(in: node) >= minDistinctIdentifiers,
               lineSpan(of: node, in: converter) >= minLines {
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

    // MARK: - Report + subsumption

    private func report(
        _ clusters: [[Int]],
        fragments: [Fragment],
        sources: [SourceInput],
        converters: [SourceLocationConverter],
        scoring: FragmentScoring
    ) -> [CloneClass] {
        // Largest clones first, so nested sub-clones get subsumed.
        let ordered = clusters.sorted { lhs, rhs in
            (lhs.map { fragments[$0].mass }.max() ?? 0) > (rhs.map { fragments[$0].mass }.max() ?? 0)
        }

        var claimed: [Int: [(start: Int, end: Int)]] = [:]
        var result: [CloneClass] = []

        func isInsideClaimedRange(_ fragment: Fragment) -> Bool {
            guard let ranges = claimed[fragment.fileIndex] else {
                return false
            }
            return ranges.contains { fragment.startOffset >= $0.start && fragment.endOffset <= $0.end }
        }

        for cluster in ordered {
            let memberIndices = withoutSelfOverlap(cluster, fragments: fragments)
            let members = memberIndices.map { fragments[$0] }
            guard members.count >= Self.minimumClusterSize else { continue }
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
                similarity: minimumPairwiseSimilarity(memberIndices, scoring: scoring)
            ))
        }
        return result
    }

    /// Members that are not contained inside another member of the *same* cluster.
    ///
    /// The subsumption above is cross-cluster: it drops a cluster whose members all sit inside
    /// ranges a larger clone already claimed. It says nothing about two members of one cluster
    /// overlapping each other, and they can — a fragment and its own parent land together when
    /// the parent adds only a wrapper that near-miss similarity tolerates:
    ///
    /// ```
    /// Clone #2 — 2 instances, 97% similar:
    ///   MLXBackend.swift:304-334
    ///   MLXBackend.swift:303-335
    /// ```
    ///
    /// The difference is `while !buffer.isEmpty {` and its closing brace. That is one region
    /// matched against itself at two granularities, not a copy of anything, and it is worse than
    /// noise: it inflates the duplicated-line total (which counts every instance) to the point of
    /// meaninglessness — 63,141 lines reported against a 66,469-line project, 95% duplication.
    ///
    /// Keeps the largest, which is the reading a caller wants: the outer fragment is where the
    /// duplication would have to be resolved if it were real.
    ///
    /// Containment is *strict*, so two members with identical ranges in one file do not remove
    /// each other and leave the cluster empty.
    private func withoutSelfOverlap(_ members: [Int], fragments: [Fragment]) -> [Int] {
        members.filter { index in
            let candidate = fragments[index]
            return !members.contains { otherIndex in
                let other = fragments[otherIndex]
                return other.fileIndex == candidate.fileIndex
                    && other.startOffset <= candidate.startOffset
                    && other.endOffset >= candidate.endOffset
                    && (other.startOffset < candidate.startOffset
                        || other.endOffset > candidate.endOffset)
            }
        }
    }

    private func minimumPairwiseSimilarity(_ members: [Int], scoring: FragmentScoring) -> Double {
        var minimum = 1.0
        for outer in 0..<members.count {
            for inner in (outer + 1)..<members.count {
                minimum = min(minimum, scoring.similarity(members[outer], members[inner]))
            }
        }
        return minimum
    }
}
