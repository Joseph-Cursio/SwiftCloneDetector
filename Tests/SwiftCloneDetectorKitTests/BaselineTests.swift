//
//  BaselineTests.swift
//  SwiftCloneDetectorKitTests
//
//  Covers the baseline fingerprint's stability (survives line drift, shifts on
//  shape change) and the partition that drives the "fail only on new" CI gate.
//

@testable import SwiftCloneDetectorKit
import Testing

@Suite("Baseline")
struct BaselineTests {
    private func instance(_ path: String, _ startLine: Int, _ endLine: Int) -> CloneInstance {
        CloneInstance(path: path, startLine: startLine, startColumn: 1, endLine: endLine, endColumn: 1)
    }

    private func cloneClass(
        _ instances: [CloneInstance],
        mass: Int = 100,
        similarity: Double? = nil
    ) -> CloneClass {
        CloneClass(mass: mass, instances: instances, similarity: similarity)
    }

    @Test("fingerprint is stable when only line numbers drift")
    func stableAcrossLineDrift() {
        let original = cloneClass([instance("a.swift", 10, 20), instance("b.swift", 30, 40)])
        // Same files, same mass — code merely moved down the file.
        let moved = cloneClass([instance("a.swift", 110, 120), instance("b.swift", 230, 240)])
        #expect(cloneFingerprint(for: original) == cloneFingerprint(for: moved))
    }

    @Test("fingerprint is order-independent across instances")
    func orderIndependent() {
        let forward = cloneClass([instance("a.swift", 1, 5), instance("b.swift", 1, 5)])
        let reversed = cloneClass([instance("b.swift", 1, 5), instance("a.swift", 1, 5)])
        #expect(cloneFingerprint(for: forward) == cloneFingerprint(for: reversed))
    }

    @Test("fingerprint shifts when the file set changes")
    func differsOnFiles() {
        let original = cloneClass([instance("a.swift", 1, 5), instance("b.swift", 1, 5)])
        let elsewhere = cloneClass([instance("a.swift", 1, 5), instance("c.swift", 1, 5)])
        #expect(cloneFingerprint(for: original) != cloneFingerprint(for: elsewhere))
    }

    @Test("fingerprint shifts when mass changes")
    func differsOnMass() {
        let small = cloneClass([instance("a.swift", 1, 5), instance("b.swift", 1, 5)], mass: 100)
        let large = cloneClass([instance("a.swift", 1, 5), instance("b.swift", 1, 5)], mass: 250)
        #expect(cloneFingerprint(for: small) != cloneFingerprint(for: large))
    }

    @Test("fingerprint shifts when instance count changes")
    func differsOnInstanceCount() {
        let pair = cloneClass([instance("a.swift", 1, 5), instance("b.swift", 1, 5)])
        let triple = cloneClass([
            instance("a.swift", 1, 5), instance("b.swift", 1, 5), instance("c.swift", 1, 5)
        ])
        #expect(cloneFingerprint(for: pair) != cloneFingerprint(for: triple))
    }

    @Test("near-miss similarity bucket participates in identity")
    func differsOnSimilarityBucket() {
        let instances = [instance("a.swift", 1, 5), instance("b.swift", 1, 5)]
        let high = cloneClass(instances, similarity: 0.95)
        let low = cloneClass(instances, similarity: 0.80)
        #expect(cloneFingerprint(for: high) != cloneFingerprint(for: low))
        // Trivial float drift within the same percent bucket stays identical.
        let jitter = cloneClass(instances, similarity: 0.9501)
        #expect(cloneFingerprint(for: high) == cloneFingerprint(for: jitter))
    }

    @Test("partition separates known from new clones")
    func partitionSplits() {
        let known = cloneClass([instance("a.swift", 1, 5), instance("b.swift", 1, 5)])
        let fresh = cloneClass([instance("c.swift", 1, 5), instance("d.swift", 1, 5)])
        let baseline = Baseline(classes: [known]).fingerprintSet

        let split = partitionClasses([known, fresh], baseline: baseline)
        #expect(split.known.count == 1)
        #expect(split.new.count == 1)
        #expect(cloneFingerprint(for: split.new[0]) == cloneFingerprint(for: fresh))
    }

    @Test("baseline entries are sorted by fingerprint for stable diffs")
    func baselineSorted() {
        let classes = (0..<8).map { index in
            cloneClass([instance("file\(index).swift", 1, 5), instance("other\(index).swift", 1, 5)])
        }
        let baseline = Baseline(classes: classes)
        let fingerprints = baseline.clones.map(\.fingerprint)
        #expect(fingerprints == fingerprints.sorted())
        #expect(baseline.version == Baseline.currentVersion)
    }
}
