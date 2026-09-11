#!/usr/bin/env bash
#
# check-reproducibility.sh
# SwiftCloneDetector
#
# Assert that repeated runs over identical input produce identical output.
#
# This is the one property the unit tests cannot cover. The detector's sums and
# orderings are derived from dictionaries, and Swift reseeds dictionary hashing
# once per process -- so a hash-order dependency is invisible within a single test
# run and only appears when the binary is invoked again. Both reproducibility
# bugs this repo has had (arbitrary clone ordering, then similarity values
# drifting by a few ULP) were of exactly that shape.
#
# Usage:  Scripts/check-reproducibility.sh [target-path]
#         RUNS=20 Scripts/check-reproducibility.sh Sources
#

set -euo pipefail

RUNS="${RUNS:-10}"
TARGET="${1:-Sources}"

if [ ! -e "$TARGET" ]; then
    echo "error: no such target: $TARGET" >&2
    exit 1
fi

echo "Building release binary..."
swift build -c release > /dev/null
BIN="$(swift build -c release --show-bin-path)/swift-clone-detector"

if [ ! -x "$BIN" ]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Running $RUNS times over $TARGET..."
for i in $(seq 1 "$RUNS"); do
    # The detector exits 2 when it finds clones, which is the expected outcome
    # here -- only a code outside {0, 2} is a real failure.
    status=0
    "$BIN" "$TARGET" --all --format json > "$WORK/run$i.json" || status=$?
    if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
        echo "error: run $i exited with code $status" >&2
        exit 1
    fi
done

# A run that finds nothing would compare equal to every other run that finds
# nothing, and the check would pass while testing precisely nothing. Require
# real findings so the comparison has something to be about.
clones="$(sed -n 's/.*"cloneCount"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$WORK/run1.json" | head -1)"
if [ -z "$clones" ] || [ "$clones" -eq 0 ]; then
    echo "error: $TARGET yielded no clones, so this check would pass vacuously" >&2
    exit 1
fi

distinct="$(shasum -a 256 "$WORK"/run*.json | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"

if [ "$distinct" -ne 1 ]; then
    echo "" >&2
    echo "NOT REPRODUCIBLE: $RUNS runs produced $distinct different outputs." >&2
    echo "" >&2
    echo "A dictionary is being iterated somewhere its order reaches the output --" >&2
    echo "either a floating-point sum accumulating in hash order, or a report" >&2
    echo "ordering that is not total. First difference:" >&2
    echo "" >&2
    for i in $(seq 2 "$RUNS"); do
        if ! cmp -s "$WORK/run1.json" "$WORK/run$i.json"; then
            diff <(tr ',' '\n' < "$WORK/run1.json") \
                 <(tr ',' '\n' < "$WORK/run$i.json") | head -20 >&2 || true
            break
        fi
    done
    exit 1
fi

echo "Reproducible: $RUNS runs over $clones clone classes produced identical output."
