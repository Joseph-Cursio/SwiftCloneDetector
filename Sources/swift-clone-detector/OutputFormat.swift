//
//  OutputFormat.swift
//  swift-clone-detector
//
//  How results are rendered to stdout. CaseIterable + ExpressibleByArgument let
//  ArgumentParser validate the value and list the choices in errors and --help.
//

import ArgumentParser

/// How results are rendered to stdout.
enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    /// The detector's own compact JSON schema, for scripting.
    case json
    /// SARIF 2.1.0, for GitHub code-scanning and IDE integration.
    case sarif
    /// Human-readable console report (the default).
    case text
}
