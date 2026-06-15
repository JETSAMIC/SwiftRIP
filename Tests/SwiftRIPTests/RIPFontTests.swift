// RIPFontTests — bitmap and vector glyph rendering correctness.

import XCTest
import CoreGraphics
@testable import SwiftRIP

final class RIPFontTests: XCTestCase {

    func testBitmapAExactPixelCount() {
        let canvas = RIPCanvas()
        let state = RIPGraphicsState()
        RIPVectorFonts.renderText("A", at: CGPoint(x: 0, y: 0),
                                  font: 0, direction: 0, size: 1, color: 15,
                                  into: canvas, state: state)
        // Bitmap glyph 'A' (ASCII 65) in our font 0 set:
        //   0x18 — 2 bits
        //   0x3C — 4 bits
        //   0x66 — 4 bits
        //   0x66 — 4 bits
        //   0x7E — 6 bits
        //   0x66 — 4 bits
        //   0x66 — 4 bits
        //   0x00 — 0 bits
        // Total expected = 28.
        let count = canvas.indexed.reduce(0) { $0 + ($1 == 15 ? 1 : 0) }
        XCTAssertEqual(count, 28)
    }

    func testBitmapASize2DoublesPixels() {
        let canvas = RIPCanvas()
        let state = RIPGraphicsState()
        RIPVectorFonts.renderText("A", at: CGPoint(x: 0, y: 0),
                                  font: 0, direction: 0, size: 2, color: 15,
                                  into: canvas, state: state)
        // Each glyph bit becomes a 2x2 pixel block — count quadruples.
        let count = canvas.indexed.reduce(0) { $0 + ($1 == 15 ? 1 : 0) }
        XCTAssertEqual(count, 28 * 4)
    }

    func testVectorAHasNonzeroStrokePixels() {
        let canvas = RIPCanvas()
        let state = RIPGraphicsState()
        RIPVectorFonts.renderText("A", at: CGPoint(x: 10, y: 10),
                                  font: 1, direction: 0, size: 1, color: 11,
                                  into: canvas, state: state)
        let count = canvas.indexed.reduce(0) { $0 + ($1 == 11 ? 1 : 0) }
        XCTAssertGreaterThan(count, 10, "vector A in font 1 must plot some stroke pixels")
    }

    func testVectorAllFamiliesProducePixels() {
        for font in 1...10 {
            let canvas = RIPCanvas()
            let state = RIPGraphicsState()
            RIPVectorFonts.renderText("X", at: CGPoint(x: 10, y: 10),
                                      font: font, direction: 0, size: 1, color: 5,
                                      into: canvas, state: state)
            let count = canvas.indexed.reduce(0) { $0 + ($1 == 5 ? 1 : 0) }
            XCTAssertGreaterThan(count, 1, "font \(font) should plot at least one pixel for 'X'")
        }
    }

    func testBitmapBlankSpaceHasNoPixels() {
        let canvas = RIPCanvas()
        let state = RIPGraphicsState()
        RIPVectorFonts.renderText(" ", at: CGPoint(x: 0, y: 0),
                                  font: 0, direction: 0, size: 1, color: 7,
                                  into: canvas, state: state)
        XCTAssertTrue(canvas.indexed.allSatisfy { $0 == 0 })
    }

    func testHorizontalVsVerticalDirection() {
        let cH = RIPCanvas()
        let cV = RIPCanvas()
        let state = RIPGraphicsState()
        RIPVectorFonts.renderText("I", at: CGPoint(x: 50, y: 50),
                                  font: 0, direction: 0, size: 1, color: 9,
                                  into: cH, state: state)
        RIPVectorFonts.renderText("I", at: CGPoint(x: 50, y: 50),
                                  font: 0, direction: 1, size: 1, color: 9,
                                  into: cV, state: state)
        // Both should plot pixels but in different positions.
        XCTAssertFalse(cH.indexed == cV.indexed)
        XCTAssertTrue(cH.indexed.contains(where: { $0 == 9 }))
        XCTAssertTrue(cV.indexed.contains(where: { $0 == 9 }))
    }
}
