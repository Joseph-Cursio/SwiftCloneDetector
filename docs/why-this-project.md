# Why this project exists: the gap between a token tool and a reading pass

Duplication detection has two established approaches, and each leaves a hole the
other fills. **Token-based tools** like PMD's CPD are cheap, deterministic, and
run in CI — but they only see verbatim copy-paste. A **reading pass** (a human,
or an LLM reading for meaning) catches the semantic and structural duplication a
token matcher can't model — but it isn't repeatable, gateable, or free.

This project, `swift-clone-detector`, exists to close most of that gap *for
Swift specifically*, where neither approach is well served: PMD has no
first-class Swift tokenizer, and a reading pass doesn't scale to every commit.

## How PMD/CPD works, and why it misses so much

CPD lexes each file into a token stream, optionally normalizes some tokens, then
slides a window looking for runs of **≥ N identical tokens** (default ~50–100).
That design is fast and language-agnostic — and every shortcoming follows from
it:

1. **It only finds contiguous, near-verbatim token runs.** Reorder a few
   statements, insert a guard, thread a parameter differently, and the run
   breaks into sub-threshold fragments that are each reported as *nothing*.
2. **The token threshold hides small-but-real duplication.** A 12-line view
   modifier repeated across two views is often under the floor, so it's never
   surfaced — exactly the boilerplate worth extracting.
3. **Structural clones are invisible.** Clone research grades duplication
   Type-1 (identical) → Type-2 (renamed) → Type-3 (statements added/removed) →
   Type-4 (same behavior, different implementation). CPD handles Type-1, Type-2
   only with normalization flags, and is essentially blind to Type-3/Type-4.
4. **Swift support is weak.** CPD ships tokenizers for a fixed language set;
   Swift isn't first-class, so it runs in a generic/anonymized mode that loses
   the semantic cues (it can't tell a `ViewModifier` from a free function).
5. **It can't reason about intent.** CPD finds text that repeats. It can't see
   "these two protocols encode the same shape" or "this switch is duplicated in
   inverted form."
6. **Cross-cutting duplication slips through.** The same concept smeared one or
   two lines at a time across five files never crosses the threshold.

CPD isn't bad — it's *precise and cheap*, and it rarely cries wolf. Its weakness
is **recall**, not precision.

## What a reading pass adds — and why it isn't enough alone

Reading for meaning catches the cases a token window structurally cannot:

- **Type-3** — copies that drifted by a few statements.
- **Type-4** — same behavior via a different implementation (e.g. a line-diff
  and a character-diff sharing one dynamic-programming core; no shared tokens at
  all).
- **Short, repeated boilerplate** below any sane token floor.
- **Distributed duplication** spread thin across many files.
- **The abstraction itself** — not just "these repeat" but "here's the type or
  function they should collapse into."

But a reading pass has real limits as the *only* mechanism:

- **Not deterministic.** It surfaces different instances run to run; you can't
  put its recall in a pre-commit hook.
- **Not exhaustive at scale.** It samples; it doesn't mechanically visit every
  node in every file.
- **Not free.** It costs minutes and tokens — backwards for the cheap,
  literal-copy-paste category a tool nails instantly.

## Where this project sits

`swift-clone-detector` takes the reading-pass insight (match *structure*, not
*tokens*) and makes it mechanical, deterministic, and CI-gateable — by working
on the **SwiftSyntax AST** instead of a token stream:

- **Type-1/2** — a stable structural hash over `(node.kind, children…)` with
  configurable identifier/literal normalization. Type-2 falls out for free,
  where CPD needs special flags and loses precision.
- **Type-3** — a Deckard-style characteristic vector (node-kind counts) clustered
  by similarity, so a small insertion only nudges the fingerprint instead of
  breaking an exact match.

It deliberately stops at **Type-4**, which has no structural overlap to match.
That stays a reading-pass job — and that's the honest boundary of any structural
tool.

## The division of labor

| | CPD (tokens) | `swift-clone-detector` (AST) | Reading pass |
|---|---|---|---|
| Type-1 / Type-2 | partial | ✅ cheap, complete, gateable | wasteful |
| Type-3 (drifted copies) | ❌ | ✅ (`--type3`) | ✅ |
| Type-4 (same behavior) | ❌ | ❌ | ✅ |
| Short / cross-cutting | ❌ | ✅ (tunable floor) | ✅ |
| Runs in CI every commit | ✅ | ✅ | ❌ |
| Explains *why* + proposes the fix | ❌ | ❌ | ✅ |

The tool owns the floor — keep the cheap, mechanical duplication from ever
reaching a human. The reading pass owns the ceiling — the semantic refactors a
tool can't model. This project widens what the *tool* column can claim on Swift,
so the reading pass is reserved for the cases that genuinely need judgment.

## Grounded in this codebase

Run against the LintStudioUI sources, the tool surfaced duplication that fits
each tier — including cases a token detector would miss:

- **Type-2** — `GitServiceActor.listBranches` / `listTags`: byte-identical
  bodies except the git arguments. The only differing tokens are literals, and
  the spans are short enough to slip under CPD's default floor.
- **Type-2** — `DiffLine.backgroundColor` / `highlightColor`: identical `switch`
  except one constant (`backgroundOpacity` vs `highlightOpacity`).
- **Type-3** — `LintRule` / `LintViolation`: two protocols with the same
  `associatedtype` constraint plus a run of `var … { get }` requirements,
  differing in property count and types (93% similar). No exact matcher can
  connect them; the characteristic vector does.
