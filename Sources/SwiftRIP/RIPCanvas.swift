// RIPCanvas — 640x350 RGBA8 raster framebuffer plus the geometric primitives
// the RIPscrip spec requires.
//
// The canvas is the renderer's draw target. Every spec primitive (line, arc,
// flood-fill, etc.) plots into this buffer using the active `RIPGraphicsState`
// at the moment of the call. Coordinates are framebuffer pixels with origin
// at the top-left (RIPscrip convention).
//
// We deliberately implement these primitives by hand rather than handing off
// to CoreGraphics for two reasons:
//
//   1. We need pixel-exact behavior: line patterns are 16-bit masks of
//      individual pixels, flood-fill must stop on a specific palette index
//      (not an RGB value), and XOR write-mode must XOR palette indices, not
//      composited RGBA.
//   2. We need to honour the spec's "Uses Viewport / Uses Write Mode / Uses
//      Line Pattern / Uses Fill Pattern" table on a per-pixel basis.
//
// A `CGImage` snapshot is provided for callers that just want the result as
// a system image.

import Foundation
import CoreGraphics

/// Pixel-addressable 640x350 RGBA8 framebuffer.
public final class RIPCanvas {

    public static let nativeWidth: Int = 640
    public static let nativeHeight: Int = 350

    /// Active framebuffer width in pixels.
    public let width: Int
    /// Active framebuffer height in pixels.
    public let height: Int

    /// Palette-indexed plane. One byte per pixel, value is a palette slot
    /// (0..15). Maintained alongside the RGBA plane so flood-fill and XOR
    /// can operate in palette space.
    public private(set) var indexed: [UInt8]

    /// 32-bit RGBA8 framebuffer, premultiplied alpha, row-major.
    public private(set) var rgba: [UInt8]

    /// Active palette used to keep `rgba` in sync with `indexed`. Updated by
    /// the interpreter whenever a palette mutation happens; the canvas
    /// re-derives RGB on demand.
    public var palette: [UInt8] = RIPPalette.default16

    /// Create a fresh canvas, cleared to palette index 0 (black in the
    /// default palette).
    public init(width: Int = RIPCanvas.nativeWidth, height: Int = RIPCanvas.nativeHeight) {
        self.width = width
        self.height = height
        self.indexed = [UInt8](repeating: 0, count: width * height)
        self.rgba = [UInt8](repeating: 0, count: width * height * 4)
        // Default-clear alpha to 255 so the buffer is opaque on snapshot.
        for i in 0..<(width * height) {
            rgba[i * 4 + 3] = 255
        }
    }

    /// Fill the entire framebuffer with one palette index.
    public func clear(to color: UInt8) {
        for i in 0..<indexed.count { indexed[i] = color }
        refreshRGBA()
    }

    /// Refresh the RGBA plane from the indexed plane using the current
    /// `palette`. O(w*h).
    public func refreshRGBA() {
        for i in 0..<indexed.count {
            writeRGBA(i, color: indexed[i])
        }
    }

    @inline(__always)
    private func writeRGBA(_ i: Int, color: UInt8) {
        let rgb = RIPPalette.resolve(color, in: palette)
        let o = i * 4
        rgba[o + 0] = rgb.r
        rgba[o + 1] = rgb.g
        rgba[o + 2] = rgb.b
        rgba[o + 3] = 255
    }

    // MARK: - Primitives — single pixel

