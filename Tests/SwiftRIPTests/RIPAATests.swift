// RIPAATests — anti-aliasing pass behavior.
//
// The compositor's AA pass is OFF by default for the NN-only path and ON
// by default at the public-API surface (`RIPRenderOptions.antiAliasing
// == true`). These tests pin down the visible difference: AA-off must
// produce a hard pixel edge (only the two source colors appear); AA-on
// must produce at least one intermediate gradient value at the edge.

import XCTest
import CoreGraphics
@testable import SwiftRIP

final class RIPAATests: XCTestCase {

    /// Render a large filled rectangle (palette 15 = white) into the
    /// native canvas so the scaled output has a long high-contrast edge
    /// that AA can either smooth or leave hard.
    private func sceneWithHardEdge() -> RIPScene {
        return RIPScene(commands: [
            .color(15),
            .fillStyle(pattern: 1, color: 15),
            .bar(x0: 100, y0: 50, x1: 300, y1: 200)
        ])
    }

    /// Pull the full RGBA buffer out of a CGImage so we can scan rows
    /// for intermediate gradient values.
    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width
        let h = image.height
        let bytesPerRow = w * 4
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        let ctx = CGContext(
            data: &buf,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bitmap
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }

    /// Count how many pixels along a horizontal row at `y` have a red
    /// channel strictly between 1 and 254 (i.e. neither pure black nor
    /// pure white). High counts mean smoothed gradient; zero means hard
    /// edge.
    private func intermediatePixelCount(_ buf: [UInt8], width: Int, y: Int) -> Int {
        let row = y * width * 4
        var count = 0
        for x in 0..<width {
            let r = buf[row + x * 4]
            if r > 0 && r < 255 {
                count += 1
            }
        }
        return count
    }

    func testAAOffProducesHardPixelEdges() {
        var opts = RIPRenderOptions()
        opts.targetSize = CGSize(width: 1280, height: 700)
        opts.antiAliasing = false
        let img = SwiftRIP.render(sceneWithHardEdge(), options: opts)
        XCTAssertNotNil(img)
        let buf = pixels(of: img!)
        // Scan a row that crosses the rectangle edge horizontally.
        // y0 = 50 in native maps to y ≈ 100 in 700-tall image.
        let intermediates = intermediatePixelCount(buf, width: 1280, y: 200)
        XCTAssertEqual(intermediates, 0,
            "AA-off must produce hard pixel edges — found \(intermediates) intermediate gradient pixels")
    }

    func testAAOnProducesSmoothedEdges() {
        var opts = RIPRenderOptions()
        opts.targetSize = CGSize(width: 1280, height: 700)
        opts.antiAliasing = true
        let img = SwiftRIP.render(sceneWithHardEdge(), options: opts)
        XCTAssertNotNil(img)
        let buf = pixels(of: img!)
        // The smoothing should produce intermediate values along the
        // bar edge. Sweep a few rows where the bar lives.
        var totalIntermediates = 0
        for y in stride(from: 150, through: 350, by: 25) {
            totalIntermediates += intermediatePixelCount(buf, width: 1280, y: y)
        }
        XCTAssertGreaterThan(totalIntermediates, 0,
            "AA-on must produce at least one smoothed (intermediate-value) pixel along the bar edge")
    }

    func testDefaultOptionsHaveAntiAliasingOn() {
        let opts = RIPRenderOptions.default
        XCTAssertTrue(opts.antiAliasing,
            "Default RIPRenderOptions must have antiAliasing == true for modern displays")
    }

    func testDefaultAnimationModeIsStatic() {
        let opts = RIPRenderOptions.default
        XCTAssertEqual(opts.animation, .static)
    }

    func testDefaultTargetSizeIsNilForNative640x350() {
        let opts = RIPRenderOptions.default
        XCTAssertNil(opts.targetSize)
    }
}
