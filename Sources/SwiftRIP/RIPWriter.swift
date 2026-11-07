// RIPWriter — encode a `RIPScene` as RIPscrip 1.54 text.
//
// Each command becomes one `!|<level><char><args>` line. Numeric arguments
// are left-zero-padded MegaNums of the width the 1.54 grammar declares
// (the same widths `RIPParser` reads). Text arguments are escaped (`\` ->
// `\\`, `!` -> `\!`, `|` -> `\|`). Long lines are folded with backslash
// continuations, only ever between whole characters / escape pairs, so a
// trailing escaped backslash produces the spec's `\\\` "literal backslash
// plus continuation" form rather than an accidental line break.

import Foundation

/// Errors thrown by ``RIPWriter``.
public enum RIPWriteError: Error, Equatable, Sendable {
    /// A numeric argument does not fit its MegaNum field.
    ///
    /// - `command`: level digits plus command character (e.g. `"L"`).
    /// - `value`: the offending value.
    /// - `width`: the field width in MegaNum digits.
    case valueOutOfRange(command: String, value: Int, width: Int)
    /// A list argument has the wrong number of elements (`setPalette` needs
    /// 16 values, `fillPattern` 8 bytes, point lists at most 1295 points).
    case invalidArgumentCount(command: String, count: Int)
    /// A text argument contains a carriage return or line feed, which cannot
    /// be represented inside a RIPscrip line.
    case lineBreakInText(command: String)
    /// An ``RIPCommand/unknown(level:command:arguments:)`` value whose level
    /// is not all decimal digits or whose command character is a digit, `|`,
    /// a backslash or a line break, so it cannot be re-emitted as one command.
    case invalidUnknownCommand(level: String, command: Character)
    /// A text argument contains a sequence that cannot be represented: a
    /// `<>` inside the filename of RIP_ENTER_BLOCK_MODE (which ends at its
    /// first `<>`), or an unescaped `|` in the arguments of an
    /// ``RIPCommand/unknown(level:command:arguments:)`` value.
    case unrepresentableText(command: String)
    /// `lineEnding` is not `"\r\n"`, `"\n"` or `"\r"`.
    case invalidLineEnding
}

/// Stateless RIPscrip 1.54 encoder.
public enum RIPWriter {

    /// Default physical line width (in characters) at which long commands
    /// are folded with a backslash continuation.
    public static let defaultLineWidth: Int = 76

    /// Encode a scene as RIPscrip text.
    ///
    /// ``RIPCommand/ansiSense(_:)`` values are not part of a RIPscrip line and
    /// are skipped; ``RIPCommand/unknown(level:command:arguments:)`` values
    /// are re-emitted verbatim.
    ///
    /// - Parameters:
    ///   - scene: The scene to encode.
    ///   - lineWidth: Maximum physical line length before a continuation is
    ///     inserted (minimum 8). Defaults to ``defaultLineWidth``.
    ///   - lineEnding: Line terminator; defaults to CRLF as used by DOS-era
    ///     hosts. The parser accepts CRLF, LF and CR.
    /// - Returns: RIPscrip text, one command per logical line.
    /// - Throws: ``RIPWriteError`` if a command cannot be represented.
    public static func encode(_ scene: RIPScene, lineWidth: Int = RIPWriter.defaultLineWidth,
                              lineEnding: String = "\r\n") throws -> String {
        guard ["\r\n", "\n", "\r"].contains(lineEnding) else { throw RIPWriteError.invalidLineEnding }
        let width = Swift.max(8, lineWidth)
        var out = ""
        for command in scene.commands {
            guard let atoms = try encodeCommand(command) else { continue }
            out += fold(["!", "|"] + atoms, width: width, lineEnding: lineEnding)
            out += lineEnding
        }
        return out
    }

    // MARK: - Per-command body

    /// Builds the body of one command as "atoms" (single characters or
    /// two-character escape pairs) so folding never splits an escape.
    private struct Body {
        let name: String
        var atoms: [String]

        init(_ name: String) {
            self.name = name
            self.atoms = name.unicodeScalars.map { String($0) }
        }

        mutating func num(_ value: Int, _ width: Int) throws {
            guard let digits = try? MegaNum.encode(value, width: width) else {
                throw RIPWriteError.valueOutOfRange(command: name, value: value, width: width)
            }
            atoms.append(contentsOf: digits.map { String($0) })
        }

        mutating func nums(_ values: [Int], _ width: Int) throws {
            for v in values { try num(v, width) }
        }

        mutating func text(_ s: String) throws {
            for scalar in s.unicodeScalars {
                switch scalar {
                case "\r", "\n":
                    throw RIPWriteError.lineBreakInText(command: name)
                case "\\", "!", "|":
                    atoms.append("\\" + String(scalar))
                default:
                    atoms.append(String(scalar))
                }
            }
        }

