//
//  SourceInput.swift
//  SwiftCloneDetectorKit
//
//  One Swift file handed to a clone finder: its path (for reporting) and its
//  source text (for parsing).
//

/// A single source file to scan: its path, used only for reporting, and its
/// full text, which the finder parses.
public struct SourceInput: Sendable {
    public let path: String
    public let text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}
