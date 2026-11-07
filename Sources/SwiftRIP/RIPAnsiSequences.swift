// RIPAnsiSequences — the RIPscrip 1.54 ANSI auto-sense escape sequences.
//
//   ESC [ !    query the RIPscrip version (reply: RIPSCRIPxxyyvs)
//   ESC [ 0 !  same as ESC [ !
//   ESC [ 1 !  disable RIPscrip processing (RIPscrip lines become raw text)
//   ESC [ 2 !  enable RIPscrip processing
//
// SwiftRIP is a library, not a terminal: it never sends the version reply.
// The parser surfaces each sequence found outside a RIPscrip line as
// `RIPCommand.ansiSense(_:)` and honours disable/enable while tokenizing.

import Foundation

/// One ANSI auto-sense sequence found in a byte stream.
public struct RIPAnsiSenseHit: Equatable, Sendable {
    /// Byte offset of the `ESC` that starts the sequence.
    public let offset: Int
    /// The sequence that was found.
    public let sense: RIPAnsiSense

    /// Create a hit.
    /// - Parameters:
    ///   - offset: Byte offset of the sequence's `ESC`.
    ///   - sense: The sequence.
    public init(offset: Int, sense: RIPAnsiSense) {
        self.offset = offset
        self.sense = sense
    }
}

/// Encoder and scanner for the RIPscrip ANSI auto-sense sequences.
public enum RIPAnsiSequences {

    /// The bytes of an auto-sense sequence.
    /// - Parameter sense: The sequence to encode.
    /// - Returns: `ESC [ !`, `ESC [ 0 !`, `ESC [ 1 !` or `ESC [ 2 !`.
    public static func bytes(for sense: RIPAnsiSense) -> [UInt8] {
        switch sense {
        case .query:          return [0x1B, 0x5B, 0x21]
        case .queryAlternate: return [0x1B, 0x5B, 0x30, 0x21]
        case .disable:        return [0x1B, 0x5B, 0x31, 0x21]
        case .enable:         return [0x1B, 0x5B, 0x32, 0x21]
        }
    }

    /// The reply a RIPscrip 1.54 terminal sends to ``RIPAnsiSense/query``:
    /// `RIPSCRIP` + major (2 digits) + minor (2 digits) + vendor code +
    /// vendor sub-version, e.g. `RIPSCRIP015400` for a generic 1.54 terminal.
    ///
    /// - Parameters:
    ///   - vendor: Vendor code digit (0 = generic, 1 = RIPterm, 2 = Qmodem Pro).
    ///   - subVersion: Vendor sub-version digit.
    /// - Returns: The reply string, or `nil` if either value is not 0...9.
    public static func versionReply(vendor: Int = 0, subVersion: Int = 0) -> String? {
        guard (0...9).contains(vendor), (0...9).contains(subVersion) else { return nil }
        return "RIPSCRIP0154\(vendor)\(subVersion)"
    }

    /// Find every auto-sense sequence outside RIPscrip lines.
    ///
    /// The scan follows the same framing rules as the parser: a RIPscrip
    /// line starts with `!|` at the beginning of a line or with `SOH |` /
    /// `STX |` anywhere, continues across backslash continuations and ends at
    /// the next line break. Sequences inside a RIPscrip line are data and are
    /// not reported.
    ///
    /// - Parameter data: Raw stream bytes.
    /// - Returns: Every hit in source order (offsets are byte offsets).
    public static func scan(_ data: Data) -> [RIPAnsiSenseHit] {
        RIPTokenizer.tokenize(data).ansiSenses
    }
}