        /// Already-escaped text: `\x` pairs stay together as one atom so a
        /// fold never separates them; a bare `|` would split the command.
        mutating func raw(_ s: String) throws {
            let scalars = Array(s.unicodeScalars)
            var i = 0
            while i < scalars.count {
                let scalar = scalars[i]
                if scalar == "\r" || scalar == "\n" {
                    throw RIPWriteError.lineBreakInText(command: name)
                }
                if scalar == "|" { throw RIPWriteError.unrepresentableText(command: name) }
                if scalar == "\\" {
                    if i + 1 < scalars.count {
                        let next = scalars[i + 1]
                        if next == "\r" || next == "\n" { throw RIPWriteError.lineBreakInText(command: name) }
                        atoms.append("\\" + String(next))
                        i += 2
                        continue
                    }
                    // A lone trailing backslash would read as a continuation.
                    atoms.append("\\\\")
                    i += 1
                    continue
                }
                atoms.append(String(scalar))
                i += 1
            }
        }

        mutating func points(_ points: [RIPPoint]) throws {
            guard points.count <= 1295 else {
                throw RIPWriteError.invalidArgumentCount(command: name, count: points.count)
            }
            try num(points.count, 2)
            for p in points {
                try num(p.x, 2)
                try num(p.y, 2)
            }
        }
    }

