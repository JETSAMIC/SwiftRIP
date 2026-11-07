// RIPVectorFonts — text rendering for RIPscrip font 0 (8x8 bitmap) and the
// ten scalable stroke fonts 1...10.
//
// RIPscrip uses Borland BGI's font set. The BGI glyph data (the .CHR stroke
// files and the ROM 8x8 font) is not redistributable, so SwiftRIP ships
// clean-room approximations:
//
//   * Font 0 — an 8x8 bitmap for ASCII 32...126 in the style of the IBM PC
//     8x8 font, drawn for SwiftRIP. Size N replicates each pixel N x N.
//   * Fonts 1...10 — one monoline stroke set over a 21-unit cell, with a
//     per-family transform (double stroke for Triplex/Complex, slant for
//     Script/Triplex Script/European, half height for Small, triple stroke
//     for Bold). Size N scales the cell by N.
//
// Glyph shapes and advance widths therefore differ from RIPterm; layout
// (drawing position updates, clipping, direction) follows the spec.
// Characters outside ASCII 32...126 advance the pen but draw nothing.

import Foundation

/// Text renderer for the RIPscrip fonts (clean-room approximations).
enum RIPVectorFonts {

    /// Horizontal advance of one character cell in pixels.
    static func advance(font: Int, size: Int) -> Int {
        let scale = Swift.max(1, Swift.min(10, size))
        return (font == 0 ? 8 : 12) * scale
    }

    /// Height of one line of text in pixels.
    static func lineHeight(font: Int, size: Int) -> Int {
        let scale = Swift.max(1, Swift.min(10, size))
        return (font == 0 ? 8 : 21) * scale
    }

    /// Width of `s` in pixels when drawn horizontally.
    static func width(of s: String, font: Int, size: Int) -> Int {
        s.unicodeScalars.count * advance(font: font, size: size)
    }

    /// Draw `s` with its top-left corner at `(x, y)` (horizontal) or its
    /// bottom-left corner at `(x, y)` reading upward (vertical).
    ///
    /// Rendering stops as soon as the pen has left `clip` in the direction
    /// of travel, so arbitrarily long strings cost at most one screen width
    /// of glyphs.
    static func renderText(_ s: String, x: Int, y: Int, font: Int, direction: Int, size: Int,
                           color: UInt8, mode: RIPWriteMode, into canvas: RIPCanvas, clip: ClipRect) {
        guard !clip.isEmpty else { return }
        let scale = Swift.max(1, Swift.min(10, size))
        let step = advance(font: font, size: scale)
        var penX = x, penY = y
        for scalar in s.unicodeScalars {
            if direction == 0 {
                if penX > clip.x1 { break }
            } else {
                if penY < clip.y0 { break }
            }
            let code = Int(scalar.value)
            if (33...126).contains(code) {
                let visible = direction == 0
                    ? penX + step >= clip.x0
                    : penY - step <= clip.y1
                if visible {
                    if font == 0 {
                        renderBitmapGlyph(code: code, x: penX, y: penY, scale: scale, direction: direction,
                                          color: color, mode: mode, canvas: canvas, clip: clip)
                    } else {
                        renderVectorGlyph(code: code, x: penX, y: penY, font: font, scale: scale,
                                          direction: direction, color: color, mode: mode,
                                          canvas: canvas, clip: clip)
                    }
                }
            }
            if direction == 0 { penX += step } else { penY -= step }
        }
    }

    // MARK: - Bitmap font 0

    private static func renderBitmapGlyph(code: Int, x: Int, y: Int, scale: Int, direction: Int,
                                          color: UInt8, mode: RIPWriteMode, canvas: RIPCanvas, clip: ClipRect) {
        let glyph = bitmap8x8[code - 32]
        for row in 0..<8 {
            let bits = glyph[row]
            for col in 0..<8 where (bits >> UInt8(7 - col)) & 1 == 1 {
                for sy in 0..<scale {
                    for sx in 0..<scale {
                        let u = col * scale + sx   // along the text
                        let v = row * scale + sy   // down the glyph
                        if direction == 0 {
                            canvas.plot(x + u, y + v, color, mode, clip)
                        } else {
                            canvas.plot(x + v, y - u, color, mode, clip)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stroke fonts

    private static func renderVectorGlyph(code: Int, x: Int, y: Int, font: Int, scale: Int, direction: Int,
                                          color: UInt8, mode: RIPWriteMode, canvas: RIPCanvas, clip: ClipRect) {
        let strokes = vectorStrokes[code - 32]
        let italic: Double
        let extraStrokes: Int
        switch font {
        case 1: italic = 0; extraStrokes = 1       // Triplex
        case 5: italic = 0.30; extraStrokes = 0    // Script
        case 7: italic = 0.30; extraStrokes = 1    // Triplex Script
        case 8: italic = 0; extraStrokes = 1       // Complex
        case 9: italic = 0.20; extraStrokes = 0    // European
        case 10: italic = 0; extraStrokes = 2      // Bold
        default: italic = 0; extraStrokes = 0      // Small, Sans Serif, Gothic, Simplex
        }
        let yScale = font == 2 ? Double(scale) * 0.5 : Double(scale)
        let xScale = Double(scale)
        let pen = Pen(color: color, mode: mode)

        func transform(_ px: Int, _ py: Int, _ offset: Int) -> (Int, Int) {
            let shear = italic * Double(20 - py)
            let u = Int((Double(px) * xScale + shear * xScale).rounded()) + offset
            let v = Int((Double(py) * yScale).rounded())
            return direction == 0 ? (x + u, y + v) : (x + v, y - u)
        }

        for stroke in strokes {
            for offset in 0...extraStrokes {
                let (ax, ay) = transform(stroke[0], stroke[1], offset)
                let (bx, by) = transform(stroke[2], stroke[3], offset)
                canvas.line(ax, ay, bx, by, pen: pen, clip: clip)
            }
        }
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
