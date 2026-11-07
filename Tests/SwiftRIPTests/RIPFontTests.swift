// RIPFontTests — bitmap and stroke font rendering.

import XCTest
@testable import SwiftRIP

final class RIPFontTests: XCTestCase {

    private func render(_ s: String, font: Int, direction: Int = 0, size: Int = 1, x: Int = 0, y: Int = 0,
                        color: UInt8 = 15) -> RIPCanvas {
        let canvas = RIPCanvas()
        RIPVectorFonts.renderText(s, x: x, y: y, font: font, direction: direction, size: size, color: color,
                                  mode: .copy, into: canvas, clip: canvas.screen)
        return canvas
    }

    func testBitmapAExactPixelCount() {
        // 'A' rows 18 3C 66 66 7E 66 66 00 -> 2+4+4+4+6+4+4 = 28 pixels.
        XCTAssertEqual(render("A", font: 0).indexed.filter { $0 == 15 }.count, 28)
    }

    func testBitmapSize2QuadruplesPixels() {
        XCTAssertEqual(render("A", font: 0, size: 2).indexed.filter { $0 == 15 }.count, 28 * 4)
    }

    func testAllStrokeFontsProducePixels() {
        for font in 1...10 {
            let count = render("X", font: font, x: 10, y: 10, color: 5).indexed.filter { $0 == 5 }.count
            XCTAssertGreaterThan(count, 1, "font \(font)")
        }
    }

    func testSpaceAndNonASCIIDrawNothing() {
        XCTAssertTrue(render(" \u{DB}\u{2603}", font: 0).indexed.allSatisfy { $0 == 0 })
    }

    func testVerticalTextGrowsUpward() {
        let c = render("I", font: 0, direction: 1, x: 50, y: 50)
        var minY = Int.max, maxY = Int.min
        for y in 0..<350 { for x in 0..<640 where c.index(x: x, y: y) == 15 { minY = min(minY, y); maxY = max(maxY, y) } }
        XCTAssertLessThanOrEqual(maxY, 50)
        XCTAssertGreaterThanOrEqual(minY, 43)
    }

    func testMetrics() {
        XCTAssertEqual(RIPVectorFonts.width(of: "abc", font: 0, size: 2), 48)
        XCTAssertEqual(RIPVectorFonts.lineHeight(font: 0, size: 3), 24)
        XCTAssertEqual(RIPVectorFonts.advance(font: 1, size: 0), 12, "size clamps to 1")
    }
}
