# swift-clone-detector

[![Why this project](https://img.shields.io/badge/docs-why%20this%20project-blue)](docs/why-this-project.md)
[![vs PMD CPD](https://img.shields.io/badge/docs-vs%20PMD%20CPD-blue)](docs/pmd-comparison.md)

A Type-1/2/3 Swift clone detector built on SwiftSyntax. It finds the copy-paste
duplication that token-based tools (PMD/CPD) handle poorly on Swift, by matching
**AST structure** instead of token runs.

A head-to-head on three real, recently de-duplicated repos backs this up:
[**swift-clone-detector vs PMD CPD**](docs/pmd-comparison.md). In each, the
verbatim pass matches PMD's count while `--type2` adds the renamed clones CPD is
blind to — over files PMD sometimes can't even tokenize.

SwiftPM package; depends on swift-syntax (parsing) and swift-argument-parser
(the CLI).

## What it catches

| Clone type | Example | Caught |
|---|---|---|
| Type-1 (exact) | verbatim copy-paste | ✅ |
| Type-2 (renamed) | same code, `total` → `sum`, `42` → `99` | ✅ (default) |
| Type-3 (statements added/removed) | a copy with an extra `guard` | ✅ (`--type3`) |
| Type-4 (same behavior, different impl) | line-diff vs char-diff sharing one algorithm | ❌ — needs a reading pass |

## How it works

### Type-1/2 — exact structural match (`CloneFinder`)

1. **Parse** each file with `SwiftParser` → `SourceFileSyntax`.
2. **Walk** every subtree post-order, computing a stable FNV-1a hash over
   `(node.kind, children…)`. Leaf tokens are normalized per `Normalization`:
   identifiers/literals collapse to placeholders for Type-2, stay verbatim for
   Type-1. Only subtrees rooted at meaningful boundaries (`AnchorKinds`) and at
   or above `--min-mass` nodes are recorded.
3. **Bucket** fragments by hash, then **confirm** each bucket with a full
   structural signature (guards against hash collisions).
4. **Subsume** — report the largest clone in a nest and drop the sub-clones it
   contains, so a duplicated function is reported once, not once per nested loop.

### Type-3 — near-miss clustering (`NearMissFinder`)

An exact hash shatters the moment a statement is inserted, so Type-3 uses a
Deckard-style **characteristic vector** instead:

1. Reduce each significant subtree to a multiset of node-kind counts — a
   fingerprint that only *shifts* when a few nodes are added or removed.
2. **Weight each kind by how rare it is** across this run's fragments,
   `1 + ln(N / df)`. Unweighted, a construct every fragment carries counts as
   much as one only a few do, and two SwiftUI bodies rendering entirely
   different things score alike because both are mostly `FunctionCallExpr` and
   `MemberAccessExpr`. `--uniform-weighting` restores the flat scoring.
3. Cluster subtrees of the **same anchor kind** whose vectors score ≥
   `--similarity` (weighted Sørensen–Dice) via union-find. Exact copies
   (identical signature) are excluded — they belong to the Type-1/2 pass.
4. **Drop self-overlap** — a fragment's own parent is also a fragment, and where
   the parent adds only a wrapper (`while`, `do`, `Task { }` around one big
   statement) the two are similar enough to cluster together. Members contained
   inside another member of the *same* cluster are discarded, keeping the
   largest. Type-1/2 needs no such step: a parent and child never share an exact
   signature.
5. Subsume nested clusters, same as above, and report each class with its
   minimum pairwise similarity.

### The passes compose

They look for different shapes and each is blind to the others', so naming more
than one now runs all of them and merges the results:

```sh
swift-clone-detector . --all              # every pass
swift-clone-detector . --type3 --sequence # or name the ones you want
```

Naming none still runs the subtree pass alone. A mixed report labels each class
with the pass that found it, because "exact" and "87% similar" are different
claims. Merging never lets a weaker claim hide a stronger one: a near-miss class
does not subsume an exact match it happens to contain.

**No single pass finds everything.** Duplication spanning more than one
declaration — two classes sharing a run of stored properties and a method — is
invisible to `--type2` and `--type3` alike, because it is not one subtree.
Scored against hand-judged cases in [`Evaluation/`](Evaluation/README.md), only
the merged run reaches full recall.

## Usage

```sh
# Type-2 (default): exact + renamed
swift run swift-clone-detector --min-mass 60 /path/to/Sources

# Type-3: near-miss copies that drifted by a few statements
swift run swift-clone-detector --type3 --min-mass 90 --similarity 0.88 /path/to/Sources

# Sequence clones: a duplicated run of statements that isn't a whole subtree
swift run swift-clone-detector --sequence --min-mass 40 /path/to/Sources
```

`--sequence` catches a copy-pasted **run of consecutive statements** that the
default pass misses because it spans a sub-list of a function body, not a single
subtree (e.g. four statements lifted out of one function into the middle of
another). It hashes each statement, finds the maximal matching runs across every
statement/member list, and confirms them with the same consistent-renaming check
as the exact pass — so these are reported as Type-1/2 clones (a sequence clone is
an exact/renamed duplication; only the *shape* it spans differs). `--min-mass`
floors the run's total node count.

`--min-mass` is the precision dial (higher = fewer, larger clones). Exit code is
`2` when clones are found (handy for CI gating), `0` when clean, and `64`
(`EX_USAGE`) on a usage error. Run `--help` for the full option list (the CLI is
built on swift-argument-parser, so `--help` and `--version` are generated).

`--min-distinct-identifiers N` is a second, orthogonal precision dial: it drops
fragments carrying fewer than `N` distinct identifier tokens. Where `--min-mass`
filters by *size*, this filters by *unique naming* — useful against
large-but-repetitive structure (a long `switch`, a chained builder) that clears
the size floor while being semantically thin. Off by default (`0`).

Build directories (`.build*`, `.swiftpm`, `DerivedData`, `.git`) are always
skipped. Use `--exclude GLOB` (repeatable) to skip your own files — generated
code, test scaffolding, fixtures. A glob matches a file's full path or its bare
name, and `*` spans directory separators, so both `--exclude '*Tests.swift'` and
`--exclude '*/Generated/*'` work:

```sh
swift run swift-clone-detector --exclude '*Tests.swift' --exclude '*.pb.swift' Sources
```

### Output formats

`--format` selects how results are rendered (all formats share the same exit
codes):

| Format | Use |
|---|---|
| `text` (default) | human-readable console report |
| `json` | the detector's own compact schema, for scripting/dashboards |
| `sarif` | SARIF 2.1.0 — drops straight into GitHub code-scanning |

```sh
# Upload to GitHub code-scanning so clones surface as inline PR annotations.
swift run swift-clone-detector --format sarif Sources > clones.sarif
```

Every format encodes with sorted keys, so output is byte-stable from one run to
the next. Each clone carries a stable `fingerprint` (see below); SARIF mirrors it
in `partialFingerprints` so GitHub can track a clone across runs.

### Baseline mode (CI ratchet)

On a codebase that already has duplication, failing on *every* clone makes the
exit-`2` gate unadoptable. A baseline records the clones you've already accepted
so the gate fails only on clones that are **new** since it was written:

```sh
# 1. Record the current clones once, commit the file.
swift run swift-clone-detector --min-mass 60 --write-baseline clones-baseline.json Sources

# 2. In CI, fail only on clones absent from the baseline.
swift run swift-clone-detector --min-mass 60 --baseline clones-baseline.json Sources
```

A clone's baseline identity is its *shape* — mass, instance count and the sorted
set of files it touches — deliberately **not** its absolute line numbers. So a
recorded clone drifting up or down its files stays suppressed, while a materially
changed clone (different size or files) resurfaces as new. The baseline file is
sorted by fingerprint and carries each clone's files/mass, so its diffs are
reviewable in a pull request. Generate and check the baseline with the **same
path arguments** so the recorded paths line up. Both `--write-baseline` and
`--baseline` work in `--cross-project` mode too.

### Cross-project mode

When several apps depend on a shared library, the question isn't "is there
duplication?" but "what duplication belongs in the shared library?" Pass each
consumer as a positional path and the library with `--shared`:

```sh
swift run swift-clone-detector --cross-project --min-mass 60 \
  --shared ../LintStudioUI \
  ../SwiftLintRuleStudio ../SwiftProjectLint ../SwiftFormatLint
```

Clones confined to a single project are dropped — only duplication that spans
project boundaries is reported, split into two actionable groups:

| Group | Meaning | Fix |
|---|---|---|
| **Hoist candidates** | the same code in ≥2 consumers, not in the shared library | extract it into the shared library, import everywhere |
| **Duplicated from shared** | a consumer re-copied code that already exists in the shared library | delete the copy, import the library's version |

Each file is assigned to a project by path prefix, and the project name is the
last path component. Combines with `--type2` (default) or `--type3`, and exits
`2` when any cross-project clone is found.

## Limitations (by design)

- **Type-4 is out of scope.** Same behavior via a different implementation (e.g.
  a line-diff and a char-diff sharing one algorithm) has no structural overlap;
  that stays a reading-pass job.
- **Identifier renaming is consistent at confirmation, blind at hashing.** The
  hash that buckets candidates folds every identifier to one placeholder (fast,
  order-independent), so it over-approximates. Match confirmation then re-checks
  each bucket with a 1:1 renaming (first distinct identifier → `$ID0`, next →
  `$ID1`, reuse preserved), so two fragments match only if they reuse identifiers
  in the same pattern — e.g. an all-`Int` struct no longer matches a
  `String, Int, String` one. Renaming is still not type-aware: type names are
  renamed like any other identifier, so very small fragments (a lone
  `let x: Int`) can still match across unrelated types. Raise `--min-mass` to
  filter those.
- **Type-3 clustering is O(n²)** within each anchor-kind/size band. Fine for
  small-to-medium codebases; a large tree would want LSH over the vectors (also
  Deckard's approach) to scale.
