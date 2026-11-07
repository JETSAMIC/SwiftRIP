// RIPCompositor — scale the native 640x350 framebuffer to a target size.
//
// Scaling is nearest-neighbour in pure Swift, so EGA pixels stay hard-edged;
// the optional smoothing pass is a separate CoreGraphics step (downscale to
// half size and back up with high-quality interpolation).

#if canImport(CoreGraphics)
import Foundation
import CoreGraphics

/// Composition of the native framebuffer into the requested output image.
enum RIPCompositor {

    /// Largest accepted output dimension.
    static let maxDimension = 16_384

    /// Native image when `options.targetSize` is `nil`, otherwise the scaled
    /// (and optionally smoothed) image.
    static func compose(_ framebuffer: RIPFramebuffer, options: RIPRenderOptions) -> CGImage? {
        let rgba = framebuffer.rgba
        guard let target = options.targetSize else {
            return RIPFramebuffer.makeImage(rgba: rgba, width: framebuffer.width, height: framebuffer.height)
        }
        let w = dimension(target.width)
        let h = dimension(target.height)
        guard let scaled = nearestNeighbourScale(rgba: rgba, width: framebuffer.width, height: framebuffer.height,
                                                 targetWidth: w, targetHeight: h) else { return nil }
        if options.antiAliasing {
            return antiAliasPass(image: scaled, width: w, height: h) ?? scaled
        }
        return scaled
    }

    static func dimension(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 1 }
        return Swift.max(1, Swift.min(maxDimension, Int(value.rounded())))
    }

    /// Nearest-neighbour scale: destination pixel `d` samples source pixel
    /// `floor(d * src / target)`.
    static func nearestNeighbourScale(rgba src: [UInt8], width srcW: Int, height srcH: Int,
                                      targetWidth: Int, targetHeight: Int) -> CGImage? {
        guard srcW > 0, srcH > 0, targetWidth > 0, targetHeight > 0, src.count == srcW * srcH * 4 else { return nil }
        let xMap = (0..<targetWidth).map { Swift.min($0 * srcW / targetWidth, srcW - 1) }
        var dst = [UInt8](repeating: 255, count: targetWidth * targetHeight * 4)
        for dy in 0..<targetHeight {
            let sy = Swift.min(dy * srcH / targetHeight, srcH - 1)
            let srcRow = sy * srcW * 4
            let dstRow = dy * targetWidth * 4
            for dx in 0..<targetWidth {
                let s = srcRow + xMap[dx] * 4
                let d = dstRow + dx * 4
                dst[d] = src[s]
                dst[d + 1] = src[s + 1]
                dst[d + 2] = src[s + 2]
            }
        }
        return RIPFramebuffer.makeImage(rgba: dst, width: targetWidth, height: targetHeight)
    }

    /// Smooth an image by resampling it to half size and back with
    /// high-quality interpolation.
    static func antiAliasPass(image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        let halfW = Swift.max(1, width / 2), halfH = Swift.max(1, height / 2)
        guard let down = CGContext(data: nil, width: halfW, height: halfH, bitsPerComponent: 8,
                                   bytesPerRow: halfW * 4, space: space, bitmapInfo: info) else { return nil }
        down.interpolationQuality = .high
        down.draw(image, in: CGRect(x: 0, y: 0, width: halfW, height: halfH))
        guard let downImage = down.makeImage(),
              let up = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                 bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
        up.interpolationQuality = .high
        up.draw(downImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return up.makeImage()
    }
}
#endif
