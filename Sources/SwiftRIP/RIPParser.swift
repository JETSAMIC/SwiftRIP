// RIPParser — turn an `RIPTokenStream` into a `RIPScene` of typed
// `RIPCommand` values.
//
// The tokenizer hands the parser one logical-line payload per RIP frame.
// Within that payload the parser walks command-by-command, dispatching by
// (level, char) and consuming fixed-width MegaNum fields per the v1.54
// spec. Variable-length last-parameter handling:
//
//   * `T`, `@`, `1t`, `1U`, `1D`, `1?`, `1R`, `1W`, `1I`     — string runs
//     to the end of the segment (i.e., the unescaped `|` that the tokenizer
//     preserved as part of the payload).
//   * `1F`                                                    — filename
//     terminated by `|`, then a 2-digit reserved MegaNum.
//   * `1M`                                                    — text then
//     `|`, then host_command then `|`.
//   * `9<`                                                    — fixed args
//     then filename to next `|`.
//   * `P`, `p`, `l`                                           — count, then
//     `count` (x,y) point pairs.
//   * `Q`                                                     — exactly 16
//     × 2-digit MegaNum palette values.
//
// Text payloads are un-escaped (`\!` → `!`, `\|` → `|`, `\\` → `\`); all
// other `\X` sequences pass through unchanged per the spec's "unknown
// escapes pass through" rule.

import Foundation

/// Errors thrown by `RIPParser.parse`.
public enum RIPParseError: Error, Equatable, Sendable {
    /// A command's argument list was cut short by end-of-payload.
    case truncated(commandChar: Character, atOffset: Int)
    /// The (level, char) pair is unknown or reserved.
    case unknownCommand(level: Int, char: Character)
    /// A MegaNum field contained an out-of-set digit.
    case invalidMegaNum(text: String)
    /// A MegaNum field had the wrong width.
    case widthMismatch(expected: Int, got: Int)
}

/// Stateless RIPscrip command parser.
public enum RIPParser {

    /// Parse a raw RIPscrip byte stream into a typed scene.
    public static func parse(_ data: Data) throws -> RIPScene {
        let text = String(decoding: data, as: UTF8.self)
        return try parse(text)
    }

    /// Parse a RIPscrip string into a typed scene.
    public static func parse(_ text: String) throws -> RIPScene {
        let stream = RIPTokenizer.tokenize(text)
        var commands: [RIPCommand] = []

        // Surface ANSI auto-sense hits as first-class commands, interleaved
        // in source order with the RIP-line tokens.
        var ansiIndex = 0
        let ansiHits = stream.ansiSenses

        for token in stream.tokens {
            // Flush any ANSI hits that occurred *before* this token.
            while ansiIndex < ansiHits.count, ansiHits[ansiIndex].offset < token.offset {
                commands.append(.ansiSense(ansiHits[ansiIndex].sense))
                ansiIndex += 1
            }
            try parseLine(token, into: &commands)
        }
        // Drain any trailing ANSI hits.
        while ansiIndex < ansiHits.count {
            commands.append(.ansiSense(ansiHits[ansiIndex].sense))
            ansiIndex += 1
        }

        return RIPScene(commands: commands)
    }

    // MARK: - Per-line walking

    private static func parseLine(_ token: RIPToken, into commands: inout [RIPCommand]) throws {
        var cursor = PayloadCursor(payload: token.payload, baseOffset: token.offset)

        while !cursor.isAtEnd {
            // Skip any stray whitespace between concatenated commands (rare,
            // but real hand-authored RIP files sometimes pad for legibility).
            cursor.skipSpaces()
            if cursor.isAtEnd { break }

            try parseCommand(&cursor, into: &commands)
        }
    }

