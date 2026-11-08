// RIPInterpreterTests — command semantics from the RIPscrip 1.54 spec,
// checked pixel by pixel on the native framebuffer.

import XCTest
@testable import SwiftRIP

final class RIPInterpreterTests: XCTestCase {

    private func count(_ r: RIPInterpreter, _ color: UInt8) -> Int {
        r.canvas.indexed.filter { $0 == color }.count
    }

    // MARK: - Basics

    func testColorThenPixel() {
        let r = execute([.color(7), .pixel(x: 5, y: 5)])
        XCTAssertEqual(r.px(5, 5), 7)
    }

    func testInitialStateMatchesResetTerminal() {
        let s = RIPGraphicsState()
        XCTAssertEqual(s.viewport, .rect(x0: 0, y0: 0, x1: 639, y1: 349))
        XCTAssertEqual(s.textWindow, RIPTextWindow(x0: 0, y0: 0, x1: 79, y1: 42, wrap: 1, size: 0))
        XCTAssertEqual(s.palette, RIPPalette.default16)
    }

    func testRectangleAndBar() {
        let r = execute([.color(4), .rectangle(x0: 30, y0: 20, x1: 10, y1: 10),
                     .fillStyle(pattern: 1, color: 6), .bar(x0: 40, y0: 10, x1: 60, y1: 20)])
        XCTAssertEqual(r.px(10, 10), 4)
        XCTAssertEqual(r.px(30, 20), 4)
        XCTAssertEqual(r.px(20, 15), 0, "rectangle is not filled")
        XCTAssertEqual(r.px(50, 15), 6)
        XCTAssertEqual(r.px(40, 10), 6, "bar has no border")
    }

    // MARK: - Viewport (RIP_VIEWPORT)

    func testViewportRelativeCoordinatesAndClipping() {
        let r = execute([.viewport(x0: 100, y0: 100, x1: 200, y1: 150), .color(6),
                     .pixel(x: 0, y: 0), .line(x0: 0, y0: 10, x1: 300, y1: 10)])
        XCTAssertEqual(r.px(100, 100), 6, "coordinates are relative to the viewport origin")
        XCTAssertEqual(r.px(0, 0), 0)
        XCTAssertEqual(r.px(200, 110), 6)
        XCTAssertEqual(r.px(201, 110), 0, "clipped at the viewport edge")
    }

    func testDisabledViewportIgnoresDrawing() {
        let r = execute([.viewport(x0: 0, y0: 0, x1: 0, y1: 0), .color(6), .pixel(x: 5, y: 5),
                     .fillStyle(pattern: 1, color: 3), .bar(x0: 0, y0: 0, x1: 10, y1: 10),
                     .move(x: 9, y: 9), .fill(x: 1, y: 1, border: 15)])
        XCTAssertTrue(r.canvas.indexed.allSatisfy { $0 == 0 })
        XCTAssertEqual(r.state.position, RIPPoint(x: 0, y: 0), "move is ignored too")
    }

    func testEraseViewClearsOnlyViewport() {
        let r = execute([.fillStyle(pattern: 1, color: 3), .bar(x0: 0, y0: 0, x1: 639, y1: 349),
                     .viewport(x0: 10, y0: 10, x1: 20, y1: 20), .eraseView])
        XCTAssertEqual(r.px(15, 15), 0)
        XCTAssertEqual(r.px(9, 15), 3)
        XCTAssertEqual(r.px(21, 15), 3)
    }

    // MARK: - Drawing position

    func testTextAdvancesPositionAndLineDoesNot() {
        let r = execute([.move(x: 10, y: 10), .text("AB"), .line(x0: 0, y0: 0, x1: 100, y1: 100)])
        XCTAssertEqual(r.state.position, RIPPoint(x: 26, y: 10))
        XCTAssertGreaterThan(count(r, 15), 28)
    }

    func testVerticalTextDoesNotMovePosition() {
        let r = execute([.fontStyle(font: 0, direction: 1, size: 1, reserved: 0), .textXY(x: 5, y: 60, string: "Hi")])
        XCTAssertEqual(r.state.position, RIPPoint(x: 5, y: 60))
    }

