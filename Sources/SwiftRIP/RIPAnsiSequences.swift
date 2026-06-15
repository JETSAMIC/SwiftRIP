// RIPAnsiSequences — RIPscrip auto-sense ANSI escape sequences.
//
// RIPscrip embeds a tiny ANSI-compatible handshake outside the `!|...|`
// frame so a BBS host can probe whether the terminal it's talking to
// supports RIPscrip at all, and at what version. The four host→terminal
// queries are:
//
//   * `ESC [ !`   (1B 5B 21)         — "Do you support any RIPscrip?"
//   * `ESC [ 0 !` (1B 5B 30 21)      — "Do you support RIPscrip 1.5x?"
//   * `ESC [ 1 !` (1B 5B 31 21)      — "Do you support RIPscrip 2.x?"
//   * `ESC [ 2 !` (1B 5B 32 21)      — "Send your Vendor Code."
//
// SwiftRIP is a library, not a terminal, so it has no Vendor Code of its
// own and does not emit responses. The tokenizer recognizes these
// sequences when they appear outside RIP frames and surfaces them as
// `RIPCommand.ansiSense(…)` so a wrapping app (e.g., a BBS terminal that
// embeds SwiftRIP) can hook them.
//
// The actual recognition lives in `RIPTokenizer` — this file documents the
// vocabulary and provides a stand-alone matcher for callers that want to
// process a buffer for sense sequences without involving the full
// tokenizer pipeline.

import Foundation

/// Static matcher for RIPscrip auto-sense escape sequences.
public enum RIPAnsiSequences {

    /// The byte sequence emitted for each sense.
    public static func bytes(for sense: RIPAnsiSense) -> [UInt8] {
        switch sense {
        case .query:    return [0x1B, 0x5B, 0x21]
        case .enable:   return [0x1B, 0x5B, 0x30, 0x21]
        case .enable2x: return [0x1B, 0x5B, 0x31, 0x21]
        case .disable:  return [0x1B, 0x5B, 0x32, 0x21]
        }
    }

    /// Scan a buffer for sense sequences. Returns every hit in source order.
    /// Sense sequences MUST be matched on a raw byte stream — they are not
    /// interpreted relative to grapheme boundaries. Embedded inside RIP
    /// frames (between `!|` and end-of-line) the sequence is just data and
    /// is NOT recognized here.
    public static func scan(_ data: Data) -> [RIPAnsiSenseHit] {
        var hits: [RIPAnsiSenseHit] = []
        var inRipFrame = false
        let n = data.count
        var i = 0
        while i < n {
            let b = data[i]

            // Track entering / leaving a `!|...<LF/CR>` frame.
            if !inRipFrame {
                if b == 0x21, i + 1 < n, data[i + 1] == 0x7C {
                    // `!|`
                    inRipFrame = true
                    i += 2
                    continue
                }
                if b == 0x01, i + 1 < n, data[i + 1] == 0x7C {
                    // `SOH |`
                    inRipFrame = true
                    i += 2
                    continue
                }
                if b == 0x02, i + 2 < n, data[i + 1] == 0x21, data[i + 2] == 0x7C {
                    // `STX !|`
                    inRipFrame = true
                    i += 3
                    continue
                }
                if b == 0x1B, i + 2 < n, data[i + 1] == 0x5B {
                    if data[i + 2] == 0x21 {
                        hits.append(RIPAnsiSenseHit(offset: i, sense: .query))
                        i += 3
                        continue
                    }
                    if i + 3 < n, data[i + 3] == 0x21 {
                        switch data[i + 2] {
                        case 0x30:
                            hits.append(RIPAnsiSenseHit(offset: i, sense: .enable))
                            i += 4
                            continue
                        case 0x31:
                            hits.append(RIPAnsiSenseHit(offset: i, sense: .enable2x))
                            i += 4
                            continue
                        case 0x32:
                            hits.append(RIPAnsiSenseHit(offset: i, sense: .disable))
                            i += 4
                            continue
                        default:
                            break
                        }
                    }
                }
            } else {
                // Inside a RIP frame — leave on LF / CR, with continuation
                // handling for trailing unescaped backslashes.
                if b == 0x0A || b == 0x0D {
                    inRipFrame = false
                }
            }
            i += 1
        }
        return hits
    }
}