    private static func parseCommand(_ cursor: inout PayloadCursor, into commands: inout [RIPCommand]) throws {
        let first = cursor.peek()!
        var level = 0

        if first == "1" || first == "9" {
            // Level prefix. Peek the next char to confirm there IS another
            // char — if not, fall through and treat as a level-0 command
            // identified by `1` or `9` (none exist, so it becomes unknown).
            if cursor.remaining >= 2 {
                level = first == "1" ? 1 : 9
                cursor.advance()
            }
        }

        guard let cmdScalar = cursor.peek() else {
            throw RIPParseError.truncated(commandChar: " ", atOffset: cursor.absoluteOffset)
        }
        let cmdChar = Character(cmdScalar)
        cursor.advance()

        switch (level, cmdChar) {
        // MARK: Level 0
        case (0, "w"):
            let x0 = try cursor.readMegaNum(width: 2, name: "w.x0")
            let y0 = try cursor.readMegaNum(width: 2, name: "w.y0")
            let x1 = try cursor.readMegaNum(width: 2, name: "w.x1")
            let y1 = try cursor.readMegaNum(width: 2, name: "w.y1")
            let wrap = try cursor.readMegaNum(width: 1, name: "w.wrap")
            let size = try cursor.readMegaNum(width: 1, name: "w.size")
            commands.append(.textWindow(x0: x0, y0: y0, x1: x1, y1: y1, wrap: wrap, size: size))

        case (0, "v"):
            let x0 = try cursor.readMegaNum(width: 3, name: "v.x0")
            let y0 = try cursor.readMegaNum(width: 3, name: "v.y0")
            let x1 = try cursor.readMegaNum(width: 3, name: "v.x1")
            let y1 = try cursor.readMegaNum(width: 3, name: "v.y1")
            commands.append(.viewport(x0: x0, y0: y0, x1: x1, y1: y1))

        case (0, "*"):
            commands.append(.resetWindows)

        case (0, "e"):
            commands.append(.eraseWindow)

        case (0, "E"):
            commands.append(.eraseView)

        case (0, "g"):
            let x = try cursor.readMegaNum(width: 3, name: "g.x")
            let y = try cursor.readMegaNum(width: 3, name: "g.y")
            commands.append(.gotoXY(x: x, y: y))

        case (0, "H"):
            commands.append(.home)

        case (0, ">"):
            commands.append(.eraseEOL)

        case (0, "c"):
            let c = try cursor.readMegaNum(width: 2, name: "c.color")
            commands.append(.color(c))

        case (0, "Q"):
            var values: [Int] = []
            values.reserveCapacity(16)
            for slot in 0..<16 {
                values.append(try cursor.readMegaNum(width: 2, name: "Q.\(slot)"))
            }
            commands.append(.setPalette(values))

        case (0, "a"):
            let slot = try cursor.readMegaNum(width: 1, name: "a.slot")
            let value = try cursor.readMegaNum(width: 2, name: "a.value")
            commands.append(.onePalette(slot: slot, value: value))

        case (0, "W"):
            let mode = try cursor.readMegaNum(width: 1, name: "W.mode")
            commands.append(.writeMode(mode))

        case (0, "m"):
            let x = try cursor.readMegaNum(width: 3, name: "m.x")
            let y = try cursor.readMegaNum(width: 3, name: "m.y")
            commands.append(.move(x: x, y: y))

        case (0, "T"):
            let s = cursor.readStringToEndOfSegment()
            commands.append(.text(s))

        case (0, "@"):
            let x = try cursor.readMegaNum(width: 3, name: "@.x")
            let y = try cursor.readMegaNum(width: 3, name: "@.y")
            let s = cursor.readStringToEndOfSegment()
            commands.append(.textXY(x: x, y: y, string: s))

        case (0, "Y"):
            let font = try cursor.readMegaNum(width: 2, name: "Y.font")
            let dir  = try cursor.readMegaNum(width: 2, name: "Y.dir")
            let size = try cursor.readMegaNum(width: 2, name: "Y.size")
            let res  = try cursor.readMegaNum(width: 2, name: "Y.reserved")
            commands.append(.fontStyle(font: font, direction: dir, size: size, reserved: res))

        case (0, "X"):
            let x = try cursor.readMegaNum(width: 3, name: "X.x")
            let y = try cursor.readMegaNum(width: 3, name: "X.y")
            commands.append(.pixel(x: x, y: y))

        case (0, "L"):
            let (x0, y0, x1, y1) = try cursor.readRect3(prefix: "L")
            commands.append(.line(x0: x0, y0: y0, x1: x1, y1: y1))

        case (0, "R"):
            let (x0, y0, x1, y1) = try cursor.readRect3(prefix: "R")
            commands.append(.rectangle(x0: x0, y0: y0, x1: x1, y1: y1))

        case (0, "B"):
            let (x0, y0, x1, y1) = try cursor.readRect3(prefix: "B")
            commands.append(.bar(x0: x0, y0: y0, x1: x1, y1: y1))

        case (0, "C"):
            let x = try cursor.readMegaNum(width: 3, name: "C.x")
            let y = try cursor.readMegaNum(width: 3, name: "C.y")
            let r = try cursor.readMegaNum(width: 3, name: "C.r")
            commands.append(.circle(x: x, y: y, radius: r))

        case (0, "O"):
            let x = try cursor.readMegaNum(width: 3, name: "O.x")
            let y = try cursor.readMegaNum(width: 3, name: "O.y")
            let sa = try cursor.readMegaNum(width: 3, name: "O.sa")
            let ea = try cursor.readMegaNum(width: 3, name: "O.ea")
            let xr = try cursor.readMegaNum(width: 3, name: "O.xr")
            let yr = try cursor.readMegaNum(width: 3, name: "O.yr")
            commands.append(.oval(x: x, y: y, startAngle: sa, endAngle: ea, xrad: xr, yrad: yr))

        case (0, "o"):
            let x = try cursor.readMegaNum(width: 3, name: "o.x")
            let y = try cursor.readMegaNum(width: 3, name: "o.y")
            let xr = try cursor.readMegaNum(width: 3, name: "o.xr")
            let yr = try cursor.readMegaNum(width: 3, name: "o.yr")
            commands.append(.filledOval(x: x, y: y, xrad: xr, yrad: yr))

        case (0, "A"):
            let x = try cursor.readMegaNum(width: 3, name: "A.x")
            let y = try cursor.readMegaNum(width: 3, name: "A.y")
            let sa = try cursor.readMegaNum(width: 3, name: "A.sa")
            let ea = try cursor.readMegaNum(width: 3, name: "A.ea")
            let r  = try cursor.readMegaNum(width: 3, name: "A.r")
            commands.append(.arc(x: x, y: y, startAngle: sa, endAngle: ea, radius: r))

        case (0, "V"):
            let x = try cursor.readMegaNum(width: 3, name: "V.x")
            let y = try cursor.readMegaNum(width: 3, name: "V.y")
            let sa = try cursor.readMegaNum(width: 3, name: "V.sa")
            let ea = try cursor.readMegaNum(width: 3, name: "V.ea")
            let xr = try cursor.readMegaNum(width: 3, name: "V.xr")
            let yr = try cursor.readMegaNum(width: 3, name: "V.yr")
            commands.append(.ovalArc(x: x, y: y, startAngle: sa, endAngle: ea, xrad: xr, yrad: yr))

        case (0, "I"):
            let x = try cursor.readMegaNum(width: 3, name: "I.x")
            let y = try cursor.readMegaNum(width: 3, name: "I.y")
            let sa = try cursor.readMegaNum(width: 3, name: "I.sa")
            let ea = try cursor.readMegaNum(width: 3, name: "I.ea")
            let r  = try cursor.readMegaNum(width: 3, name: "I.r")
            commands.append(.pieSlice(x: x, y: y, startAngle: sa, endAngle: ea, radius: r))

        case (0, "i"):
            let x = try cursor.readMegaNum(width: 3, name: "i.x")
            let y = try cursor.readMegaNum(width: 3, name: "i.y")
            let sa = try cursor.readMegaNum(width: 3, name: "i.sa")
            let ea = try cursor.readMegaNum(width: 3, name: "i.ea")
            let xr = try cursor.readMegaNum(width: 3, name: "i.xr")
            let yr = try cursor.readMegaNum(width: 3, name: "i.yr")
            commands.append(.ovalPieSlice(x: x, y: y, startAngle: sa, endAngle: ea, xrad: xr, yrad: yr))

        case (0, "Z"):
            let x0 = try cursor.readMegaNum(width: 3, name: "Z.x0")
            let y0 = try cursor.readMegaNum(width: 3, name: "Z.y0")
            let x1 = try cursor.readMegaNum(width: 3, name: "Z.x1")
            let y1 = try cursor.readMegaNum(width: 3, name: "Z.y1")
            let x2 = try cursor.readMegaNum(width: 3, name: "Z.x2")
            let y2 = try cursor.readMegaNum(width: 3, name: "Z.y2")
            let x3 = try cursor.readMegaNum(width: 3, name: "Z.x3")
            let y3 = try cursor.readMegaNum(width: 3, name: "Z.y3")
            let cnt = try cursor.readMegaNum(width: 2, name: "Z.cnt")
            commands.append(.bezier(x0: x0, y0: y0, x1: x1, y1: y1, x2: x2, y2: y2, x3: x3, y3: y3, count: cnt))

        case (0, "P"):
            let points = try cursor.readPointList(prefix: "P")
            commands.append(.polygon(points: points))

        case (0, "p"):
            let points = try cursor.readPointList(prefix: "p")
            commands.append(.fillPolygon(points: points))

        case (0, "l"):
            let points = try cursor.readPointList(prefix: "l")
            commands.append(.polyline(points: points))

        case (0, "F"):
            let x = try cursor.readMegaNum(width: 3, name: "F.x")
            let y = try cursor.readMegaNum(width: 3, name: "F.y")
            let b = try cursor.readMegaNum(width: 1, name: "F.border")
            commands.append(.fill(x: x, y: y, border: b))

        case (0, "="):
            let style = try cursor.readMegaNum(width: 2, name: "=.style")
            let user  = try cursor.readMegaNum(width: 4, name: "=.user")
            let thick = try cursor.readMegaNum(width: 2, name: "=.thick")
            commands.append(.lineStyle(style: style, userPattern: user, thickness: thick))

        case (0, "S"):
            let pat = try cursor.readMegaNum(width: 2, name: "S.pattern")
            let col = try cursor.readMegaNum(width: 2, name: "S.color")
            commands.append(.fillStyle(pattern: pat, color: col))

        case (0, "f"):
            var bytes: [UInt8] = []
            bytes.reserveCapacity(8)
            for b in 0..<8 {
                let v = try cursor.readMegaNum(width: 2, name: "f.b\(b)")
                bytes.append(UInt8(truncatingIfNeeded: v))
            }
            let col = try cursor.readMegaNum(width: 2, name: "f.color")
            commands.append(.fillPattern(bytes: bytes, color: col))

        // MARK: Level 1

        case (1, "M"):
            let num = try cursor.readMegaNum(width: 2, name: "1M.num")
            let x0 = try cursor.readMegaNum(width: 3, name: "1M.x0")
            let y0 = try cursor.readMegaNum(width: 3, name: "1M.y0")
            let x1 = try cursor.readMegaNum(width: 3, name: "1M.x1")
            let y1 = try cursor.readMegaNum(width: 3, name: "1M.y1")
            let clk = try cursor.readMegaNum(width: 1, name: "1M.clk")
            let clr = try cursor.readMegaNum(width: 1, name: "1M.clear")
            let text = cursor.readStringToPipe()
            let host = cursor.readStringToEndOfSegment()
            commands.append(.mouse(num: num, x0: x0, y0: y0, x1: x1, y1: y1, click: clk, clear: clr, text: text, hostCommand: host))

        case (1, "K"):
            commands.append(.killMouseFields)

        case (1, "T"):
            let x0 = try cursor.readMegaNum(width: 3, name: "1T.x0")
            let y0 = try cursor.readMegaNum(width: 3, name: "1T.y0")
            let x1 = try cursor.readMegaNum(width: 3, name: "1T.x1")
            let y1 = try cursor.readMegaNum(width: 3, name: "1T.y1")
            let res = try cursor.readMegaNum(width: 2, name: "1T.reserved")
            commands.append(.beginText(x0: x0, y0: y0, x1: x1, y1: y1, reserved: res))

        case (1, "t"):
            let flags = try cursor.readMegaNum(width: 2, name: "1t.flags")
            let s = cursor.readStringToEndOfSegment()
            commands.append(.regionText(flags: flags, string: s))

        case (1, "E"):
            commands.append(.endText)

        case (1, "G"):
            let (x0, y0, x1, y1) = try cursor.readRect3(prefix: "1G")
            let res = try cursor.readMegaNum(width: 2, name: "1G.reserved")
            commands.append(.getImage(x0: x0, y0: y0, x1: x1, y1: y1, reserved: res))

        case (1, "P"):
            let x = try cursor.readMegaNum(width: 3, name: "1P.x")
            let y = try cursor.readMegaNum(width: 3, name: "1P.y")
            let mode = try cursor.readMegaNum(width: 1, name: "1P.mode")
            let res = try cursor.readMegaNum(width: 2, name: "1P.reserved")
            commands.append(.putImage(x: x, y: y, mode: mode, reserved: res))

        case (1, "W"):
            let s = cursor.readStringToEndOfSegment()
            commands.append(.writeIcon(filename: s))

        case (1, "I"):
            let x = try cursor.readMegaNum(width: 3, name: "1I.x")
            let y = try cursor.readMegaNum(width: 3, name: "1I.y")
            let mode = try cursor.readMegaNum(width: 1, name: "1I.mode")
            let cb = try cursor.readMegaNum(width: 1, name: "1I.clipboard")
            let res = try cursor.readMegaNum(width: 2, name: "1I.reserved")
            let s = cursor.readStringToEndOfSegment()
            commands.append(.loadIcon(x: x, y: y, mode: mode, clipboard: cb, reserved: res, filename: s))

        case (1, "B"):
            let w = try cursor.readMegaNum(width: 3, name: "1B.w")
            let h = try cursor.readMegaNum(width: 3, name: "1B.h")
            let or = try cursor.readMegaNum(width: 2, name: "1B.orient")
            let fl = try cursor.readMegaNum(width: 4, name: "1B.flags")
            let bv = try cursor.readMegaNum(width: 2, name: "1B.bevel")
            let df = try cursor.readMegaNum(width: 2, name: "1B.dfore")
            let db = try cursor.readMegaNum(width: 2, name: "1B.dback")
            let br = try cursor.readMegaNum(width: 2, name: "1B.bright")
            let dk = try cursor.readMegaNum(width: 2, name: "1B.dark")
            let su = try cursor.readMegaNum(width: 2, name: "1B.surface")
            let gb = try cursor.readMegaNum(width: 2, name: "1B.gborder")
            let gc = try cursor.readMegaNum(width: 2, name: "1B.gcorner")
            let ul = try cursor.readMegaNum(width: 2, name: "1B.uline")
            let co = try cursor.readMegaNum(width: 2, name: "1B.corner")
            let re = try cursor.readMegaNum(width: 2, name: "1B.reserved")
            let label = cursor.readStringToEndOfSegment()
            commands.append(.buttonStyle(width: w, height: h, orientation: or, flags: fl, bevelSize: bv, dfore: df, dback: db, bright: br, dark: dk, surface: su, gborder: gb, gcorner: gc, uline: ul, corner: co, reserved: re, label: label))

        case (1, "U"):
            let x0 = try cursor.readMegaNum(width: 3, name: "1U.x0")
            let y0 = try cursor.readMegaNum(width: 3, name: "1U.y0")
            let x1 = try cursor.readMegaNum(width: 3, name: "1U.x1")
            let y1 = try cursor.readMegaNum(width: 3, name: "1U.y1")
            let hk = try cursor.readMegaNum(width: 2, name: "1U.hotkey")
            let fl = try cursor.readMegaNum(width: 3, name: "1U.flags")
            let lb = cursor.readStringToEndOfSegment()
            commands.append(.button(x0: x0, y0: y0, x1: x1, y1: y1, hotkey: hk, flags: fl, label: lb))

        case (1, "D"):
            let id = try cursor.readMegaNum(width: 3, name: "1D.id")
            let fl = try cursor.readMegaNum(width: 2, name: "1D.flags")
            let s = cursor.readStringToEndOfSegment()
            commands.append(.define(id: id, flags: fl, string: s))

        case (1, "?"):
            let fl = try cursor.readMegaNum(width: 2, name: "1?.flags")
            let s = cursor.readStringToEndOfSegment()
            commands.append(.query(flags: fl, string: s))

        case (1, "C"):
            let x0 = try cursor.readMegaNum(width: 3, name: "1C.x0")
            let y0 = try cursor.readMegaNum(width: 3, name: "1C.y0")
            let x1 = try cursor.readMegaNum(width: 3, name: "1C.x1")
            let y1 = try cursor.readMegaNum(width: 3, name: "1C.y1")
            let dp = try cursor.readMegaNum(width: 1, name: "1C.destPage")
            let dx = try cursor.readMegaNum(width: 3, name: "1C.destX")
            let dy = try cursor.readMegaNum(width: 3, name: "1C.destY")
            commands.append(.copyRegion(x0: x0, y0: y0, x1: x1, y1: y1, destPage: dp, destX: dx, destY: dy))

        case (1, "R"):
            let s = cursor.readStringToEndOfSegment()
            commands.append(.readScene(filename: s))

        case (1, "F"):
            let name = cursor.readStringToPipe()
            let res = try cursor.readMegaNum(width: 2, name: "1F.reserved")
            commands.append(.fileQuery(filename: name, reserved: res))

        // MARK: Level 9

        case (9, "<"):
            let mode = try cursor.readMegaNum(width: 1, name: "9<.mode")
            let ft = try cursor.readMegaNum(width: 2, name: "9<.filetype")
            let res = try cursor.readMegaNum(width: 4, name: "9<.reserved")
            let name = cursor.readStringToEndOfSegment()
            commands.append(.enterBlockMode(mode: mode, fileType: ft, reserved: res, filename: name))

        case (9, "N"):
            // Optional `oMore` mnemonic; tolerate either bare `9N` (rare) or
            // the full `9NoMore` form.
            cursor.skipLiteral("oMore")
            commands.append(.noMore)

        default:
            // Unknown / reserved — read to end-of-segment (next unescaped
            // `|` if any). Surface for diagnostics without aborting.
            let raw = cursor.readStringToEndOfSegment()
            commands.append(.unknown(level: level, char: cmdChar, raw: raw))
        }
    }
}