    func testTextXYMovesPositionPastText() {
        let r = execute([.fontStyle(font: 0, direction: 0, size: 2, reserved: 0), .textXY(x: 5, y: 6, string: "Hi")])
        XCTAssertEqual(r.state.position, RIPPoint(x: 5 + 32, y: 6))
    }

    // MARK: - Write mode (RIP_WRITE_MODE)

    func testXORLineTwiceRestores() {
        let r = execute([.fillStyle(pattern: 1, color: 5), .bar(x0: 0, y0: 0, x1: 50, y1: 50), .writeMode(1), .color(3),
                     .line(x0: 0, y0: 25, x1: 50, y1: 25)])
        XCTAssertEqual(r.px(10, 25), 5 ^ 3)
        r.step(.line(x0: 0, y0: 25, x1: 50, y1: 25))
        XCTAssertEqual(r.px(10, 25), 5)
    }

    func testXORRectangleDoesNotCancelCorners() {
        let r = execute([.writeMode(1), .color(9), .rectangle(x0: 10, y0: 10, x1: 20, y1: 20)])
        for (x, y) in [(10, 10), (20, 10), (10, 20), (20, 20)] {
            XCTAssertEqual(r.px(x, y), 9, "corner (\(x),\(y))")
        }
    }

    func testCommandsWithoutWriteModeAlwaysCopy() {
        let r = execute([.fillStyle(pattern: 1, color: 5), .bar(x0: 0, y0: 0, x1: 50, y1: 50), .writeMode(1), .color(3),
                     .pixel(x: 1, y: 1), .bar(x0: 10, y0: 10, x1: 12, y1: 12), .circle(x: 30, y: 30, radius: 5)])
        XCTAssertEqual(r.px(1, 1), 3, "RIP_PIXEL does not use the write mode")
        XCTAssertEqual(r.px(11, 11), 5, "RIP_BAR does not use the write mode")
        XCTAssertEqual(r.px(35, 30), 3, "RIP_CIRCLE does not use the write mode")
    }

    // MARK: - Fill styles

    func testFillPatternClearBitsUseBackgroundNotDrawColor() {
        let r = execute([.color(14), .fillStyle(pattern: 2, color: 4), .bar(x0: 0, y0: 0, x1: 7, y1: 7)])
        XCTAssertEqual(r.px(0, 0), 4)
        XCTAssertEqual(r.px(0, 2), 0)
    }

    func testPredefinedPatternsMatchSpecTable() {
        XCTAssertEqual(RIPFillPattern.predefinedRows[3], [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80])
        XCTAssertEqual(RIPFillPattern.predefinedRows[5], [0xF0, 0x78, 0x3C, 0x1E, 0x0F, 0x87, 0xC3, 0xE1])
        XCTAssertEqual(RIPFillPattern.predefinedRows[6], [0xA5, 0xD2, 0x69, 0xB4, 0x5A, 0x2D, 0x96, 0x4B])
        XCTAssertEqual(RIPFillPattern.predefinedRows[7], [0xFF, 0x88, 0x88, 0x88, 0xFF, 0x88, 0x88, 0x88])
        let r = execute([.fillStyle(pattern: 3, color: 2), .bar(x0: 0, y0: 0, x1: 7, y1: 7)])
        XCTAssertEqual(r.px(7, 0), 2)
        XCTAssertEqual(r.px(0, 7), 2)
        XCTAssertEqual(r.px(0, 0), 0)
    }

    func testCustomFillPattern() {
        let r = execute([.fillPattern(bytes: [0x80, 0, 0, 0, 0, 0, 0, 0], color: 12), .bar(x0: 0, y0: 0, x1: 15, y1: 15)])
        XCTAssertEqual(r.px(0, 0), 12)
        XCTAssertEqual(r.px(8, 8), 12)
        XCTAssertEqual(r.px(1, 0), 0)
    }

    // MARK: - Line styles

