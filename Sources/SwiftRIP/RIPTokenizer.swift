// RIPTokenizer — split a raw RIPscrip stream into logical RIPscrip lines.
//
// Rules implemented (RIPscrip 1.54, "General Structure"):
//
//   * A RIPscrip line starts with `!|` at the beginning of a physical line
//     (rule 1/2). `!|` in the middle of a line is literal text.
//   * `SOH |` (0x01 0x7C) and `STX |` (0x02 0x7C) start a RIPscrip line in
//     any column (rule 12). `STX !|` is tolerated as well.
//   * A run of N backslashes immediately before CR / LF / CRLF contributes
//     N/2 literal (still escaped) backslash pairs and, when N is odd, folds
//     the next physical line into the same logical line (rules 5 and 13).
//   * ANSI auto-sense sequences (`ESC[!`, `ESC[0!`, `ESC[1!`, `ESC[2!`)
//     outside RIPscrip lines are reported; `ESC[1!` disables RIPscrip
//     processing (subsequent `!|` lines are plain text) until `ESC[2!`.
//
// Everything that is not part of a RIPscrip line (plain ASCII / ANSI text)
// is skipped: SwiftRIP does not emulate the TTY text window.
//
// The tokenizer works on Unicode scalars so CRLF is two elements. `Data`
// input is decoded as ISO-8859-1 (one scalar per byte), so scalar offsets
// are byte offsets and no byte sequence is ever rejected or replaced.

import Foundation

/// One logical RIPscrip line: the payload after the start marker with
/// continuations folded. Escape sequences (`\!`, `\|`, `\\`) are preserved
/// so the parser can still distinguish delimiters from literal characters.
struct RIPToken: Equatable, Sendable {
    /// Payload after the start marker (the marker's `|` is the first
    /// command delimiter and is not included).
    let payload: String
    /// Scalar offset of the start marker in the input.
    let offset: Int
}

/// Tokenizer output: RIPscrip lines plus out-of-band ANSI auto-sense hits.
struct RIPTokenStream: Equatable, Sendable {
    let tokens: [RIPToken]
    let ansiSenses: [RIPAnsiSenseHit]
}

/// Stateless RIPscrip lexical analyzer.
enum RIPTokenizer {

    static let soh: Unicode.Scalar = "\u{01}"
    static let stx: Unicode.Scalar = "\u{02}"
    static let esc: Unicode.Scalar = "\u{1B}"
    static let cr: Unicode.Scalar = "\r"
    static let lf: Unicode.Scalar = "\n"
    static let bang: Unicode.Scalar = "!"
    static let pipe: Unicode.Scalar = "|"
    static let backslash: Unicode.Scalar = "\\"
    static let leftBracket: Unicode.Scalar = "["

    /// Decode bytes as ISO-8859-1: every byte becomes the scalar with the
    /// same value. Never fails.
    static func scalars(from data: Data) -> [Unicode.Scalar] {
        data.map { Unicode.Scalar($0) }
    }

    /// Tokenize a byte buffer (decoded as ISO-8859-1).
    static func tokenize(_ data: Data) -> RIPTokenStream {
        tokenize(scalars: scalars(from: data))
    }

    /// Tokenize a string.
    static func tokenize(_ text: String) -> RIPTokenStream {
        tokenize(scalars: Array(text.unicodeScalars))
    }

    /// Tokenize a scalar buffer.
    static func tokenize(scalars: [Unicode.Scalar]) -> RIPTokenStream {
        var tokens: [RIPToken] = []
        var ansi: [RIPAnsiSenseHit] = []
        let n = scalars.count
        var i = 0
        var atLineStart = true
        var ripEnabled = true

        while i < n {
            let s = scalars[i]

            if s == esc, let (sense, length) = matchAnsiSense(scalars, at: i) {
                ansi.append(RIPAnsiSenseHit(offset: i, sense: sense))
                switch sense {
                case .disable: ripEnabled = false
                case .enable: ripEnabled = true
                case .query, .queryAlternate: break
                }
                i += length
                atLineStart = false
                continue
            }

            if ripEnabled {
                let markerLength = matchStartMarker(scalars, at: i, atLineStart: atLineStart)
                if markerLength > 0 {
                    let start = i + markerLength
                    let (payload, consumed) = assembleLogicalLine(scalars, from: start)
                    tokens.append(RIPToken(payload: payload, offset: i))
                    i = start + consumed
                    atLineStart = true
                    continue
                }
            }

            atLineStart = (s == cr || s == lf)
            i += 1
        }
        return RIPTokenStream(tokens: tokens, ansiSenses: ansi)
    }

    // MARK: - ANSI auto-sense

    /// Match `ESC[!`, `ESC[0!`, `ESC[1!` or `ESC[2!` at `i`.
    static func matchAnsiSense(_ scalars: [Unicode.Scalar], at i: Int) -> (RIPAnsiSense, Int)? {
        let n = scalars.count
        guard i + 2 < n, scalars[i] == esc, scalars[i + 1] == leftBracket else { return nil }
        if scalars[i + 2] == bang { return (.query, 3) }
        guard i + 3 < n, scalars[i + 3] == bang else { return nil }
        switch scalars[i + 2] {
        case "0": return (.queryAlternate, 4)
        case "1": return (.disable, 4)
        case "2": return (.enable, 4)
        default: return nil
        }
    }

    // MARK: - Start marker

    /// Length of the RIPscrip start marker at `i`, or 0 if there is none.
    private static func matchStartMarker(_ scalars: [Unicode.Scalar], at i: Int, atLineStart: Bool) -> Int {
        let n = scalars.count
        guard i + 1 < n else { return 0 }
        let s = scalars[i]
        if (s == soh || s == stx), scalars[i + 1] == pipe {
            return 2
        }
        if s == stx, i + 2 < n, scalars[i + 1] == bang, scalars[i + 2] == pipe {
            return 3
        }
        if atLineStart, s == bang, scalars[i + 1] == pipe {
            return 2
        }
        return 0
    }

    // MARK: - Logical-line assembly

    /// Read from `start` to the first real (non-continuation) line break.
    /// Returns the folded payload and the number of scalars consumed,
    /// including the terminating line break.
    private static func assembleLogicalLine(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var out = String.UnicodeScalarView()
        let n = scalars.count
        var i = start

        func lineBreakLength(at j: Int) -> Int {
            if scalars[j] == cr, j + 1 < n, scalars[j + 1] == lf { return 2 }
            return 1
        }

        while i < n {
            let s = scalars[i]
            if s == backslash {
                var run = 0
                while i + run < n, scalars[i + run] == backslash { run += 1 }
                let after = i + run
                if after < n, scalars[after] == cr || scalars[after] == lf {
                    // N trailing backslashes: N/2 escaped literals, plus a
                    // continuation when N is odd.
                    for _ in 0..<(run / 2) {
                        out.append(backslash)
                        out.append(backslash)
                    }
                    i = after + lineBreakLength(at: after)
                    if run % 2 == 1 { continue }
                    return (String(out), i - start)
                }
                for _ in 0..<run { out.append(backslash) }
                i = after
                continue
            }
            if s == cr || s == lf {
                i += lineBreakLength(at: i)
                return (String(out), i - start)
            }
            out.append(s)
            i += 1
        }
        return (String(out), i - start)
    }
}
