// RIPGraphicsState — mutable drawing state for a RIP rendering session.
//
// Every primitive in the spec lists which state fields it consumes ("Uses
// Draw Color", "Uses Line Pattern", "Uses Fill Pattern", "Uses Write Mode",
// "Uses Viewport", etc.). This struct collects all of those into a single
// value that the interpreter mutates as it walks a `RIPScene` and that
// primitives read from before plotting pixels.
//
// All defaults match the spec's "initial state on a fresh RIP terminal":
//   * Draw color = 15 (white in the default palette)
//   * Fill color = 15, fill pattern = solid (index 1)
//   * Line style = solid (index 0), thickness = 1, user pattern = 0xFFFF
//   * Write mode = copy (0)
//   * Font = 0 (8x8 bitmap), direction = horizontal (0), size = 1
//   * Current draw position = (0, 0)
//   * Palette = the default 16-color RIP palette (see `RIPPalette.default16`)
//   * Text window = (0, 0, 639, 349), wrap = on, line-size = 0
//   * Viewport = disabled (0, 0, 0, 0 sentinel)

import Foundation

/// Run-time graphics state for a RIPscrip rendering session. Mutated by the
/// interpreter as commands are dispatched, read by primitives at draw time.
public struct RIPGraphicsState: Equatable, Sendable {

    // MARK: - Colors

    /// Current drawing/line color (0..15 palette index).
    public var drawColor: UInt8 = 15

    /// Current fill color (0..15 palette index).
    public var fillColor: UInt8 = 15

    /// 16-color active palette. Each entry is one of the 64 EGA master
    /// register values; the renderer resolves through `RIPPalette.master`.
    public var palette: [UInt8] = RIPPalette.default16

    // MARK: - Fill

    /// Predefined fill pattern (0..11) per spec, or `.custom` for an 8-byte
    /// pattern set by `fillPattern`.
    public var fillPattern: RIPFillPattern = .predefined(1) // solid

    // MARK: - Line

    /// Line style. Predefined index (0..3) or user pattern (index 4) with a
    /// 16-bit mask.
    public var lineStyle: RIPLineStyle = .predefined(0)

    /// Line thickness in pixels (1 = normal, 3 = thick per spec; other values
    /// rendered as plotted-square brush of that diameter).
    public var lineThickness: Int = 1

    // MARK: - Raster

    /// Pixel write mode. Copy = source replaces dest. XOR = source XORed
    /// against dest (returns to original on a second draw).
    public var writeMode: RIPWriteMode = .copy

    // MARK: - Text

    /// Font index 0..0xA. 0 = 8x8 bitmap, 1..A = stroked vector fonts.
    public var font: Int = 0

    /// 0 = horizontal, 1 = vertical (90deg CCW).
    public var fontDirection: Int = 0

    /// Font scale factor 1..10. Size 1 = native; size N multiplies both axes
    /// by N (vector) or selects nearest bitmap multiple (bitmap).
    public var fontSize: Int = 1

    // MARK: - Cursor

    /// Current draw position (used by `text`, `line` continuations, etc.).
    public var position: RIPPoint = .init(x: 0, y: 0)

    // MARK: - Windows

    /// Text-mode window in character cells: x0..x1, y0..y1 (char coords).
    /// Word-wrap flag and line spacing follow the spec's `w` command.
    public var textWindow: RIPTextWindow = .init(x0: 0, y0: 0, x1: 79, y1: 24, wrap: 1, size: 0)

    /// Graphics viewport. `(0,0,0,0)` is the spec sentinel meaning "viewport
    /// disabled, full 640x350 framebuffer is clip rect".
    public var viewport: RIPViewport = .disabled

    // MARK: - Lifecycle

    public init() {}

    /// Reset to the spec's "RESET_WINDOWS" state — full-screen text window,
    /// disabled viewport, default 16-color palette, default colors.
    public mutating func resetWindows() {
        self = RIPGraphicsState()
    }
}

/// Spec-defined fill pattern selector. Either a predefined index (0..11) or
/// a user-supplied 8-byte raster pattern.
public enum RIPFillPattern: Equatable, Sendable {
    case predefined(Int)
    case custom([UInt8])
}

/// Spec-defined line style. Either a predefined index (solid=0, dotted=1,
/// center=2, dashed=3) or a user 16-bit pattern (index 4 with 16-bit mask).
public enum RIPLineStyle: Equatable, Sendable {
    case predefined(Int)
    case user(UInt16)
}

/// Pixel write mode. Spec uses 0=copy, 1=XOR.
public enum RIPWriteMode: Equatable, Sendable {
    case copy
    case xor

    public init(rawValue: Int) {
        self = (rawValue == 1) ? .xor : .copy
    }
}

/// Text-mode window settings (`w` command).
public struct RIPTextWindow: Equatable, Sendable {
    public var x0: Int
    public var y0: Int
    public var x1: Int
    public var y1: Int
    public var wrap: Int
    public var size: Int
}

/// Graphics viewport (`v` command). `disabled` is the spec sentinel
/// `(0,0,0,0)`.
public enum RIPViewport: Equatable, Sendable {
    case disabled
    case rect(x0: Int, y0: Int, x1: Int, y1: Int)

    /// Convert a spec `v` arg tuple into a viewport, applying the `(0,0,0,0)`
    /// sentinel rule.
    public static func from(x0: Int, y0: Int, x1: Int, y1: Int) -> RIPViewport {
        if x0 == 0 && y0 == 0 && x1 == 0 && y1 == 0 {
            return .disabled
        }
        return .rect(x0: x0, y0: y0, x1: x1, y1: y1)
    }

    /// Clip rectangle in framebuffer coordinates. For `.disabled`, this is
    /// the full 640x350 canvas.
    public func clipRect() -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        switch self {
        case .disabled:
            return (0, 0, 639, 349)
        case .rect(let x0, let y0, let x1, let y1):
            return (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
        }
    }
}
