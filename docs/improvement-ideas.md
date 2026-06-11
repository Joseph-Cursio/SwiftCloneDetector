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

### 4. `--exclude` globs

File discovery hardcodes build-artifact skipping but gives the user no way to
exclude their own `*Tests.swift`, generated `*.pb.swift`, or `.snapshot`
fixtures — all of which are legitimately duplicative and create noise.

### 5. Parallel parsing

`loadSwiftFiles` parses sequentially and the finder is `@MainActor`. Parsing
(the expensive SwiftSyntax pass) is embarrassingly parallel and independent of
the analysis — a `TaskGroup` over file reads/parses before the serial analysis
stage would cut wall-clock on large trees with zero change to results.

### 6. Sequence clones

The duplicated-run-of-sibling-statements case the README already flags as
not-yet-detected. A sliding window over `CodeBlockItemList` is the natural
follow-on and probably the most common real-world copy-paste shape currently
missed (people copy a *block*, not a whole function).

## Low / housekeeping

### 7. `.swiftlint.yml.*.backup` clutter

35 backup files sit in the working dir. They're correctly gitignored
(`*.backup`), so this is just on-disk clutter from some snapshotting tool — safe
to `rm`. Worth checking *what's* generating them, though; that's a lot of
snapshots.

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
