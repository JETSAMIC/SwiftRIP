// RIPPaletteTests — spec-table values for the default 16 RIP palette
// entries, plus mutator behavior.

import XCTest
@testable import SwiftRIP

final class RIPPaletteTests: XCTestCase {

    func testMasterTableSize() {
        XCTAssertEqual(RIPPalette.master.count, 64)
    }

    func testDefault16Length() {
        XCTAssertEqual(RIPPalette.default16.count, 16)
    }

    func testDefault16NamedColors() {
        // Spot-check the canonical EGA colors.
        let p = RIPPalette.default16
        XCTAssertEqual(RIPPalette.master[Int(p[0])],  RIPPalette.RGB(0x00, 0x00, 0x00))  // black
        XCTAssertEqual(RIPPalette.master[Int(p[1])],  RIPPalette.RGB(0x00, 0x00, 0xAA))  // blue
        XCTAssertEqual(RIPPalette.master[Int(p[2])],  RIPPalette.RGB(0x00, 0xAA, 0x00))  // green
        XCTAssertEqual(RIPPalette.master[Int(p[3])],  RIPPalette.RGB(0x00, 0xAA, 0xAA))  // cyan
        XCTAssertEqual(RIPPalette.master[Int(p[4])],  RIPPalette.RGB(0xAA, 0x00, 0x00))  // red
        XCTAssertEqual(RIPPalette.master[Int(p[5])],  RIPPalette.RGB(0xAA, 0x00, 0xAA))  // magenta
        XCTAssertEqual(RIPPalette.master[Int(p[6])],  RIPPalette.RGB(0xAA, 0x55, 0x00))  // brown
        XCTAssertEqual(RIPPalette.master[Int(p[7])],  RIPPalette.RGB(0xAA, 0xAA, 0xAA))  // lightgray
        XCTAssertEqual(RIPPalette.master[Int(p[8])],  RIPPalette.RGB(0x55, 0x55, 0x55))  // darkgray
        XCTAssertEqual(RIPPalette.master[Int(p[15])], RIPPalette.RGB(0xFF, 0xFF, 0xFF))  // white
    }

    func testSetAll() {
        var state = RIPGraphicsState()
        let values = Array(0..<16)
        RIPPalette.setAll(values, on: &state)
        XCTAssertEqual(state.palette, values.map { UInt8($0) })
    }

    func testSetOne() {
        var state = RIPGraphicsState()
        let before = state.palette[5]
        RIPPalette.setOne(slot: 5, value: 42, on: &state)
        XCTAssertEqual(state.palette[5], 42)
        XCTAssertNotEqual(state.palette[5], before)
    }

    func testSetOneOutOfBounds() {
        var state = RIPGraphicsState()
        let original = state.palette
        RIPPalette.setOne(slot: 99, value: 1, on: &state)
        XCTAssertEqual(state.palette, original)
    }
}
