// RIPCompositor — pixel-replicating scale + optional anti-aliasing pass
// for the native 640x350 RIPscrip framebuffer.
//
// Why a separate compositor? The renderer must stay pixel-exact on its
// native 640x350 EGA framebuffer (line patterns, XOR write-mode, flood-fill
// border-stop all depend on that). Modern displays are 1080p+ and the
// chunky-EGA look is part of the format's identity. This file's job is to
// bridge those two facts:
//
//   * `compose(canvas:options:)` always starts from the native 640x350
//     framebuffer the interpreter wrote to.
//   * If `targetSize` is nil we return the native snapshot unchanged.
//   * If `targetSize` is non-nil we run a NEAREST-NEIGHBOUR pixel
//     replicator written in pure Swift (no CoreGraphics interpolation) so
//     the chunky-EGA pixels are preserved on integer scales and explicit
//     floor-replicated on fractional scales.
//   * If `antiAliasing` is true, we then apply a SEPARATE CoreGraphics
//     `.high` interpolation pass on top of the NN-scaled buffer. This is
//     intentionally a second pass — the chunky-EGA pre-AA buffer is the
//     option callers can keep by flipping `antiAliasing` to `false`.

import Foundation
import CoreGraphics

/// Stateless compositor that converts the interpreter's native 640x350
/// framebuffer into a target-sized `CGImage`. Pure functions; no state.
public enum RIPCompositor {

    /// Compose the canvas through the scale + AA pipeline described in
    /// `RIPRenderOptions`. Returns the native `CGImage` if `targetSize`
    /// is nil; otherwise nearest-neighbour scaled (and optionally
    /// AA-smoothed) to `targetSize`.
    public static func compose(canvas: RIPCanvas, options: RIPRenderOptions) -> CGImage? {
        guard let nativeImage = canvas.cgImage() else { return nil }
        guard let target = options.targetSize else { return nativeImage }
        let w = max(1, Int(target.width.rounded()))
        let h = max(1, Int(target.height.rounded()))
        guard let scaled = nearestNeighbourScale(canvas: canvas, targetWidth: w, targetHeight: h) else {
            return nativeImage
        }
        if options.antiAliasing {
            return antiAliasPass(image: scaled, width: w, height: h) ?? scaled
        }
        return scaled
    }

    // MARK: - Nearest-neighbour scale

    /// Pure-Swift pixel-replicating scale from the native 640x350
    /// framebuffer to `(targetWidth, targetHeight)`. No CoreGraphics
    /// interpolation — every destination pixel maps to exactly one
    /// source pixel via `floor(dst * src / target)`.
    ///
    /// Integer scales are exact pixel replication (e.g. 640→1280 doubles
    /// every column twice). Non-integer scales floor-replicate per
    /// destination pixel; this keeps individual EGA pixels hard-edged
    /// at the cost of slightly uneven column widths.
    public static func nearestNeighbourScale(canvas: RIPCanvas, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let srcW = canvas.width
        let srcH = canvas.height
        guard srcW > 0, srcH > 0, targetWidth > 0, targetHeight > 0 else { return nil }

        // Pre-compute source-column for each destination column. Integer
        // scales collapse to exact replication; fractional scales use
        // floor(dst * src / target).
        var xMap = [Int](repeating: 0, count: targetWidth)
        for dx in 0..<targetWidth {
            let sx = (dx * srcW) / targetWidth
            xMap[dx] = min(sx, srcW - 1)
        }
        var yMap = [Int](repeating: 0, count: targetHeight)
        for dy in 0..<targetHeight {
            let sy = (dy * srcH) / targetHeight
            yMap[dy] = min(sy, srcH - 1)
        }

        let srcStride = srcW * 4
        let dstStride = targetWidth * 4
        var dst = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        let src = canvas.rgba

        for dy in 0..<targetHeight {
            let sy = yMap[dy]
            let srcRow = sy * srcStride
            let dstRow = dy * dstStride
            for dx in 0..<targetWidth {
                let sx = xMap[dx]
                let s = srcRow + sx * 4
                let d = dstRow + dx * 4
                dst[d + 0] = src[s + 0]
                dst[d + 1] = src[s + 1]
                dst[d + 2] = src[s + 2]
                dst[d + 3] = src[s + 3]
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(dst) as CFData) else { return nil }
        return CGImage(
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dstStride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Anti-aliasing pass

    /// Optional smoothing pass applied AFTER nearest-neighbour scale. Uses
    /// CoreGraphics `.high` interpolation; output is a same-sized
    /// `CGImage`. Intentionally a separate stage so the chunky-EGA NN
    /// buffer is the option callers can keep by flipping `antiAliasing`
    /// to `false` on `RIPRenderOptions`. Combining NN-replicate + a
    /// downstream blur is a deliberate two-step pipeline so the
    /// pre-AA chunky output is not lost — callers that want pixel-art
    /// fidelity drop the second pass; callers driving a Retina display
    /// keep it.
    public static func antiAliasPass(image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
