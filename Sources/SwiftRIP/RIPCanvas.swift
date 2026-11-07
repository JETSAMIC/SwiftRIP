// RIPCanvas — the palette-indexed 640x350 framebuffer and the raster
// primitives the interpreter draws with.
//
// The canvas stores one palette index (0...15) per pixel. RGB is derived
// only when a snapshot is taken, so palette commands are O(1) and XOR,
// flood fill and PUT_IMAGE logic operate on palette indexes exactly like
// the EGA planes they model.
//
// All primitives take absolute screen coordinates and an explicit clip
// rectangle; every loop is bounded by the clip rectangle or by the
// (clamped) size of the primitive, never by unbounded input values.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An immutable snapshot of the native RIPscrip framebuffer.
public struct RIPFramebuffer: Equatable, Sendable {
    /// Width in pixels (640).
    public let width: Int
    /// Height in pixels (350).
    public let height: Int
    /// One palette index (0...15) per pixel, row-major from the top-left.
    public let indexed: [UInt8]
    /// The 16-entry palette (master-palette values) in effect.
    public let palette: [UInt8]

    /// Create a framebuffer from raw values.
    /// - Parameters:
    ///   - width: Width in pixels.
    ///   - height: Height in pixels.
    ///   - indexed: `width * height` palette indexes.
    ///   - palette: 16 master-palette values.
    public init(width: Int, height: Int, indexed: [UInt8], palette: [UInt8]) {
        self.width = width
        self.height = height
        self.indexed = indexed
        self.palette = palette
    }

    /// Palette index at `(x, y)`, or `nil` outside the framebuffer.
    public func colorIndex(x: Int, y: Int) -> UInt8? {
        guard x >= 0, y >= 0, x < width, y < height, y * width + x < indexed.count else { return nil }
        return indexed[y * width + x]
    }

    /// RGBA8 pixels (opaque, row-major), resolved through ``palette``.
    public var rgba: [UInt8] {
        let lut = (0..<16).map { RIPPalette.resolve(UInt8($0), in: palette) }
        var out = [UInt8](repeating: 255, count: indexed.count * 4)
        for (i, index) in indexed.enumerated() {
            let c = lut[Int(index & 0x0F)]
            out[i * 4] = c.r
            out[i * 4 + 1] = c.g
            out[i * 4 + 2] = c.b
        }
        return out
    }

    #if canImport(CoreGraphics)
    /// The framebuffer as an sRGB `CGImage` (RGBA8, opaque).
    public func cgImage() -> CGImage? {
        RIPFramebuffer.makeImage(rgba: rgba, width: width, height: height)
    }

    static func makeImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
    #endif
}

/// Inclusive clip rectangle in absolute pixels.
struct ClipRect: Equatable {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int

    var isEmpty: Bool { x0 > x1 || y0 > y1 }

    @inline(__always)
    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= x0 && x <= x1 && y >= y0 && y <= y1
    }

    func intersection(_ o: ClipRect) -> ClipRect {
        ClipRect(x0: Swift.max(x0, o.x0), y0: Swift.max(y0, o.y0),
                 x1: Swift.min(x1, o.x1), y1: Swift.min(y1, o.y1))
    }
}

/// A fill pattern resolved for drawing: set bits use `color`, clear bits
/// use the background color 0.
struct FillSpec {
    let rows: [UInt8]
    let color: UInt8

    @inline(__always)
    func color(atX x: Int, y: Int) -> UInt8 {
        let row = rows[y & 7]
        return (row >> UInt8(7 - (x & 7))) & 1 == 1 ? color : 0
    }
}

/// A line pen: color, write mode, 16-bit pattern and thickness (1 or 3).
struct Pen {
    var color: UInt8
    var mode: RIPWriteMode = .copy
    var mask: UInt16 = 0xFFFF
    var thickness: Int = 1
}

/// Mutable palette-indexed framebuffer used while rendering.
final class RIPCanvas {

