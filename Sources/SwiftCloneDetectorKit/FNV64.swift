//
//  FNV64.swift
//  SwiftCloneDetectorKit
//
//  A stable 64-bit FNV-1a hash. Unlike Swift's `Hasher`, the output is
//  deterministic across processes — essential for a tool whose results must
//  be reproducible from one CI run to the next.
//

struct FNV64 {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value = (value ^ UInt64(byte)) &* Self.prime
        }
    }

    mutating func combine(_ other: UInt64) {
        var bits = other
        for _ in 0..<8 {
            value = (value ^ (bits & 0xff)) &* Self.prime
            bits >>= 8
        }
    }
}
