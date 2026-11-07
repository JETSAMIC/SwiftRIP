// RIPPaletteTests — EGA master palette and the default RIPscrip palette.

import XCTest
@testable import SwiftRIP

final class RIPPaletteTests: XCTestCase {

    func testMasterTable() {
        XCTAssertEqual(RIPPalette.master.count, 64)
        XCTAssertEqual(RIPPalette.master[0], RIPPalette.RGB(0, 0, 0))
        XCTAssertEqual(RIPPalette.master[0o07], RIPPalette.RGB(0xAA, 0xAA, 0xAA))
        XCTAssertEqual(RIPPalette.master[0o70], RIPPalette.RGB(0x55, 0x55, 0x55))
        XCTAssertEqual(RIPPalette.master[0o77], RIPPalette.RGB(0xFF, 0xFF, 0xFF))
        XCTAssertEqual(RIPPalette.master[20], RIPPalette.RGB(0xAA, 0x55, 0x00))
    }

    func testDefault16NamedColors() {
        let expected: [RIPPalette.RGB] = [
            .init(0x00, 0x00, 0x00), .init(0x00, 0x00, 0xAA), .init(0x00, 0xAA, 0x00), .init(0x00, 0xAA, 0xAA),
            .init(0xAA, 0x00, 0x00), .init(0xAA, 0x00, 0xAA), .init(0xAA, 0x55, 0x00), .init(0xAA, 0xAA, 0xAA),
            .init(0x55, 0x55, 0x55), .init(0x55, 0x55, 0xFF), .init(0x55, 0xFF, 0x55), .init(0x55, 0xFF, 0xFF),
            .init(0xFF, 0x55, 0x55), .init(0xFF, 0x55, 0xFF), .init(0xFF, 0xFF, 0x55), .init(0xFF, 0xFF, 0xFF),
        ]
        XCTAssertEqual((0..<16).map { RIPPalette.resolve(UInt8($0), in: RIPPalette.default16) }, expected)
    }

    func testResolveIsTotal() {
        XCTAssertEqual(RIPPalette.resolve(200, in: [0, 63]), RIPPalette.master[0])
        XCTAssertEqual(RIPPalette.resolve(1, in: [0, 255]), RIPPalette.master[63])
    }

    func testSetPaletteAndOnePalette() {
        let r = execute([.setPalette(Array(0..<16)), .onePalette(slot: 5, value: 42), .onePalette(slot: 99, value: 1),
                     .onePalette(slot: 6, value: 100)])
        var expected = (0..<16).map(UInt8.init)
        expected[5] = 42
        expected[6] = 100 & 0x3F
        XCTAssertEqual(r.state.palette, expected)
    }

    func testPaletteChangeRecolorsExistingPixels() {
        let r = execute([.color(1), .pixel(x: 100, y: 100), .onePalette(slot: 1, value: 4)])
        let o = (100 * 640 + 100) * 4
        XCTAssertEqual(Array(r.canvas.rgba[o..<(o + 3)]), [0xAA, 0x00, 0x00])
    }
}