    static let nativeWidth = 640
    static let nativeHeight = 350

    let width: Int
    let height: Int
    /// One palette index per pixel.
    private(set) var indexed: [UInt8]
    /// Active palette (16 master values); used only for snapshots.
    var palette: [UInt8] = RIPPalette.default16
    /// Number of pixel writes performed so far (the render work budget).
    private(set) var pixelWrites = 0
    /// Flood-fill visitation stamps (one generation per fill).
    private var stamps: [UInt32] = []
    private var stampGeneration: UInt32 = 0

    init(width: Int = RIPCanvas.nativeWidth, height: Int = RIPCanvas.nativeHeight) {
        self.width = width
        self.height = height
        self.indexed = [UInt8](repeating: 0, count: width * height)
    }

    var screen: ClipRect { ClipRect(x0: 0, y0: 0, x1: width - 1, y1: height - 1) }

    /// Immutable snapshot.
    var framebuffer: RIPFramebuffer {
        RIPFramebuffer(width: width, height: height, indexed: indexed, palette: palette)
    }

    /// RGBA8 view of the current pixels (convenience for tests).
    var rgba: [UInt8] { framebuffer.rgba }

    // MARK: - Pixels

    @inline(__always)
    func index(x: Int, y: Int) -> UInt8 { indexed[y * width + x] }

    /// Fill the whole canvas with one palette index.
    func clear(to color: UInt8) {
        for i in indexed.indices { indexed[i] = color }
        pixelWrites += indexed.count
    }

    /// Plot one pixel if it lies inside `clip` (which must be on-screen).
    @inline(__always)
    func plot(_ x: Int, _ y: Int, _ color: UInt8, _ mode: RIPWriteMode, _ clip: ClipRect) {
        guard clip.contains(x, y) else { return }
        let i = y * width + x
        indexed[i] = mode == .xor ? (indexed[i] ^ color) & 0x0F : color & 0x0F
        pixelWrites += 1
    }

    /// Fill a rectangle (inclusive) with a pattern, copy mode.
    func fillRect(x0: Int, y0: Int, x1: Int, y1: Int, fill: FillSpec, clip: ClipRect) {
        let r = ClipRect(x0: Swift.min(x0, x1), y0: Swift.min(y0, y1),
                         x1: Swift.max(x0, x1), y1: Swift.max(y0, y1)).intersection(clip)
        guard !r.isEmpty else { return }
        for y in r.y0...r.y1 {
            span(y: y, from: r.x0, to: r.x1, fill: fill, clip: clip)
        }
    }

    /// Fill one horizontal span with a pattern, copy mode.
    @inline(__always)
    func span(y: Int, from xa: Int, to xb: Int, fill: FillSpec, clip: ClipRect) {
        guard y >= clip.y0, y <= clip.y1 else { return }
        let lo = Swift.max(Swift.min(xa, xb), clip.x0)
        let hi = Swift.min(Swift.max(xa, xb), clip.x1)
        guard lo <= hi else { return }
        let base = y * width
        for x in lo...hi {
            indexed[base + x] = fill.color(atX: x, y: y)
        }
        pixelWrites += hi - lo + 1
    }

    // MARK: - Lines