    func testLineStyleMapping() {
        var r = execute([.lineStyle(style: 4, userPattern: 0xF0F0, thickness: 3)])
        XCTAssertEqual(r.state.lineStyle, .user(0xF0F0))
        XCTAssertEqual(r.state.lineThickness, 3)
        r = execute([.lineStyle(style: 9, userPattern: 0, thickness: 2)])
        XCTAssertEqual(r.state.lineStyle, .predefined(0))
        XCTAssertEqual(r.state.lineThickness, 1)
        r = execute([.lineStyle(style: 1, userPattern: 0, thickness: 1), .line(x0: 0, y0: 0, x1: 15, y1: 0)])
        XCTAssertEqual((0..<16).map { r.px($0, 0) == 15 }, (0..<16).map { (0x3333 >> (15 - $0)) & 1 == 1 })
    }

    // MARK: - Circles, arcs, slices

    func testCircleIsAspectCorrected() {
        let r = execute([.circle(x: 100, y: 100, radius: 48)])
        XCTAssertEqual(r.px(148, 100), 15)
        XCTAssertEqual(r.px(52, 100), 15)
        XCTAssertEqual(r.px(100, 65), 15, "y radius = 48 * 350 / 480 = 35")
        XCTAssertEqual(r.px(100, 135), 15)
        XCTAssertEqual(r.px(100, 64), 0)
    }

    func testArcAnglesCounterClockwiseFromThreeOClock() {
        let r = execute([.arc(x: 100, y: 100, startAngle: 0, endAngle: 90, radius: 40)])
        XCTAssertEqual(r.px(140, 100), 15, "0 degrees is 3 o'clock")
        XCTAssertEqual(r.px(100, 100 - RIPInterpreter.aspectRadius(40)), 15, "90 degrees is 12 o'clock")
        XCTAssertEqual(r.px(60, 100), 0, "180 degrees not drawn")
        XCTAssertEqual(r.px(100, 100 + RIPInterpreter.aspectRadius(40)), 0, "270 degrees not drawn")
    }

    func testArcWithEqualAnglesDrawsNothing() {
        let r = execute([.arc(x: 100, y: 100, startAngle: 45, endAngle: 45, radius: 40),
                     .ovalArc(x: 100, y: 100, startAngle: 10, endAngle: 10, xrad: 40, yrad: 20)])
        XCTAssertEqual(count(r, 15), 0)
    }

    func testFullOvalArc() {
        let r = execute([.ovalArc(x: 100, y: 100, startAngle: 0, endAngle: 360, xrad: 40, yrad: 20)])
        XCTAssertEqual(r.px(60, 100), 15)
        XCTAssertEqual(r.px(140, 100), 15)
        XCTAssertEqual(r.px(100, 80), 15)
        XCTAssertEqual(r.px(100, 120), 15)
    }

    func testPieSliceFillsAndOutlines() {
        let r = execute([.color(2), .fillStyle(pattern: 1, color: 9),
                     .pieSlice(x: 100, y: 100, startAngle: 0, endAngle: 90, radius: 40)])
        XCTAssertEqual(r.px(110, 95), 9, "interior filled")
        XCTAssertEqual(r.px(120, 100), 2, "radius line in draw color")
        XCTAssertEqual(r.px(90, 105), 0, "outside the slice")
    }

    func testFilledOvalOutlineAndInterior() {
        let r = execute([.color(2), .fillStyle(pattern: 1, color: 9), .filledOval(x: 100, y: 100, xrad: 30, yrad: 10)])
        XCTAssertEqual(r.px(100, 100), 9)
        XCTAssertEqual(r.px(130, 100), 2)
        XCTAssertEqual(r.px(100, 90), 2)
    }

    // MARK: - Bezier and polygons

    func testBezierEndpointsAndSegmentCount() {
        let r = execute([.bezier(x0: 10, y0: 10, x1: 20, y1: 40, x2: 40, y2: 40, x3: 50, y3: 10, count: 8)])
        XCTAssertEqual(r.px(10, 10), 15)
        XCTAssertEqual(r.px(50, 10), 15)
        let none = execute([.bezier(x0: 10, y0: 10, x1: 20, y1: 40, x2: 40, y2: 40, x3: 50, y3: 10, count: 0)])
        XCTAssertEqual(count(none, 15), 0)
    }

