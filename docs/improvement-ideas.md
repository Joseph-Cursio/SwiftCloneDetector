# Improvement Ideas

A ranked backlog of potential improvements for swift-clone-detector, based on a
read-through of the package (~1,600 LOC). Most are "next step" ideas rather than
fixes — the tool is already mature and well-documented.

## Done

### 1. Machine-readable output (`--json` / SARIF) ✅

`--format text|json|sarif`. SARIF 2.1.0 drops straight into GitHub code-scanning,
with a stable `partialFingerprints` value per clone so GitHub tracks it across
runs. The compact `json` schema is for scripting/dashboards. All formats encode
with sorted keys, so output is byte-stable between runs.

### 2. Baseline / diff mode ✅

`--write-baseline PATH` records the accepted clones; `--baseline PATH` then fails
only on clones absent from it — the standard CI ratchet. Clone identity is its
*shape* (mass + instance count + sorted file set), not its absolute line numbers,
so a recorded clone survives line drift while a materially changed one resurfaces.
The baseline file is fingerprint-sorted and carries each clone's files/mass for
reviewable diffs. Works in `--cross-project` mode too.

### 3. Argument-parsing footguns ✅

Migrated the CLI to **swift-argument-parser** (`CloneDetectorCommand`). The
library now provides what the hand-rolled parser had to do by hand: unknown
options, type-mismatched values (`--min-mass abc`) and missing values are all
rejected with clear errors, and `--help`/`--version` are generated. Range checks
(`--min-mass` floor, `--similarity` in `0...1`) live in `validate()`. Usage errors
exit `64` (`EX_USAGE`) — the framework convention — while the clones-found `2` and
clean `0` exit codes are preserved. Baseline I/O failures surface as
`ValidationError`. Cost: one dependency (swift-syntax is no longer the only one).

## Medium

### 4. `--exclude` globs ✅

`--exclude GLOB` (repeatable) skips the user's own files on top of the always-on
build-artifact filter. A glob is matched with `fnmatch` against both the full
path and the bare file name, with `*` spanning directory separators — so
`*Tests.swift`, `*.pb.swift` and `*/Generated/*` all work. Covered by discovery
unit tests and an end-to-end test that watches a clone disappear under
`--exclude '*Tests.swift'`.

### 5. Parallel parsing ✅

All three finders parse via a shared `parseSources` helper that runs
`Parser.parse` across every file concurrently (`DispatchQueue.concurrentPerform`)
before the serial collect + match stages — parsing is the expensive,
independent, embarrassingly parallel pass. `find` stays synchronous, so the CLI
needed no async change. Results are unchanged (the existing finder suites are the
regression guard, plus a 12-file test asserting each clone maps back to the right
file path).

Swift 6 strict concurrency makes this delicate: SwiftSyntax trees aren't
`Sendable`, so the parsed result is carried in an `@unchecked Sendable`
`ParsedSource` (sound — trees are immutable, parsed independently, and the
concurrent pass is a barrier before any tree is read) and the result buffer is a
`nonisolated(unsafe)` pointer written only at distinct indices. The collect pass
is still serial; parallelizing it too would need the same care for the
`Syntax`-holding fragment types.

### 6. Sequence clones ✅

`--sequence` (`SequenceCloneFinder`) detects a duplicated *run* of consecutive
statements or members that spans a sub-list of a `CodeBlockItemList` /
`MemberBlockItemList` rather than a single subtree — the most common real-world
copy-paste shape the subtree pass misses. Each item is hashed; matching runs are
found by recursively grouping item positions by hash and keeping each maximal
(left- and right-maximal) run, then confirmed with the same consistent-renaming
signature as `CloneFinder` (so Type-2 reuse must match across the whole run) and
filtered for overlap/mass. Reported as Type-1/2. The shared hash/signature logic
was extracted into `Structure` and reused by both finders.

Worst case is O(n²) within a hash bucket (same band as Type-3); typical input is
near-linear. A future refinement could expose `--min-sequence-items` and use a
suffix-array of statement hashes for guaranteed-linear maximal-repeat finding.

## Low / housekeeping

### 7. `.swiftlint.yml.*.backup` clutter ✅

Removed the 35 backup files (gitignored, so no tracked change). They were
intermediate config snapshots, not duplicates of the final config — the tracked
`.swiftlint.yml` has the full curated rule set; the backups captured earlier,
smaller rule sets.

**Source:** SwiftLintRuleStudio's Config Version History feature, which writes
`.swiftlint.yml.<unix-timestamp>.backup` before each rule edit
(`ConfigVersionHistoryViewModel`). The Jun 11 burst — 35 snapshots in four
minutes — was that tool building up this repo's rule set, one toggle at a time.
They'll reappear if SwiftLintRuleStudio is pointed at this repo again; the clean
fix is on that side (write snapshots to a dedicated history dir or `/tmp`, as its
own tests already do), not here.

### 8. Output-format tests ✅ (JSON/SARIF)

The JSON and SARIF reporters moved into the kit (as `package`, so they stay out
of the library's public API) and gained round-trip tests: emit from known clone
classes, parse the output back, and assert structure, fingerprints and
byte-stability. Coverage of `Reporters.swift` went from untested (0%) to ~99%;
kit line coverage is ~98%.

Argument parsing is now tested too: a `SwiftCloneDetectorCLITests` target
`@testable import`s the executable (importable since it uses `@main`) and drives
`CloneDetectorCommand.parse([...])` — covering option/flag/path decoding, the
`validate()` bounds, and the framework's type/unknown-option errors.
`CloneDetectorCommand` line coverage went from 0% to ~28%.

An integration pass closed the rest: `IntegrationTests` runs the command
end-to-end over temp-directory fixtures (planted clones, clean trees, every
output format, baseline write/suppress/new-clone, missing/corrupt baselines,
cross-project hoist), capturing stdout and asserting exit codes, output and the
written baseline. That lifted the executable target from near-zero to
`CloneDetectorCommand` ~88%, `CommandLineSupport` ~90%, `BaselineFile` ~84% line
coverage; the whole package now sits at ~96% lines / ~94% functions. The thin
remainder is defensive error branches (encode/IO failures) and a few format
permutations not worth a dedicated fixture.

## Recommendation

**#1 (SARIF) + #2 (baseline)** together turn this from "a clever detector" into
"a tool a team can actually adopt in CI," and they reinforce each other (baseline
naturally serializes to the same structured model SARIF needs).
