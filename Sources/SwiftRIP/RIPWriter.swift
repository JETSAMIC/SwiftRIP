// RIPWriter — encode a typed `RIPScene` back into RIPscrip 1.54 text.
//
// One RIPCommand maps to one `!|<level><char><args>` logical line. Arguments
// are MegaNum base-36, left-zero-padded to the width specified by the v1.54
// command grammar (see RIPParser.swift for the canonical width table — the
// writer mirrors those widths exactly so a round-trip is byte-equivalent at
// the parser-token boundary).
//
// Text payloads are emitted with the spec's escaping rules: `\`, `!`, and
// `|` are escaped as `\\`, `\!`, `\|`. When a text payload's last character
// is `\`, a *trailing* literal `\` at end-of-line collides with the
// line-continuation rule — the spec's escape produces a run of three
// backslashes (`...\\\`) which the tokenizer reads as "two `\` characters
// (one literal `\\`, one continuation)". The writer breaks at the printable
// right margin with explicit `\` continuation, never accidentally producing
// a run that the tokenizer would misread.
//
// The writer never emits the `unknown` case (no information to recover) and
// never emits `ansiSense` markers (those are out-of-band BBS signaling, not
// part of the file format). These are noted as skips in the deliverable.

import Foundation

/// Stateless RIPscrip command-stream encoder.
public enum RIPWriter {

    /// Default right-margin column for backslash-continuation line breaks.
    /// The spec recommends keeping physical lines under 80 columns where
    /// practical; we use 76 to leave room for the leading `!|` and the
    /// trailing `\`.
    public static let defaultLineWidth: Int = 76

    /// Encode a `RIPScene` into RIPscrip 1.54 text form.
    public static func encode(_ scene: RIPScene, lineWidth: Int = RIPWriter.defaultLineWidth) -> String {
        var out: [String] = []
        out.reserveCapacity(scene.commands.count)
        for cmd in scene.commands {
            guard let body = encodeCommand(cmd) else { continue }
            out.append(wrap(prefix: "!|", body: body, width: lineWidth))
        }
        return out.joined(separator: "\n") + (out.isEmpty ? "" : "\n")
    }

    // MARK: - Per-command body

