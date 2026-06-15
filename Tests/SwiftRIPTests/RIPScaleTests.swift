// RIPScaleTests — nearest-neighbour pixel-replicate behavior on integer
// and non-integer target sizes.
//
// The native 640x350 framebuffer is the renderer's contract; the
// compositor's job is to lift it to a target display size without
// blurring individual EGA pixels. These tests pin down both halves:
// integer scales must duplicate pixels exactly; fractional scales must
// floor-replicate per pixel.

import XCTest
import CoreGraphics
@testable import SwiftRIP

final class RIPScaleTests: XCTestCase {

    /// Drop a tiny isolated rectangle into the canvas so we can read
    /// individual pixels back through the scaled CGImage. Returns the
    /// expected RGB triplet for palette index 15 (white in the default
    /// 16-color RIP palette) and the canvas.
    private func tinyCanvasWithPixel(at x: Int, y: Int, color: UInt8 = 15) -> RIPCanvas {
        let canvas = RIPCanvas()
        let state = RIPGraphicsState()
        canvas.palette = state.palette
        canvas.clear(to: 0)
        canvas.setPixel(x: x, y: y, color: color, state: state)
        return canvas
    }

    private func sample(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
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
        let o = y * bytesPerRow + x * 4
        return (buf[o + 0], buf[o + 1], buf[o + 2])
    }

    // MARK: - Integer 2x scale: 640x350 -> 1280x700

    func testIntegerDoubleScaleReplicatesPixels() {
        // Plant a white pixel at (10, 20) on the native canvas.
        let canvas = tinyCanvasWithPixel(at: 10, y: 20)
        let scaled = RIPCompositor.nearestNeighbourScale(canvas: canvas, targetWidth: 1280, targetHeight: 700)
        XCTAssertNotNil(scaled)
        let img = scaled!
        XCTAssertEqual(img.width, 1280)
        XCTAssertEqual(img.height, 700)

        // Source pixel (10, 20) maps to destination columns [20, 21] and
        // destination rows [40, 41] under exact 2x replication.
        for dy in 40...41 {
            for dx in 20...21 {
                let (r, g, b) = sample(img, x: dx, y: dy)
                XCTAssertEqual(r, 255, "pixel (\(dx),\(dy)) should be white")
                XCTAssertEqual(g, 255)
                XCTAssertEqual(b, 255)
            }
        }
        // Pixels immediately outside the 2x2 cluster must still be black.
        let outside = sample(img, x: 19, y: 40)
        XCTAssertEqual(outside.0, 0)
        XCTAssertEqual(outside.1, 0)
        XCTAssertEqual(outside.2, 0)
        let outsideRight = sample(img, x: 22, y: 40)
        XCTAssertEqual(outsideRight.0, 0)
    }

    // MARK: - Non-integer scale: 640x350 -> 1920x1080

    func testFractionalScaleFloorReplicates() {
        // Plant a white pixel at native (100, 50). The fractional scale
        // is 1920/640 = 3.0 horizontally (still integer) and 1080/350 ≈
        // 3.0857 vertically. Vertical mapping is dy * 350 / 1080.
        let canvas = tinyCanvasWithPixel(at: 100, y: 50)
        let scaled = RIPCompositor.nearestNeighbourScale(canvas: canvas, targetWidth: 1920, targetHeight: 1080)
        XCTAssertNotNil(scaled)
        let img = scaled!
        XCTAssertEqual(img.width, 1920)
        XCTAssertEqual(img.height, 1080)

        // Find every destination row that maps to source row 50: those
        // where floor(dy * 350 / 1080) == 50. That range is
        // dy in [ceil(50*1080/350), floor(51*1080/350)-1] = [155, 157].
        let lo = 155
        let hi = 157
        let dxRange = 300...302 // 100 * 3 = 300

        for dy in lo...hi {
            for dx in dxRange {
                let (r, g, b) = sample(img, x: dx, y: dy)
                XCTAssertEqual(r, 255, "destination (\(dx),\(dy)) should map to source (100,50)")
                XCTAssertEqual(g, 255)
                XCTAssertEqual(b, 255)
            }
        }
        // One row above the cluster (dy = 154) maps to source row 49 —
        // black.
        let above = sample(img, x: 300, y: 154)
        XCTAssertEqual(above.0, 0)
        XCTAssertEqual(above.1, 0)
        XCTAssertEqual(above.2, 0)
        // One row below the cluster (dy = 158) maps to source row 51 —
        // black.
        let below = sample(img, x: 300, y: 158)
        XCTAssertEqual(below.0, 0)
        XCTAssertEqual(below.1, 0)
        XCTAssertEqual(below.2, 0)
    }

    // MARK: - composeFromScene with targetSize honors the pipeline

    func testComposeWithTargetSizeProducesScaledImage() {
        let scene = RIPScene(commands: [
            .color(15),
            .pixel(x: 5, y: 5)
        ])
        var opts = RIPRenderOptions()
        opts.targetSize = CGSize(width: 1280, height: 700)
        opts.antiAliasing = false
        let img = SwiftRIP.render(scene, options: opts)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 1280)
        XCTAssertEqual(img?.height, 700)
    }

    // MARK: - Default options yield native 640x350 image

    func testDefaultOptionsYieldNativeSize() {
        let scene = RIPScene(commands: [])
        let img = SwiftRIP.render(scene, options: .default)
        XCTAssertEqual(img?.width, 640)
        XCTAssertEqual(img?.height, 350)
    }
}
