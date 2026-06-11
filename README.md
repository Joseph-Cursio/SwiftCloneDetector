# swift-clone-detector

A Type-1/Type-2 Swift clone detector built on SwiftSyntax. It finds the
copy-paste duplication that token-based tools (PMD/CPD) handle poorly on Swift,
by matching **AST subtrees** instead of token runs.

This is a self-contained package under `Tools/` — it is **not** referenced by the
root `LintStudioUI` manifest, so it never pulls SwiftSyntax into the app build.

## What it catches

| Clone type | Example | Caught |
|---|---|---|
| Type-1 (exact) | verbatim copy-paste | ✅ |
| Type-2 (renamed) | same code, `total` → `sum`, `42` → `99` | ✅ (default) |
| Type-3 (statements added/removed) | a copy with an extra `guard` | ❌ — see *Limitations* |
| Type-4 (same behavior, different impl) | line-diff vs char-diff sharing one algorithm | ❌ — needs a reading pass |

## How it works

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

## Usage

```sh
cd Tools/SwiftCloneDetector
swift run swift-clone-detector --type2 --min-mass 25 ../../Sources
```

Exit code is `2` when clones are found (handy for CI gating), `0` when clean.

## Limitations (by design)

- **Type-3/Type-4 are out of scope.** An inserted statement changes the
  enclosing subtree's hash, so near-misses are missed. Catching them needs a
  fuzzier engine (characteristic-vector clustering, à la Deckard).
- **Identifier renaming is "blind"** — all identifiers map to one placeholder
  rather than enforcing a consistent 1:1 mapping, which can slightly over-match.
- **Sequence clones** (a duplicated *run* of sibling statements that isn't a
  single subtree) aren't detected yet; that needs a sliding window over
  `CodeBlockItemList`.
