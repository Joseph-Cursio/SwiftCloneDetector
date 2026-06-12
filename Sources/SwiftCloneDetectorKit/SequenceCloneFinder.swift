//
//  SequenceCloneFinder.swift
//  SwiftCloneDetectorKit
//
//  Sequence-clone detection: a duplicated *run* of consecutive sibling
//  statements (or members) that isn't a single subtree, so the subtree-anchored
//  CloneFinder misses it. Each statement/member list becomes a sequence of
//  per-item structural hashes; matching runs are found by recursively grouping
//  item positions by hash and keeping each maximal (left- and right-maximal)
//  run, then confirmed with a consistent-renaming signature like CloneFinder.
//
//  Reported as Type-1/2: a sequence clone is an exact/renamed duplication; only
//  the *shape* it spans (a run, not a subtree) differs.
//

import SwiftSyntax

/// Detects duplicated runs of consecutive sibling statements or members — clones
/// that span a sub-list of a `CodeBlockItemList`/`MemberBlockItemList` rather
/// than a single subtree.
public struct SequenceCloneFinder {
    // One element of a statement/member list.
    private struct Item {
        let fileIndex: Int
        let node: Syntax
        let mass: Int
        let blindHash: UInt64
        let startOffset: Int
        let endOffset: Int
    }

    // A start position into a list's item array.
    private struct Position {
        let listId: Int
        let index: Int
    }

    // One occurrence of a matched run, before location conversion.
    private struct RunInstance {
        let fileIndex: Int
        let startOffset: Int
        let endOffset: Int
        let startNode: Syntax
        let endNode: Syntax
    }

    private struct RunClass {
        let mass: Int
        let instances: [RunInstance]
    }

    // A clone class needs at least this many matching instances.
    private static let minimumInstances = 2

    /// Which clone type to catch: `.type1` (exact) or `.type2` (renamed).
    public let normalization: Normalization
    /// Minimum total run size (in AST nodes) to report.
    public let minMass: Int
    /// Minimum number of consecutive items a run must span.
    public let minItems: Int
    /// Minimum distinct identifier tokens a run must carry (0 disables it).
    public let minDistinctIdentifiers: Int

    /// Create a finder. `minMass` floors the total run size; `minItems` is the
    /// smallest run length in statements; `minDistinctIdentifiers` is the
    /// distinct-naming floor (0 = off).
    public init(
        normalization: Normalization = .type2,
        minMass: Int = 20,
        minItems: Int = 2,
        minDistinctIdentifiers: Int = 0
    ) {
        self.normalization = normalization
        self.minMass = minMass
        self.minItems = minItems
        self.minDistinctIdentifiers = minDistinctIdentifiers
    }

    /// Find all sequence-clone classes across the given sources, largest first
    /// and with runs subsumed by larger runs that contain them.
    public func find(in sources: [SourceInput]) -> [CloneClass] {
        let parsed = parseSources(sources)
        let converters = parsed.map(\.converter)
        var lists: [[Item]] = []
        for source in parsed {
            collectLists(Syntax(source.tree), fileIndex: source.index, into: &lists)
        }

        let runClasses = detectRuns(in: lists)
        return subsume(runClasses, sources: sources, converters: converters)
    }

    // MARK: - Collect lists

    private func collectLists(_ node: Syntax, fileIndex: Int, into lists: inout [[Item]]) {
        if node.kind == .codeBlockItemList || node.kind == .memberBlockItemList {
            let items = node.children(viewMode: .sourceAccurate).map { child -> Item in
                let digest = Structure.hash(of: child, normalization: normalization)
                return Item(
                    fileIndex: fileIndex,
                    node: child,
                    mass: digest.mass,
                    blindHash: digest.hash,
                    startOffset: child.positionAfterSkippingLeadingTrivia.utf8Offset,
                    endOffset: child.endPositionBeforeTrailingTrivia.utf8Offset
                )
            }
            if items.count >= minItems {
                lists.append(items)
            }
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectLists(child, fileIndex: fileIndex, into: &lists)
        }
    }

    // MARK: - Run detection

    private func detectRuns(in lists: [[Item]]) -> [RunClass] {
        var firstItemBuckets: [UInt64: [Position]] = [:]
        for (listId, items) in lists.enumerated() {
            for index in items.indices {
                firstItemBuckets[items[index].blindHash, default: []].append(Position(listId: listId, index: index))
            }
        }

        var runClasses: [RunClass] = []
        for bucket in firstItemBuckets.values where bucket.count >= Self.minimumInstances {
            extend(bucket, length: 1, lists: lists, into: &runClasses)
        }
        return runClasses
    }

    // Grow a set of positions that already share `length` items, recursing into
    // each sub-group that can extend, and emitting this group when it is the
    // maximal run shared by all its members.
    private func extend(_ positions: [Position], length: Int, lists: [[Item]], into runClasses: inout [RunClass]) {
        var groups: [UInt64: [Position]] = [:]
        var atEndCount = 0
        for position in positions {
            let nextIndex = position.index + length
            if nextIndex < lists[position.listId].count {
                groups[lists[position.listId][nextIndex].blindHash, default: []].append(position)
            } else {
                atEndCount += 1
            }
        }

        for group in groups.values where group.count >= Self.minimumInstances {
            extend(group, length: length + 1, lists: lists, into: &runClasses)
        }

        // Right-maximal unless every member extends, together, into one group.
        let extendsUniformly = atEndCount == 0 && groups.count == 1
            && groups.values.first?.count == positions.count
        guard length >= minItems, !extendsUniformly, isLeftMaximal(positions, lists: lists) else {
            return
        }
        runClasses.append(contentsOf: emit(positions, length: length, lists: lists))
    }

