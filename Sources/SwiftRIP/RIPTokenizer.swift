// RIPTokenizer — turn a raw RIPscrip stream into a flat list of
// logical-line segments, each carrying one or more concatenated commands.
//
// Stage 1 (logical-line assembly):
//   * Detect a RIP start marker at the beginning of a physical line:
//       - `!|`           (canonical)
//       - `SOH |`        (0x01 7C)         — allowed at any column
//       - `STX !|`       (0x02 21 7C)      — allowed at any column
//   * Handle line continuation: an *unescaped* trailing `\` immediately
//     before CR / LF / CRLF folds the next physical line into the same
//     logical command line.
//   * Honor the literal-EOL gotcha from the v1.54 spec: a triple-backslash
//     run at end of line means "literal `\` + continuation"; a run of `N`
//     trailing backslashes contributes `N/2` literal `\` characters, with
//     a continuation iff `N` is odd.
//   * Out-of-frame ANSI auto-sense escape sequences (`ESC[!`, `ESC[0!`,
//     `ESC[1!`, `ESC[2!`) are recognized and surfaced separately.
//
// The tokenizer's contract: produce one `RIPToken` per RIP-line. The parser
// walks the payload using per-command spec grammar to split fixed-width
// commands and consume variable-length text payloads at the next unescaped
// `|`.
//
// The tokenizer operates on `Unicode.Scalar` (not `Character`) so that CRLF
// is treated as two distinct codepoints rather than a single extended
// grapheme cluster — RIPscrip is fundamentally a byte stream and the
// grapheme view would silently merge `\r\n` into one element.

import Foundation

/// A single RIP-line segment after tokenization. Contains one logical
/// `!|...` line's worth of command payload, with continuations folded and
/// the leading start marker stripped.
public struct RIPToken: Equatable, Sendable {
    /// Raw payload — everything after the start marker, after continuation
    /// folding and start-marker stripping. Escape sequences (`\!`, `\|`,
    /// `\\`) are preserved as two-character sequences; per-command
    /// argument decoders un-escape them in text fields.
    public let payload: String
    /// Codepoint offset in the original input where this line began.
    public let offset: Int

    public init(payload: String, offset: Int) {
        self.payload = payload
        self.offset = offset
    }
}

/// Tokenization step output: RIP-line tokens plus any ANSI auto-sense
/// escape sequences encountered outside RIP frames.
public struct RIPTokenStream: Equatable, Sendable {
    public let tokens: [RIPToken]
    public let ansiSenses: [RIPAnsiSenseHit]

    public init(tokens: [RIPToken], ansiSenses: [RIPAnsiSenseHit] = []) {
        self.tokens = tokens
        self.ansiSenses = ansiSenses
    }
}

/// One ANSI auto-sense escape sequence hit, with its source-stream offset.
public struct RIPAnsiSenseHit: Equatable, Sendable {
    public let offset: Int
    public let sense: RIPAnsiSense

    public init(offset: Int, sense: RIPAnsiSense) {
        self.offset = offset
        self.sense = sense
    }
}

/// Stateless RIPscrip lexical analyzer.
public enum RIPTokenizer {

    private static let soh: Unicode.Scalar = Unicode.Scalar(0x01)!
    private static let stx: Unicode.Scalar = Unicode.Scalar(0x02)!
    private static let esc: Unicode.Scalar = Unicode.Scalar(0x1B)!
    private static let cr: Unicode.Scalar  = Unicode.Scalar(0x0D)!
    private static let lf: Unicode.Scalar  = Unicode.Scalar(0x0A)!
    private static let bang: Unicode.Scalar = Unicode.Scalar(0x21)! // !
    private static let pipe: Unicode.Scalar = Unicode.Scalar(0x7C)! // |
    private static let bs: Unicode.Scalar   = Unicode.Scalar(0x5C)! // \
    private static let lbr: Unicode.Scalar  = Unicode.Scalar(0x5B)! // [

    /// Tokenize a UTF-8 encoded Data buffer.
    public static func tokenize(_ data: Data) -> RIPTokenStream {
        let text = String(decoding: data, as: UTF8.self)
        return tokenize(text)
    }

