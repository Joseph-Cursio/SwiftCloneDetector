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
        scoring: FragmentScoring,
        naming: IdentifierWeights
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
            byKind[fragments[index].span.kind, default: []].append(index)
        }

        // Size prune: for Dice ≥ t the smaller vector must be at least
        // t / (2 - t) of the larger, else the score can't reach the threshold.
        let sizeRatio = similarityThreshold / (Self.diceOverlapFactor - similarityThreshold)

        // A fragment with no distinguishing structure matches anything of its
        // size; comparing it says nothing either way.
        let floorApplies = minDistinctiveness > 0 && scoring.rarityIsMeaningful
        let carriesStructure = { (index: Int) in
            !floorApplies || scoring.distinctiveness(index) >= self.minDistinctiveness
        }

        for indices in byKind.values where indices.count >= Self.minimumClusterSize {
            for outer in 0..<indices.count {
                for inner in (outer + 1)..<indices.count {
                    let lhsIndex = indices[outer]
                    let rhsIndex = indices[inner]
                    guard carriesStructure(lhsIndex), carriesStructure(rhsIndex) else { continue }
                    let left = fragments[lhsIndex]
                    let right = fragments[rhsIndex]

                    // Size prune on the weighted magnitudes, so it stays a valid
                    // bound on the score it is pruning against.
                    let smaller = min(scoring.magnitude(lhsIndex), scoring.magnitude(rhsIndex))
                    let larger = max(scoring.magnitude(lhsIndex), scoring.magnitude(rhsIndex))
                    if larger == 0 || smaller / larger < sizeRatio { continue }

                    // Exact (Type-1/2) copies belong to CloneFinder, not here.
                    if left.signature == right.signature { continue }

                    if scoring.similarity(lhsIndex, rhsIndex) >= similarityThreshold,
                       sharesNaming(left, right, naming: naming) {
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
            .flatMap { refine($0, fragments: fragments, scoring: scoring, naming: naming) }
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
        scoring: FragmentScoring,
        naming: IdentifierWeights
    ) -> [[Int]] {
        // Biggest first, ties broken on position so a run is reproducible — the
        // same order a report uses, applied to one fragment at a time.
        let ordered = component
            .map { (order: CloneOrder(fragments[$0].span), index: $0) }
            .sorted { $0.order < $1.order }
            .map(\.index)

        var classes: [[Int]] = []
        for index in ordered {
            let home = classes.firstIndex { members in
                members.allSatisfy { member in
                    scoring.similarity(member, index) >= similarityThreshold
                        && sharesNaming(fragments[member], fragments[index], naming: naming)
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

    /// Whether two fragments name enough of the same things to be copies, and not
    /// just two constructs of the same shape. Checked in the candidate pass and
    /// again in refinement, so the gate holds for every pair in a class, as the
    /// similarity threshold does.
    func sharesNaming(_ lhs: Fragment, _ rhs: Fragment, naming: IdentifierWeights) -> Bool {
        minIdentifierOverlap <= 0
            || identifierOverlap(lhs.identifiers, rhs.identifiers, weights: naming) >= minIdentifierOverlap
    }
}
