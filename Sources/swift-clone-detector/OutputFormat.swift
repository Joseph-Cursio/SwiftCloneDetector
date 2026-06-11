//
//  OutputFormat.swift
//  swift-clone-detector
//
//  How results are rendered to stdout.
//

/// How results are rendered to stdout.
enum OutputFormat: String {
    /// The detector's own compact JSON schema, for scripting.
    case json
    /// SARIF 2.1.0, for GitHub code-scanning and IDE integration.
    case sarif
    /// Human-readable console report (the default).
    case text
}
