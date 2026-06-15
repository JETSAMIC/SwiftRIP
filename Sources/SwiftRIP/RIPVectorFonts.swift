// RIPVectorFonts — bitmap font 0 (8x8) and clean-room vector fonts 1..A.
//
// The RIPscrip spec inherits Borland's BGI font model: font 0 is an 8x8
// bitmap, fonts 1..A are stroked vector fonts (Triplex, Small, SansSerif,
// Gothic, Script, Simplex, TriplexScript, Complex, European, Bold).
//
// We do NOT copy the BGI .CHR data or any other implementation's glyph
// definitions. This file contains a clean-room synthesis:
//
//   * Font 0 — a compact ASCII 32..126 bitmap, hand-drawn in 8x8 cells,
//     loosely resembling the IBM PC 8x8 set in proportions but constructed
//     here for SwiftRIP. Public-domain authorship.
//
//   * Fonts 1..A — each is built from a small per-glyph stroke list (move/
//     line) over a 21x21 normalized cell. Family identity is encoded by a
//     per-family stroke-style transform applied on render:
//
//        Triplex (1)       — double-stroked (parallel offset) for weight
//        Small (2)         — half-height
//        SansSerif (3)     — single stroke, no embellishments
//        Gothic (4)        — single stroke, with vertical accent
//        Script (5)        — italic slant
//        Simplex (6)       — single stroke (alias of SansSerif)
//        TriplexScript (7) — italic slant + double stroke
//        Complex (8)       — double stroke
//        European (9)      — italic slant + accent
//        Bold (A=10)       — quad-stroke (thicker)
//
//   The base stroke set covers ASCII 32..126 with simple line geometry — the
//   priority is "renders as the right letter shape", not perfect typography.
//   Vector text per the spec scales by an integer factor 1..10; size N
//   multiplies the 21x21 cell by N.

import Foundation
import CoreGraphics

/// Public stroke-font interface. Stateless; reads font index/size off the
/// graphics state at call time.
public enum RIPVectorFonts {

    /// Render a string into `canvas` at `p`, using state's font, direction,
    /// size, and color.
    public static func renderText(_ s: String, at p: CGPoint, font: Int, direction: Int, size: Int, color: UInt8, into canvas: RIPCanvas, state: RIPGraphicsState) {
        var pen = CGPoint(x: p.x, y: p.y)
        let scale = max(1, min(10, size))
        let (advance, cellH) = font == 0
            ? (8 * scale, 8 * scale)
            : (12 * scale, 21 * scale)
        for ch in s.unicodeScalars {
            let code = Int(ch.value)
            guard (32...126).contains(code) else {
                pen = step(pen, dx: advance, dy: 0, direction: direction)
                continue
            }
            if font == 0 {
                renderBitmapGlyph(code: code, at: pen, scale: scale, direction: direction, color: color, into: canvas, state: state, cellH: cellH)
            } else {
                renderVectorGlyph(code: code, at: pen, font: font, scale: scale, direction: direction, color: color, into: canvas, state: state)
            }
            pen = step(pen, dx: advance, dy: 0, direction: direction)
        }
    }

