//
//  ParsedSource.swift
//  SwiftCloneDetectorKit
//
//  Concurrent parsing. Parsing each file with SwiftSyntax is the expensive,
//  embarrassingly parallel pass and is independent of the cross-file analysis,
//  so it runs across all cores before the serial matching stage. The collect and
//  match stages stay serial, so results are unchanged.
//

import Dispatch
import SwiftParser
import SwiftSyntax

/// A parsed file: its index in the input, its syntax tree, and a location
/// converter built from that tree.
///
/// `@unchecked Sendable` is sound here: a parsed SwiftSyntax tree is immutable,
/// each file is parsed independently into its own arena, and the concurrent
/// parse completes (a barrier) before any tree is read on the calling thread —
/// so no tree is ever mutated or read across threads at the same time.
struct ParsedSource: @unchecked Sendable {
    let index: Int
    let tree: SourceFileSyntax
    let converter: SourceLocationConverter
}

/// Parse every source concurrently, returning the results in input order.
func parseSources(_ sources: [SourceInput]) -> [ParsedSource] {
    let count = sources.count
    guard count > 0 else {
        return []
    }

    // Each iteration writes a distinct index, so concurrent writes never race;
    // `nonisolated(unsafe)` lets the concurrent closure capture the pointer.
    nonisolated(unsafe) let storage = UnsafeMutablePointer<ParsedSource?>.allocate(capacity: count)
    storage.initialize(repeating: nil, count: count)
    defer {
        storage.deinitialize(count: count)
        storage.deallocate()
    }

    DispatchQueue.concurrentPerform(iterations: count) { index in
        let source = sources[index]
        let tree = Parser.parse(source: source.text)
        let converter = SourceLocationConverter(fileName: source.path, tree: tree)
        // Each iteration writes a distinct index, so the writes never race.
        storage[index] = ParsedSource(index: index, tree: tree, converter: converter)
    }

    return (0..<count).compactMap { storage[$0] }
}