    /// Plot a single pixel honoring viewport clip and write mode. `state` is
    /// passed so write-mode + viewport apply uniformly.
    public func setPixel(x: Int, y: Int, color: UInt8, state: RIPGraphicsState) {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return }
        let clip = state.viewport.clipRect()
        if x < clip.x0 || x > clip.x1 || y < clip.y0 || y > clip.y1 { return }
        let i = y * width + x
        let dst = indexed[i]
        let plotted: UInt8
        switch state.writeMode {
        case .copy: plotted = color
        case .xor:  plotted = dst ^ color
        }
        indexed[i] = plotted
        writeRGBA(i, color: plotted)
    }

    /// Raw indexed-plane read without viewport check. Used by flood-fill.
    @inline(__always)
    func rawIndex(x: Int, y: Int) -> UInt8 {
        return indexed[y * width + x]
    }

    // MARK: - Line drawing

    /// Bresenham line with thickness, pattern, and write mode honored.
    public func drawLine(x0: Int, y0: Int, x1: Int, y1: Int, color: UInt8, state: RIPGraphicsState) {
        let mask = lineMask(for: state.lineStyle)
        var bit = 0
        var x = x0, y = y0
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            if mask == 0xFFFF || ((mask >> (bit & 15)) & 1) == 1 {
                plotThick(x: x, y: y, color: color, state: state)
            }
            bit += 1
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// Pixel-square brush of `state.lineThickness` width centered on (x,y).
    private func plotThick(x: Int, y: Int, color: UInt8, state: RIPGraphicsState) {
        let t = max(1, state.lineThickness)
        if t == 1 {
            setPixel(x: x, y: y, color: color, state: state)
            return
        }
        let half = t / 2
        for dy in -half..<(t - half) {
            for dx in -half..<(t - half) {
                setPixel(x: x + dx, y: y + dy, color: color, state: state)
            }
        }
    }

    private func lineMask(for style: RIPLineStyle) -> UInt16 {
        switch style {
        case .predefined(let i):
            switch i {
            case 0: return 0xFFFF // solid
            case 1: return 0x3333 // dotted
            case 2: return 0x1E3F // center
            case 3: return 0x1F1F // dashed
            default: return 0xFFFF
            }
        case .user(let m):
            return m
        }
    }

    // MARK: - Rectangle

    public func drawRectangle(x0: Int, y0: Int, x1: Int, y1: Int, color: UInt8, state: RIPGraphicsState) {
        drawLine(x0: x0, y0: y0, x1: x1, y1: y0, color: color, state: state)
        drawLine(x0: x1, y0: y0, x1: x1, y1: y1, color: color, state: state)
        drawLine(x0: x1, y0: y1, x1: x0, y1: y1, color: color, state: state)
        drawLine(x0: x0, y0: y1, x1: x0, y1: y0, color: color, state: state)
    }

    public func fillRectangle(x0: Int, y0: Int, x1: Int, y1: Int, state: RIPGraphicsState) {
        let lx = min(x0, x1), rx = max(x0, x1)
        let ty = min(y0, y1), by = max(y0, y1)
        for y in ty...by {
            for x in lx...rx {
                let c = patternColor(at: x, y: y, state: state)
                setPixel(x: x, y: y, color: c, state: state)
            }
        }
    }

    /// Sample the fill pattern at (x,y) returning the palette index to plot.
    private func patternColor(at x: Int, y: Int, state: RIPGraphicsState) -> UInt8 {
        let bytes = patternBytes(for: state.fillPattern)
        let row = bytes[y & 7]
        let bit = (row >> (7 - (x & 7))) & 1
        return bit == 1 ? state.fillColor : state.drawColor
    }

    private func patternBytes(for fill: RIPFillPattern) -> [UInt8] {
        switch fill {
        case .custom(let b):
            // Pad or truncate to 8 bytes defensively.
            var out = b
            if out.count < 8 { out.append(contentsOf: [UInt8](repeating: 0, count: 8 - out.count)) }
            if out.count > 8 { out = Array(out.prefix(8)) }
            return out
        case .predefined(let i):
            return Self.predefinedPatterns[max(0, min(11, i))]
        }
    }

    /// Spec's 12 predefined fill patterns expressed as 8x8 1-bit rasters.
    /// Pattern 0 = empty (all 0), 1 = solid (all 1), 2..11 follow the
    /// canonical BGI/RIP pattern list (line, lt-slash, slash, bk-slash,
    /// lt-bk-slash, hatch, x-hatch, interleave, wide-dot, close-dot, user
    /// placeholder).
    static let predefinedPatterns: [[UInt8]] = [
        /* 0  empty       */ [0,0,0,0,0,0,0,0],
        /* 1  solid       */ [0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF],
        /* 2  line        */ [0xFF,0xFF,0,0,0xFF,0xFF,0,0],
        /* 3  lt-slash    */ [0x10,0x20,0x40,0x80,0x01,0x02,0x04,0x08],
        /* 4  slash       */ [0x70,0xE0,0xC1,0x83,0x07,0x0E,0x1C,0x38],
        /* 5  bk-slash    */ [0x07,0x0E,0x1C,0x38,0x70,0xE0,0xC1,0x83],
        /* 6  lt-bk-slash */ [0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01],
        /* 7  hatch       */ [0x22,0x22,0xFF,0x22,0x22,0x22,0xFF,0x22],
        /* 8  x-hatch     */ [0x81,0x42,0x24,0x18,0x18,0x24,0x42,0x81],
        /* 9  interleave  */ [0xCC,0x33,0xCC,0x33,0xCC,0x33,0xCC,0x33],
        /* 10 wide-dot    */ [0x80,0x00,0x08,0x00,0x80,0x00,0x08,0x00],
        /* 11 close-dot   */ [0x88,0x00,0x22,0x00,0x88,0x00,0x22,0x00]
    ]

    // MARK: - Polygon

    public func drawPolygon(points: [RIPPoint], color: UInt8, state: RIPGraphicsState) {
        guard points.count >= 2 else { return }
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            drawLine(x0: a.x, y0: a.y, x1: b.x, y1: b.y, color: color, state: state)
        }
    }

    public func drawPolyline(points: [RIPPoint], color: UInt8, state: RIPGraphicsState) {
        guard points.count >= 2 else { return }
        for i in 0..<(points.count - 1) {
            drawLine(x0: points[i].x, y0: points[i].y,
                     x1: points[i + 1].x, y1: points[i + 1].y,
                     color: color, state: state)
        }
    }

    public func fillPolygon(points: [RIPPoint], state: RIPGraphicsState) {
        guard points.count >= 3 else { return }
        // Scanline fill with even-odd rule.
        let minY = max(0, points.map(\.y).min() ?? 0)
        let maxY = min(height - 1, points.map(\.y).max() ?? 0)
        for y in minY...maxY {
            var crossings: [Int] = []
            for i in 0..<points.count {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                    let dy = b.y - a.y
                    if dy == 0 { continue }
                    let x = a.x + (y - a.y) * (b.x - a.x) / dy
                    crossings.append(x)
                }
            }
            crossings.sort()
            var i = 0
            while i + 1 < crossings.count {
                let xs = max(0, crossings[i])
                let xe = min(width - 1, crossings[i + 1])
                if xs <= xe {
                    for x in xs...xe {
                        let c = patternColor(at: x, y: y, state: state)
                        setPixel(x: x, y: y, color: c, state: state)
                    }
                }
                i += 2
            }
        }
        // Border in current draw color.
        drawPolygon(points: points, color: state.drawColor, state: state)
    }

    // MARK: - Circle / ellipse / arc

    /// Midpoint ellipse rasteriser; circle is the special case xrad==yrad
    /// after applying the spec's aspect ratio.
    public func drawEllipse(cx: Int, cy: Int, xrad: Int, yrad: Int, color: UInt8, state: RIPGraphicsState) {
        guard xrad > 0 && yrad > 0 else {
            setPixel(x: cx, y: cy, color: color, state: state); return
        }
        var x = 0, y = yrad
        let a2 = xrad * xrad
        let b2 = yrad * yrad
        var dx = 0
        var dy = 2 * a2 * y
        var d1 = b2 - (a2 * yrad) + (a2 / 4)
        while dx < dy {
            plotEllipsePoints(cx: cx, cy: cy, x: x, y: y, color: color, state: state)
            if d1 < 0 {
                x += 1; dx += 2 * b2; d1 += dx + b2
            } else {
                x += 1; y -= 1
                dx += 2 * b2; dy -= 2 * a2
                d1 += dx - dy + b2
            }
        }
        var d2 = Int(Double(b2) * (Double(x) + 0.5) * (Double(x) + 0.5) + Double(a2) * Double(y - 1) * Double(y - 1) - Double(a2 * b2))
        while y >= 0 {
            plotEllipsePoints(cx: cx, cy: cy, x: x, y: y, color: color, state: state)
            if d2 > 0 {
                y -= 1; dy -= 2 * a2; d2 += a2 - dy
            } else {
                y -= 1; x += 1
                dx += 2 * b2; dy -= 2 * a2
                d2 += dx - dy + a2
            }
        }
    }

    /// RIPscrip uses a 4:3 aspect ratio for `circle` — yrad = round(xrad *
    /// 350/480) on the original EGA. We honour that so circles look round.
    public func drawCircle(cx: Int, cy: Int, radius: Int, color: UInt8, state: RIPGraphicsState) {
        // The spec defines 350/480 as the ratio; many implementations
        // simplify to 7/10 which gives identical pixels for small radii.
        let yrad = (radius * 7 + 5) / 10
        drawEllipse(cx: cx, cy: cy, xrad: radius, yrad: yrad, color: color, state: state)
    }

    public func fillEllipse(cx: Int, cy: Int, xrad: Int, yrad: Int, state: RIPGraphicsState) {
        guard xrad > 0 && yrad > 0 else { return }
        let a2 = xrad * xrad
        let b2 = yrad * yrad
        for dy in -yrad...yrad {
            let ratio = Double(dy * dy) / Double(b2)
            if ratio > 1 { continue }
            let dxF = Double(a2) * (1.0 - ratio)
            let dx = Int(dxF.squareRoot().rounded())
            let y = cy + dy
            let xs = cx - dx
            let xe = cx + dx
            for x in xs...xe {
                let c = patternColor(at: x, y: y, state: state)
                setPixel(x: x, y: y, color: c, state: state)
            }
        }
        drawEllipse(cx: cx, cy: cy, xrad: xrad, yrad: yrad, color: state.drawColor, state: state)
    }

    private func plotEllipsePoints(cx: Int, cy: Int, x: Int, y: Int, color: UInt8, state: RIPGraphicsState) {
        setPixel(x: cx + x, y: cy + y, color: color, state: state)
        setPixel(x: cx - x, y: cy + y, color: color, state: state)
        setPixel(x: cx + x, y: cy - y, color: color, state: state)
        setPixel(x: cx - x, y: cy - y, color: color, state: state)
    }

    // MARK: - Arc / pie

    /// Arc/pie samples in polar space and plots line segments — good enough
    /// for the small radii typical of RIPscrip scenes. Angles per the spec
    /// are 0..360 with 0 east, 90 north (counter-clockwise).
    public func drawArc(cx: Int, cy: Int, xrad: Int, yrad: Int, startAngle: Int, endAngle: Int, color: UInt8, state: RIPGraphicsState) {
        let pts = arcPoints(cx: cx, cy: cy, xrad: xrad, yrad: yrad, startAngle: startAngle, endAngle: endAngle)
        guard pts.count >= 2 else { return }
        for i in 0..<(pts.count - 1) {
            drawLine(x0: pts[i].x, y0: pts[i].y, x1: pts[i + 1].x, y1: pts[i + 1].y, color: color, state: state)
        }
    }

    public func drawPieSlice(cx: Int, cy: Int, xrad: Int, yrad: Int, startAngle: Int, endAngle: Int, state: RIPGraphicsState) {
        var pts = arcPoints(cx: cx, cy: cy, xrad: xrad, yrad: yrad, startAngle: startAngle, endAngle: endAngle)
        pts.insert(RIPPoint(x: cx, y: cy), at: 0)
        pts.append(RIPPoint(x: cx, y: cy))
        fillPolygon(points: pts, state: state)
    }

    private func arcPoints(cx: Int, cy: Int, xrad: Int, yrad: Int, startAngle: Int, endAngle: Int) -> [RIPPoint] {
        let s = Double(startAngle) * .pi / 180.0
        var e = Double(endAngle) * .pi / 180.0
        if e < s { e += 2 * .pi }
        let arcLen = e - s
        let steps = max(8, Int(arcLen * Double(max(xrad, yrad)) / 2.0))
        var pts: [RIPPoint] = []
        pts.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = s + arcLen * Double(i) / Double(steps)
            let x = cx + Int((Double(xrad) * cos(t)).rounded())
            // RIPscrip Y grows downward but angles are CCW math-convention,
            // so we negate sin to flip Y.
            let y = cy - Int((Double(yrad) * sin(t)).rounded())
            pts.append(RIPPoint(x: x, y: y))
        }
        return pts
    }

    // MARK: - Bezier

    /// Cubic Bezier with explicit segment count (spec `Z` command).
    public func drawBezier(_ p0: RIPPoint, _ p1: RIPPoint, _ p2: RIPPoint, _ p3: RIPPoint, segments: Int, color: UInt8, state: RIPGraphicsState) {
        let n = max(2, segments)
        var prev = p0
        for i in 1...n {
            let t = Double(i) / Double(n)
            let u = 1.0 - t
            let xF = u*u*u * Double(p0.x) + 3 * u*u*t * Double(p1.x) + 3 * u*t*t * Double(p2.x) + t*t*t * Double(p3.x)
            let yF = u*u*u * Double(p0.y) + 3 * u*u*t * Double(p1.y) + 3 * u*t*t * Double(p2.y) + t*t*t * Double(p3.y)
            let cur = RIPPoint(x: Int(xF.rounded()), y: Int(yF.rounded()))
            drawLine(x0: prev.x, y0: prev.y, x1: cur.x, y1: cur.y, color: color, state: state)
            prev = cur
        }
    }

    // MARK: - Flood fill

    /// Boundary-fill per spec. Plots the current fill pattern; will not
    /// paint the border color and will not fill at all if the start pixel is
    /// already the border color.
    public func floodFill(x: Int, y: Int, border: UInt8, state: RIPGraphicsState) {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return }
        let clip = state.viewport.clipRect()
        if x < clip.x0 || x > clip.x1 || y < clip.y0 || y > clip.y1 { return }
        if rawIndex(x: x, y: y) == border { return }

        var stack: [(Int, Int)] = [(x, y)]
        // Track painted pixels so the loop terminates regardless of what the
        // fill pattern actually plots (pattern may plot the border color
        // itself, which would otherwise cause re-entry).
        var visited = [Bool](repeating: false, count: width * height)
        while let (px, py) = stack.popLast() {
            if px < clip.x0 || px > clip.x1 || py < clip.y0 || py > clip.y1 { continue }
            let i = py * width + px
            if visited[i] { continue }
            if indexed[i] == border { continue }
            visited[i] = true
            let c = patternColor(at: px, y: py, state: state)
            // Bypass setPixel's redundant clip + write-mode XOR (fill is
            // always copy per spec).
            indexed[i] = c
            writeRGBA(i, color: c)
            stack.append((px + 1, py))
            stack.append((px - 1, py))
            stack.append((px, py + 1))
            stack.append((px, py - 1))
        }
    }

    // MARK: - CGImage snapshot

    /// Snapshot the current framebuffer as a `CGImage`. Always premultiplied
    /// RGBA8 in sRGB.
    public func cgImage() -> CGImage? {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
