// RIPParser — turn a RIPscrip stream into a `RIPScene` of typed commands.
//
// Grammar (RIPscrip 1.54, "General Structure"):
//
//   * Every command is preceded by `|` (the `|` of the `!|` start marker is
//     the first one), so a logical line is split at each *unescaped* `|`.
//   * A command is: optional level digits (`1`, `9`, or sub-levels such as
//     `15`), one command type character, then its arguments.
//   * Numeric arguments are fixed-width MegaNums. The last argument of a
//     command that has no text argument may be shorter than its declared
//     width ("a variable width numeric parameter may be used as the last
//     parameter"), e.g. `!|cA` is color 10; if it is missing entirely it
//     reads as 0 (the spec's own RIP_BEGIN_TEXT example omits `res`).
//   * A text argument is always last and runs to the end of the command.
//     `\!`, `\|` and `\\` are un-escaped; any other `\x` is kept verbatim.
//   * Text following a command's arguments is ignored (rule 6).
//
// Malformed numeric arguments throw `RIPParseError`. Commands that are
// well-formed but not defined by 1.54 become `RIPCommand.unknown`.

import Foundation

/// Errors thrown by ``RIPParser``.
public enum RIPParseError: Error, Equatable, Sendable {
    /// A command ended before all of its numeric arguments were present.
    ///
    /// - `command`: level digits plus command character (e.g. `"L"`, `"1M"`).
    /// - `offset`: offset of the RIPscrip line that contains the command
    ///   (bytes for `Data` input, Unicode scalars for `String` input).
    case truncated(command: String, offset: Int)
    /// A numeric argument contained a character that is not a MegaNum digit.
    ///
    /// - `command`: level digits plus command character.
    /// - `text`: the offending argument characters.
    /// - `offset`: offset of the RIPscrip line that contains the command.
    case invalidMegaNum(command: String, text: String, offset: Int)
}

/// Stateless RIPscrip 1.54 parser.
public enum RIPParser {

    /// Parse a raw RIPscrip byte stream.
    ///
    /// Bytes are decoded as ISO-8859-1 (one character per byte), so text
    /// arguments preserve every byte value and error offsets are byte offsets.
    ///
    /// - Parameter data: Contents of a `.RIP` file or a captured session.
    /// - Returns: The commands found in RIPscrip lines, interleaved with any
    ///   ANSI auto-sense sequences, in source order.
    /// - Throws: ``RIPParseError`` if a command's numeric arguments are
    ///   truncated or not valid MegaNums.
    public static func parse(_ data: Data) throws -> RIPScene {
        try parse(stream: RIPTokenizer.tokenize(data))
    }

    /// Parse RIPscrip text.
    ///
    /// - Parameter text: RIPscrip source. Line breaks may be CRLF, LF or CR.
    /// - Returns: The parsed scene.
    /// - Throws: ``RIPParseError`` on malformed numeric arguments.
    public static func parse(_ text: String) throws -> RIPScene {
        try parse(stream: RIPTokenizer.tokenize(text))
    }

    static func parse(stream: RIPTokenStream) throws -> RIPScene {
        var commands: [RIPCommand] = []
        var ansiIndex = 0
        let ansiHits = stream.ansiSenses
        for token in stream.tokens {
            while ansiIndex < ansiHits.count, ansiHits[ansiIndex].offset < token.offset {
                commands.append(.ansiSense(ansiHits[ansiIndex].sense))
                ansiIndex += 1
            }
            try parseLine(token, into: &commands)
        }
        while ansiIndex < ansiHits.count {
            commands.append(.ansiSense(ansiHits[ansiIndex].sense))
            ansiIndex += 1
        }
        return RIPScene(commands: commands)
    }

    // MARK: - Line splitting

    private static func parseLine(_ token: RIPToken, into commands: inout [RIPCommand]) throws {
        let scalars = Array(token.payload.unicodeScalars)
        let n = scalars.count
        var segmentStart = 0
        var j = 0
        while j < n {
            let s = scalars[j]
            if s == "\\" {
                j += 2
                continue
            }
            if s == "|" {
                try parseCommand(scalars[segmentStart..<j], lineOffset: token.offset, into: &commands)
                j += 1
                segmentStart = j
                continue
            }
            j += 1
        }
        if segmentStart < n {
            try parseCommand(scalars[segmentStart..<n], lineOffset: token.offset, into: &commands)
        }
    }