    private static func step(_ p: CGPoint, dx: Int, dy: Int, direction: Int) -> CGPoint {
        if direction == 0 {
            return CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy))
        } else {
            // Vertical text: positive X advance becomes negative Y (text
            // grows upward).
            return CGPoint(x: p.x + CGFloat(dy), y: p.y - CGFloat(dx))
        }
    }

    // MARK: - Bitmap font 0

    private static func renderBitmapGlyph(code: Int, at p: CGPoint, scale: Int, direction: Int, color: UInt8, into canvas: RIPCanvas, state: RIPGraphicsState, cellH: Int) {
        let glyph = bitmap8x8[code - 32]
        let ox = Int(p.x.rounded())
        let oy = Int(p.y.rounded())
        for row in 0..<8 {
            let bits = glyph[row]
            for col in 0..<8 {
                if (bits >> (7 - col)) & 1 == 0 { continue }
                let dx = col * scale
                let dy = row * scale
                for sy in 0..<scale {
                    for sx in 0..<scale {
                        let (px, py): (Int, Int)
                        if direction == 0 {
                            px = ox + dx + sx
                            py = oy + dy + sy
                        } else {
                            px = ox + dy + sy
                            py = oy - dx - sx
                        }
                        canvas.setPixel(x: px, y: py, color: color, state: state)
                    }
                }
            }
        }
    }

    // MARK: - Vector glyph dispatch

    private static func renderVectorGlyph(code: Int, at p: CGPoint, font: Int, scale: Int, direction: Int, color: UInt8, into canvas: RIPCanvas, state: RIPGraphicsState) {
        let strokes = vectorStrokes[code - 32]
        let ox = Int(p.x.rounded())
        let oy = Int(p.y.rounded())

        // Per-family transforms.
        let italic: Double
        let extraStrokes: Int
        switch font {
        case 1: italic = 0; extraStrokes = 1            // Triplex
        case 2: italic = 0; extraStrokes = 0            // Small
        case 3: italic = 0; extraStrokes = 0            // SansSerif
        case 4: italic = 0; extraStrokes = 0            // Gothic
        case 5: italic = 0.30; extraStrokes = 0         // Script
        case 6: italic = 0; extraStrokes = 0            // Simplex
        case 7: italic = 0.30; extraStrokes = 1         // TriplexScript
        case 8: italic = 0; extraStrokes = 1            // Complex
        case 9: italic = 0.20; extraStrokes = 0         // European
        case 10: italic = 0; extraStrokes = 2           // Bold
        default: italic = 0; extraStrokes = 0
        }

        // Font 2 (Small) — half height.
        let yScale = (font == 2) ? Double(scale) * 0.5 : Double(scale)
        let xScale = Double(scale)

        for stroke in strokes {
            // stroke is [x0,y0,x1,y1] in 21x21 cell coords.
            for offset in 0...extraStrokes {
                let dxOff = offset // parallel-line offset
                let (sx0, sy0) = transform(x: stroke[0], y: stroke[1], xScale: xScale, yScale: yScale, italic: italic, dxOff: dxOff)
                let (sx1, sy1) = transform(x: stroke[2], y: stroke[3], xScale: xScale, yScale: yScale, italic: italic, dxOff: dxOff)
                let (a, b) = orient(x: sx0, y: sy0, direction: direction)
                let (c, d) = orient(x: sx1, y: sy1, direction: direction)
                canvas.drawLine(x0: ox + a, y0: oy + b, x1: ox + c, y1: oy + d, color: color, state: state)
            }
        }
    }

    private static func transform(x: Int, y: Int, xScale: Double, yScale: Double, italic: Double, dxOff: Int) -> (Int, Int) {
        // y origin is top of cell. Italic shears top of cell to the right.
        let shear = italic * Double(20 - y)
        let sx = Int((Double(x) * xScale + shear * xScale).rounded()) + dxOff
        let sy = Int((Double(y) * yScale).rounded())
        return (sx, sy)
    }

    private static func orient(x: Int, y: Int, direction: Int) -> (Int, Int) {
        if direction == 0 { return (x, y) }
        return (y, -x)
    }

    // MARK: - Glyph data

    /// 8x8 bitmap glyphs for ASCII 32..126. Each glyph is 8 bytes, each byte
    /// is one row top-to-bottom, MSB-first within the byte (bit 7 = leftmost
    /// pixel). Clean-room authored for SwiftRIP, public domain.
    static let bitmap8x8: [[UInt8]] = {
        var t: [[UInt8]] = Array(repeating: [0,0,0,0,0,0,0,0], count: 95)
        // Helper: assign by ASCII.
        func set(_ ascii: Int, _ rows: [UInt8]) {
            t[ascii - 32] = rows
        }
        // 32 space
        set(32, [0,0,0,0,0,0,0,0])
        set(33, [0x18,0x18,0x18,0x18,0x18,0,0x18,0])           // !
        set(34, [0x66,0x66,0x66,0,0,0,0,0])                     // "
        set(35, [0x66,0x66,0xFF,0x66,0xFF,0x66,0x66,0])         // #
        set(36, [0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0])         // $
        set(37, [0x62,0x66,0x0C,0x18,0x30,0x66,0x46,0])         // %
        set(38, [0x3C,0x66,0x3C,0x38,0x67,0x66,0x3F,0])         // &
        set(39, [0x18,0x18,0x30,0,0,0,0,0])                     // '
        set(40, [0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0])         // (
        set(41, [0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0])         // )
        set(42, [0,0x66,0x3C,0xFF,0x3C,0x66,0,0])               // *
        set(43, [0,0x18,0x18,0x7E,0x18,0x18,0,0])               // +
        set(44, [0,0,0,0,0,0x18,0x18,0x30])                     // ,
        set(45, [0,0,0,0x7E,0,0,0,0])                           // -
        set(46, [0,0,0,0,0,0x18,0x18,0])                        // .
        set(47, [0,0x03,0x06,0x0C,0x18,0x30,0x60,0])            // /
        // digits 0..9
        set(48, [0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0])
        set(49, [0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0])
        set(50, [0x3C,0x66,0x06,0x1C,0x30,0x60,0x7E,0])
        set(51, [0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0])
        set(52, [0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0])
        set(53, [0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0])
        set(54, [0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0])
        set(55, [0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0])
        set(56, [0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0])
        set(57, [0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0])
        set(58, [0,0x18,0x18,0,0x18,0x18,0,0])                  // :
        set(59, [0,0x18,0x18,0,0x18,0x18,0x30,0])               // ;
        set(60, [0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0])         // <
        set(61, [0,0,0x7E,0,0x7E,0,0,0])                        // =
        set(62, [0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0])         // >
        set(63, [0x3C,0x66,0x06,0x0C,0x18,0,0x18,0])            // ?
        set(64, [0x3C,0x66,0x6E,0x6E,0x60,0x62,0x3C,0])         // @
        // A..Z
        set(65, [0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0])
        set(66, [0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0])
        set(67, [0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0])
        set(68, [0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0])
        set(69, [0x7E,0x60,0x60,0x78,0x60,0x60,0x7E,0])
        set(70, [0x7E,0x60,0x60,0x78,0x60,0x60,0x60,0])
        set(71, [0x3C,0x66,0x60,0x6E,0x66,0x66,0x3C,0])
        set(72, [0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0])
        set(73, [0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0])
        set(74, [0x1E,0x0C,0x0C,0x0C,0x0C,0x6C,0x38,0])
        set(75, [0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0])
        set(76, [0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0])
        set(77, [0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0])
        set(78, [0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0])
        set(79, [0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0])
        set(80, [0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0])
        set(81, [0x3C,0x66,0x66,0x66,0x6A,0x6C,0x36,0])
        set(82, [0x7C,0x66,0x66,0x7C,0x78,0x6C,0x66,0])
        set(83, [0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0])
        set(84, [0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0])
        set(85, [0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0])
        set(86, [0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0])
        set(87, [0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0])
        set(88, [0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0])
        set(89, [0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0])
        set(90, [0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0])
        set(91, [0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0])         // [
        set(92, [0,0x60,0x30,0x18,0x0C,0x06,0x03,0])            // backslash
        set(93, [0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0])         // ]
        set(94, [0x18,0x3C,0x66,0,0,0,0,0])                     // ^
        set(95, [0,0,0,0,0,0,0,0x7E])                           // _
        set(96, [0x30,0x18,0,0,0,0,0,0])                        // `
        // a..z (same shapes as uppercase, smaller — clean-room compact)
        set(97, [0,0,0x3C,0x06,0x3E,0x66,0x3E,0])
        set(98, [0x60,0x60,0x7C,0x66,0x66,0x66,0x7C,0])
        set(99, [0,0,0x3C,0x66,0x60,0x66,0x3C,0])
        set(100, [0x06,0x06,0x3E,0x66,0x66,0x66,0x3E,0])
        set(101, [0,0,0x3C,0x66,0x7E,0x60,0x3C,0])
        set(102, [0x0E,0x18,0x3E,0x18,0x18,0x18,0x18,0])
        set(103, [0,0,0x3E,0x66,0x66,0x3E,0x06,0x3C])
        set(104, [0x60,0x60,0x7C,0x66,0x66,0x66,0x66,0])
        set(105, [0x18,0,0x38,0x18,0x18,0x18,0x3C,0])
        set(106, [0x06,0,0x06,0x06,0x06,0x06,0x66,0x3C])
        set(107, [0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0])
        set(108, [0x38,0x18,0x18,0x18,0x18,0x18,0x3C,0])
        set(109, [0,0,0x66,0x7F,0x6B,0x6B,0x63,0])
        set(110, [0,0,0x7C,0x66,0x66,0x66,0x66,0])
        set(111, [0,0,0x3C,0x66,0x66,0x66,0x3C,0])
        set(112, [0,0,0x7C,0x66,0x66,0x7C,0x60,0x60])
        set(113, [0,0,0x3E,0x66,0x66,0x3E,0x06,0x06])
        set(114, [0,0,0x6C,0x76,0x60,0x60,0x60,0])
        set(115, [0,0,0x3E,0x60,0x3C,0x06,0x7C,0])
        set(116, [0x18,0x18,0x3E,0x18,0x18,0x18,0x0E,0])
        set(117, [0,0,0x66,0x66,0x66,0x66,0x3E,0])
        set(118, [0,0,0x66,0x66,0x66,0x3C,0x18,0])
        set(119, [0,0,0x63,0x6B,0x6B,0x7F,0x36,0])
        set(120, [0,0,0x66,0x3C,0x18,0x3C,0x66,0])
        set(121, [0,0,0x66,0x66,0x66,0x3E,0x06,0x3C])
        set(122, [0,0,0x7E,0x0C,0x18,0x30,0x7E,0])
        set(123, [0x0E,0x18,0x18,0x30,0x18,0x18,0x0E,0])        // {
        set(124, [0x18,0x18,0x18,0x18,0x18,0x18,0x18,0])        // |
        set(125, [0x70,0x18,0x18,0x0C,0x18,0x18,0x70,0])        // }
        set(126, [0x32,0x4C,0,0,0,0,0,0])                       // ~
        return t
    }()

    /// Vector stroke set for ASCII 32..126. Each entry is a list of
    /// `[x0,y0,x1,y1]` strokes in a 0..20 cell. Clean-room authored — simple
    /// monoline glyph outlines. Per-family weight/italic is applied by the
    /// renderer.
    static let vectorStrokes: [[[Int]]] = {
        var g: [[[Int]]] = Array(repeating: [], count: 95)
        func set(_ ch: Int, _ s: [[Int]]) { g[ch - 32] = s }
        // Space
        set(32, [])
        // ! — vertical stroke + dot
        set(33, [[8,2,8,14],[8,17,8,18]])
        // "
        set(34, [[5,2,5,6],[11,2,11,6]])
        // #
        set(35, [[5,2,3,18],[13,2,11,18],[2,8,16,8],[2,12,16,12]])
        // $
        set(36, [[8,0,8,20],[14,4,4,4],[4,4,4,10],[4,10,14,10],[14,10,14,16],[14,16,4,16]])
        // %
        set(37, [[4,2,4,6],[6,2,6,6],[4,2,6,2],[4,6,6,6],[2,18,16,2],[12,14,12,18],[14,14,14,18],[12,14,14,14],[12,18,14,18]])
        // &
        set(38, [[14,18,4,8],[4,8,4,4],[4,4,8,2],[8,2,12,4],[12,4,12,8],[12,8,4,14],[4,14,4,18],[4,18,10,18],[10,18,14,14]])
        // '
        set(39, [[8,2,8,6]])
        // (
        set(40, [[12,0,4,10],[4,10,12,20]])
        // )
        set(41, [[4,0,12,10],[12,10,4,20]])
        // *
        set(42, [[8,4,8,16],[3,7,13,13],[13,7,3,13]])
        // +
        set(43, [[8,4,8,16],[2,10,14,10]])
        // ,
        set(44, [[8,16,8,18],[8,18,6,20]])
        // -
        set(45, [[2,10,14,10]])
        // .
        set(46, [[8,16,8,18]])
        // /
        set(47, [[16,2,2,18]])
        // 0
        set(48, [[6,2,10,2],[10,2,14,6],[14,6,14,14],[14,14,10,18],[10,18,6,18],[6,18,2,14],[2,14,2,6],[2,6,6,2]])
        // 1
        set(49, [[6,4,10,2],[10,2,10,18],[6,18,14,18]])
        // 2
        set(50, [[2,4,8,2],[8,2,14,4],[14,4,14,8],[14,8,2,18],[2,18,14,18]])
        // 3
        set(51, [[2,4,8,2],[8,2,14,4],[14,4,8,10],[8,10,14,14],[14,14,8,18],[8,18,2,16]])
        // 4
        set(52, [[12,2,2,14],[2,14,14,14],[12,2,12,18]])
        // 5
        set(53, [[14,2,4,2],[4,2,4,10],[4,10,10,10],[10,10,14,12],[14,12,14,16],[14,16,8,18],[8,18,2,16]])
        // 6
        set(54, [[14,4,8,2],[8,2,4,6],[4,6,4,16],[4,16,8,18],[8,18,12,18],[12,18,14,14],[14,14,12,10],[12,10,4,10]])
        // 7
        set(55, [[2,2,14,2],[14,2,6,18]])
        // 8
        set(56, [[6,2,10,2],[10,2,14,6],[14,6,10,10],[10,10,14,14],[14,14,10,18],[10,18,6,18],[6,18,2,14],[2,14,6,10],[6,10,2,6],[2,6,6,2]])
        // 9
        set(57, [[14,8,12,2],[12,2,8,2],[8,2,4,4],[4,4,4,8],[4,8,8,10],[8,10,14,8],[14,8,12,18]])
        // :
        set(58, [[8,8,8,9],[8,15,8,16]])
        // ;
        set(59, [[8,8,8,9],[8,15,8,16],[8,16,6,18]])
        // <
        set(60, [[14,4,4,10],[4,10,14,16]])
        // =
        set(61, [[2,8,14,8],[2,12,14,12]])
        // >
        set(62, [[4,4,14,10],[14,10,4,16]])
        // ?
        set(63, [[2,4,8,2],[8,2,14,4],[14,4,14,8],[14,8,8,12],[8,12,8,14],[8,17,8,18]])
        // @
        set(64, [[14,18,4,18],[4,18,2,14],[2,14,2,6],[2,6,6,2],[6,2,12,2],[12,2,16,6],[16,6,16,12],[16,12,12,12],[12,12,10,8],[10,8,8,8],[8,8,8,12],[8,12,12,12]])
        // A
        set(65, [[2,18,8,2],[8,2,14,18],[5,12,11,12]])
        // B
        set(66, [[2,2,2,18],[2,2,10,2],[10,2,14,5],[14,5,10,10],[10,10,2,10],[10,10,14,14],[14,14,10,18],[10,18,2,18]])
        // C
        set(67, [[14,4,8,2],[8,2,4,6],[4,6,4,14],[4,14,8,18],[8,18,14,16]])
        // D
        set(68, [[2,2,2,18],[2,2,10,2],[10,2,14,6],[14,6,14,14],[14,14,10,18],[10,18,2,18]])
        // E
        set(69, [[14,2,2,2],[2,2,2,18],[2,18,14,18],[2,10,10,10]])
        // F
        set(70, [[14,2,2,2],[2,2,2,18],[2,10,10,10]])
        // G
        set(71, [[14,4,8,2],[8,2,4,6],[4,6,4,14],[4,14,8,18],[8,18,14,16],[14,16,14,10],[14,10,8,10]])
        // H
        set(72, [[2,2,2,18],[14,2,14,18],[2,10,14,10]])
        // I
        set(73, [[4,2,12,2],[8,2,8,18],[4,18,12,18]])
        // J
        set(74, [[14,2,14,14],[14,14,10,18],[10,18,6,18],[6,18,2,14]])
        // K
        set(75, [[2,2,2,18],[14,2,2,10],[2,10,14,18]])
        // L
        set(76, [[2,2,2,18],[2,18,14,18]])
        // M
        set(77, [[2,18,2,2],[2,2,8,10],[8,10,14,2],[14,2,14,18]])
        // N
        set(78, [[2,18,2,2],[2,2,14,18],[14,18,14,2]])
        // O
        set(79, [[6,2,10,2],[10,2,14,6],[14,6,14,14],[14,14,10,18],[10,18,6,18],[6,18,2,14],[2,14,2,6],[2,6,6,2]])
        // P
        set(80, [[2,2,2,18],[2,2,10,2],[10,2,14,5],[14,5,10,10],[10,10,2,10]])
        // Q
        set(81, [[6,2,10,2],[10,2,14,6],[14,6,14,14],[14,14,10,18],[10,18,6,18],[6,18,2,14],[2,14,2,6],[2,6,6,2],[10,14,16,20]])
        // R
        set(82, [[2,2,2,18],[2,2,10,2],[10,2,14,5],[14,5,10,10],[10,10,2,10],[8,10,14,18]])
        // S
        set(83, [[14,4,8,2],[8,2,4,4],[4,4,4,8],[4,8,14,12],[14,12,14,16],[14,16,8,18],[8,18,2,16]])
        // T
        set(84, [[2,2,14,2],[8,2,8,18]])
        // U
        set(85, [[2,2,2,14],[2,14,6,18],[6,18,10,18],[10,18,14,14],[14,14,14,2]])
        // V
        set(86, [[2,2,8,18],[8,18,14,2]])
        // W
        set(87, [[1,2,4,18],[4,18,8,10],[8,10,12,18],[12,18,15,2]])
        // X
        set(88, [[2,2,14,18],[14,2,2,18]])
        // Y
        set(89, [[2,2,8,10],[14,2,8,10],[8,10,8,18]])
        // Z
        set(90, [[2,2,14,2],[14,2,2,18],[2,18,14,18]])
        // [
        set(91, [[12,0,4,0],[4,0,4,20],[4,20,12,20]])
        // backslash
        set(92, [[2,2,16,18]])
        // ]
        set(93, [[4,0,12,0],[12,0,12,20],[12,20,4,20]])
        // ^
        set(94, [[4,8,8,2],[8,2,12,8]])
        // _
        set(95, [[0,20,16,20]])
        // `
        set(96, [[6,2,10,6]])
        // a..z — reuse uppercase strokes (compact set).
        for upper in 65...90 {
            g[(upper + 32) - 32] = g[upper - 32]
        }
        // {
        set(123, [[12,0,8,2],[8,2,8,9],[8,9,4,10],[4,10,8,11],[8,11,8,18],[8,18,12,20]])
        // |
        set(124, [[8,0,8,20]])
        // }
        set(125, [[4,0,8,2],[8,2,8,9],[8,9,12,10],[12,10,8,11],[8,11,8,18],[8,18,4,20]])
        // ~
        set(126, [[2,8,6,4],[6,4,10,8],[10,8,14,4]])
        return g
    }()
}