    /// Bresenham line. Thickness 3 draws three parallel lines offset along
    /// the minor axis (as BGI does); the pattern's MSB is plotted first.
    func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, pen: Pen, clip: ClipRect) {
        if pen.thickness >= 3 {
            let steep = abs(y1 - y0) > abs(x1 - x0)
            for d in -1...1 {
                if steep {
                    thinLine(x0 + d, y0, x1 + d, y1, pen: pen, clip: clip)
                } else {
                    thinLine(x0, y0 + d, x1, y1 + d, pen: pen, clip: clip)
                }
            }
        } else {
            thinLine(x0, y0, x1, y1, pen: pen, clip: clip)
        }
    }

    private func thinLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, pen: Pen, clip: ClipRect) {
        // Trivially reject lines entirely on one side of the clip rectangle.
        if (x0 < clip.x0 && x1 < clip.x0) || (x0 > clip.x1 && x1 > clip.x1) ||
            (y0 < clip.y0 && y1 < clip.y0) || (y0 > clip.y1 && y1 > clip.y1) { return }
        var x = x0, y = y0
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        var bit = 15
        while true {
            if (pen.mask >> UInt16(bit)) & 1 == 1 {
                plot(x, y, pen.color, pen.mode, clip)
            }
            bit = bit == 0 ? 15 : bit - 1
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    // MARK: - Ellipses

    /// Ellipse outline (copy mode, solid). Thickness 3 adds the radii +/- 1.
    func ellipse(cx: Int, cy: Int, rx: Int, ry: Int, color: UInt8, thickness: Int, clip: ClipRect) {
        if thickness >= 3 {
            for d in -1...1 {
                thinEllipse(cx: cx, cy: cy, rx: Swift.max(0, rx + d), ry: Swift.max(0, ry + d), color: color, clip: clip)
            }
        } else {
            thinEllipse(cx: cx, cy: cy, rx: rx, ry: ry, color: color, clip: clip)
        }
    }

    private func thinEllipse(cx: Int, cy: Int, rx: Int, ry: Int, color: UInt8, clip: ClipRect) {
        if cx + rx < clip.x0 || cx - rx > clip.x1 || cy + ry < clip.y0 || cy - ry > clip.y1 { return }
        func plot4(_ dx: Int, _ dy: Int) {
            plot(cx + dx, cy + dy, color, .copy, clip)
            plot(cx - dx, cy + dy, color, .copy, clip)
            plot(cx + dx, cy - dy, color, .copy, clip)
            plot(cx - dx, cy - dy, color, .copy, clip)
        }
        if rx == 0 || ry == 0 {
            line(cx - rx, cy - ry, cx + rx, cy + ry, pen: Pen(color: color), clip: clip)
            return
        }
        let fx = Double(rx), fy = Double(ry)
        for dx in 0...rx {
            let t = Double(dx) / fx
            plot4(dx, Int((fy * (1 - t * t).squareRoot()).rounded()))
        }
        for dy in 0...ry {
            let t = Double(dy) / fy
            plot4(Int((fx * (1 - t * t).squareRoot()).rounded()), dy)
        }
    }

    /// Filled ellipse interior (copy mode, pattern).
    func fillEllipse(cx: Int, cy: Int, rx: Int, ry: Int, fill: FillSpec, clip: ClipRect) {
        guard ry >= 0, rx >= 0 else { return }
        let top = Swift.max(-ry, clip.y0 - cy)
        let bottom = Swift.min(ry, clip.y1 - cy)
        guard top <= bottom else { return }
        let fx = Double(rx), fy = Double(Swift.max(ry, 1))
        for dy in top...bottom {
            let t = Double(dy) / fy
            let half = Int((fx * Swift.max(0, 1 - t * t).squareRoot()).rounded())
            span(y: cy + dy, from: cx - half, to: cx + half, fill: fill, clip: clip)
        }
    }

    // MARK: - Polygons

    /// Even-odd scanline fill of a closed polygon (copy mode, pattern).
    func fillPolygon(_ points: [RIPPoint], fill: FillSpec, clip: ClipRect) {
        guard points.count >= 3 else { return }
        var minY = Int.max, maxY = Int.min
        for p in points { minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y) }
        let top = Swift.max(minY, clip.y0), bottom = Swift.min(maxY, clip.y1)
        guard top <= bottom else { return }
        var crossings: [Int] = []
        crossings.reserveCapacity(points.count)
        for y in top...bottom {
            crossings.removeAll(keepingCapacity: true)
            let sampleY = Double(y) + 0.5
            for i in 0..<points.count {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                let ay = Double(a.y), by = Double(b.y)
                if (ay <= sampleY && by > sampleY) || (by <= sampleY && ay > sampleY) {
                    let x = Double(a.x) + (sampleY - ay) * Double(b.x - a.x) / (by - ay)
                    crossings.append(Int(x.rounded()))
                }
            }
            crossings.sort()
            var i = 0
            while i + 1 < crossings.count {
                span(y: y, from: crossings[i], to: crossings[i + 1], fill: fill, clip: clip)
                i += 2
            }
        }
    }

    // MARK: - Flood fill

    /// Border flood fill (4-connected, scanline, copy mode). Pixels inside
    /// `clip` that are reachable from `(x, y)` without crossing `border`
    /// are painted with `fill`. Each pixel is visited at most once, so the
    /// work is bounded by the clip area regardless of the pattern colors.
    func floodFill(x: Int, y: Int, border: UInt8, fill: FillSpec, clip: ClipRect) {
        guard clip.contains(x, y), index(x: x, y: y) != border else { return }
        if stamps.count != indexed.count {
            stamps = [UInt32](repeating: 0, count: indexed.count)
            stampGeneration = 0
        }
        if stampGeneration == UInt32.max {
            for i in stamps.indices { stamps[i] = 0 }
            stampGeneration = 0
        }
        stampGeneration += 1
        let gen = stampGeneration

        @inline(__always) func fillable(_ px: Int, _ py: Int) -> Bool {
            let i = py * width + px
            return stamps[i] != gen && indexed[i] != border
        }

        var stack: [(Int, Int)] = [(x, y)]
        while let (sx, sy) = stack.popLast() {
            guard fillable(sx, sy) else { continue }
            var left = sx
            while left - 1 >= clip.x0, fillable(left - 1, sy) { left -= 1 }
            var right = sx
            while right + 1 <= clip.x1, fillable(right + 1, sy) { right += 1 }
            let base = sy * width
            for px in left...right {
                stamps[base + px] = gen
                indexed[base + px] = fill.color(atX: px, y: sy)
            }
            pixelWrites += right - left + 1
            for ny in [sy - 1, sy + 1] where ny >= clip.y0 && ny <= clip.y1 {
                var px = left
                while px <= right {
                    if fillable(px, ny) {
                        stack.append((px, ny))
                        while px <= right, fillable(px, ny) { px += 1 }
                    } else {
                        px += 1
                    }
                }
            }
        }
    }

    // MARK: - Blocks

    /// Copy a rectangle of palette indexes (inclusive, must be on-screen).
    func copyBlock(x0: Int, y0: Int, x1: Int, y1: Int) -> ClipImage {
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        var pixels: [UInt8] = []
        pixels.reserveCapacity(w * h)
        for y in y0...y1 {
            let base = y * width
            pixels.append(contentsOf: indexed[(base + x0)...(base + x1)])
        }
        return ClipImage(width: w, height: h, pixels: pixels)
    }

    /// Paste a block at `(x, y)` combining with `mode` (0 copy, 1 XOR,
    /// 2 OR, 3 AND, 4 NOT), clipped to `clip`.
    func paste(_ image: ClipImage, x: Int, y: Int, mode: Int, clip: ClipRect) {
        let r = ClipRect(x0: x, y0: y, x1: x + image.width - 1, y1: y + image.height - 1).intersection(clip)
        guard !r.isEmpty else { return }
        for py in r.y0...r.y1 {
            let src = (py - y) * image.width
            let dst = py * width
            for px in r.x0...r.x1 {
                let s = image.pixels[src + px - x]
                let d = indexed[dst + px]
                let v: UInt8
                switch mode {
                case 1: v = d ^ s
                case 2: v = d | s
                case 3: v = d & s
                case 4: v = ~s
                default: v = s
                }
                indexed[dst + px] = v & 0x0F
            }
        }
        pixelWrites += (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1)
    }
}

/// A palette-indexed bitmap (the RIPscrip clipboard).
struct ClipImage: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}
