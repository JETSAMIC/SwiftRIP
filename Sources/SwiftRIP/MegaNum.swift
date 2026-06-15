// MegaNum — RIPscrip's base-36 (hexa-tri-decimal) unsigned-integer encoding.
//
// RIPscrip numeric arguments are encoded as fixed-width unsigned integers in
// base 36, using the digits 0..9 and A..Z (most-significant digit first). The
// width of each argument is specified by the command grammar — see the
// reference document in /Reference. The encoding is case-insensitive on input
// and uppercase on output; padding is always to the spec-defined width.

import Foundation

/// Base-36 encoder/decoder for RIPscrip MegaNum arguments.
public enum MegaNum {

    /// Errors produced by the strict (width-checked) decoder.
    public enum DecodeError: Error, Equatable, Sendable {
        /// The provided substring was not the exact expected width.
        case widthMismatch(expected: Int, got: Int)
        /// A character outside the 0..9 / A..Z digit set was encountered.
        case invalidDigit(Character)
    }

    /// Decode a fixed-width MegaNum substring (case-insensitive).
    ///
    /// - Parameters:
    ///   - chars: substring of exactly `width` digits in `0..9` / `A..Z`.
    ///   - width: expected width in digits.
    /// - Returns: integer value of the substring.
    /// - Throws: `DecodeError.widthMismatch` or `.invalidDigit`.
    public static func decode(_ chars: Substring, width: Int) throws -> Int {
        if chars.count != width {
            throw DecodeError.widthMismatch(expected: width, got: chars.count)
        }
        var value = 0
        for ch in chars {
            guard let digit = digitValue(ch) else {
                throw DecodeError.invalidDigit(ch)
            }
            value = value * 36 + digit
        }
        return value
    }

    /// Variable-width tolerant decode used for the trailing part of a logical
    /// command line (e.g. inside macro IDs that the grammar treats as
    /// "consume until non-digit"). Returns `nil` on any invalid digit or empty
    /// input.
    public static func decode(_ chars: Substring) -> Int? {
        if chars.isEmpty { return nil }
        var value = 0
        for ch in chars {
            guard let digit = digitValue(ch) else { return nil }
            value = value * 36 + digit
        }
        return value
    }

    /// Encode an unsigned value to a left-zero-padded base-36 string of the
    /// requested width. The returned string is always uppercase. Values that
    /// do not fit in `width` digits are encoded at their natural width — the
    /// caller is responsible for catching overflow before encoding. This
    /// mirrors the spec's "overflow is undefined" wording (the writer is
    /// expected to validate prior to emitting).
    public static func encode(_ value: Int, width: Int) -> String {
        precondition(value >= 0, "MegaNum cannot encode negative values")
        if value == 0 {
            return String(repeating: "0", count: max(width, 1))
        }
        var digits: [Character] = []
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

    @inlinable
    static func digitValue(_ ch: Character) -> Int? {
        guard let ascii = ch.asciiValue else { return nil }
        switch ascii {
        case 0x30...0x39: // 0-9
            return Int(ascii - 0x30)
        case 0x41...0x5A: // A-Z
            return Int(ascii - 0x41) + 10
        case 0x61...0x7A: // a-z (case-insensitive on input)
            return Int(ascii - 0x61) + 10
        default:
            return nil
        }
    }

    @inlinable
    static func digitCharacter(_ value: Int) -> Character {
        precondition(value >= 0 && value < 36, "MegaNum digit out of range")
        if value < 10 {
            return Character(UnicodeScalar(0x30 + value)!)
        }
        return Character(UnicodeScalar(0x41 + value - 10)!)
    }
}
