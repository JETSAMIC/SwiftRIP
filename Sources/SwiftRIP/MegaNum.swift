// MegaNum — RIPscrip's base-36 ("Hexa-Tri-Decimal") unsigned-integer encoding.
//
// RIPscrip numeric arguments are fixed-width unsigned integers in base 36,
// using the digits 0..9 and A..Z, most-significant digit first. The width of
// each argument is fixed by the command grammar (`:1`, `:2`, `:4`, ... in the
// 1.54 specification). Input is case-insensitive; output is uppercase.

import Foundation

/// Base-36 encoder/decoder for RIPscrip "MegaNum" arguments.
///
/// A MegaNum of width *w* holds values in `0 ..< 36^w`; for example a
/// two-digit MegaNum (the width of every RIPscrip 1.54 coordinate) holds
/// `0...1295`.
public enum MegaNum {

    /// Errors produced by the MegaNum decoder and encoder.
    public enum DecodeError: Error, Equatable, Sendable {
        /// The provided substring was not the exact expected width.
        case widthMismatch(expected: Int, got: Int)
        /// A character outside the `0-9` / `A-Z` / `a-z` digit set was found.
        case invalidDigit(Character)
        /// The decoded value does not fit in `Int`.
        case overflow
        /// The value is negative or needs more than `width` digits.
        case valueOutOfRange(value: Int, width: Int)
    }

    /// The largest value representable in `width` MegaNum digits, or `nil`
    /// if `width` is not positive or `36^width - 1` would overflow `Int`.
    ///
    /// - Parameter width: Number of base-36 digits (1...12 on 64-bit).
    /// - Returns: `36^width - 1`, e.g. `1295` for `width == 2`.
    public static func maxValue(width: Int) -> Int? {
        guard width > 0 else { return nil }
        var result = 1
        for _ in 0..<width {
            let (next, overflow) = result.multipliedReportingOverflow(by: 36)
            if overflow { return nil }
            result = next
        }
        return result - 1
    }

    /// Decode a fixed-width MegaNum substring (case-insensitive).
    ///
    /// - Parameters:
    ///   - chars: Exactly `width` digits from `0-9` / `A-Z` (either case).
    ///   - width: Expected width in digits.
    /// - Returns: The integer value of `chars`.
    /// - Throws: ``DecodeError/widthMismatch(expected:got:)`` if the length
    ///   differs from `width`, ``DecodeError/invalidDigit(_:)`` for a
    ///   non-MegaNum character and ``DecodeError/overflow`` if the value does
    ///   not fit in `Int`.
    public static func decode(_ chars: Substring, width: Int) throws -> Int {
        if chars.count != width {
            throw DecodeError.widthMismatch(expected: width, got: chars.count)
        }
        var value = 0
        for ch in chars {
            guard let digit = digitValue(ch) else {
                throw DecodeError.invalidDigit(ch)
            }
            let (m, o1) = value.multipliedReportingOverflow(by: 36)
            let (a, o2) = m.addingReportingOverflow(digit)
            if o1 || o2 { throw DecodeError.overflow }
            value = a
        }
        return value
    }

    /// Decode a MegaNum of any width.
    ///
    /// - Parameter chars: One or more MegaNum digits (case-insensitive).
    /// - Returns: The decoded value, or `nil` if `chars` is empty, contains a
    ///   non-MegaNum character, or the value does not fit in `Int`.
    public static func decode(_ chars: Substring) -> Int? {
        if chars.isEmpty { return nil }
        return try? decode(chars, width: chars.count)
    }

    /// Encode a non-negative value as an uppercase, left-zero-padded MegaNum
    /// of exactly `width` digits.
    ///
    /// - Parameters:
    ///   - value: The value to encode; must be in `0...maxValue(width:)`.
    ///   - width: Number of digits to emit (at least 1).
    /// - Returns: A string of exactly `width` characters.
    /// - Throws: ``DecodeError/valueOutOfRange(value:width:)`` if `value` is
    ///   negative or needs more than `width` digits.
    public static func encode(_ value: Int, width: Int) throws -> String {
        guard width > 0, value >= 0 else {
            throw DecodeError.valueOutOfRange(value: value, width: width)
        }
        if let maximum = maxValue(width: width), value > maximum {
            throw DecodeError.valueOutOfRange(value: value, width: width)
        }
        var digits: [Character] = []
        digits.reserveCapacity(width)
        var v = value
        while v > 0 {
            digits.append(digitCharacter(v % 36))
            v /= 36
        }
        while digits.count < width {
            digits.append("0")
        }
        return String(digits.reversed())
    }

    // MARK: - Internal helpers

    /// Value of one MegaNum digit, or `nil` for a non-digit.
    static func digitValue(_ ch: Character) -> Int? {
        guard let ascii = ch.asciiValue else { return nil }
        return digitValue(ascii: ascii)
    }

    /// Value of one MegaNum digit given its ASCII code, or `nil`.
    static func digitValue(ascii: UInt8) -> Int? {
        switch ascii {
        case 0x30...0x39: return Int(ascii - 0x30)        // 0-9
        case 0x41...0x5A: return Int(ascii - 0x41) + 10   // A-Z
        case 0x61...0x7A: return Int(ascii - 0x61) + 10   // a-z
        default: return nil
        }
    }

    /// Uppercase digit character for `value` in `0..<36`.
    static func digitCharacter(_ value: Int) -> Character {
        digitTable[value]
    }

    private static let digitTable: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
}
