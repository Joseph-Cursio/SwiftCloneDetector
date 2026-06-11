# swift-clone-detector

[![Why this project](https://img.shields.io/badge/docs-why%20this%20project-blue)](docs/why-this-project.md)

A Type-1/2/3 Swift clone detector built on SwiftSyntax. It finds the copy-paste
duplication that token-based tools (PMD/CPD) handle poorly on Swift, by matching
**AST structure** instead of token runs.

Standalone SwiftPM package — depends only on swift-syntax.

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
2. Cluster subtrees of the **same anchor kind** whose vectors score ≥
   `--similarity` (Sørensen–Dice) via union-find. Exact copies (identical
   signature) are excluded — they belong to the Type-1/2 pass.
3. Subsume nested clusters, same as above, and report each class with its
   minimum pairwise similarity.

## Usage

```sh
# Type-2 (default): exact + renamed
swift run swift-clone-detector --min-mass 60 /path/to/Sources

# Type-3: near-miss copies that drifted by a few statements
swift run swift-clone-detector --type3 --min-mass 90 --similarity 0.88 /path/to/Sources
```

`--min-mass` is the precision dial (higher = fewer, larger clones). Exit code is
`2` when clones are found (handy for CI gating), `0` when clean.

## Limitations (by design)

- **Type-4 is out of scope.** Same behavior via a different implementation (e.g.
  a line-diff and a char-diff sharing one algorithm) has no structural overlap;
  that stays a reading-pass job.
- **Identifier renaming is "blind"** — all identifiers map to one placeholder
  rather than enforcing a consistent 1:1 mapping, which can slightly over-match.
- **Sequence clones** (a duplicated *run* of sibling statements that isn't a
  single subtree) aren't detected yet; that needs a sliding window over
  `CodeBlockItemList`.
- **Type-3 clustering is O(n²)** within each anchor-kind/size band. Fine for
  small-to-medium codebases; a large tree would want LSH over the vectors (also
  Deckard's approach) to scale.
