// RIPCanvasTests — raster primitives of the palette-indexed framebuffer.

import XCTest
@testable import SwiftRIP

final class RIPCanvasTests: XCTestCase {

    func testPlotInBoundsAndClipped() {
        let c = RIPCanvas()
        c.plot(10, 20, 5, .copy, c.screen)
        c.plot(-1, 10, 4, .copy, c.screen)
        c.plot(640, 10, 4, .copy, c.screen)
        c.plot(10, 350, 4, .copy, c.screen)
        XCTAssertEqual(c.index(x: 10, y: 20), 5)
        XCTAssertEqual(c.indexed.filter { $0 != 0 }.count, 1)
    }

    func testHorizontalAndVerticalLines() {
        let c = RIPCanvas()
        c.line(5, 10, 20, 10, pen: Pen(color: 3), clip: c.screen)
        c.line(50, 5, 50, 15, pen: Pen(color: 2), clip: c.screen)
        for x in 5...20 { XCTAssertEqual(c.index(x: x, y: 10), 3) }
        for y in 5...15 { XCTAssertEqual(c.index(x: 50, y: y), 2) }
    }

    /// RIP_LINE_STYLE: the most-significant bit of the pattern is plotted at
    /// the line's starting point.
    func testLinePatternMSBFirst() {
        let c = RIPCanvas()
        c.line(0, 0, 15, 0, pen: Pen(color: 1, mask: 0xF000), clip: c.screen)
        XCTAssertEqual((0..<16).map { c.index(x: $0, y: 0) }, [1, 1, 1, 1] + Array(repeating: 0, count: 12))
    }

    func testThickLineIsThreePixelsWide() {
        let c = RIPCanvas()
        c.line(10, 10, 30, 10, pen: Pen(color: 4, thickness: 3), clip: c.screen)
        XCTAssertEqual(c.index(x: 20, y: 9), 4)
        XCTAssertEqual(c.index(x: 20, y: 10), 4)
        XCTAssertEqual(c.index(x: 20, y: 11), 4)
        XCTAssertEqual(c.index(x: 20, y: 12), 0)
    }

    func testXORPlotToggles() {
        let c = RIPCanvas()
        c.plot(30, 30, 5, .copy, c.screen)
        c.plot(30, 30, 5, .xor, c.screen)
        XCTAssertEqual(c.index(x: 30, y: 30), 0)
        c.plot(30, 30, 3, .xor, c.screen)
        c.plot(30, 30, 6, .xor, c.screen)
        XCTAssertEqual(c.index(x: 30, y: 30), 5)
    }

    func testFillRectUsesPatternAndBackground() {
        let c = RIPCanvas()
        c.clear(to: 9)
        let spec = FillSpec(rows: RIPFillPattern.predefinedRows[2], color: 7) // line fill
        c.fillRect(x0: 0, y0: 0, x1: 15, y1: 7, fill: spec, clip: c.screen)
        XCTAssertEqual(c.index(x: 3, y: 0), 7)
        XCTAssertEqual(c.index(x: 3, y: 2), 0, "clear pattern bits are background color 0")
        XCTAssertEqual(c.index(x: 3, y: 8), 9, "outside untouched")
    }

    func testFloodFillStopsAtBorder() {
        let c = RIPCanvas()
        let r = RIPInterpreter(canvas: c)
        r.drawRectangle(50, 50, 60, 60, pen: Pen(color: 4), clip: c.screen)
        c.floodFill(x: 55, y: 55, border: 4, fill: FillSpec(rows: RIPFillPattern.predefinedRows[1], color: 9), clip: c.screen)
        XCTAssertEqual(c.index(x: 50, y: 50), 4)
        XCTAssertEqual(c.index(x: 55, y: 55), 9)
        XCTAssertEqual(c.index(x: 51, y: 59), 9)
        XCTAssertEqual(c.index(x: 40, y: 40), 0)
    }

    func testFloodFillStartingOnBorderIsNoOp() {
        let c = RIPCanvas()
        c.clear(to: 4)
        c.floodFill(x: 5, y: 5, border: 4, fill: FillSpec(rows: RIPFillPattern.predefinedRows[1], color: 9), clip: c.screen)
        XCTAssertTrue(c.indexed.allSatisfy { $0 == 4 })
    }

    /// The fill color equals the border color: a naive fill re-enters its own
    /// output; the visited-set fill must terminate and paint each pixel once.
    func testFloodFillWithFillColorEqualToBorderTerminates() {
        let c = RIPCanvas()
        let spec = FillSpec(rows: RIPFillPattern.predefinedRows[8], color: 4)
        c.floodFill(x: 320, y: 175, border: 4, fill: spec, clip: c.screen)
        XCTAssertEqual(c.pixelWrites, 640 * 350)
    }

    func testCGImageSnapshot() {
        let c = RIPCanvas()
        let img = c.framebuffer.cgImage()
        XCTAssertEqual(img?.width, 640)
        XCTAssertEqual(img?.height, 350)
    }

    func testFramebufferAccessors() {
        let c = RIPCanvas()
        c.plot(1, 2, 12, .copy, c.screen)
        let fb = c.framebuffer
        XCTAssertEqual(fb.colorIndex(x: 1, y: 2), 12)
        XCTAssertNil(fb.colorIndex(x: -1, y: 0))
        XCTAssertNil(fb.colorIndex(x: 640, y: 0))
        let o = (2 * 640 + 1) * 4
        XCTAssertEqual(Array(fb.rgba[o..<(o + 4)]), [0xFF, 0x55, 0x55, 0xFF]) // light red
    }
}
