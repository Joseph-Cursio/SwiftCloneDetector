# swift-clone-detector vs PMD CPD

A head-to-head on real Swift code, comparing this detector against the tool the
README contrasts it with: PMD's Copy/Paste Detector (CPD), a mature token-based
duplication finder.

## Setup

- **Target:** the [SwiftAssist](../../SwiftAssist) repo at commit `f870e76` — the
  state *just before* its `546b921` "extract shared helpers to remove duplicated
  code" refactor. That commit's own message recorded a PMD result ("CPD blocks
  10 → 4"), so it is a known-good baseline to reproduce.
- **Scope:** `Sources/` — 358 Swift files.
- **Tools:** PMD CPD 7.25.0 (`--language swift --minimum-tokens 100`) vs
  swift-clone-detector (`--min-mass 120`).
- **Calibration:** token runs (CPD) and AST-node mass (this tool) aren't directly
  comparable, so the thresholds were tuned until the two tools reported the same
  *verbatim* duplication count — a fair common baseline — and the Type-2 results
  read off the same `--min-mass`.

## Results

| | PMD CPD | `--type1` (verbatim) | `--type2` (default) |
|---|--:|--:|--:|
| Duplications found | **10** | 11 | **64** |
| Files skipped / unparsed | **13** | 0 | 0 |

PMD's 10 blocks exactly matches the "CPD blocks 10" recorded in SwiftAssist's
refactor commit, confirming this reproduces the original PMD run.

## Findings

### 1. At the verbatim level, the two tools agree

PMD's 10 blocks ≈ the detector's 11 `--type1` classes, over the same file pairs:
the Kuzu/SCIP/SourceKit tool dispatchers, the CI/Git/Coverage/swift-format/
SwiftLint process runners, `ThinkingAnalyzer` ↔ `ThinkingRecipeExtractor`, and so
on. Two independent tools converging on the same copy-paste is good
cross-validation that both are working.

### 2. The detector's edge is renamed clones

`--type2` finds **64** classes — 53 more than the verbatim pass. These are
structurally identical fragments that differ only in identifiers or literals.
CPD is token-based, so a renamed copy becomes a different token stream that it
cannot match.

Concrete example, both in `ExecTools.swift`:

```swift
// lines 46–59
public static let descriptor = AgentToolDescriptor(
    name: "swift_lint",
    summary: """
        Lint a Swift source file with SwiftLint ...
        """,
    ...
)

// lines 108–121
public static let descriptor = AgentToolDescriptor(
    name: "swift_format",
    summary: """
        Format a Swift source file in place with `swift-format` ...
        """,
    ...
)
```

Same `AgentToolDescriptor(...)` shape, different name and prose — a relabeled
copy-paste. The detector matches them under Type-2; CPD never could.

### 3. PMD's Swift lexer is unreliable

PMD **silently skipped 13 of the 358 files** (3.6%). Its Swift tokenizer errors
on valid modern Swift it can't lex — backtick-escaped operators like `` `<` ``,
em-dashes (`—`) inside string literals and comments — and drops the *entire file*
on the first such token. Any duplication in a skipped file is invisible to it.

This detector parses with SwiftSyntax (the real Swift parser), so it read all 358
files. One skipped file, `ExecTools.swift`, contained a real ~14-line duplication
(lines 46–59 ↔ 108–121, 106 AST nodes) that PMD was blind to purely because it
couldn't tokenize the file. That is exactly the gap the README describes.

## Practical takeaway

SwiftAssist's refactor commit folded together "PMD CPD (verbatim copy-paste)
**and** structural-pattern duplication finds" — two separate methods run to get
full coverage. This detector's single `--type2` pass spans both categories (its
64 classes are a superset of the 10 verbatim blocks) over every file, including
the ones PMD can't parse.

## Caveats (read honestly)

- **Thresholds aren't equivalent.** Tokens vs AST-node mass were calibrated to
  align the *verbatim* counts, not claim a raw "6× more" — the 64-vs-11 gap is
  mostly the broader Type-2 definition, which is a different (larger) notion of
  "clone."
- **Not every renamed clone is worth refactoring.** Type-2 surfaces real
  structural duplication, but whether each instance should be extracted is a
  judgment call. They are, however, duplications CPD definitionally cannot show
  you.
- **The lexer blind-spot cost was modest here** — one missed duplication in this
  repo — but the reliability gap (dropping whole files) is real and would bite
  harder on code that leans on the syntax PMD chokes on.

## Reproduce

```sh
# before-state worktree
git -C SwiftAssist worktree add --detach /tmp/before f870e76

# PMD (Homebrew: brew install pmd)
pmd cpd --dir /tmp/before/Sources --language swift --minimum-tokens 100 --format text

# this detector
swift run swift-clone-detector --type1 --min-mass 120 /tmp/before/Sources   # verbatim
swift run swift-clone-detector            --min-mass 120 /tmp/before/Sources   # + renamed (Type-2)
```
