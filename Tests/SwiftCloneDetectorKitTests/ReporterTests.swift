//
//  ReporterTests.swift
//  SwiftCloneDetectorKitTests
//
//  Round-trip tests for the JSON and SARIF reporters: emit from known clone
//  classes, parse the output back, and assert the structure, fingerprints and
//  byte-stability that downstream tools (GitHub code-scanning, scripts) rely on.
//

import Foundation
@testable import SwiftCloneDetectorKit
import Testing

@Suite("Reporters")
struct ReporterTests {
    // MARK: Fixtures

    private func instance(_ path: String, _ startLine: Int, _ endLine: Int) -> CloneInstance {
        CloneInstance(path: path, startLine: startLine, startColumn: 5, endLine: endLine, endColumn: 9)
    }

    private func exactClone() -> CloneClass {
        CloneClass(
            mass: 80,
            instances: [instance("a.swift", 10, 20), instance("b.swift", 60, 70)]
        )
    }

    private func nearMissClone() -> CloneClass {
        CloneClass(
            mass: 120,
            instances: [instance("a.swift", 1, 12), instance("b.swift", 30, 42)],
            similarity: 0.9
        )
    }

    private func object(_ text: String) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(parsed as? [String: Any])
    }

    // MARK: JSON

    @Test("JSON report carries tool metadata, counts and per-clone fields")
    func jsonReportShape() throws {
        let clone = exactClone()
        let root = try object(jsonReport([clone], fileCount: 7, nearMiss: false))

        #expect(root["tool"] as? String == "swift-clone-detector")
        #expect(root["mode"] as? String == "type1-2")
        #expect(root["fileCount"] as? Int == 7)
        #expect(root["cloneCount"] as? Int == 1)
        // 11-line span duplicated once (two instances).
        #expect(root["duplicatedLines"] as? Int == 11)

        let clones = try #require(root["clones"] as? [[String: Any]])
        let first = try #require(clones.first)
        #expect(first["fingerprint"] as? String == cloneFingerprint(for: clone))
        #expect(first["mass"] as? Int == 80)
        #expect(first["lineSpan"] as? Int == 11)
        #expect(first["similarity"] == nil)  // exact clones omit similarity
        let instances = try #require(first["instances"] as? [[String: Any]])
        #expect(instances.count == 2)
        #expect(instances.first?["path"] as? String == "a.swift")
        #expect(instances.first?["startLine"] as? Int == 10)
    }

    @Test("near-miss JSON report sets type3 mode and includes similarity")
    func jsonReportNearMiss() throws {
        let root = try object(jsonReport([nearMissClone()], fileCount: 2, nearMiss: true))
        #expect(root["mode"] as? String == "type3")
        let clones = try #require(root["clones"] as? [[String: Any]])
        #expect(clones.first?["similarity"] as? Double == 0.9)
    }

    @Test("JSON report for no clones is well-formed and empty")
    func jsonReportEmpty() throws {
        let root = try object(jsonReport([], fileCount: 4, nearMiss: false))
        #expect(root["cloneCount"] as? Int == 0)
        #expect(root["duplicatedLines"] as? Int == 0)
        #expect((root["clones"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("JSON output is byte-stable across runs")
    func jsonReportStable() {
        let clones = [exactClone(), nearMissClone()]
        let first = jsonReport(clones, fileCount: 3, nearMiss: false)
        let second = jsonReport(clones, fileCount: 3, nearMiss: false)
        #expect(first == second)
    }

    // MARK: SARIF

    @Test("SARIF report is a valid 2.1.0 log with one result per clone")
    func sarifReportShape() throws {
        let clone = exactClone()
        let root = try object(sarifReport([clone], nearMiss: false))

        #expect(root["version"] as? String == "2.1.0")
        #expect(root["$schema"] is String)

        let runs = try #require(root["runs"] as? [[String: Any]])
        let run = try #require(runs.first)
        let driver = try #require((run["tool"] as? [String: Any])?["driver"] as? [String: Any])
        #expect(driver["name"] as? String == "swift-clone-detector")
        let rules = try #require(driver["rules"] as? [[String: Any]])
        #expect(rules.first?["id"] as? String == "type1-2-clone")

        let results = try #require(run["results"] as? [[String: Any]])
        let result = try #require(results.first)
        #expect(result["ruleId"] as? String == "type1-2-clone")
        #expect(result["level"] as? String == "warning")

        let prints = try #require(result["partialFingerprints"] as? [String: Any])
        #expect(prints["swiftCloneDetector/v1"] as? String == cloneFingerprint(for: clone))

        let locations = try #require(result["locations"] as? [[String: Any]])
        #expect(locations.count == 2)
        let region = try #require(
            ((locations.first?["physicalLocation"] as? [String: Any])?["region"]) as? [String: Any]
        )
        #expect(region["startLine"] as? Int == 10)
        #expect(region["endLine"] as? Int == 20)
    }

    @Test("near-miss SARIF uses the type3 rule and notes similarity")
    func sarifReportNearMiss() throws {
        let root = try object(sarifReport([nearMissClone()], nearMiss: true))
        let run = try #require((root["runs"] as? [[String: Any]])?.first)
        let result = try #require((run["results"] as? [[String: Any]])?.first)
        #expect(result["ruleId"] as? String == "type3-near-miss-clone")
        let message = try #require((result["message"] as? [String: Any])?["text"] as? String)
        #expect(message.contains("90% similar"))
    }

    // MARK: Cross-project

    private func crossClone(_ kind: CrossProjectKind) -> CrossProjectClone {
        CrossProjectClone(cloneClass: exactClone(), projects: ["AppA", "AppB"], kind: kind)
    }

    @Test("cross-project JSON labels kind and projects")
    func jsonCrossProject() throws {
        let root = try object(jsonReportCrossProject([crossClone(.hoistCandidate)], fileCount: 9))
        #expect(root["mode"] as? String == "cross-project")
        let first = try #require((root["clones"] as? [[String: Any]])?.first)
        #expect(first["kind"] as? String == "cross-project-hoist-candidate")
        #expect(first["projects"] as? [String] == ["AppA", "AppB"])
    }

    @Test("cross-project SARIF declares both rules and tags each result by kind")
    func sarifCrossProject() throws {
        let root = try object(sarifReportCrossProject([crossClone(.duplicatedFromShared)]))
        let run = try #require((root["runs"] as? [[String: Any]])?.first)
        let driver = try #require((run["tool"] as? [String: Any])?["driver"] as? [String: Any])
        let ruleIDs = try #require(driver["rules"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        #expect(ruleIDs.contains("cross-project-hoist-candidate"))
        #expect(ruleIDs.contains("cross-project-duplicated-from-shared"))
        let result = try #require((run["results"] as? [[String: Any]])?.first)
        #expect(result["ruleId"] as? String == "cross-project-duplicated-from-shared")
    }
}
