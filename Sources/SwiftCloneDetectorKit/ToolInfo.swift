//
//  ToolInfo.swift
//  SwiftCloneDetectorKit
//
//  Tool metadata shared by the command configuration and the reporters. Lives in
//  the kit (as `package`) so the reporters can stamp it into their output while
//  staying unit-testable.
//

/// Static tool metadata: name, version and project URL.
package enum ToolInfo {
    package static let name = "swift-clone-detector"
    package static let version = "0.1.0"
    package static let informationURI = "https://github.com/Joseph-Cursio/SwiftCloneDetector"
}