    func testPolygonClosedPolylineOpen() {
        let pts = [RIPPoint(x: 10, y: 10), RIPPoint(x: 50, y: 10), RIPPoint(x: 50, y: 50)]
        let closed = execute([.polygon(points: pts)])
        let open = execute([.polyline(points: pts)])
        XCTAssertEqual(closed.px(30, 30), 15, "closing edge drawn")
        XCTAssertEqual(open.px(30, 30), 0, "poly-line is not closed")
    }

    func testFillPolygonEvenOdd() {
        let r = execute([.color(2), .fillStyle(pattern: 1, color: 14), .fillPolygon(points: [
            RIPPoint(x: 100, y: 50), RIPPoint(x: 140, y: 50), RIPPoint(x: 140, y: 90), RIPPoint(x: 100, y: 90)])])
        XCTAssertEqual(r.px(120, 70), 14)
        XCTAssertEqual(r.px(100, 70), 2)
    }

    // MARK: - Flood fill (RIP_FILL)

    func testFloodFillInsideViewportStopsAtViewportEdge() {
        let r = execute([.viewport(x0: 100, y0: 100, x1: 199, y1: 199), .fillStyle(pattern: 1, color: 3),
                     .fill(x: 50, y: 50, border: 15)])
        XCTAssertEqual(r.px(100, 100), 3)
        XCTAssertEqual(r.px(199, 199), 3)
        XCTAssertEqual(r.px(99, 150), 0)
        XCTAssertEqual(count(r, 3), 100 * 100)
    }

    // MARK: - Text window commands

    func testEraseWindowAndEOLUseTextWindowCells() {
        let r = execute([.fillStyle(pattern: 1, color: 3), .bar(x0: 0, y0: 0, x1: 639, y1: 349),
                     .textWindow(x0: 1, y0: 1, x1: 2, y1: 2, wrap: 0, size: 0), .eraseWindow])
        XCTAssertEqual(r.px(8, 8), 0)
        XCTAssertEqual(r.px(23, 23), 0)
        XCTAssertEqual(r.px(24, 24), 3)
        XCTAssertEqual(r.px(7, 7), 3)
        r.step(.bar(x0: 0, y0: 0, x1: 639, y1: 349))
        r.step(.gotoXY(x: 1, y: 0))
        r.step(.eraseEOL)
        XCTAssertEqual(r.px(16, 8), 0)
        XCTAssertEqual(r.px(15, 8), 3)
        XCTAssertEqual(r.px(16, 16), 3)
    }

    func testTextWindowCursorRules() {
        let r = execute([.gotoXY(x: 5, y: 6)])
        XCTAssertEqual(r.state.textCursor, RIPPoint(x: 5, y: 6))
        XCTAssertEqual(r.state.position, RIPPoint(x: 0, y: 0), "GOTOXY moves the text cursor only")
        r.step(.textWindow(x0: 0, y0: 0, x1: 79, y1: 42, wrap: 0, size: 0))
        XCTAssertEqual(r.state.textCursor, RIPPoint(x: 5, y: 6), "identical window (only wrap differs) keeps cursor")
        r.step(.textWindow(x0: 0, y0: 0, x1: 40, y1: 20, wrap: 0, size: 0))
        XCTAssertEqual(r.state.textCursor, RIPPoint(x: 0, y: 0))
        r.step(.gotoXY(x: 5, y: 6))
        r.step(.home)
        XCTAssertEqual(r.state.textCursor, RIPPoint(x: 0, y: 0))
    }

