//
//  NearMissFinder+Clustering.swift
//  SwiftCloneDetectorKit
//
//  Grouping fragments into clone classes: union-find as a cheap candidate pass,
//  then complete-linkage refinement so every member of a class is a near copy of
//  every other. Split from the finder to keep either file readable.
//

import SwiftSyntax

extension NearMissFinder {
    func cluster(
        _ fragments: [Fragment],
        scoring: FragmentScoring
    ) -> [[Int]] {
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
        let sizeRatio = similarityThreshold / (Self.diceOverlapFactor - similarityThreshold)

        for indices in byKind.values where indices.count >= Self.minimumClusterSize {
            for outer in 0..<indices.count {
                for inner in (outer + 1)..<indices.count {
                    let lhsIndex = indices[outer]
                    let rhsIndex = indices[inner]
                    let left = fragments[lhsIndex]
                    let right = fragments[rhsIndex]

                    // Size prune on the weighted magnitudes, so it stays a valid
                    // bound on the score it is pruning against.
                    let smaller = min(scoring.magnitude(lhsIndex), scoring.magnitude(rhsIndex))
                    let larger = max(scoring.magnitude(lhsIndex), scoring.magnitude(rhsIndex))
                    if larger == 0 || smaller / larger < sizeRatio { continue }

                    // Exact (Type-1/2) copies belong to CloneFinder, not here.
                    if left.signature == right.signature { continue }

                    if scoring.similarity(lhsIndex, rhsIndex) >= similarityThreshold {
                        union(lhsIndex, rhsIndex)
                    }
                }
            }
        }

        var components: [Int: [Int]] = [:]
        for index in 0..<count {
            components[find(index), default: []].append(index)
        }
        return components.values
            .filter { $0.count >= Self.minimumClusterSize }
            .flatMap { refine($0, fragments: fragments, scoring: scoring) }
    }

    /// Split one connected component into classes whose members are *all* near
    /// copies of each other.
    ///
    /// Union-find gives single-linkage clustering: A joins B, B joins C, and A
    /// and C land in one class however unlike they are. Over a corpus the chains
    /// run a long way — one scan produced a class of 34,942 fragments whose
    /// least-similar pair scored 3%, and 158 classes below 50%, at a threshold
    /// of 85%. A class like that is not a false positive so much as a category
    /// error: it asserts "these are copies of each other" about fragments that
    /// have nothing in common but a path between them.
    ///
    /// A clone class wants complete linkage — every pair above the threshold —
    /// which is the guarantee its own reported similarity already implies.
    /// `minimumPairwiseSimilarity` has always computed exactly that number for
    /// the report; nothing acted on it.
    ///
    /// Greedy, seeded largest-first so the biggest fragment anchors its class,
    /// which is the one a reader opens. The cost is bounded by the pair loop
    /// above, which is already quadratic in the component.
    ///
    /// **This trades recall for the guarantee, deliberately.** Where A and B
    /// score 0.90, B and C 0.90, but A and C 0.83 at a 0.85 threshold, the three
    /// no longer form one class: A and B pair, and C is left over. The pair
    /// B–C is genuinely lost. The alternative is claiming C is a copy of A.
    private func refine(
        _ component: [Int],
        fragments: [Fragment],
        scoring: FragmentScoring
    ) -> [[Int]] {
        // Ties broken on position so a run is reproducible.
        let ordered = component.sorted { lhs, rhs in
            let left = fragments[lhs]
            let right = fragments[rhs]
            if left.mass != right.mass {
                return left.mass > right.mass
            }
            if left.fileIndex != right.fileIndex {
                return left.fileIndex < right.fileIndex
            }
            return left.startOffset < right.startOffset
        }

        var classes: [[Int]] = []
        for index in ordered {
            let candidate = fragments[index]
            let home = classes.firstIndex { members in
                members.allSatisfy { member in
                    scoring.similarity(member, index) >= similarityThreshold
                }
            }
            if let home {
                classes[home].append(index)
            } else {
                classes.append([index])
            }
        }
        return classes.filter { $0.count >= Self.minimumClusterSize }
    }
}
