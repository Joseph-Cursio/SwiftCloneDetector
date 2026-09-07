# Labelled cases

Clone findings **read by hand and judged**, so a scoring change can be checked
against a verdict rather than against a count.

Counts cannot say whether a detector got better. Every change in this repository
has moved the count in whichever direction removing large false positives
happens to move it — usually *up*, because a bogus class claims the ranges
beneath it. Eighteen cases with a verdict attached say something a count cannot.

## Reproducing

The line numbers are only valid at these commits:

| name | repository | commit |
|---|---|---|
| `slrst` | SwiftLintRuleStudioTeam | `08af925` |
| `assist` | SwiftAssist | `f274ff1` |
| `projectlint` | SwiftProjectLint | `b6131cb` |
| `alamofire` | [Alamofire](https://github.com/Alamofire/Alamofire) | `903c53c7` |
| `icecubes` | [IceCubesApp](https://github.com/Dimillian/IceCubesApp) | `0fc41d2c` |
| `moya` | [Moya](https://github.com/Moya/Moya) | `24c26671` |
| `nimble` | [Nimble](https://github.com/Quick/Nimble) | `035b88a` |
| `grdb` | [GRDB.swift](https://github.com/groue/GRDB.swift) | `b83108d10` |
| `euclid` | [Euclid](https://github.com/nicklockwood/Euclid) | `0b00927` |
| `kingfisher` | [Kingfisher](https://github.com/onevcat/Kingfisher) | `db0ea414` |

Check each out into one directory, named as above, then:

```sh
swift build -c release
./Evaluation/evaluate.py ~/eval                      # --type3, the default scoring
./Evaluation/evaluate.py ~/eval --mode sequence
./Evaluation/evaluate.py ~/eval --mode any           # union of type2 + type3 + sequence
./Evaluation/evaluate.py ~/eval -- --uniform-weighting
./Evaluation/evaluate.py ~/eval --cpd --min-tokens 40  # PMD CPD, for comparison
```

## How a case is matched

A reported instance stands for a case's fragment when their line ranges agree by
**intersection over union ≥ 0.5**. Exact equality would score CPD unfairly, since
it reports the matched token run rather than the enclosing declaration. A
one-sided coverage test is wrong in both directions, and both errors happened
while this harness was written: a small class sitting *inside* a large fragment
counted as having found it, and so did a 274-line class that merely swallowed a
37-line one. Each inflated a score before it was caught.

## What the set is, and is not

Cases come from three places, recorded per case in `found_by` and by which
repository they name. Eighteen are from repositories the author owns; fourteen
are from widely-used third-party libraries, so the set is not only one person's
style. Two were sampled from **PMD CPD's** output rather than this tool's.

**Seven of the third-party cases — Nimble, GRDB, Euclid, Kingfisher — were added
after `--min-distinctiveness` had been tuned, and are the only honest check on
it.** They caught the first choice of default: 1.4 scored 3/7 on them, exactly
what the floor being switched off scores. It had fitted the cases it was chosen
from and generalised nothing. 1.55 scores 6/7. Keep held-out cases when tuning
anything here; the aggregate will not tell you.

A set drawn only from one tool's output cannot measure that tool's recall — a
clone it never reports is structurally absent from the set. The two CPD-sourced
cases were added for exactly that reason, and **both are missed by `--type3` and
`--type2`**, which is a gap no amount of sampling from this tool's own output
would ever have shown.

The set is small, and the false cases outnumber what any one run would show a
reader. It is evidence, not a benchmark. There is no Swift clone-detection
benchmark to use instead: BigCloneBench, SemanticCloneBench and GPTCloneBench are
Java/C/C#/Python, and PMD ships a Swift *tokenizer* test fixture, not labelled
duplication.