    func testResetWindows() {
        let r = execute([.color(4), .onePalette(slot: 1, value: 4), .viewport(x0: 10, y0: 10, x1: 20, y1: 20),
                     .fillStyle(pattern: 1, color: 3), .bar(x0: 0, y0: 0, x1: 5, y1: 5),
                     .mouse(num: 0, x0: 0, y0: 0, x1: 5, y1: 5, click: 0, clear: 0, reserved: 0, hostCommand: "x"),
                     .getImage(x0: 0, y0: 0, x1: 1, y1: 1, reserved: 0),
                     .resetWindows])
        XCTAssertTrue(r.canvas.indexed.allSatisfy { $0 == 0 })
        XCTAssertEqual(r.state.palette, RIPPalette.default16)
        XCTAssertEqual(r.state.viewport, .fullScreen)
        XCTAssertTrue(r.interactive.mouseRegions.isEmpty)
        XCTAssertNil(r.clipboard)
        XCTAssertEqual(r.state.drawColor, 4, "drawing color is not part of the reset")
    }

    // MARK: - Clipboard and regions

    func testGetAndPutImageModes() {
        let r = execute([.fillStyle(pattern: 1, color: 6), .bar(x0: 0, y0: 0, x1: 3, y1: 3),
                     .getImage(x0: 0, y0: 0, x1: 3, y1: 3, reserved: 0),
                     .fillStyle(pattern: 1, color: 3), .bar(x0: 10, y0: 0, x1: 50, y1: 3),
                     .putImage(x: 10, y: 0, mode: 0, reserved: 0),
                     .putImage(x: 20, y: 0, mode: 1, reserved: 0),
                     .putImage(x: 30, y: 0, mode: 2, reserved: 0),
                     .putImage(x: 40, y: 0, mode: 3, reserved: 0),
                     .putImage(x: 46, y: 0, mode: 4, reserved: 0)])
        XCTAssertEqual(r.px(10, 0), 6)
        XCTAssertEqual(r.px(20, 0), 6 ^ 3)
        XCTAssertEqual(r.px(30, 0), 6 | 3)
        XCTAssertEqual(r.px(40, 0), 6 & 3)
        XCTAssertEqual(r.px(46, 0), ~6 & 0x0F)
    }

    func testPutImageOffRightEdgeIsIgnored() {
        let r = execute([.fillStyle(pattern: 1, color: 6), .bar(x0: 0, y0: 0, x1: 9, y1: 9),
                     .getImage(x0: 0, y0: 0, x1: 9, y1: 9, reserved: 0), .putImage(x: 635, y: 100, mode: 0, reserved: 0)])
        XCTAssertEqual(r.px(636, 100), 0)
    }

    func testGetImageWithInvalidCornersIsIgnored() {
        let r = execute([.getImage(x0: 10, y0: 10, x1: 5, y1: 5, reserved: 0)])
        XCTAssertNil(r.clipboard)
    }

    func testCopyRegionAlignsToEightPixelsAndUsesAbsoluteCoordinates() {
        let r = execute([.fillStyle(pattern: 1, color: 5), .bar(x0: 14, y0: 0, x1: 38, y1: 0),
                     .viewport(x0: 100, y0: 100, x1: 200, y1: 200),
                     .copyRegion(x0: 14, y0: 0, x1: 38, y1: 0, reserved: 0, destLine: 10)])
        XCTAssertEqual(r.px(14, 10), 5)
        XCTAssertEqual(r.px(38, 10), 5)
        XCTAssertEqual(r.px(8, 10), 0, "aligned columns are copied too (source was background)")
        XCTAssertEqual(r.px(13, 10), 0)
    }

    func testCopyRegionOffScreenIsIgnored() {
        let r = execute([.fillStyle(pattern: 1, color: 5), .bar(x0: 0, y0: 0, x1: 7, y1: 10),
                     .copyRegion(x0: 0, y0: 0, x1: 7, y1: 10, reserved: 0, destLine: 345)])
        XCTAssertEqual(r.px(0, 345), 0)
    }

    // MARK: - Text regions