    /// Returns the body of a single command (level digit + char + args),
    /// without the `!|` prefix. Returns `nil` for commands that have no
    /// textual representation in the file format (`.unknown`, `.ansiSense`).
    private static func encodeCommand(_ cmd: RIPCommand) -> String? {
        switch cmd {
        // MARK: Level 0

        case let .textWindow(x0, y0, x1, y1, wrap, size):
            return "w" + mn(x0, 2) + mn(y0, 2) + mn(x1, 2) + mn(y1, 2) + mn(wrap, 1) + mn(size, 1)

        case let .viewport(x0, y0, x1, y1):
            return "v" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3)

        case .resetWindows:
            return "*"
        case .eraseWindow:
            return "e"
        case .eraseView:
            return "E"
        case let .gotoXY(x, y):
            return "g" + mn(x, 3) + mn(y, 3)
        case .home:
            return "H"
        case .eraseEOL:
            return ">"
        case let .color(c):
            return "c" + mn(c, 2)
        case let .setPalette(values):
            return "Q" + values.map { mn($0, 2) }.joined()
        case let .onePalette(slot, value):
            return "a" + mn(slot, 1) + mn(value, 2)
        case let .writeMode(m):
            return "W" + mn(m, 1)
        case let .move(x, y):
            return "m" + mn(x, 3) + mn(y, 3)
        case let .text(s):
            return "T" + escapeText(s)
        case let .textXY(x, y, s):
            return "@" + mn(x, 3) + mn(y, 3) + escapeText(s)
        case let .fontStyle(font, dir, size, res):
            return "Y" + mn(font, 2) + mn(dir, 2) + mn(size, 2) + mn(res, 2)
        case let .pixel(x, y):
            return "X" + mn(x, 3) + mn(y, 3)
        case let .line(x0, y0, x1, y1):
            return "L" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3)
        case let .rectangle(x0, y0, x1, y1):
            return "R" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3)
        case let .bar(x0, y0, x1, y1):
            return "B" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3)
        case let .circle(x, y, r):
            return "C" + mn(x, 3) + mn(y, 3) + mn(r, 3)
        case let .oval(x, y, sa, ea, xr, yr):
            return "O" + mn(x, 3) + mn(y, 3) + mn(sa, 3) + mn(ea, 3) + mn(xr, 3) + mn(yr, 3)
        case let .filledOval(x, y, xr, yr):
            return "o" + mn(x, 3) + mn(y, 3) + mn(xr, 3) + mn(yr, 3)
        case let .arc(x, y, sa, ea, r):
            return "A" + mn(x, 3) + mn(y, 3) + mn(sa, 3) + mn(ea, 3) + mn(r, 3)
        case let .ovalArc(x, y, sa, ea, xr, yr):
            return "V" + mn(x, 3) + mn(y, 3) + mn(sa, 3) + mn(ea, 3) + mn(xr, 3) + mn(yr, 3)
        case let .pieSlice(x, y, sa, ea, r):
            return "I" + mn(x, 3) + mn(y, 3) + mn(sa, 3) + mn(ea, 3) + mn(r, 3)
        case let .ovalPieSlice(x, y, sa, ea, xr, yr):
            return "i" + mn(x, 3) + mn(y, 3) + mn(sa, 3) + mn(ea, 3) + mn(xr, 3) + mn(yr, 3)
        case let .bezier(x0, y0, x1, y1, x2, y2, x3, y3, count):
            return "Z" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3) + mn(x2, 3) + mn(y2, 3) + mn(x3, 3) + mn(y3, 3) + mn(count, 2)
        case let .polygon(points):
            return "P" + mn(points.count, 2) + pointBytes(points)
        case let .fillPolygon(points):
            return "p" + mn(points.count, 2) + pointBytes(points)
        case let .polyline(points):
            return "l" + mn(points.count, 2) + pointBytes(points)
        case let .fill(x, y, border):
            return "F" + mn(x, 3) + mn(y, 3) + mn(border, 1)
        case let .lineStyle(style, user, thick):
            return "=" + mn(style, 2) + mn(user, 4) + mn(thick, 2)
        case let .fillStyle(pattern, color):
            return "S" + mn(pattern, 2) + mn(color, 2)
        case let .fillPattern(bytes, color):
            let body = bytes.map { mn(Int($0), 2) }.joined()
            return "f" + body + mn(color, 2)

        // MARK: Level 1

        case let .mouse(num, x0, y0, x1, y1, click, clear, text, host):
            // Two text payloads delimited by `|`. The first is escaped but the
            // delimiter is literal; the host_command is the final segment.
            return "1M" + mn(num, 2) + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3) + mn(click, 1) + mn(clear, 1) + escapeText(text) + "|" + escapeText(host)
        case .killMouseFields:
            return "1K"
        case let .beginText(x0, y0, x1, y1, res):
            return "1T" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3) + mn(res, 2)
        case let .regionText(flags, s):
            return "1t" + mn(flags, 2) + escapeText(s)
        case .endText:
            return "1E"
        case let .getImage(x0, y0, x1, y1, res):
            return "1G" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3) + mn(res, 2)
        case let .putImage(x, y, mode, res):
            return "1P" + mn(x, 3) + mn(y, 3) + mn(mode, 1) + mn(res, 2)
        case let .writeIcon(filename):
            return "1W" + escapeText(filename)
        case let .loadIcon(x, y, mode, cb, res, filename):
            return "1I" + mn(x, 3) + mn(y, 3) + mn(mode, 1) + mn(cb, 1) + mn(res, 2) + escapeText(filename)
        case let .buttonStyle(w, h, or, fl, bv, df, db, br, dk, su, gb, gc, ul, co, re, label):
            return "1B" + mn(w, 3) + mn(h, 3) + mn(or, 2) + mn(fl, 4) + mn(bv, 2) + mn(df, 2) + mn(db, 2) + mn(br, 2) + mn(dk, 2) + mn(su, 2) + mn(gb, 2) + mn(gc, 2) + mn(ul, 2) + mn(co, 2) + mn(re, 2) + escapeText(label)
        case let .button(x0, y0, x1, y1, hk, fl, label):
            return "1U" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3) + mn(hk, 2) + mn(fl, 3) + escapeText(label)
        case let .define(id, fl, s):
            return "1D" + mn(id, 3) + mn(fl, 2) + escapeText(s)
        case let .query(fl, s):
            return "1?" + mn(fl, 2) + escapeText(s)
        case let .copyRegion(x0, y0, x1, y1, dp, dx, dy):
            return "1C" + mn(x0, 3) + mn(y0, 3) + mn(x1, 3) + mn(y1, 3) + mn(dp, 1) + mn(dx, 3) + mn(dy, 3)
        case let .readScene(filename):
            return "1R" + escapeText(filename)
        case let .fileQuery(filename, res):
            // filename terminated by `|`, then a 2-digit reserved MegaNum.
            return "1F" + escapeText(filename) + "|" + mn(res, 2)

        // MARK: Level 9

        case let .enterBlockMode(mode, ft, res, filename):
            return "9<" + mn(mode, 1) + mn(ft, 2) + mn(res, 4) + escapeText(filename)
        case .noMore:
            return "9NoMore"

        // MARK: Out-of-band / opaque

        case .ansiSense:
            // ANSI auto-sense escape sequences live OUTSIDE the `!|` frame.
            // They are surfaced by the parser for diagnostics but have no
            // representation inside a `.rip` body.
            return nil
        case .unknown:
            // Unknown/reserved bytes by definition have no canonical width
            // table — we cannot re-encode them losslessly. Skip.
            return nil
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func mn(_ value: Int, _ width: Int) -> String {
        MegaNum.encode(value, width: width)
    }

    private static func pointBytes(_ points: [RIPPoint]) -> String {
        var s = ""
        s.reserveCapacity(points.count * 6)
        for p in points {
            s += mn(p.x, 3)
            s += mn(p.y, 3)
        }
        return s
    }

    /// Apply the spec's text-payload escapes: `\` → `\\`, `!` → `\!`, `|` → `\|`.
    private static func escapeText(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        let bs: Unicode.Scalar = Unicode.Scalar(0x5C)!
        let bang: Unicode.Scalar = Unicode.Scalar(0x21)!
        let pipe: Unicode.Scalar = Unicode.Scalar(0x7C)!
        for scalar in s.unicodeScalars {
            switch scalar {
            case bs:
                out.append(bs)
                out.append(bs)
            case bang:
                out.append(bs)
                out.append(bang)
            case pipe:
                out.append(bs)
                out.append(pipe)
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// Wrap a logical command line with the `!|` prefix and break it across
    /// physical lines at the right margin using `\` continuations. Continuation
    /// is only applied at "safe" positions — never inside a MegaNum digit run
    /// (which is always less than the right margin anyway), and never directly
    /// after an unescaped trailing-text `\` (which would produce a three-`\`
    /// run that the tokenizer reads as "literal `\` + continuation"). The
    /// simplest safe scheme: break only on byte boundaries that are NOT a
    /// backslash, and prefer to break right after a non-`\` character.
    private static func wrap(prefix: String, body: String, width: Int) -> String {
        let full = prefix + body
        if full.count <= width { return full }
        // Greedy split into chunks of `width` codepoints, separated by a
        // backslash-continuation. The trailing run of `\` on each physical
        // line must be ODD (one literal continuation `\`) — never even
        // (which the tokenizer would read as a literal `\\` with no
        // continuation) and never three (which would read as literal `\`
        // plus continuation, drifting state across the seam).
        //
        // The chunk boundary is shifted leftward until the chunk does NOT
        // end on `\`. In practice this never moves more than one position
        // because runs of `\` in encoded output only arise from escaped
        // text (`\\`, `\!`, `\|`) where the `\` is always immediately
        // followed by another character we want to keep paired.
        let scalars = Array(full.unicodeScalars)
        let bs = Unicode.Scalar(0x5C)!
        var pieces: [String] = []
        var i = 0
        while i < scalars.count {
            var end = Swift.min(i + width, scalars.count)
            if end < scalars.count {
                // Don't end the chunk on a `\` (that would collide with the
                // continuation `\` we're about to append).
                while end > i + 1, scalars[end - 1] == bs {
                    end -= 1
                }
            }
            var v = String.UnicodeScalarView()
            v.append(contentsOf: scalars[i..<end])
            pieces.append(String(v))
            i = end
        }
        return pieces.joined(separator: "\\\n")
    }
}
