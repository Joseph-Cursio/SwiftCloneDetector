//
//  SequenceCloneFinder+Filters.swift
//  SwiftCloneDetectorKit
//
//  Runs the sequence pass matches but does not report: a block of imports, and
//  runs of one shape that name different things. Split from the finder to keep
//  either file readable.
//

extension SequenceCloneFinder {
    /// Whether every item in this run is an `import`.
    ///
    /// Files that use the same modules open with the same import block, so the
    /// run pass matches it across every one of them — 91 instances in one app,
    /// its largest finding by volume. It is duplication in the literal sense and
    /// there is nothing to do about it: nobody factors out an import list.
    ///
    /// Only an entirely-import run is dropped. A run that reaches past them into
    /// real declarations is kept, imports and all, because that one is about the
    /// declarations.
    func isAllImports(_ position: Position, _ length: Int, lists: [[Item]]) -> Bool {
        let items = lists[position.listId]
        return (position.index..<(position.index + length)).allSatisfy { items[$0].isImport }
    }

    /// Split runs of one shape into groups whose every pair shares enough naming.
    ///
    /// Greedy, in position order, which is the order the group arrives in: each
    /// run joins the first group it overlaps every member of, or starts its own.
    /// A group left with one run is dropped — it is not a copy of anything here.
    func namingGroups(
        _ positions: [Position],
        _ length: Int,
        lists: [[Item]],
        naming: IdentifierWeights
    ) -> [[Position]] {
        guard minIdentifierOverlap > 0 else {
            return [positions]
        }
        let identifiers = positions.map { position in
            var seen: Set<String> = []
            for offset in 0..<length {
                collectIdentifiers(in: lists[position.listId][position.index + offset].span.node, into: &seen)
            }
            return seen
        }
        var groups: [[Int]] = []
        for index in positions.indices {
            let home = groups.firstIndex { members in
                members.allSatisfy { member in
                    identifierOverlap(identifiers[member], identifiers[index], weights: naming)
                        >= minIdentifierOverlap
                }
            }
            if let home {
                groups[home].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups
            .filter { $0.count >= Self.minimumInstances }
            .map { members in members.map { positions[$0] } }
    }
}