    func testRegionTextLinesAndDiscard() {
        let r = execute([.beginText(x0: 10, y0: 10, x1: 200, y1: 25, reserved: 0),
                     .regionText(justify: 0, string: "A"), .regionText(justify: 0, string: "B"),
                     .regionText(justify: 0, string: "C"), .endText])
        XCTAssertGreaterThan(r.canvas.indexed[(10 * 640)..<(18 * 640)].filter { $0 == 15 }.count, 0)
        XCTAssertGreaterThan(r.canvas.indexed[(18 * 640)..<(26 * 640)].filter { $0 == 15 }.count, 0)
        XCTAssertEqual(r.canvas.indexed[(26 * 640)..<(34 * 640)].filter { $0 == 15 }.count, 0, "third line discarded")
        XCTAssertNil(r.state.textRegion)
    }

    func testRegionTextJustifiesToRightEdge() {
        let r = execute([.beginText(x0: 0, y0: 0, x1: 99, y1: 50, reserved: 0), .regionText(justify: 1, string: "I I")])
        var lit: [Int] = []
        for y in 0..<8 { for x in 0..<100 where r.px(x, y) == 15 { lit.append(x) } }
        XCTAssertEqual(lit.max(), 92 + 5, "second word starts at 100 - 8; glyph 'I' spans columns 2...5")
    }

    // MARK: - Mouse regions and buttons

    func testMouseRegionsAreGlobalAndCapped() {
        var commands: [RIPCommand] = [.viewport(x0: 50, y0: 60, x1: 300, y1: 300)]
        for _ in 0..<130 {
            commands.append(.mouse(num: 0, x0: 1, y0: 2, x1: 3, y1: 4, click: 1, clear: 0, reserved: 0, hostCommand: "GO^M"))
        }
        let r = execute(commands)
        XCTAssertEqual(r.interactive.mouseRegions.count, 128)
        XCTAssertEqual(r.interactive.mouseRegions[0], RIPMouseRegion(
            kind: .mouseField, x0: 51, y0: 62, x1: 53, y1: 64, hostCommand: "GO^M",
            invertsWhenClicked: true, resetsOnClick: false, hotkey: nil))
        r.step(.killMouseFields)
        XCTAssertTrue(r.interactive.mouseRegions.isEmpty)
    }

    func testPlainBevelledMouseButton() {
        let style = RIPButtonStyle(width: 0, height: 0, orientation: 2,
                                   flags: RIPButtonStyle.Flag.plain | RIPButtonStyle.Flag.bevel | RIPButtonStyle.Flag.mouseButton,
                                   bevelSize: 2, labelColor: 1, dropShadowColor: 0, brightColor: 15, darkColor: 8,
                                   surfaceColor: 7, groupNumber: 0, flags2: 0, underlineColor: 0, cornerColor: 0, reserved: 0)
        let r = execute([.buttonStyle(style),
                     .button(x0: 100, y0: 100, x1: 160, y1: 120, hotkey: 79, flags: 0, reserved: 0, text: "<>OK<>ok^m")])
        XCTAssertEqual(r.px(101, 101), 7, "surface")
        XCTAssertEqual(r.px(130, 98), 15, "bright bevel above")
        XCTAssertEqual(r.px(130, 122), 8, "dark bevel below")
        var labelPixels = 0
        for y in 106..<114 { for x in 101..<160 where r.px(x, y) == 1 { labelPixels += 1 } }
        XCTAssertGreaterThan(labelPixels, 0, "label drawn")
        XCTAssertEqual(r.interactive.mouseRegions, [RIPMouseRegion(
            kind: .button, x0: 98, y0: 98, x1: 162, y1: 122, hostCommand: "ok^m",
            invertsWhenClicked: false, resetsOnClick: false, hotkey: 79)])
    }

