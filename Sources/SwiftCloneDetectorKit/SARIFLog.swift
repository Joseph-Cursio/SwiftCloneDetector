//
//  SARIFLog.swift
//  SwiftCloneDetectorKit
//
//  The root SARIF document. Lives apart from SARIFModel because its `$schema`
//  key needs a CodingKeys mapping.
//

/// The root of a SARIF 2.1.0 log file.
struct SARIFLog: Encodable {
    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case version
        case runs
    }

    let schema: String
    let version: String
    let runs: [SARIF.Run]
}
