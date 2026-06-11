//
//  SARIFRule.swift
//  SwiftCloneDetectorKit
//
//  A SARIF rule descriptor. Lives apart from SARIFModel because its `id` key
//  needs a CodingKeys mapping (the Swift property is spelled out to satisfy the
//  identifier-length rule).
//

/// A SARIF `reportingDescriptor` — one rule the tool can report against.
struct SARIFRule: Encodable {
    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case name
        case shortDescription
        case defaultConfiguration
    }

    let identifier: String
    let name: String
    let shortDescription: SARIF.Text
    let defaultConfiguration: SARIF.Configuration
}
