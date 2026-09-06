#!/usr/bin/env python3
"""Score a clone detector against findings that were read by hand and judged.

    ./Evaluation/evaluate.py <checkouts-dir> [--binary PATH] [--cpd] [-- <flags>]

`<checkouts-dir>` holds one directory per repo named in labelled-cases.json,
checked out at the commits README.md pins. Anything after `--` is passed to the
detector, so a scoring change can be compared against the same verdicts:

    ./Evaluation/evaluate.py ~/eval -- --uniform-weighting
"""
import argparse, json, pathlib, subprocess, sys, xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent
CASES = json.loads((HERE / "labelled-cases.json").read_text())["cases"]


def detector_classes(binary, root, mode, flags):
    result = subprocess.run(
        [binary, str(root), f"--{mode}", "--min-mass", "20", "--format", "json", *flags],
        capture_output=True, text=True, check=False)
    data = json.loads(result.stdout or "[]")
    classes = data if isinstance(data, list) else (data.get("cloneClasses") or data.get("clones") or [])
    return [[(pathlib.Path(i["path"]).name, i["startLine"], i["endLine"]) for i in c["instances"]]
            for c in classes]


def cpd_classes(root, tokens):
    """PMD CPD's blocks, in the same shape. CPD is Type-1/2 only; that is the point."""
    result = subprocess.run(
        ["pmd", "cpd", "--dir", str(root), "--language", "swift",
         "--minimum-tokens", str(tokens), "--format", "xml", "--no-fail-on-violation"],
        capture_output=True, text=True, check=False)
    if "<duplication" not in result.stdout:
        return []
    # CPD's report is namespaced, so `iter("duplication")` silently matches
    # nothing and every score comes back as "found none of them".
    def named(node, name):
        return [child for child in node.iter() if child.tag.rsplit("}", 1)[-1] == name]

    out = []
    for dup in named(ET.fromstring(result.stdout), "duplication"):
        out.append([(pathlib.Path(f.get("path")).name,
                     int(f.get("line")),
                     int(f.get("endline", f.get("line"))))
                    for f in named(dup, "file")])
    return out


# A reported instance stands for a case's fragment when their line ranges agree
# this well, measured as intersection over union.
#
# Exact equality would score CPD unfairly — it reports the matched token run, not
# the enclosing declaration. But a one-sided coverage test is wrong in both
# directions: a small class sitting inside a large fragment would count as having
# found it, and so would a 274-line class that merely swallowed a 37-line one.
# Both happened while this harness was being written, and both inflated a score.
# Intersection over union penalises either kind of mismatch.
kMinimumAgreement = 0.5


def overlaps(want, got):
    if want[0] != got[0]:
        return False
    first = max(want[1], got[1])
    last = min(want[2], got[2])
    if last < first:
        return False
    shared = last - first + 1
    union = max(want[2], got[2]) - min(want[1], got[1]) + 1
    return shared / union >= kMinimumAgreement


def reports(classes, instances):
    for members in classes:
        if sum(1 for want in instances if any(overlaps(want, got) for got in members)) >= 2:
            return True
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("checkouts")
    parser.add_argument("--binary", default=".build/release/swift-clone-detector")
    parser.add_argument("--cpd", action="store_true", help="score PMD CPD instead")
    parser.add_argument("--mode", default="type3", choices=["type1", "type2", "type3", "sequence", "any"],
                        help="detector pass to score; 'any' unions all three, which no single run does")
    parser.add_argument("--min-tokens", type=int, default=40)
    args, flags = parser.parse_known_args()
    flags = [f for f in flags if f != "--"]

    checkouts = pathlib.Path(args.checkouts).expanduser()
    repos = sorted({case["repo"] for case in CASES})
    found = {}
    for repo in repos:
        root = checkouts / repo
        if not root.is_dir():
            sys.exit(f"missing checkout: {root}")
        if args.cpd:
            found[repo] = cpd_classes(root, args.min_tokens)
        elif args.mode == "any":
            found[repo] = [c for mode in ("type2", "type3", "sequence")
                           for c in detector_classes(args.binary, root, mode, flags)]
        else:
            found[repo] = detector_classes(args.binary, root, args.mode, flags)

    correct = 0
    print(f"{'case':52}{'verdict':9}{'reported':10}")
    print("-" * 79)
    for case in CASES:
        instances = [tuple(i) for i in case["instances"]]
        hit = reports(found[case["repo"]], instances)
        ok = hit == case["verdict"]
        correct += ok
        print(f"{case['label'][:50]:52}{'TRUE' if case['verdict'] else 'FALSE':9}"
              f"{('yes' if hit else 'no'):10}{'ok' if ok else 'MISS'}")
    print("-" * 79)
    true_cases = [c for c in CASES if c["verdict"]]
    false_cases = [c for c in CASES if not c["verdict"]]
    kept = sum(1 for c in true_cases if reports(found[c["repo"]], [tuple(i) for i in c["instances"]]))
    quiet = sum(1 for c in false_cases if not reports(found[c["repo"]], [tuple(i) for i in c["instances"]]))
    print(f"{correct}/{len(CASES)} correct  "
          f"(recall {kept}/{len(true_cases)} true kept, precision {quiet}/{len(false_cases)} false dropped)")


main()