    /// RIPscrip 1.54, RIP_BUTTON_STYLE flag 64 ("auto-stamp image onto
    /// clipboard"): the first button's image including its effects, but
    /// without the recess and the label, replaces the clipboard; the style
    /// then becomes a clipboard-button style with icon, plain, chisel, bevel,
    /// auto-stamp and sunken cleared.
    func testAutoStampButtonReplacesClipboardAndStyle() {
        typealias F = RIPButtonStyle.Flag
        let style = RIPButtonStyle(width: 0, height: 0, orientation: 2,
                                   flags: F.plain | F.bevel | F.autoStamp | F.mouseButton | F.recessed,
                                   bevelSize: 2, labelColor: 1, dropShadowColor: 0, brightColor: 15, darkColor: 8,
                                   surfaceColor: 7, groupNumber: 0, flags2: 0, underlineColor: 0, cornerColor: 0, reserved: 0)
        let r = execute([.buttonStyle(style),
                         .button(x0: 100, y0: 100, x1: 130, y1: 115, hotkey: 65, flags: 0, reserved: 0, text: "<>A<>a"),
                         .button(x0: 200, y0: 200, x1: 0, y1: 0, hotkey: 66, flags: 0, reserved: 0, text: "<><>b")])
        XCTAssertEqual(r.state.buttonStyle?.flags, F.clipboard | F.mouseButton | F.recessed)

        // The stamp is the 35x20 bevelled image (31x16 base plus 2 pixels of
        // bevel on each side); the second button is that image at (200, 200).
        XCTAssertEqual(r.clipboard?.width, 35)
        XCTAssertEqual(r.clipboard?.height, 20)
        XCTAssertEqual(r.px(200, 200), 15, "bright bevel corner")
        XCTAssertEqual(r.px(205, 205), 7, "surface")
        XCTAssertEqual(r.px(199, 210), 0, "recess: black outline outside the stamped image")
        XCTAssertEqual(r.px(198, 210), 8, "recess: inverted bevel (dark on the left)")
        for y in 202..<218 { for x in 202..<233 { XCTAssertNotEqual(r.px(x, y), 1, "label is not stamped") } }
        XCTAssertEqual(r.interactive.mouseRegions.last, RIPMouseRegion(
            kind: .button, x0: 200, y0: 200, x1: 234, y1: 219, hostCommand: "b",
            invertsWhenClicked: false, resetsOnClick: false, hotkey: 66))
    }

    func testButtonWithoutStyleIsIgnored() {
        let r = execute([.button(x0: 1, y0: 1, x1: 9, y1: 9, hotkey: 0, flags: 0, reserved: 0, text: "<>x")])
        XCTAssertEqual(count(r, 0), 640 * 350)
    }

    // MARK: - Recorded commands

    func testInteractiveCapture() {
        let r = execute([.query(mode: 0, reserved: 0, text: "$DATE$"), .define(flags: 0, reserved: 0, text: "A:"),
                     .readScene(reserved: 0, filename: "X.RIP"), .fileQuery(mode: 0, reserved: 0, filename: "X"),
                     .enterBlockMode(mode: 0, transferProtocol: 7, fileType: 0, reserved: 0, filename: ""),
                     .writeIcon(reserved: 0, filename: "A.ICN"),
                     .loadIcon(x: 0, y: 0, mode: 0, clipboard: 0, reserved: 10, filename: "A.ICN"),
                     .ansiSense(.query), .unknown(level: "15", command: "L", arguments: ""), .noMore])
        let i = r.interactive
        XCTAssertEqual([i.queries.count, i.defines.count, i.reads.count, i.fileQueries.count, i.blockModes.count,
                        i.writeIcons.count, i.loadIcons.count, i.ansiSenses.count, i.unknowns.count],
                       Array(repeating: 1, count: 9))
        XCTAssertTrue(i.noMore)
        XCTAssertTrue(r.canvas.indexed.allSatisfy { $0 == 0 })
    }

    // MARK: - Public façade

    func testPublicFacade() throws {
        let scene = try SwiftRIP.decode("!|c0F|B00000505\r\n")
        let result = SwiftRIP.renderResult(scene)
        XCTAssertEqual(result.framebuffer.colorIndex(x: 2, y: 2), 15)
        XCTAssertFalse(result.isTruncated)
        let img = SwiftRIP.render(scene)
        XCTAssertEqual(img?.width, 640)
        XCTAssertEqual(img?.height, 350)
        XCTAssertEqual(try SwiftRIP.decode(Data(SwiftRIP.encode(scene).utf8)), scene)
    }
}