// MARK: - PayloadCursor

/// Mutable scanner over one RIP-line's payload. The cursor walks scalars
/// rather than `Character`s so multi-byte grapheme clusters (notably CRLF)
/// don't merge into one element. The tokenizer pre-folds line breaks
/// before any cursor walks the payload, so the payload here is one
/// continuous stream.
struct PayloadCursor {
    private let scalars: [Unicode.Scalar]
    private(set) var index: Int = 0
    let baseOffset: Int

    init(payload: String, baseOffset: Int) {
        self.scalars = Array(payload.unicodeScalars)
        self.baseOffset = baseOffset
    }

    var isAtEnd: Bool { index >= scalars.count }
    var remaining: Int { scalars.count - index }
    var absoluteOffset: Int { baseOffset + index }

    mutating func advance(_ k: Int = 1) {
        index = Swift.min(index + k, scalars.count)
    }

    func peek() -> Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    mutating func skipSpaces() {
        while index < scalars.count, scalars[index] == " " || scalars[index] == "\t" {
            index += 1
        }
    }

    mutating func skipLiteral(_ literal: String) {
        let lit = Array(literal.unicodeScalars)
        guard index + lit.count <= scalars.count else { return }
        for i in 0..<lit.count {
            if scalars[index + i] != lit[i] { return }
        }
        index += lit.count
    }

