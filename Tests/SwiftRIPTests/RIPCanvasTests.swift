// RIPCanvasTests — primitive pixel-level behavior of the framebuffer.

import XCTest
@testable import SwiftRIP

final class RIPCanvasTests: XCTestCase {

    func testSetPixelInBounds() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        c.setPixel(x: 10, y: 20, color: 5, state: s)
        XCTAssertEqual(c.indexed[20 * c.width + 10], 5)
    }

    func testSetPixelOutOfBounds() {
        let c = RIPCanvas()
        let s = RIPGraphicsState()
        c.setPixel(x: -1, y: 10, color: 4, state: s)
        c.setPixel(x: 640, y: 10, color: 4, state: s)
        c.setPixel(x: 10, y: 350, color: 4, state: s)
        // No crash, no plotting outside bounds — all pixels remain 0.
        XCTAssertTrue(c.indexed.allSatisfy { $0 == 0 })
    }

    func testHorizontalLine() {
        let c = RIPCanvas()
        let s = RIPGraphicsState()
        c.drawLine(x0: 5, y0: 10, x1: 20, y1: 10, color: 3, state: s)
        for x in 5...20 {
            XCTAssertEqual(c.indexed[10 * c.width + x], 3, "pixel at (\(x),10) should be 3")
        }
    }

    func testVerticalLine() {
        let c = RIPCanvas()
        let s = RIPGraphicsState()
        c.drawLine(x0: 50, y0: 5, x1: 50, y1: 15, color: 2, state: s)
        for y in 5...15 {
            XCTAssertEqual(c.indexed[y * c.width + 50], 2, "pixel at (50,\(y)) should be 2")
        }
    }

    func testFillRectangleBounded() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        s.drawColor = 1
        s.fillColor = 7
        s.fillPattern = .predefined(1) // solid
        c.fillRectangle(x0: 100, y0: 100, x1: 110, y1: 110, state: s)
        // Inside the rect, every pixel = fill color (solid pattern).
        for y in 100...110 {
            for x in 100...110 {
                XCTAssertEqual(c.indexed[y * c.width + x], 7)
            }
        }
        // Outside the rect, untouched.
        XCTAssertEqual(c.indexed[99 * c.width + 100], 0)
        XCTAssertEqual(c.indexed[111 * c.width + 100], 0)
    }

    func testFloodFillBoundaryStops() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        s.drawColor = 9
        s.fillColor = 9
        s.fillPattern = .predefined(1)
        // Draw a closed 10x10 rectangle border in color 4.
        c.drawRectangle(x0: 50, y0: 50, x1: 60, y1: 60, color: 4, state: s)
        // Flood inside (51,51) with fill color 9, border 4.
        c.floodFill(x: 55, y: 55, border: 4, state: s)
        // Border pixels remain color 4.
        XCTAssertEqual(c.indexed[50 * c.width + 50], 4)
        XCTAssertEqual(c.indexed[55 * c.width + 50], 4)
        // Interior pixels are now color 9.
        XCTAssertEqual(c.indexed[55 * c.width + 55], 9)
        // Outside the rectangle remains background.
        XCTAssertEqual(c.indexed[40 * c.width + 40], 0)
    }

    func testFloodFillStartOnBorderIsNoOp() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        s.fillColor = 9
        s.fillPattern = .predefined(1)
        c.drawRectangle(x0: 50, y0: 50, x1: 60, y1: 60, color: 4, state: s)
        c.floodFill(x: 50, y: 50, border: 4, state: s)
        // Start pixel was already border color — nothing filled.
        XCTAssertEqual(c.indexed[55 * c.width + 55], 0)
    }

    func testXORWriteModeInverts() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        // Plot a pixel in copy mode then again in XOR with the same value —
        // it should toggle back to 0.
        s.writeMode = .copy
        c.setPixel(x: 30, y: 30, color: 5, state: s)
        XCTAssertEqual(c.indexed[30 * c.width + 30], 5)
        s.writeMode = .xor
        c.setPixel(x: 30, y: 30, color: 5, state: s)
        XCTAssertEqual(c.indexed[30 * c.width + 30], 0)
    }

    func testCircleBoundingBox() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        s.drawColor = 11
        c.drawCircle(cx: 100, cy: 100, radius: 20, color: 11, state: s)
        // Top, bottom, left, right of the bounding box should be set.
        // The Y-radius is reduced 7/10 of X-radius per spec aspect, so top
        // is at cy - 14 and bottom at cy + 14.
        XCTAssertEqual(c.indexed[(100 - 14) * c.width + 100], 11)
        XCTAssertEqual(c.indexed[(100 + 14) * c.width + 100], 11)
        XCTAssertEqual(c.indexed[100 * c.width + (100 - 20)], 11)
        XCTAssertEqual(c.indexed[100 * c.width + (100 + 20)], 11)
    }

    func testViewportClips() {
        let c = RIPCanvas()
        var s = RIPGraphicsState()
        s.drawColor = 6
        s.viewport = .rect(x0: 100, y0: 100, x1: 200, y1: 150)
        c.setPixel(x: 50, y: 50, color: 6, state: s)
        c.setPixel(x: 150, y: 125, color: 6, state: s)
        XCTAssertEqual(c.indexed[50 * c.width + 50], 0)  // outside viewport
        XCTAssertEqual(c.indexed[125 * c.width + 150], 6) // inside
    }

    func testCGImageSnapshot() {
        let c = RIPCanvas()
        let img = c.cgImage()
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 640)
        XCTAssertEqual(img?.height, 350)
    }
}
