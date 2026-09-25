//
//  Reporters.swift
//  SwiftCloneDetectorKit
//
//  Machine-readable output: the detector's own JSON schema and SARIF 2.1.0. The
//  console reporter lives in the executable; this builds the structured formats
//  and lives in the kit so it is unit-testable. All output is encoded with
//  sorted keys so it is byte-stable from one CI run to the next. The entry
//  points are `package` — usable by the executable and tests, but not part of
//  the library's public API.
//

import Foundation

/// Key under `partialFingerprints` so GitHub can track a clone across runs.
private let kFingerprintKey = "swiftCloneDetector/v1"
private let kSarifLevel = "warning"
private let kSarifVersion = "2.1.0"
private let kSarifSchema = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1.0.json"

// MARK: - Encoding

/// A pretty-printing, key-sorting JSON encoder — shared with baseline writing so
/// every file this tool emits is reproducible.
package func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}

private func encodeToString(_ value: some Encodable) -> String {
    guard let data = try? makeEncoder().encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

// MARK: - Shared helpers

func lineSpan(of cloneClass: CloneClass) -> Int {
    let first = cloneClass.instances[0]
    return first.endLine - first.startLine + 1
}

func duplicatedLineCount(_ classes: [CloneClass]) -> Int {
    var total = 0
    for cloneClass in classes {
        total += lineSpan(of: cloneClass) * (cloneClass.instances.count - 1)
    }
    return total
}

private func similarityNote(_ cloneClass: CloneClass) -> String {
    guard let similarity = cloneClass.similarity else {
        return ""
    }
    let percentScale = 100.0
    let percent = Int((similarity * percentScale).rounded())
    return ", \(percent)% similar"
}

private func crossKindID(_ kind: CrossProjectKind) -> String {
    switch kind {
    case .hoistCandidate:
        return "cross-project-hoist-candidate"
    case .duplicatedFromShared:
        return "cross-project-duplicated-from-shared"
    }
}

private func crossKindDescription(_ kind: CrossProjectKind) -> String {
    switch kind {
    case .hoistCandidate:
        return "Hoist candidate"
    case .duplicatedFromShared:
        return "Duplicated from shared"
    }
}

// MARK: - JSON

private func jsonClone(_ cloneClass: CloneClass) -> CloneReportJSON.Clone {
    CloneReportJSON.Clone(
        fingerprint: cloneFingerprint(for: cloneClass),
        mass: cloneClass.mass,
        lineSpan: lineSpan(of: cloneClass),
        similarity: cloneClass.similarity,
        instances: cloneClass.instances.map(CloneReportJSON.Instance.init)
    )
}

private func jsonCrossClone(_ clone: CrossProjectClone) -> CloneReportJSON.CrossClone {
    let cloneClass = clone.cloneClass
    return CloneReportJSON.CrossClone(
        fingerprint: cloneFingerprint(for: cloneClass),
        mass: cloneClass.mass,
        lineSpan: lineSpan(of: cloneClass),
        similarity: cloneClass.similarity,
        kind: crossKindID(clone.kind),
        projects: clone.projects,
        instances: cloneClass.instances.map(CloneReportJSON.Instance.init)
    )
}

/// Render clone classes as the detector's compact JSON schema.
package func jsonReport(_ classes: [CloneClass], fileCount: Int, nearMiss: Bool) -> String {
    let report = CloneReportJSON.Report(
        tool: ToolInfo.name,
        version: ToolInfo.version,
        mode: nearMiss ? "type3" : "type1-2",
        fileCount: fileCount,
        duplicatedLines: duplicatedLineCount(classes),
        cloneCount: classes.count,
        clones: classes.map { jsonClone($0) }
    )
    return encodeToString(report)
}

/// Render cross-project clones as the detector's compact JSON schema.
package func jsonReportCrossProject(_ clones: [CrossProjectClone], fileCount: Int) -> String {
    let report = CloneReportJSON.CrossReport(
        tool: ToolInfo.name,
        version: ToolInfo.version,
        mode: "cross-project",
        fileCount: fileCount,
        duplicatedLines: duplicatedLineCount(clones.map(\.cloneClass)),
        cloneCount: clones.count,
        clones: clones.map { jsonCrossClone($0) }
    )
    return encodeToString(report)
}

// MARK: - SARIF

private func sarifDocument(findings: [SARIF.Finding], rules: [SARIFRule]) -> String {
    let results = findings.map { finding in
        SARIF.Result(
            ruleId: finding.ruleID,
            level: kSarifLevel,
            message: SARIF.Text(text: finding.message),
            locations: finding.instances.map(SARIF.Location.init),
            partialFingerprints: [kFingerprintKey: finding.fingerprint]
        )
    }
    let driver = SARIF.Driver(
        name: ToolInfo.name,
        version: ToolInfo.version,
        informationUri: ToolInfo.informationURI,
        rules: rules
    )
    let log = SARIFLog(
        schema: kSarifSchema,
        version: kSarifVersion,
        runs: [SARIF.Run(tool: SARIF.Tool(driver: driver), results: results)]
    )
    return encodeToString(log)
}

/// Render clone classes as a SARIF 2.1.0 log.
package func sarifReport(_ classes: [CloneClass], nearMiss: Bool) -> String {
    let ruleID = nearMiss ? "type3-near-miss-clone" : "type1-2-clone"
    let ruleName = nearMiss ? "Type-3 near-miss clone" : "Type-1/2 clone"
    let rule = SARIFRule(
        identifier: ruleID,
        name: ruleName,
        shortDescription: SARIF.Text(text: "Duplicated code detected by structural matching."),
        defaultConfiguration: SARIF.Configuration(level: kSarifLevel)
    )
    let findings = classes.map { cloneClass in
        let message = "\(ruleName): \(cloneClass.instances.count) instances, "
            + "\(cloneClass.mass) nodes (~\(lineSpan(of: cloneClass)) lines)"
            + similarityNote(cloneClass)
        return SARIF.Finding(
            ruleID: ruleID,
            message: message,
            fingerprint: cloneFingerprint(for: cloneClass),
            instances: cloneClass.instances
        )
    }
    return sarifDocument(findings: findings, rules: [rule])
}

/// Render cross-project clones as a SARIF 2.1.0 log.
package func sarifReportCrossProject(_ clones: [CrossProjectClone]) -> String {
    let rules = [
        SARIFRule(
            identifier: crossKindID(.hoistCandidate),
            name: "Hoist candidate",
            shortDescription: SARIF.Text(text: "Duplicated across consumers; extract into the shared package."),
            defaultConfiguration: SARIF.Configuration(level: kSarifLevel)
        ),
        SARIFRule(
            identifier: crossKindID(.duplicatedFromShared),
            name: "Duplicated from shared",
            shortDescription: SARIF.Text(text: "A consumer re-copied shared code; import it instead."),
            defaultConfiguration: SARIF.Configuration(level: kSarifLevel)
        )
    ]
    let findings = clones.map { clone in
        let cloneClass = clone.cloneClass
        let message = "\(crossKindDescription(clone.kind)): \(cloneClass.instances.count) instances, "
            + "\(cloneClass.mass) nodes (~\(lineSpan(of: cloneClass)) lines), "
            + "in \(clone.projects.joined(separator: " + "))"
            + similarityNote(cloneClass)
        return SARIF.Finding(
            ruleID: crossKindID(clone.kind),
            message: message,
            fingerprint: cloneFingerprint(for: cloneClass),
            instances: cloneClass.instances
        )
    }
    return sarifDocument(findings: findings, rules: rules)
}
