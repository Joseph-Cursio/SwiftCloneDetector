//
//  SARIF.swift
//  swift-clone-detector
//
//  The SARIF 2.1.0 object model, minus the two types that need custom JSON keys
//  (SARIFRule's `id` and SARIFLog's `$schema`, which live in their own files).
//  Namespaced under `SARIF` so the whole schema reads as one unit.
//

import SwiftCloneDetectorKit

/// Namespace for the SARIF 2.1.0 result-format types the reporter emits.
enum SARIF {
    /// A `{ "text": ... }` message wrapper, used for rule and result messages.
    struct Text: Encodable {
        let text: String
    }

    /// A rule's default severity, e.g. `{ "level": "warning" }`.
    struct Configuration: Encodable {
        let level: String
    }

    /// The file a location points into.
    struct ArtifactLocation: Encodable {
        let uri: String
    }

    /// A 1-based source span within an artifact.
    struct Region: Encodable {
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int
    }

    /// An artifact plus the region within it.
    struct PhysicalLocation: Encodable {
        let artifactLocation: ArtifactLocation
        let region: Region
    }

    /// One source location of a result — one instance of a clone.
    struct Location: Encodable {
        let physicalLocation: PhysicalLocation

        init(_ instance: CloneInstance) {
            self.physicalLocation = PhysicalLocation(
                artifactLocation: ArtifactLocation(uri: instance.path),
                region: Region(
                    startLine: instance.startLine,
                    startColumn: instance.startColumn,
                    endLine: instance.endLine,
                    endColumn: instance.endColumn
                )
            )
        }
    }

    /// A single reported clone, spread across all the locations it occupies.
    struct Result: Encodable {
        let ruleId: String
        let level: String
        let message: Text
        let locations: [Location]
        let partialFingerprints: [String: String]
    }

    /// The tool that produced the run.
    struct Driver: Encodable {
        let name: String
        let version: String
        let informationUri: String
        let rules: [SARIFRule]
    }

    /// The `tool` wrapper around its driver.
    struct Tool: Encodable {
        let driver: Driver
    }

    /// One analysis run: the tool plus its results.
    struct Run: Encodable {
        let tool: Tool
        let results: [Result]
    }

    /// A format-agnostic finding, so normal and cross-project runs can feed the
    /// same SARIF builder before the SARIF types are assembled.
    struct Finding {
        let ruleID: String
        let message: String
        let fingerprint: String
        let instances: [CloneInstance]
    }
}
