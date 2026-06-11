//
//  CloneReportJSON.swift
//  SwiftCloneDetectorKit
//
//  The detector's own compact JSON schema (`--format json`), namespaced under
//  CloneReportJSON. Distinct clone types for the normal and cross-project runs
//  keep every field non-optional and the output self-describing.
//

/// Namespace for the detector's own JSON output schema.
enum CloneReportJSON {
    /// One source location of a clone.
    struct Instance: Encodable {
        let path: String
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int

        init(_ instance: CloneInstance) {
            self.path = instance.path
            self.startLine = instance.startLine
            self.startColumn = instance.startColumn
            self.endLine = instance.endLine
            self.endColumn = instance.endColumn
        }
    }

    /// One clone class in a single-project run.
    struct Clone: Encodable {
        let fingerprint: String
        let mass: Int
        let lineSpan: Int
        let similarity: Double?
        let instances: [Instance]
    }

    /// One clone class in a cross-project run, with its projects and verdict.
    struct CrossClone: Encodable {
        let fingerprint: String
        let mass: Int
        let lineSpan: Int
        let similarity: Double?
        let kind: String
        let projects: [String]
        let instances: [Instance]
    }

    /// The top-level document for a single-project run.
    struct Report: Encodable {
        let tool: String
        let version: String
        let mode: String
        let fileCount: Int
        let duplicatedLines: Int
        let cloneCount: Int
        let clones: [Clone]
    }

    /// The top-level document for a cross-project run.
    struct CrossReport: Encodable {
        let tool: String
        let version: String
        let mode: String
        let fileCount: Int
        let duplicatedLines: Int
        let cloneCount: Int
        let clones: [CrossClone]
    }
}