    // MARK: - One command

    private static func parseCommand(_ segment: ArraySlice<Unicode.Scalar>, lineOffset: Int,
                                     into commands: inout [RIPCommand]) throws {
        if segment.allSatisfy({ $0 == " " || $0 == "\t" }) { return }

        var k = segment.startIndex
        var level = ""
        while k < segment.endIndex, ("0"..."9").contains(segment[k]) {
            level.unicodeScalars.append(segment[k])
            k += 1
        }
        guard k < segment.endIndex else {
            throw RIPParseError.truncated(command: level, offset: lineOffset)
        }
        let commandScalar = segment[k]
        let command = Character(commandScalar)
        var name = level
        name.unicodeScalars.append(commandScalar)
        var r = ArgumentReader(scalars: segment[(k + 1)...], command: name, offset: lineOffset)

        let cmd: RIPCommand
        switch (level, commandScalar) {
        // MARK: Level 0
        case ("", "w"):
            let a = try r.numbers([2, 2, 2, 2, 1, 1])
            cmd = .textWindow(x0: a[0], y0: a[1], x1: a[2], y1: a[3], wrap: a[4], size: a[5])
        case ("", "v"):
            let a = try r.numbers([2, 2, 2, 2])
            cmd = .viewport(x0: a[0], y0: a[1], x1: a[2], y1: a[3])
        case ("", "*"): cmd = .resetWindows
        case ("", "e"): cmd = .eraseWindow
        case ("", "E"): cmd = .eraseView
        case ("", "g"):
            let a = try r.numbers([2, 2])
            cmd = .gotoXY(x: a[0], y: a[1])
        case ("", "H"): cmd = .home
        case ("", ">"): cmd = .eraseEOL
        case ("", "c"):
            cmd = .color(try r.numbers([2])[0])
        case ("", "Q"):
            cmd = .setPalette(try r.numbers(Array(repeating: 2, count: 16)))
        case ("", "a"):
            let a = try r.numbers([2, 2])
            cmd = .onePalette(slot: a[0], value: a[1])
        case ("", "W"):
            cmd = .writeMode(try r.numbers([2])[0])
        case ("", "m"):
            let a = try r.numbers([2, 2])
            cmd = .move(x: a[0], y: a[1])
        case ("", "T"):
            cmd = .text(r.text())
        case ("", "@"):
            let a = try r.numbers([2, 2], textFollows: true)
            cmd = .textXY(x: a[0], y: a[1], string: r.text())
        case ("", "Y"):
            let a = try r.numbers([2, 2, 2, 2])
            cmd = .fontStyle(font: a[0], direction: a[1], size: a[2], reserved: a[3])
        case ("", "X"):
            let a = try r.numbers([2, 2])
            cmd = .pixel(x: a[0], y: a[1])
        case ("", "L"):
            let a = try r.numbers([2, 2, 2, 2])
            cmd = .line(x0: a[0], y0: a[1], x1: a[2], y1: a[3])
        case ("", "R"):
            let a = try r.numbers([2, 2, 2, 2])
            cmd = .rectangle(x0: a[0], y0: a[1], x1: a[2], y1: a[3])
        case ("", "B"):
            let a = try r.numbers([2, 2, 2, 2])
            cmd = .bar(x0: a[0], y0: a[1], x1: a[2], y1: a[3])
        case ("", "C"):
            let a = try r.numbers([2, 2, 2])
            cmd = .circle(x: a[0], y: a[1], radius: a[2])
        case ("", "O"):
            let a = try r.numbers([2, 2, 2, 2, 2, 2])
            cmd = .oval(x: a[0], y: a[1], startAngle: a[2], endAngle: a[3], xrad: a[4], yrad: a[5])
        case ("", "o"):
            let a = try r.numbers([2, 2, 2, 2])
            cmd = .filledOval(x: a[0], y: a[1], xrad: a[2], yrad: a[3])
        case ("", "A"):
            let a = try r.numbers([2, 2, 2, 2, 2])
            cmd = .arc(x: a[0], y: a[1], startAngle: a[2], endAngle: a[3], radius: a[4])
        case ("", "V"):
            let a = try r.numbers([2, 2, 2, 2, 2, 2])
            cmd = .ovalArc(x: a[0], y: a[1], startAngle: a[2], endAngle: a[3], xrad: a[4], yrad: a[5])
        case ("", "I"):
            let a = try r.numbers([2, 2, 2, 2, 2])
            cmd = .pieSlice(x: a[0], y: a[1], startAngle: a[2], endAngle: a[3], radius: a[4])
        case ("", "i"):
            let a = try r.numbers([2, 2, 2, 2, 2, 2])
            cmd = .ovalPieSlice(x: a[0], y: a[1], startAngle: a[2], endAngle: a[3], xrad: a[4], yrad: a[5])
        case ("", "Z"):
            let a = try r.numbers(Array(repeating: 2, count: 9))
            cmd = .bezier(x0: a[0], y0: a[1], x1: a[2], y1: a[3], x2: a[4], y2: a[5], x3: a[6], y3: a[7], count: a[8])
        case ("", "P"):
            cmd = .polygon(points: try r.points())
        case ("", "p"):
            cmd = .fillPolygon(points: try r.points())
        case ("", "l"):
            cmd = .polyline(points: try r.points())
        case ("", "F"):
            let a = try r.numbers([2, 2, 2])
            cmd = .fill(x: a[0], y: a[1], border: a[2])
        case ("", "="):
            let a = try r.numbers([2, 4, 2])
            cmd = .lineStyle(style: a[0], userPattern: a[1], thickness: a[2])
        case ("", "S"):
            let a = try r.numbers([2, 2])
            cmd = .fillStyle(pattern: a[0], color: a[1])
        case ("", "s"):
            let a = try r.numbers(Array(repeating: 2, count: 9))
            cmd = .fillPattern(bytes: a[0..<8].map { UInt8(truncatingIfNeeded: $0) }, color: a[8])
        case ("", "#"): cmd = .noMore

        // MARK: Level 1
        case ("1", "M"):
            let a = try r.numbers([2, 2, 2, 2, 2, 1, 1, 5], textFollows: true)
            cmd = .mouse(num: a[0], x0: a[1], y0: a[2], x1: a[3], y1: a[4], click: a[5], clear: a[6],
                         reserved: a[7], hostCommand: r.text())
        case ("1", "K"): cmd = .killMouseFields
        case ("1", "T"):
            let a = try r.numbers([2, 2, 2, 2, 2])
            cmd = .beginText(x0: a[0], y0: a[1], x1: a[2], y1: a[3], reserved: a[4])
        case ("1", "t"):
            let a = try r.numbers([1], textFollows: true)
            cmd = .regionText(justify: a[0], string: r.text())
        case ("1", "E"): cmd = .endText
        case ("1", "C"):
            let a = try r.numbers([2, 2, 2, 2, 1])
            cmd = .getImage(x0: a[0], y0: a[1], x1: a[2], y1: a[3], reserved: a[4])
        case ("1", "P"):
            let a = try r.numbers([2, 2, 2, 1])
            cmd = .putImage(x: a[0], y: a[1], mode: a[2], reserved: a[3])
        case ("1", "W"):
            let a = try r.numbers([1], textFollows: true)
            cmd = .writeIcon(reserved: a[0], filename: r.text())
        case ("1", "I"):
            let a = try r.numbers([2, 2, 2, 1, 2], textFollows: true)
            cmd = .loadIcon(x: a[0], y: a[1], mode: a[2], clipboard: a[3], reserved: a[4], filename: r.text())
        case ("1", "B"):
            let a = try r.numbers([2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 6])
            cmd = .buttonStyle(RIPButtonStyle(
                width: a[0], height: a[1], orientation: a[2], flags: a[3], bevelSize: a[4],
                labelColor: a[5], dropShadowColor: a[6], brightColor: a[7], darkColor: a[8],
                surfaceColor: a[9], groupNumber: a[10], flags2: a[11], underlineColor: a[12],
                cornerColor: a[13], reserved: a[14]))
        case ("1", "U"):
            let a = try r.numbers([2, 2, 2, 2, 2, 1, 1], textFollows: true)
            cmd = .button(x0: a[0], y0: a[1], x1: a[2], y1: a[3], hotkey: a[4], flags: a[5],
                          reserved: a[6], text: r.text())
        case ("1", "D"):
            let a = try r.numbers([3, 2], textFollows: true)
            cmd = .define(flags: a[0], reserved: a[1], text: r.text())
        case ("1", "\u{1B}"):
            let a = try r.numbers([1, 3], textFollows: true)
            cmd = .query(mode: a[0], reserved: a[1], text: r.text())
        case ("1", "G"):
            let a = try r.numbers([2, 2, 2, 2, 2, 2])
            cmd = .copyRegion(x0: a[0], y0: a[1], x1: a[2], y1: a[3], reserved: a[4], destLine: a[5])
        case ("1", "R"):
            let a = try r.numbers([8], textFollows: true)
            cmd = .readScene(reserved: a[0], filename: r.text())
        case ("1", "F"):
            let a = try r.numbers([2, 4], textFollows: true)
            cmd = .fileQuery(mode: a[0], reserved: a[1], filename: r.text())

        // MARK: Level 9
        case ("9", "\u{1B}"):
            let a = try r.numbers([1, 1, 2, 4], textFollows: true)
            var name = r.text()
            if let terminator = name.range(of: "<>") {
                name = String(name[..<terminator.lowerBound])
            }
            cmd = .enterBlockMode(mode: a[0], transferProtocol: a[1], fileType: a[2], reserved: a[3], filename: name)

        default:
            cmd = .unknown(level: level, command: command, arguments: r.rawRemainder())
        }
        commands.append(cmd)
    }
}

