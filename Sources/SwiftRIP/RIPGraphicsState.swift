// RIPGraphicsState — the drawing state a RIPscrip terminal keeps between
// commands (colors, palette, styles, font, windows, cursors).
//
// Initial values follow the state of a freshly reset RIPscrip terminal:
// full-screen 640x350 viewport, full-screen 80x43 text window (8x8 cells),
// default 16-color palette, white (15) drawing and solid white fill, solid
// one-pixel lines, copy write mode and the 8x8 bitmap font at size 1.

import Foundation

/// Drawing state of a RIPscrip rendering session.
///
/// The renderer mutates this value as it executes commands; the final state
/// is returned in ``RIPRenderResult/state``. All properties are read-only to
/// clients so the renderer's invariants (16-entry palette, thickness 1 or 3,
/// clamped ranges) always hold.
public struct RIPGraphicsState: Equatable, Sendable {

    /// Drawing color (palette index 0...15) used for outlines and text.
    public internal(set) var drawColor: UInt8 = 15
    /// Fill color (palette index 0...15) for the set bits of the fill pattern.
    public internal(set) var fillColor: UInt8 = 15
    /// The 16-entry active palette; each entry is a master-palette value
    /// (0...63) resolved through ``RIPPalette/master``.
    public internal(set) var palette: [UInt8] = RIPPalette.default16
    /// Current fill pattern.
    public internal(set) var fillPattern: RIPFillPattern = .predefined(1)
    /// Current line style.
    public internal(set) var lineStyle: RIPLineStyle = .predefined(0)
    /// Line thickness in pixels: 1 (normal) or 3 (thick).
    public internal(set) var lineThickness: Int = 1
    /// Write mode for lines, rectangles, polygons, Beziers and text.
    public internal(set) var writeMode: RIPWriteMode = .copy
    /// Font number: 0 = 8x8 bitmap, 1...10 = scalable stroke fonts.
    public internal(set) var font: Int = 0
    /// Text direction: 0 = horizontal, 1 = vertical (rotated 90 degrees
    /// counter-clockwise, reading bottom to top).
    public internal(set) var fontDirection: Int = 0
    /// Font magnification 1...10.
    public internal(set) var fontSize: Int = 1
    /// Graphics drawing position, relative to the viewport origin.
    public internal(set) var position: RIPPoint = RIPPoint(x: 0, y: 0)
    /// The TTY text window (character cells).
    public internal(set) var textWindow: RIPTextWindow = .fullScreen
    /// Text cursor: 0-based column and row inside ``textWindow``.
    public internal(set) var textCursor: RIPPoint = RIPPoint(x: 0, y: 0)
    /// Graphics viewport in absolute screen pixels.
    public internal(set) var viewport: RIPViewport = .fullScreen
    /// The most recent `1B` RIP_BUTTON_STYLE, if any.
    public internal(set) var buttonStyle: RIPButtonStyle?

    /// Active `1T` text region (absolute pixels) and the top of its next line.
    var textRegion: TextRegion?

    struct TextRegion: Equatable, Sendable {
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
        var nextY: Int
    }

    /// The state of a freshly reset terminal.
    public init() {}
}

/// A fill pattern: one of the twelve predefined RIPscrip patterns or a
/// custom 8x8 pattern from `s` RIP_FILL_PATTERN.
public enum RIPFillPattern: Equatable, Sendable {
    /// Predefined pattern 0...11 (see ``predefinedRows``); other values
    /// render as solid.
    case predefined(Int)
    /// Eight row bytes, top row first, most-significant bit leftmost.
    case custom([UInt8])

    /// The pattern's eight row bytes.
    public var rows: [UInt8] {
        switch self {
        case .predefined(let index):
            return RIPFillPattern.predefinedRows[(0...11).contains(index) ? index : 1]
        case .custom(let bytes):
            var rows = Array(bytes.prefix(8))
            while rows.count < 8 { rows.append(0) }
            return rows
        }
    }

    /// Row bytes of the twelve predefined patterns, exactly as tabulated in
    /// the RIPscrip 1.54 RIP_FILL_STYLE section.
    public static let predefinedRows: [[UInt8]] = [
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // 00 background
        [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], // 01 solid
        [0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00], // 02 line
        [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80], // 03 light slash
        [0xE0, 0xC1, 0x83, 0x07, 0x0E, 0x1C, 0x38, 0x70], // 04 normal slash
        [0xF0, 0x78, 0x3C, 0x1E, 0x0F, 0x87, 0xC3, 0xE1], // 05 normal backslash
        [0xA5, 0xD2, 0x69, 0xB4, 0x5A, 0x2D, 0x96, 0x4B], // 06 light backslash
        [0xFF, 0x88, 0x88, 0x88, 0xFF, 0x88, 0x88, 0x88], // 07 light hatch
        [0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81], // 08 heavy cross hatch
        [0xCC, 0x33, 0xCC, 0x33, 0xCC, 0x33, 0xCC, 0x33], // 09 interleaving line
        [0x80, 0x00, 0x08, 0x00, 0x80, 0x00, 0x08, 0x00], // 0A widely spaced dot
        [0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00]  // 0B closely spaced dot
    ]
}