    /// Read a fixed-width MegaNum field.
    mutating func readMegaNum(width: Int, name: String) throws -> Int {
        if remaining < width {
            let ch: Character = name.first ?? "?"
            throw RIPParseError.truncated(commandChar: ch, atOffset: absoluteOffset)
        }
        let slice = scalars[index..<index + width]
        index += width
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        let str = String(view)
        do {
            return try MegaNum.decode(Substring(str), width: width)
        } catch let e as MegaNum.DecodeError {
            switch e {
            case .widthMismatch(let exp, let got):
                throw RIPParseError.widthMismatch(expected: exp, got: got)
            case .invalidDigit:
                throw RIPParseError.invalidMegaNum(text: str)
            }
        }
    }

    /// Helper for the very common 4×3-digit rect args.
    mutating func readRect3(prefix: String) throws -> (Int, Int, Int, Int) {
        let x0 = try readMegaNum(width: 3, name: "\(prefix).x0")
        let y0 = try readMegaNum(width: 3, name: "\(prefix).y0")
        let x1 = try readMegaNum(width: 3, name: "\(prefix).x1")
        let y1 = try readMegaNum(width: 3, name: "\(prefix).y1")
        return (x0, y0, x1, y1)
    }

    /// Read a polygon-style point list: 2-digit count followed by `count`
    /// (x:MN3, y:MN3) pairs.
    mutating func readPointList(prefix: String) throws -> [RIPPoint] {
        let count = try readMegaNum(width: 2, name: "\(prefix).count")
        var pts: [RIPPoint] = []
        pts.reserveCapacity(count)
        for i in 0..<count {
            let x = try readMegaNum(width: 3, name: "\(prefix).x\(i)")
            let y = try readMegaNum(width: 3, name: "\(prefix).y\(i)")
            pts.append(RIPPoint(x: x, y: y))
        }
        return pts
    }