// MARK: - Argument reader

/// Cursor over the arguments of one command (still in escaped form).
struct ArgumentReader {
    private let scalars: ArraySlice<Unicode.Scalar>
    private var index: Int
    let command: String
    let offset: Int

    init(scalars: ArraySlice<Unicode.Scalar>, command: String, offset: Int) {
        self.scalars = scalars
        self.index = scalars.startIndex
        self.command = command
        self.offset = offset
    }

    /// Read consecutive MegaNums of the given widths. Unless `textFollows`,
    /// the last one may be shorter than its width or absent (reads as 0).
    mutating func numbers(_ widths: [Int], textFollows: Bool = false) throws -> [Int] {
        var values: [Int] = []
        values.reserveCapacity(widths.count)
        for (i, width) in widths.enumerated() {
            let variable = !textFollows && i == widths.count - 1
            values.append(try number(width: width, variable: variable))
        }
        return values
    }

    /// Read a point list: a 2-digit count followed by that many 2-digit
    /// (x, y) pairs. The final y may be variable-width.
    mutating func points() throws -> [RIPPoint] {
        let count = try number(width: 2, variable: false)
        var points: [RIPPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let x = try number(width: 2, variable: false)
            let y = try number(width: 2, variable: i == count - 1)
            points.append(RIPPoint(x: x, y: y))
        }
        return points
    }

