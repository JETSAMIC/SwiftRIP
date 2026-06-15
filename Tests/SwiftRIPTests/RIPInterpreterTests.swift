// RIPInterpreterTests — end-to-end command-stream dispatch into the canvas.

import XCTest
@testable import SwiftRIP

final class RIPInterpreterTests: XCTestCase {

    func testSetColorThenPixel() {
        let scene = RIPScene(commands: [
            .color(7),
            .pixel(x: 5, y: 5),
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        XCTAssertEqual(canvas.indexed[5 * canvas.width + 5], 7)
    }

    func testDrawRectangleAndBar() {
        let scene = RIPScene(commands: [
            .color(4),
            .rectangle(x0: 10, y0: 10, x1: 30, y1: 20),
            .fillStyle(pattern: 1, color: 6),
            .bar(x0: 40, y0: 10, x1: 60, y1: 20),
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        // Rectangle border is color 4.
        XCTAssertEqual(canvas.indexed[10 * canvas.width + 10], 4)
        XCTAssertEqual(canvas.indexed[20 * canvas.width + 30], 4)
        // Bar interior is fill color 6.
        XCTAssertEqual(canvas.indexed[15 * canvas.width + 50], 6)
    }

    func testTextDrawsPixels() {
        let scene = RIPScene(commands: [
            .color(15),
            .move(x: 10, y: 10),
            .text("A"),
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        // 'A' in font 0 8x8 has a non-trivial pixel count.
        let count = canvas.indexed.reduce(0) { $0 + ($1 == 15 ? 1 : 0) }
        XCTAssertGreaterThan(count, 5, "letter A should plot some pixels")
    }

    func testSetPaletteApplied() {
        let scene = RIPScene(commands: [
            // Slot 1 to register 4 (red).
            .onePalette(slot: 1, value: 4),
            .color(1),
            .pixel(x: 100, y: 100),
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        XCTAssertEqual(state.palette[1], 4)
        // The RGBA plane should now show that pixel as red.
        let i = (100 * canvas.width + 100) * 4
        XCTAssertEqual(canvas.rgba[i + 0], 0xAA)
        XCTAssertEqual(canvas.rgba[i + 1], 0x00)
        XCTAssertEqual(canvas.rgba[i + 2], 0x00)
    }

    func testLineStyleStateMutation() {
        let scene = RIPScene(commands: [
            .lineStyle(style: 1, userPattern: 0xFFFF, thickness: 3),
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        if case .predefined(let i) = state.lineStyle {
            XCTAssertEqual(i, 1)
        } else {
            XCTFail("expected predefined style 1")
        }
        XCTAssertEqual(state.lineThickness, 3)
    }

    func testFilledPolygon() {
        let scene = RIPScene(commands: [
            .color(2),
            .fillStyle(pattern: 1, color: 14),
            .fillPolygon(points: [
                RIPPoint(x: 100, y: 50),
                RIPPoint(x: 140, y: 50),
                RIPPoint(x: 140, y: 90),
                RIPPoint(x: 100, y: 90),
            ]),
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        XCTAssertEqual(canvas.indexed[70 * canvas.width + 120], 14, "interior of filled polygon")
    }

    func testResetWindowsClearsCanvas() {
        let scene1 = RIPScene(commands: [
            .fillStyle(pattern: 1, color: 3),
            .bar(x0: 0, y0: 0, x1: 100, y1: 50),
        ])
        let scene2 = RIPScene(commands: [
            .resetWindows,
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        _ = RIPInterpreter.interpret(scene1, into: canvas, state: &state)
        XCTAssertEqual(canvas.indexed[10 * canvas.width + 10], 3)
        _ = RIPInterpreter.interpret(scene2, into: canvas, state: &state)
        XCTAssertEqual(canvas.indexed[10 * canvas.width + 10], 0)
    }

    func testInteractiveCapture() {
        let scene = RIPScene(commands: [
            .mouse(num: 1, x0: 10, y0: 10, x1: 50, y1: 20, click: 0, clear: 0, text: "OK", hostCommand: "hi"),
            .query(flags: 0, string: "Are you there?"),
            .noMore,
        ])
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        let inter = RIPInterpreter.interpret(scene, into: canvas, state: &state)
        XCTAssertEqual(inter.mouseFields.count, 1)
        XCTAssertEqual(inter.queries.count, 1)
        XCTAssertTrue(inter.noMore)
        // None of those should plot pixels.
        XCTAssertTrue(canvas.indexed.allSatisfy { $0 == 0 })
    }

    func testPublicFacadeRoundTrip() {
        let scene = RIPScene(commands: [.color(15), .bar(x0: 0, y0: 0, x1: 5, y1: 5)])
        let img = SwiftRIP.render(scene)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 640)
        XCTAssertEqual(img?.height, 350)
    }
}