    /// Read the rest of the payload up to (but not including) the next
    /// unescaped `|`, or to end-of-payload. Consumes the `|`. Un-escapes
    /// `\!`, `\|`, `\\` as it goes; all other `\X` sequences pass through.
    mutating func readStringToPipe() -> String {
        readString(consumeTerminator: true)
    }

    /// Read the rest of the payload to end-of-segment (a terminating `|`
    /// emitted by the tokenizer, or end-of-line). Consumes the terminator.
    mutating func readStringToEndOfSegment() -> String {
        readString(consumeTerminator: true)
    }

    private mutating func readString(consumeTerminator: Bool) -> String {
        var out: [Unicode.Scalar] = []
        let bs: Unicode.Scalar = Unicode.Scalar(0x5C)!
        let pipe: Unicode.Scalar = Unicode.Scalar(0x7C)!
        while index < scalars.count {
            let s = scalars[index]
            if s == bs, index + 1 < scalars.count {
                let next = scalars[index + 1]
                if next == bs || next == pipe || next == Unicode.Scalar(0x21)! /* ! */ || next == Unicode.Scalar(0x22)! /* " */ {
                    out.append(next)
                    index += 2
                    continue
                }
                // Unknown escape — pass through unchanged (spec rule).
                out.append(s)
                out.append(next)
                index += 2
                continue
            }
            if s == pipe {
                if consumeTerminator { index += 1 }
                break
            }
            out.append(s)
            index += 1
        }
        var v = String.UnicodeScalarView()
        v.append(contentsOf: out)
        return String(v)
    }
}