/// A line style: one of the four predefined patterns or a custom 16-bit
/// pattern (style 4).
public enum RIPLineStyle: Equatable, Sendable {
    /// Predefined style: 0 solid, 1 dotted, 2 centered, 3 dashed.
    case predefined(Int)
    /// Custom 16-bit pattern; the most-significant bit is plotted first.
    case user(UInt16)

    /// The 16-bit pixel mask, most-significant bit first along the line.
    public var mask: UInt16 {
        switch self {
        case .predefined(1): return 0x3333
        case .predefined(2): return 0x1E3F
        case .predefined(3): return 0x1F1F
        case .predefined: return 0xFFFF
        case .user(let m): return m
        }
    }
}

/// How a primitive combines with the pixels already on screen.
public enum RIPWriteMode: Equatable, Sendable {
    /// Replace the destination pixel (`W00`).
    case copy
    /// XOR the palette index with the destination (`W01`); drawing the same
    /// primitive twice restores the original pixels.
    case xor

    /// Map a RIP_WRITE_MODE value: 1 is XOR, anything else is copy.
    /// - Parameter rawValue: The `W` command argument.
    public init(rawValue: Int) {
        self = (rawValue == 1) ? .xor : .copy
    }
}

/// The TTY text window set by `w` RIP_TEXT_WINDOW, in character cells.
public struct RIPTextWindow: Equatable, Sendable {
    /// Left column (inclusive).
    public let x0: Int
    /// Top row (inclusive).
    public let y0: Int
    /// Right column (inclusive).
    public let x1: Int
    /// Bottom row (inclusive).
    public let y1: Int
    /// 1 = wrap and scroll, 0 = truncate.
    public let wrap: Int
    /// Cell size selector 0...4 (8x8, 7x8, 8x14, 7x14, 16x14 pixels).
    public let size: Int

    /// Create a text window value.
    public init(x0: Int, y0: Int, x1: Int, y1: Int, wrap: Int, size: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        self.wrap = wrap
        self.size = size
    }

    /// The full-screen 80x43 window installed by RIP_RESET_WINDOWS.
    public static let fullScreen = RIPTextWindow(x0: 0, y0: 0, x1: 79, y1: 42, wrap: 1, size: 0)

    /// `false` when all four coordinates are zero (window made invisible).
    public var isActive: Bool { !(x0 == 0 && y0 == 0 && x1 == 0 && y1 == 0) }

    /// Character cell size in pixels for ``size`` (out-of-range sizes use 8x8).
    public var cellSize: (width: Int, height: Int) {
        switch size {
        case 1: return (7, 8)
        case 2: return (8, 14)
        case 3: return (7, 14)
        case 4: return (16, 14)
        default: return (8, 8)
        }
    }
}

/// The graphics viewport set by `v` RIP_VIEWPORT.
public enum RIPViewport: Equatable, Sendable {
    /// All-zero viewport: commands that use the viewport are ignored.
    case disabled
    /// Inclusive absolute pixel rectangle; coordinates of viewport commands
    /// are relative to `(x0, y0)` and output is clipped to the rectangle.
    case rect(x0: Int, y0: Int, x1: Int, y1: Int)

    /// The full 640x350 screen.
    public static let fullScreen = RIPViewport.rect(x0: 0, y0: 0, x1: 639, y1: 349)

    /// Build a viewport from `v` arguments: all zeros disables output;
    /// otherwise corners are ordered and clamped to the 640x350 screen.
    public static func from(x0: Int, y0: Int, x1: Int, y1: Int) -> RIPViewport {
        if x0 == 0 && y0 == 0 && x1 == 0 && y1 == 0 { return .disabled }
        func cx(_ v: Int) -> Int { Swift.min(Swift.max(v, 0), 639) }
        func cy(_ v: Int) -> Int { Swift.min(Swift.max(v, 0), 349) }
        return .rect(x0: cx(Swift.min(x0, x1)), y0: cy(Swift.min(y0, y1)),
                     x1: cx(Swift.max(x0, x1)), y1: cy(Swift.max(y0, y1)))
    }
}
