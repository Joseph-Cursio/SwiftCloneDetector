//
//  FNV64.swift
//  SwiftCloneDetectorKit
//
//  A stable 64-bit FNV-1a hash. Unlike Swift's `Hasher`, the output is
//  deterministic across processes — essential for a tool whose results must
//  be reproducible from one CI run to the next.
//

struct FNV64 {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3
    /// Bytes in a `UInt64` — the number of low-byte rounds when folding one in.
    private static let byteCount = 8
    private static let bitsPerByte = 8
    private static let lowByteMask: UInt64 = 0xff

    private(set) var value = Self.offsetBasis

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value = (value ^ UInt64(byte)) &* Self.prime
        }
    }

    mutating func combine(_ other: UInt64) {
        var bits = other
        for _ in 0..<Self.byteCount {
            value = (value ^ (bits & Self.lowByteMask)) &* Self.prime
            bits >>= Self.bitsPerByte
        }
    }
}