    /// Tokenize a Swift String. Linebreaks are accepted as CRLF, LF, or CR.
    public static func tokenize(_ text: String) -> RIPTokenStream {
        var tokens: [RIPToken] = []
        var ansi: [RIPAnsiSenseHit] = []

        let scalars = Array(text.unicodeScalars)
        var i = 0
        let n = scalars.count

        while i < n {
            // ANSI auto-sense sequences live OUTSIDE the !| frame.
            if scalars[i] == Self.esc, i + 2 < n, scalars[i + 1] == Self.lbr {
                if scalars[i + 2] == Self.bang {
                    ansi.append(RIPAnsiSenseHit(offset: i, sense: .query))
                    i += 3
                    continue
                }
                if i + 3 < n, scalars[i + 3] == Self.bang {
                    switch scalars[i + 2] {
                    case "0":
                        ansi.append(RIPAnsiSenseHit(offset: i, sense: .enable))
                        i += 4
                        continue
                    case "1":
                        ansi.append(RIPAnsiSenseHit(offset: i, sense: .enable2x))
                        i += 4
                        continue
                    case "2":
                        ansi.append(RIPAnsiSenseHit(offset: i, sense: .disable))
                        i += 4
                        continue
                    default:
                        break
                    }
                }
            }

            // Detect a RIP start marker.
            let markerLen = matchStartMarker(scalars, at: i)
            if markerLen > 0 {
                let segStart = i + markerLen
                let (payload, consumed) = assembleLogicalLine(scalars, from: segStart)
                tokens.append(RIPToken(payload: payload, offset: i))
                i = segStart + consumed
                continue
            }

            i += 1
        }

        return RIPTokenStream(tokens: tokens, ansiSenses: ansi)
    }

    // MARK: - Start marker

    /// Returns the length of the matched RIP start marker, or 0 if none.
    private static func matchStartMarker(_ scalars: [Unicode.Scalar], at i: Int) -> Int {
        let n = scalars.count
        // `!|`
        if i + 1 < n, scalars[i] == Self.bang, scalars[i + 1] == Self.pipe {
            if i == 0 || scalars[i - 1] != Self.bs {
                return 2
            }
        }
        // `SOH |`
        if i + 1 < n, scalars[i] == Self.soh, scalars[i + 1] == Self.pipe {
            return 2
        }
        // `STX !|`
        if i + 2 < n, scalars[i] == Self.stx, scalars[i + 1] == Self.bang, scalars[i + 2] == Self.pipe {
            return 3
        }
        return 0
    }

    // MARK: - Logical-line assembly

    /// Reads forward from `start` through to a real (non-continuation) line
    /// break. Returns the assembled logical-line payload and the number of
    /// input scalars consumed (including the terminator).
    private static func assembleLogicalLine(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var out: [Unicode.Scalar] = []
        var i = start
        let n = scalars.count

        while i < n {
            let s = scalars[i]

            if s == Self.bs {
                // Count consecutive backslashes.
                var run = 0
                while i + run < n, scalars[i + run] == Self.bs {
                    run += 1
                }
                let afterRun = i + run
                if afterRun < n, isLineBreak(scalars[afterRun]) {
                    // A run of N trailing backslashes at EOL:
                    //   * N odd:  floor(N/2) literal `\` (each as `\\`) + continuation.
                    //   * N even: N/2 literal `\` (each as `\\`) + REAL line break.
                    let literals = run / 2
                    let continues = (run % 2 == 1)
                    for _ in 0..<literals {
                        // Preserve as an escaped literal so the per-command
                        // text-payload decoder sees `\\` and un-escapes it.
                        out.append(Self.bs)
                        out.append(Self.bs)
                    }
                    if continues {
                        i = afterRun
                        if scalars[i] == Self.cr, i + 1 < n, scalars[i + 1] == Self.lf {
                            i += 2
                        } else {
                            i += 1
                        }
                        continue
                    } else {
                        i = afterRun
                        if scalars[i] == Self.cr, i + 1 < n, scalars[i + 1] == Self.lf {
                            return (string(from: out), (i + 2) - start)
                        }
                        return (string(from: out), (i + 1) - start)
                    }
                } else {
                    for _ in 0..<run {
                        out.append(Self.bs)
                    }
                    i = afterRun
                    continue
                }
            }

            if isLineBreak(s) {
                if s == Self.cr, i + 1 < n, scalars[i + 1] == Self.lf {
                    return (string(from: out), (i + 2) - start)
                }
                return (string(from: out), (i + 1) - start)
            }

            out.append(s)
            i += 1
        }
        // EOF without a terminator.
        return (string(from: out), i - start)
    }

    @inline(__always)
    private static func isLineBreak(_ s: Unicode.Scalar) -> Bool {
        s == Self.cr || s == Self.lf
    }

    @inline(__always)
    private static func string(from scalars: [Unicode.Scalar]) -> String {
        var v = String.UnicodeScalarView()
        v.append(contentsOf: scalars)
        return String(v)
    }
}
