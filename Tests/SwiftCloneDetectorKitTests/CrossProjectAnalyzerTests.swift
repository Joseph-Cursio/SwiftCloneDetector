//
//  CrossProjectAnalyzerTests.swift
//  SwiftCloneDetectorKitTests
//
//  Covers file→project mapping, the ≥2-project filter, and hoist vs
//  duplicated-from-shared classification.
//

import Testing
@testable import SwiftCloneDetectorKit

@Suite("CrossProjectAnalyzer")
struct CrossProjectAnalyzerTests {

    private let roots = [
        ProjectRoot(name: "LintStudioUI", path: "/work/LintStudioUI", isShared: true),
        ProjectRoot(name: "SwiftLintRuleStudio", path: "/work/SwiftLintRuleStudio"),
        ProjectRoot(name: "SwiftProjectLint", path: "/work/SwiftProjectLint"),
        ProjectRoot(name: "SwiftFormatLint", path: "/work/SwiftFormatLint")
    ]

    private func cloneClass(_ paths: [String]) -> CloneClass {
        let instances = paths.map {
            CloneInstance(path: $0, startLine: 1, startColumn: 1, endLine: 10, endColumn: 1)
        }
        return CloneClass(mass: 40, instances: instances)
    }

    @Test("maps a file to its owning project by path prefix")
    func mapsFileToProject() {
        let analyzer = CrossProjectAnalyzer(roots: roots)
        #expect(analyzer.project(for: "/work/SwiftProjectLint/Sources/App.swift")?.name == "SwiftProjectLint")
        #expect(analyzer.project(for: "/work/LintStudioUI/Sources/View.swift")?.name == "LintStudioUI")
        #expect(analyzer.project(for: "/elsewhere/Other/File.swift") == nil)
    }

    @Test("does not match a sibling whose name shares a prefix")
    func respectsComponentBoundaries() {
        let analyzer = CrossProjectAnalyzer(roots: [
            ProjectRoot(name: "Lint", path: "/work/Lint")
        ])
        // "/work/LintStudioUI/..." must not be claimed by the "/work/Lint" root.
        #expect(analyzer.project(for: "/work/LintStudioUI/Sources/View.swift") == nil)
    }

    @Test("flags code duplicated across two consumers as a hoist candidate")
    func hoistCandidateAcrossConsumers() {
        let analyzer = CrossProjectAnalyzer(roots: roots)
        let classes = [cloneClass([
            "/work/SwiftLintRuleStudio/Sources/Badge.swift",
            "/work/SwiftProjectLint/Sources/Badge.swift"
        ])]
        let cross = analyzer.analyze(classes)
        #expect(cross.count == 1)
        #expect(cross.first?.kind == .hoistCandidate)
        #expect(cross.first?.projects == ["SwiftLintRuleStudio", "SwiftProjectLint"])
    }

    @Test("flags a consumer copy of shared code as duplicated-from-shared")
    func duplicatedFromShared() {
        let analyzer = CrossProjectAnalyzer(roots: roots)
        let classes = [cloneClass([
            "/work/LintStudioUI/Sources/Badge.swift",
            "/work/SwiftFormatLint/Sources/Badge.swift"
        ])]
        let cross = analyzer.analyze(classes)
        #expect(cross.first?.kind == .duplicatedFromShared)
    }

    @Test("shared involvement wins even when several consumers also copied it")
    func sharedWinsOverMultipleConsumers() {
        let analyzer = CrossProjectAnalyzer(roots: roots)
        let classes = [cloneClass([
            "/work/LintStudioUI/Sources/Badge.swift",
            "/work/SwiftProjectLint/Sources/Badge.swift",
            "/work/SwiftFormatLint/Sources/Badge.swift"
        ])]
        let cross = analyzer.analyze(classes)
        #expect(cross.first?.kind == .duplicatedFromShared)
        #expect(cross.first?.projects.count == 3)
    }

    @Test("drops duplication confined to a single project")
    func dropsIntraProjectDuplication() {
        let analyzer = CrossProjectAnalyzer(roots: roots)
        let classes = [cloneClass([
            "/work/SwiftProjectLint/Sources/A.swift",
            "/work/SwiftProjectLint/Sources/B.swift"
        ])]
        #expect(analyzer.analyze(classes).isEmpty)
    }

    @Test("ignores instances outside every known project root")
    func ignoresUnknownFiles() {
        let analyzer = CrossProjectAnalyzer(roots: roots)
        // One known consumer + one stray file: only one project, so not cross-project.
        let classes = [cloneClass([
            "/work/SwiftProjectLint/Sources/A.swift",
            "/tmp/scratch/A.swift"
        ])]
        #expect(analyzer.analyze(classes).isEmpty)
    }
}