    // A group is left-maximal unless every member shares the same preceding
    // item — in which case the run starting one item earlier already covers it.
    private func isLeftMaximal(_ positions: [Position], lists: [[Item]]) -> Bool {
        guard positions.allSatisfy({ $0.index > 0 }) else {
            return true
        }
        let previous = Set(positions.map { lists[$0.listId][$0.index - 1].blindHash })
        return previous.count > 1
    }

    // Confirm a group with consistent-renaming signatures (so Type-2 reuse must
    // match across the whole run), then apply the mass/identifier floors and
    // drop self-overlapping instances.
    private func emit(_ positions: [Position], length: Int, lists: [[Item]]) -> [RunClass] {
        var bySignature: [String: [Position]] = [:]
        for position in positions {
            bySignature[runSignature(position, length, lists: lists), default: []].append(position)
        }

        var classes: [RunClass] = []
        for group in bySignature.values where group.count >= Self.minimumInstances {
            let mass = runMass(group[0], length, lists: lists)
            guard mass >= minMass else { continue }
            if minDistinctIdentifiers > 0,
               runDistinctIdentifiers(group[0], length, lists: lists) < minDistinctIdentifiers {
                continue
            }
            let instances = nonOverlappingInstances(group, length, lists: lists)
            guard instances.count >= Self.minimumInstances else { continue }
            classes.append(RunClass(mass: mass, instances: instances))
        }
        return classes
    }

    // MARK: - Run helpers

    private func runMass(_ position: Position, _ length: Int, lists: [[Item]]) -> Int {
        var total = 0
        for offset in 0..<length {
            total += lists[position.listId][position.index + offset].mass
        }
        return total
    }

    private func runSignature(_ position: Position, _ length: Int, lists: [[Item]]) -> String {
        var parts: [String] = []
        var mapping: [String: Int] = [:]
        for offset in 0..<length {
            Structure.appendSignature(
                of: lists[position.listId][position.index + offset].node,
                normalization: normalization,
                into: &parts,
                mapping: &mapping
            )
        }
        return parts.joined(separator: " ")
    }

    private func runDistinctIdentifiers(_ position: Position, _ length: Int, lists: [[Item]]) -> Int {
        var seen: Set<String> = []
        for offset in 0..<length {
            collectIdentifiers(in: lists[position.listId][position.index + offset].node, into: &seen)
        }
        return seen.count
    }

    private func nonOverlappingInstances(_ positions: [Position], _ length: Int, lists: [[Item]]) -> [RunInstance] {
        let sorted = positions
            .map { position -> RunInstance in
                let start = lists[position.listId][position.index]
                let end = lists[position.listId][position.index + length - 1]
                return RunInstance(
                    fileIndex: start.fileIndex,
                    startOffset: start.startOffset,
                    endOffset: end.endOffset,
                    startNode: start.node,
                    endNode: end.node
                )
            }
            .sorted { ($0.fileIndex, $0.startOffset) < ($1.fileIndex, $1.startOffset) }

        var kept: [RunInstance] = []
        var lastEnd: [Int: Int] = [:]
        for instance in sorted {
            if let end = lastEnd[instance.fileIndex], instance.startOffset < end { continue }
            kept.append(instance)
            lastEnd[instance.fileIndex] = instance.endOffset
        }
        return kept
    }

    // MARK: - Subsumption

    private func subsume(
        _ runClasses: [RunClass],
        sources: [SourceInput],
        converters: [SourceLocationConverter]
    ) -> [CloneClass] {
        let ordered = runClasses.sorted { $0.mass > $1.mass }
        var claimed: [Int: [(start: Int, end: Int)]] = [:]
        var result: [CloneClass] = []

        func isClaimed(_ instance: RunInstance) -> Bool {
            guard let ranges = claimed[instance.fileIndex] else {
                return false
            }
            return ranges.contains { instance.startOffset >= $0.start && instance.endOffset <= $0.end }
        }

        for runClass in ordered {
            if runClass.instances.allSatisfy(isClaimed) { continue }

            for instance in runClass.instances {
                claimed[instance.fileIndex, default: []].append((instance.startOffset, instance.endOffset))
            }

            let instances = runClass.instances.map { instance -> CloneInstance in
                let converter = converters[instance.fileIndex]
                let start = converter.location(for: instance.startNode.positionAfterSkippingLeadingTrivia)
                let end = converter.location(for: instance.endNode.endPositionBeforeTrailingTrivia)
                return CloneInstance(
                    path: sources[instance.fileIndex].path,
                    startLine: start.line,
                    startColumn: start.column,
                    endLine: end.line,
                    endColumn: end.column
                )
            }
            result.append(CloneClass(mass: runClass.mass, instances: instances))
        }
        return result
    }
}