    private mutating func number(width: Int, variable: Bool) throws -> Int {
        var value = 0
        var taken = 0
        while taken < width {
            guard index < scalars.endIndex else { break }
            let s = scalars[index]
            guard s.isASCII, let digit = MegaNum.digitValue(ascii: UInt8(s.value)) else {
                if variable && taken > 0 { break }
                let end = Swift.min(index + (width - taken), scalars.endIndex)
                var bad = String.UnicodeScalarView()
                bad.append(contentsOf: scalars[(index - taken)..<end])
                throw RIPParseError.invalidMegaNum(command: command, text: String(bad), offset: offset)
            }
            value = value * 36 + digit   // width <= 8, cannot overflow
            taken += 1
            index += 1
        }
        if !variable && taken < width {
            throw RIPParseError.truncated(command: command, offset: offset)
        }
        return value   // a missing variable-width last parameter reads as 0
    }

    /// The rest of the command, un-escaped.
    mutating func text() -> String {
        var out = String.UnicodeScalarView()
        while index < scalars.endIndex {
            let s = scalars[index]
            if s == "\\", index + 1 < scalars.endIndex {
                let next = scalars[index + 1]
                if next == "\\" || next == "|" || next == "!" {
                    out.append(next)
                } else {
                    out.append(s)
                    out.append(next)
                }
                index += 2
                continue
            }
            out.append(s)
            index += 1
        }
        return String(out)
    }

    /// The rest of the command exactly as on the wire (still escaped).
    mutating func rawRemainder() -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[index...])
        index = scalars.endIndex
        return String(out)
    }
}
