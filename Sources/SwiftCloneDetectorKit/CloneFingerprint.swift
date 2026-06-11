//
//  CloneFingerprint.swift
//  SwiftCloneDetectorKit
//
//  A stable, process-independent identity for a clone class, plus the partition
//  that drives the baseline "fail only on new clones" gate. The fingerprint
//  folds the clone's shape (mass, instance count, file set) — not its absolute
//  line positions — so a clone moving up or down within a file keeps the same
//  identity, while a materially changed clone (different size or files) is
//  surfaced as new.
//

/// A stable, process-independent identity for a clone class.
///
/// Built from the clone's mass, instance count, the sorted set of file paths it
/// touches and — for near-miss classes — its similarity bucket. Deliberately
/// *excludes* absolute line numbers so the identity survives the clone drifting
/// up or down its files as surrounding code changes.
public func cloneFingerprint(for cloneClass: CloneClass) -> String {
    var hash = FNV64()
    hash.combine(UInt64(cloneClass.mass))
    hash.combine(UInt64(cloneClass.instances.count))
    if let similarity = cloneClass.similarity {
        // Bucket to whole percent so trivial float drift doesn't shift identity.
        let percentScale = 100.0
        hash.combine(UInt64(max(0, (similarity * percentScale).rounded())))
    }
    for path in cloneClass.instances.map(\.path).sorted() {
        hash.combine(path)
    }
    return hexString(hash.value)
}

/// Split a freshly detected set of clone classes into those already recorded in
/// a baseline and those that are new — the only ones a baseline-gated run should
/// fail on.
public func partitionClasses(
    _ classes: [CloneClass],
    baseline fingerprints: Set<String>
) -> (new: [CloneClass], known: [CloneClass]) {
    var newClasses: [CloneClass] = []
    var knownClasses: [CloneClass] = []
    for cloneClass in classes {
        if fingerprints.contains(cloneFingerprint(for: cloneClass)) {
            knownClasses.append(cloneClass)
        } else {
            newClasses.append(cloneClass)
        }
    }
    return (newClasses, knownClasses)
}

/// Lower-case, zero-padded 16-digit hex for a `UInt64` — no Foundation needed.
private func hexString(_ value: UInt64) -> String {
    let digits = Array("0123456789abcdef")
    let bitsPerNibble = 4
    let nibbleMask: UInt64 = 0xf
    var result = ""
    var shift = UInt64.bitWidth - bitsPerNibble
    while shift >= 0 {
        let nibble = Int((value >> UInt64(shift)) & nibbleMask)
        result.append(digits[nibble])
        shift -= bitsPerNibble
    }
    return result
}
