# swift-clone-detector vs PMD CPD

A head-to-head on real Swift code, comparing this detector against the tool the
README contrasts it with: PMD's Copy/Paste Detector (CPD), a mature token-based
duplication finder.

Three case studies, each on the pre-refactor state of a repo that was recently
de-duplicated by hand — so the duplication is still present and the findings can
be checked against the cleanup commits that followed.

## Case study 1 — SwiftAssist

### Setup

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

### Results

| | PMD CPD | `--type1` (verbatim) | `--type2` (default) |
|---|--:|--:|--:|
| Duplications found | **10** | 11 | **64** |
| Files skipped / unparsed | **13** | 0 | 0 |

PMD's 10 blocks exactly matches the "CPD blocks 10" recorded in SwiftAssist's
refactor commit, confirming this reproduces the original PMD run.

### Findings

#### 1. At the verbatim level, the two tools agree

PMD's 10 blocks ≈ the detector's 11 `--type1` classes, over the same file pairs:
the Kuzu/SCIP/SourceKit tool dispatchers, the CI/Git/Coverage/swift-format/
SwiftLint process runners, `ThinkingAnalyzer` ↔ `ThinkingRecipeExtractor`, and so
on. Two independent tools converging on the same copy-paste is good
cross-validation that both are working.

#### 2. The detector's edge is renamed clones

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

#### 3. PMD's Swift lexer is unreliable

PMD **silently skipped 13 of the 358 files** (3.6%). Its Swift tokenizer errors
on valid modern Swift it can't lex — backtick-escaped operators like `` `<` ``,
em-dashes (`—`) inside string literals and comments — and drops the *entire file*
on the first such token. Any duplication in a skipped file is invisible to it.

This detector parses with SwiftSyntax (the real Swift parser), so it read all 358
files. One skipped file, `ExecTools.swift`, contained a real ~14-line duplication
(lines 46–59 ↔ 108–121, 106 AST nodes) that PMD was blind to purely because it
couldn't tokenize the file. That is exactly the gap the README describes.

### Practical takeaway

SwiftAssist's refactor commit folded together "PMD CPD (verbatim copy-paste)
**and** structural-pattern duplication finds" — two separate methods run to get
full coverage. This detector's single `--type2` pass spans both categories (its
64 classes are a superset of the 10 verbatim blocks) over every file, including
the ones PMD can't parse.

## Case study 2 — SwiftLintRuleStudio

### Setup

