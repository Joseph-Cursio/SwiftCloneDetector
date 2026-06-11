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

## High leverage

### 3. Argument-parsing footguns (partially addressed)

`--format` now rejects unknown values with a usage error, and value options run
through a known-name set. Still open: an unknown **flag** (`--min-mas 60`, a typo)
falls through `applyFlag`'s `default` and gets appended to `paths`, then silently
skipped as a non-existent path — so the user gets results with a *different*
min-mass than they asked for and no warning. Reject unknown `--flags` outright,
or migrate to **swift-argument-parser** (already checked out in the workspace).
The trade-off is one dependency vs. the current zero-dep-beyond-swift-syntax
purity; given the silent-failure UX, lean toward fixing it.

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

### 8. Output-format snapshot tests

The three test files cover the finders well, but `report()` /
`reportCrossProject()` formatting is untested — and that's exactly the surface
that'll regress when adding `--json`/SARIF.

## Recommendation

**#1 (SARIF) + #2 (baseline)** together turn this from "a clever detector" into
"a tool a team can actually adopt in CI," and they reinforce each other (baseline
naturally serializes to the same structured model SARIF needs).
