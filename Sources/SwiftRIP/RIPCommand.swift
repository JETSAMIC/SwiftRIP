// RIPCommand — typed representation of every RIPscrip 1.54 command.
//
// Each case captures the spec-declared arguments in their natural Swift types.
// Coordinates are `Int` (RIPscrip has no negative coordinates and no
// fractional values — clipping/rounding is the renderer's job). String
// payloads have already been un-escaped (no `\!`, `\|`, `\\` sequences
// remain) by the parser.
//
// The enum is exhaustive over Levels 0, 1, and 9 of the 1.54 spec. The
// `unknown` case lets the parser surface a reserved/unimplemented command
// byte without aborting the whole scene.

import Foundation

/// A single parsed RIPscrip command, plus an `ansiSense` carrier for the
/// out-of-band ANSI auto-sense escape sequences (see RIPAnsiSequences).
public enum RIPCommand: Equatable, Sendable {

    // MARK: - Level 0: state + drawing

    case textWindow(x0: Int, y0: Int, x1: Int, y1: Int, wrap: Int, size: Int)
    case viewport(x0: Int, y0: Int, x1: Int, y1: Int)
    case resetWindows
    case eraseWindow
    case eraseView
    case gotoXY(x: Int, y: Int)
    case home
    case eraseEOL
    case color(Int)
    /// 16 EGA-register values (0..63), one per palette index.
    case setPalette([Int])
    case onePalette(slot: Int, value: Int)
    case writeMode(Int)
    case move(x: Int, y: Int)
    case text(String)
    case textXY(x: Int, y: Int, string: String)
    case fontStyle(font: Int, direction: Int, size: Int, reserved: Int)
    case pixel(x: Int, y: Int)
    case line(x0: Int, y0: Int, x1: Int, y1: Int)
    case rectangle(x0: Int, y0: Int, x1: Int, y1: Int)
    case bar(x0: Int, y0: Int, x1: Int, y1: Int)
    case circle(x: Int, y: Int, radius: Int)
    case oval(x: Int, y: Int, startAngle: Int, endAngle: Int, xrad: Int, yrad: Int)
    case filledOval(x: Int, y: Int, xrad: Int, yrad: Int)
    case arc(x: Int, y: Int, startAngle: Int, endAngle: Int, radius: Int)
    case ovalArc(x: Int, y: Int, startAngle: Int, endAngle: Int, xrad: Int, yrad: Int)
    case pieSlice(x: Int, y: Int, startAngle: Int, endAngle: Int, radius: Int)
    case ovalPieSlice(x: Int, y: Int, startAngle: Int, endAngle: Int, xrad: Int, yrad: Int)
    case bezier(x0: Int, y0: Int, x1: Int, y1: Int, x2: Int, y2: Int, x3: Int, y3: Int, count: Int)
    case polygon(points: [RIPPoint])
    case fillPolygon(points: [RIPPoint])
    case polyline(points: [RIPPoint])
    case fill(x: Int, y: Int, border: Int)
    case lineStyle(style: Int, userPattern: Int, thickness: Int)
    case fillStyle(pattern: Int, color: Int)
    case fillPattern(bytes: [UInt8], color: Int)

    // MARK: - Level 1: graphical objects

    case mouse(num: Int, x0: Int, y0: Int, x1: Int, y1: Int, click: Int, clear: Int, text: String, hostCommand: String)
    case killMouseFields
    case beginText(x0: Int, y0: Int, x1: Int, y1: Int, reserved: Int)
    case regionText(flags: Int, string: String)
    case endText
    case getImage(x0: Int, y0: Int, x1: Int, y1: Int, reserved: Int)
    case putImage(x: Int, y: Int, mode: Int, reserved: Int)
    case writeIcon(filename: String)
    case loadIcon(x: Int, y: Int, mode: Int, clipboard: Int, reserved: Int, filename: String)
    case buttonStyle(width: Int, height: Int, orientation: Int, flags: Int, bevelSize: Int, dfore: Int, dback: Int, bright: Int, dark: Int, surface: Int, gborder: Int, gcorner: Int, uline: Int, corner: Int, reserved: Int, label: String)
    case button(x0: Int, y0: Int, x1: Int, y1: Int, hotkey: Int, flags: Int, label: String)
    case define(id: Int, flags: Int, string: String)
    case query(flags: Int, string: String)
    case copyRegion(x0: Int, y0: Int, x1: Int, y1: Int, destPage: Int, destX: Int, destY: Int)
    case readScene(filename: String)
    case fileQuery(filename: String, reserved: Int)

    // MARK: - Level 9: system

    case enterBlockMode(mode: Int, fileType: Int, reserved: Int, filename: String)
    case noMore

    // MARK: - Out-of-band

    /// ANSI auto-sense sequence emitted by a BBS host outside the `!|...|`
    /// frame. Parsed and surfaced so a wrapping app can respond appropriately;
    /// has no rendering effect.
    case ansiSense(RIPAnsiSense)

    /// Unknown or reserved command byte. The parser collects level + char +
    /// the raw remaining bytes that would have been arguments (up to the next
    /// unescaped `|` or end-of-line) for downstream inspection.
    case unknown(level: Int, char: Character, raw: String)
}

/// A 2D coordinate pair in native RIPscrip framebuffer space (0..639, 0..349).
public struct RIPPoint: Equatable, Sendable, Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// The four ANSI auto-sense interactions described in the spec.
public enum RIPAnsiSense: Equatable, Sendable {
    /// `ESC[!` — "Do you support any RIPscrip?"
    case query
    /// `ESC[0!` — "Do you support RIPscrip 1.5x?"
    case enable
    /// `ESC[1!` — "Do you support RIPscrip 2.x?"
    case enable2x
    /// `ESC[2!` — "Send your Vendor Code."
    case disable
}

/// A parsed RIPscrip scene — the in-memory result of parsing one input
/// stream. The commands are listed in source order; the renderer's job is to
/// execute them sequentially against a `RIPState`.
public struct RIPScene: Equatable, Sendable {
    public let commands: [RIPCommand]

    public init(commands: [RIPCommand]) {
        self.commands = commands
    }
}
