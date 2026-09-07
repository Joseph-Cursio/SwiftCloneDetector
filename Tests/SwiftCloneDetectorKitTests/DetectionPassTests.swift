//
//  DetectionPassTests.swift
//  SwiftCloneDetectorKitTests
//
//  The pass identity carried on every clone class: how it names itself, and how
//  strong a claim it makes when two passes cover the same region.
//

import Foundation
@testable import SwiftCloneDetectorKit
import Testing

@Suite("DetectionPass")
struct DetectionPassTests {
    @Test("every pass names itself, and no two share a name")
    func labelsAreDistinct() {
        let labels = DetectionPass.allCases.map(\.label)
        #expect(labels.allSatisfy { $0.isEmpty == false })
        #expect(Set(labels).count == DetectionPass.allCases.count)
    }

    // The order the merge relies on: an exact match outranks a run of identical
    // statements, which outranks "87% alike".
    @Test("claims are ordered exact, sequence, near-miss")
    func specificityIsOrdered() {
        #expect(DetectionPass.subtree.specificity < DetectionPass.sequence.specificity)
        #expect(DetectionPass.sequence.specificity < DetectionPass.nearMiss.specificity)
    }

    @Test("every pass has a distinct rank, so the merge order is total")
    func specificityIsTotal() {
        let ranks = DetectionPass.allCases.map(\.specificity)
        #expect(Set(ranks).count == DetectionPass.allCases.count)
    }

    @Test("the raw values survive a round trip, so a report can be re-read")
    func codableRoundTrip() throws {
        for pass in DetectionPass.allCases {
            let encoded = try JSONEncoder().encode(pass)
            #expect(try JSONDecoder().decode(DetectionPass.self, from: encoded) == pass)
        }
    }
}