    private static func encodeCommand(_ cmd: RIPCommand) throws -> [String]? {
        var b: Body
        switch cmd {
        // MARK: Level 0
        case let .textWindow(x0, y0, x1, y1, wrap, size):
            b = Body("w"); try b.nums([x0, y0, x1, y1], 2); try b.num(wrap, 1); try b.num(size, 1)
        case let .viewport(x0, y0, x1, y1):
            b = Body("v"); try b.nums([x0, y0, x1, y1], 2)
        case .resetWindows: b = Body("*")
        case .eraseWindow: b = Body("e")
        case .eraseView: b = Body("E")
        case let .gotoXY(x, y):
            b = Body("g"); try b.nums([x, y], 2)
        case .home: b = Body("H")
        case .eraseEOL: b = Body(">")
        case let .color(c):
            b = Body("c"); try b.num(c, 2)
        case let .setPalette(values):
            b = Body("Q")
            guard values.count == 16 else {
                throw RIPWriteError.invalidArgumentCount(command: "Q", count: values.count)
            }
            try b.nums(values, 2)
        case let .onePalette(slot, value):
            b = Body("a"); try b.nums([slot, value], 2)
        case let .writeMode(m):
            b = Body("W"); try b.num(m, 2)
        case let .move(x, y):
            b = Body("m"); try b.nums([x, y], 2)
        case let .text(s):
            b = Body("T"); try b.text(s)
        case let .textXY(x, y, s):
            b = Body("@"); try b.nums([x, y], 2); try b.text(s)
        case let .fontStyle(font, dir, size, res):
            b = Body("Y"); try b.nums([font, dir, size, res], 2)
        case let .pixel(x, y):
            b = Body("X"); try b.nums([x, y], 2)
        case let .line(x0, y0, x1, y1):
            b = Body("L"); try b.nums([x0, y0, x1, y1], 2)
        case let .rectangle(x0, y0, x1, y1):
            b = Body("R"); try b.nums([x0, y0, x1, y1], 2)
        case let .bar(x0, y0, x1, y1):
            b = Body("B"); try b.nums([x0, y0, x1, y1], 2)
        case let .circle(x, y, r):
            b = Body("C"); try b.nums([x, y, r], 2)
        case let .oval(x, y, sa, ea, xr, yr):
            b = Body("O"); try b.nums([x, y, sa, ea, xr, yr], 2)
        case let .filledOval(x, y, xr, yr):
            b = Body("o"); try b.nums([x, y, xr, yr], 2)
        case let .arc(x, y, sa, ea, r):
            b = Body("A"); try b.nums([x, y, sa, ea, r], 2)
        case let .ovalArc(x, y, sa, ea, xr, yr):
            b = Body("V"); try b.nums([x, y, sa, ea, xr, yr], 2)
        case let .pieSlice(x, y, sa, ea, r):
            b = Body("I"); try b.nums([x, y, sa, ea, r], 2)
        case let .ovalPieSlice(x, y, sa, ea, xr, yr):
            b = Body("i"); try b.nums([x, y, sa, ea, xr, yr], 2)
        case let .bezier(x0, y0, x1, y1, x2, y2, x3, y3, count):
            b = Body("Z"); try b.nums([x0, y0, x1, y1, x2, y2, x3, y3, count], 2)
        case let .polygon(points):
            b = Body("P"); try b.points(points)
        case let .fillPolygon(points):
            b = Body("p"); try b.points(points)
        case let .polyline(points):
            b = Body("l"); try b.points(points)
        case let .fill(x, y, border):
            b = Body("F"); try b.nums([x, y, border], 2)
        case let .lineStyle(style, user, thick):
            b = Body("="); try b.num(style, 2); try b.num(user, 4); try b.num(thick, 2)
        case let .fillStyle(pattern, color):
            b = Body("S"); try b.nums([pattern, color], 2)
        case let .fillPattern(bytes, color):
            b = Body("s")
            guard bytes.count == 8 else {
                throw RIPWriteError.invalidArgumentCount(command: "s", count: bytes.count)
            }
            try b.nums(bytes.map(Int.init), 2); try b.num(color, 2)
        case .noMore: b = Body("#")

        // MARK: Level 1
        case let .mouse(num, x0, y0, x1, y1, click, clear, reserved, host):
            b = Body("1M"); try b.nums([num, x0, y0, x1, y1], 2)
            try b.num(click, 1); try b.num(clear, 1); try b.num(reserved, 5); try b.text(host)
        case .killMouseFields: b = Body("1K")
        case let .beginText(x0, y0, x1, y1, res):
            b = Body("1T"); try b.nums([x0, y0, x1, y1, res], 2)
        case let .regionText(justify, s):
            b = Body("1t"); try b.num(justify, 1); try b.text(s)
        case .endText: b = Body("1E")
        case let .getImage(x0, y0, x1, y1, res):
            b = Body("1C"); try b.nums([x0, y0, x1, y1], 2); try b.num(res, 1)
        case let .putImage(x, y, mode, res):
            b = Body("1P"); try b.nums([x, y, mode], 2); try b.num(res, 1)
        case let .writeIcon(res, filename):
            b = Body("1W"); try b.num(res, 1); try b.text(filename)
        case let .loadIcon(x, y, mode, clipboard, res, filename):
            b = Body("1I"); try b.nums([x, y, mode], 2); try b.num(clipboard, 1); try b.num(res, 2)
            try b.text(filename)
        case let .buttonStyle(s):
            b = Body("1B")
            try b.nums([s.width, s.height, s.orientation], 2); try b.num(s.flags, 4)
            try b.nums([s.bevelSize, s.labelColor, s.dropShadowColor, s.brightColor, s.darkColor,
                        s.surfaceColor, s.groupNumber, s.flags2, s.underlineColor, s.cornerColor], 2)
            try b.num(s.reserved, 6)
        case let .button(x0, y0, x1, y1, hotkey, flags, res, text):
            b = Body("1U"); try b.nums([x0, y0, x1, y1, hotkey], 2); try b.num(flags, 1); try b.num(res, 1)
            try b.text(text)
        case let .define(flags, res, text):
            b = Body("1D"); try b.num(flags, 3); try b.num(res, 2); try b.text(text)
        case let .query(mode, res, text):
            b = Body("1\u{1B}"); try b.num(mode, 1); try b.num(res, 3); try b.text(text)
        case let .copyRegion(x0, y0, x1, y1, res, dest):
            b = Body("1G"); try b.nums([x0, y0, x1, y1, res, dest], 2)
        case let .readScene(res, filename):
            b = Body("1R"); try b.num(res, 8); try b.text(filename)
        case let .fileQuery(mode, res, filename):
            b = Body("1F"); try b.num(mode, 2); try b.num(res, 4); try b.text(filename)

        // MARK: Level 9
        case let .enterBlockMode(mode, proto, fileType, res, filename):
            b = Body("9\u{1B}"); try b.num(mode, 1); try b.num(proto, 1); try b.num(fileType, 2)
            guard !filename.contains("<>") else { throw RIPWriteError.unrepresentableText(command: "9\u{1B}") }
            try b.num(res, 4); try b.text(filename); b.atoms.append(contentsOf: ["<", ">"])

        // MARK: Out-of-band
        case .ansiSense:
            return nil
        case let .unknown(level, command, arguments):
            let scalars = command.unicodeScalars
            let badCommand = scalars.count != 1 || command.isNumber || command.isWhitespace
                || ["|", "\\"].contains(command) || isDefined(level: level, command: command)
            guard !badCommand, level.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else {
                throw RIPWriteError.invalidUnknownCommand(level: level, command: command)
            }
            b = Body(level + String(command)); try b.raw(arguments)
        }
        return b.atoms
    }

    /// `true` if `(level, command)` is a RIPscrip 1.54 command, which an
    /// `.unknown` value must not imitate.
    private static func isDefined(level: String, command: Character) -> Bool {
        switch level {
        case "": return "wv*eEgH>cQaWmT@YXLRBCOoAVIiZPplF=Ss#".contains(command)
        case "1": return "MKTtECPWIBUDGRF\u{1B}".contains(command)
        case "9": return command == "\u{1B}"
        default: return false
        }
    }

    // MARK: - Folding

    /// Join atoms into physical lines of at most `width` characters (the
    /// continuation backslash included), never splitting an atom.
    private static func fold(_ atoms: [String], width: Int, lineEnding: String) -> String {
        var out = ""
        var lineLength = 0
        for atom in atoms {
            let length = atom.unicodeScalars.count
            if lineLength > 0, lineLength + length > width - 1 {
                out += "\\" + lineEnding
                lineLength = 0
            }
            out += atom
            lineLength += length
        }
        return out
    }
}