- **Target:** SwiftLintRuleStudio at commit `a511208` ("Add CPD copy-paste
  detection script") — the state when the CPD tripwire was first added, before
  the cleanup commits that followed.
- **Scope + config:** the repo's own `scripts/cpd.sh` settings —
  `--minimum-tokens 100 --skip-lexical-errors`, over `UI App
  SwiftLintRuleStudioCore/Sources` (172 production files).
- **Calibration:** here min-tokens 100 lines up with `--min-mass 160` (not 120
  as for SwiftAssist — see the caveats).

### Results (at the calibrated min-mass 160)

| | PMD CPD | `--type1` (verbatim) | `--type2` (default) |
|---|--:|--:|--:|
| Duplications found | **5** | 5 | **10** |
| Files skipped / unparsed | **2** | 0 | 0 |

PMD's "2 files skipped" matches the note in the repo's own `cpd.sh`.

### Findings

The same shape as case 1, on a smaller, cleaner codebase:

- **Verbatim agreement.** PMD 5 = detector `--type1` 5 — both flag the
  config-view boilerplate (`ConfigImportView` ↔ `VersionCompatibilityView` /
  `GitBranchDiffView` / `MigrationAssistantView`) and the
  `RuleDetailView+MarkdownHelpers` ↔ `RuleBrowserView+DocumentationHelpers` dup.
  These map straight to the cleanup commits `1bec6a0` ("Remove dead
  markdown-to-plain-text duplicate") and `195c8d3` (shared SQLite ID-binding).
- **The renamed edge.** `--type2` = 10 → +5 renamed clones. Example:
  `MigrationAssistantView:162-187` ↔ `ConfigImportView:187-212` — a 26-line
  structurally identical block with renamed bindings, exactly the duplication
  folded together in `d1eb8f1` ("Extract shared config-view components"). CPD
  can't see it.
- **Blind spots.** PMD skipped 2 files (the backtick-token issue its own script
  comment notes), but neither contained detected duplication here — no
  blind-spot cost this time, unlike SwiftAssist's `ExecTools.swift`.

## Case study 3 — SwiftProjectLint

### Setup

- **Target:** SwiftProjectLint at commit `8501ab3` — the parent of the `ab75882`
  visitor-extraction batch (Jun 8: "Extract CrossFileVisitorBase; migrate 15
  cross-file visitors", `TestMissingMacroVisitorBase`, `SuppressionVisitorBase`,
  `MainActorMissingVisitorBase`, …). All that duplicated visitor boilerplate is
  still present at this state.
- **Scope:** the first-party production sources — `Sources/App`, `Sources/Core`,
  and seven `Packages/*/Sources/*` directories (the bulk being 249 lint-rule
  files under `SwiftProjectLintRules`). 357 Swift files.
- **Tools:** PMD CPD 7.25.0 (`--minimum-tokens 100`) vs swift-clone-detector,
  calibrated to `--min-mass 116` (where `--type1` exactly hits PMD's count).

### Results (at the calibrated min-mass 116)

| | PMD CPD | `--type1` (verbatim) | `--type2` (default) |
|---|--:|--:|--:|
| Duplications found | **22** | 22 | **72** |
| Files skipped / unparsed | **0** | 0 | 0 |

### Findings

The same shape as cases 1–2, with the sharpest numbers of the three:

- **Verbatim agreement is exact.** PMD 22 = detector `--type1` 22, over the same
  fragments — and they map straight onto the extraction commits: the
  `TestMissingAssertion` ↔ `TestMissingExpect` ↔ `TestMissingRequire` visitor trio
  (~lines 119–147, folded into `TestMissingMacroVisitorBase`, commit `83cb749`)
  and the `SingletonUsage` ↔ `AccessingImplementationDetails` ↔
  `DirectInstantiation` cross-file visitors (→ `CrossFileVisitorBase`, `6f322a3`).
- **The renamed edge is the largest of the three runs: +50** (`--type2` = 72).
  Concrete example — the `PatternRegistrarProtocol` boilerplate, the same struct
  shape differing only by rule name, visitor type, severity, category and prose:

  ```swift
  // IdempotencyViolation.swift                 // ControlMissingAccessibilityLabel.swift
  struct IdempotencyViolation: …Protocol {      struct ControlMissingAccessibilityLabel: …Protocol {
    var pattern: SyntaxPattern {                  var pattern: SyntaxPattern {
      SyntaxPattern(name: .idempotencyViolation,    SyntaxPattern(name: .controlMissing…,
        visitor: IdempotencyViolationVisitor.self,    visitor: ControlMissing…Visitor.self,
        severity: .error, category: .idempotency,     severity: .warning, category: .accessibility,
        messageTemplate: …, suggestion: …, …)         messageTemplate: …, suggestion: …, …) } }
  ```

  Token-based CPD sees two different token streams; the detector matches them
  under Type-2.
- **Zero lexer blind spots.** PMD skipped **0 of 357** files — no backtick-escaped
  operators or em-dashes to choke on (cleaner than SwiftAssist's 13 skips). The
  reliability gap didn't bite here; the structural-duplication gap did, hard.

## Caveats (read honestly)

- **Thresholds aren't equivalent, and the mapping is per-repo.** Tokens (CPD) vs
  AST-node mass (this tool) were calibrated to align the *verbatim* counts, not
  to claim a raw multiplier. The mapping even differs between codebases —
  min-tokens 100 ≈ min-mass 120 for SwiftAssist, 116 for SwiftProjectLint, and
  160 for SwiftLintRuleStudio, because SwiftUI view code has a different
  token-to-node density than actor/CLI or SwiftSyntax-visitor code. Recalibrate
  per project.
- **The two tools weight "size" differently.** Token count and AST-node mass rank
  individual blocks differently even when overall counts align. In case 2, PMD
  flagged the `ViolationStorageActor` self-duplication (a run of repetitive
  SQLite `bind` calls — token-dense but node-sparse) at this threshold, while the
  detector needs a lower `--min-mass` to surface it. Neither metric is strictly
  more correct; they emphasize different things.
- **Not every renamed clone is worth refactoring.** Type-2 surfaces real
  structural duplication, but whether each instance should be extracted is a
  judgment call. They are, however, duplications CPD definitionally cannot show
  you.
- **The lexer blind-spot cost varied by repo** — one missed duplication in
  SwiftAssist (13 files skipped), none in SwiftLintRuleStudio (2 skipped) or
  SwiftProjectLint (0 skipped) — but the reliability gap (dropping whole files)
  is real and would bite harder on code that leans on the syntax PMD chokes on.

## Reproduce

```sh
# Case 1 — SwiftAssist (before-state worktree)
git -C SwiftAssist worktree add --detach /tmp/before f870e76

# PMD (Homebrew: brew install pmd)
pmd cpd --dir /tmp/before/Sources --language swift --minimum-tokens 100 --format text

# this detector
swift run swift-clone-detector --type1 --min-mass 120 /tmp/before/Sources   # verbatim
swift run swift-clone-detector            --min-mass 120 /tmp/before/Sources   # + renamed (Type-2)

# Case 2 — SwiftLintRuleStudio (uses the repo's own scripts/cpd.sh config)
git -C SwiftLintRuleStudio worktree add --detach /tmp/slrs a511208
cd /tmp/slrs
pmd cpd --minimum-tokens 100 --language swift --skip-lexical-errors \
  --dir UI --dir App --dir SwiftLintRuleStudioCore/Sources --format text
swift-clone-detector --type1 --min-mass 160 UI App SwiftLintRuleStudioCore/Sources  # verbatim
swift-clone-detector            --min-mass 160 UI App SwiftLintRuleStudioCore/Sources  # + renamed

# Case 3 — SwiftProjectLint (multi-package; scan the production source dirs)
git -C SwiftProjectLint worktree add --detach /tmp/spl ab75882~1
cd /tmp/spl
DIRS="Sources/App Sources/Core $(ls -d Packages/*/Sources/*)"
pmd cpd --minimum-tokens 100 --language swift --no-fail-on-error \
  $(for d in $DIRS; do printf -- '--dir %s ' "$d"; done) --format text
swift-clone-detector --type1 --min-mass 116 $DIRS   # verbatim
swift-clone-detector            --min-mass 116 $DIRS   # + renamed
```
