import XCTest
@testable import SwiftRIP

/// Round-trip and escape-edge tests for `RIPWriter`. Each test builds a
/// synthetic `RIPScene`, encodes it, parses the result back, and asserts
/// structural equality of the resulting command list.
final class RIPWriterTests: XCTestCase {

    private func roundTrip(_ scene: RIPScene,
                           file: StaticString = #file,
                           line: UInt = #line) {
        let text = RIPWriter.encode(scene)
        do {
            let parsed = try RIPParser.parse(text)
            XCTAssertEqual(parsed.commands, scene.commands,
                           "encoded text did not round-trip:\n\(text)",
                           file: file, line: line)
        } catch {
            XCTFail("parse of encoded text threw \(error):\n\(text)",
                    file: file, line: line)
        }
    }

    // MARK: - Framing

    func testEncodeEmitsBangPipePrefix() {
        let scene = RIPScene(commands: [.resetWindows])
        XCTAssertEqual(RIPWriter.encode(scene), "!|*\n")
    }

    func testEncodeMultipleCommandsAsSeparateLines() {
        let scene = RIPScene(commands: [.eraseWindow, .home, .eraseEOL])
        XCTAssertEqual(RIPWriter.encode(scene), "!|e\n!|H\n!|>\n")
    }

    // MARK: - Level 0 round-trips

    func testLevel0StateRoundTrip() {
        let scene = RIPScene(commands: [
            .textWindow(x0: 1, y0: 1, x1: 10, y1: 5, wrap: 0, size: 1),
            .viewport(x0: 0, y0: 0, x1: 639, y1: 349),
            .resetWindows,
            .eraseWindow,
            .eraseView,
            .gotoXY(x: 123, y: 45),
            .home,
            .eraseEOL,
            .color(15),
            .writeMode(1),
            .move(x: 320, y: 175),
        ])
        roundTrip(scene)
    }

    func testPaletteRoundTripPreservesIndexes() {
        let palette = (0..<16).map { ($0 * 3) % 64 }
        let scene = RIPScene(commands: [
            .setPalette(palette),
            .onePalette(slot: 7, value: 63),
        ])
        roundTrip(scene)
        // And specifically check that the palette indexes survive byte-equal.
        let text = RIPWriter.encode(scene)
        let parsed = try? RIPParser.parse(text)
        XCTAssertNotNil(parsed)
        if case let .setPalette(values) = parsed!.commands.first! {
            XCTAssertEqual(values, palette)
        } else {
            XCTFail("expected setPalette")
        }
    }

    func testDrawingPrimitivesRoundTrip() {
        let scene = RIPScene(commands: [
            .pixel(x: 10, y: 20),
            .line(x0: 0, y0: 0, x1: 639, y1: 349),
            .rectangle(x0: 1, y0: 2, x1: 3, y1: 4),
            .bar(x0: 5, y0: 6, x1: 7, y1: 8),
            .circle(x: 100, y: 100, radius: 50),
            .oval(x: 10, y: 20, startAngle: 0, endAngle: 359, xrad: 30, yrad: 20),
            .filledOval(x: 10, y: 20, xrad: 30, yrad: 20),
            .arc(x: 100, y: 100, startAngle: 0, endAngle: 90, radius: 40),
            .ovalArc(x: 100, y: 100, startAngle: 0, endAngle: 90, xrad: 40, yrad: 30),
            .pieSlice(x: 100, y: 100, startAngle: 0, endAngle: 90, radius: 40),
            .ovalPieSlice(x: 100, y: 100, startAngle: 0, endAngle: 90, xrad: 40, yrad: 30),
            .bezier(x0: 0, y0: 0, x1: 10, y1: 10, x2: 20, y2: 0, x3: 30, y3: 10, count: 16),
            .fill(x: 1, y: 2, border: 15),
        ])
        roundTrip(scene)
    }

    func testPointListsRoundTrip() {
        let pts = [RIPPoint(x: 0, y: 0), RIPPoint(x: 100, y: 50), RIPPoint(x: 200, y: 0)]
        let scene = RIPScene(commands: [
            .polygon(points: pts),
            .fillPolygon(points: pts),
            .polyline(points: pts),
        ])
        roundTrip(scene)
    }

    func testStyleAndFontRoundTrip() {
        let scene = RIPScene(commands: [
            .fontStyle(font: 1, direction: 0, size: 2, reserved: 0),
            .lineStyle(style: 0, userPattern: 0xABCD, thickness: 1),
            .fillStyle(pattern: 11, color: 4),
            .fillPattern(bytes: [0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55], color: 9),
        ])
        roundTrip(scene)
    }

    // MARK: - Text round-trips & escape edges

    func testPlainTextRoundTrip() {
        let scene = RIPScene(commands: [.text("HELLO WORLD")])
        roundTrip(scene)
    }

    func testTextWithBangIsEscapedAndRoundTrips() {
        let scene = RIPScene(commands: [.text("Hello! World!")])
        let text = RIPWriter.encode(scene)
        XCTAssertTrue(text.contains("\\!"),
                      "expected ! to be escaped as \\!, got:\n\(text)")
        roundTrip(scene)
    }

    func testTextWithPipeIsEscapedAndRoundTrips() {
        let scene = RIPScene(commands: [.text("a|b|c")])
        let text = RIPWriter.encode(scene)
        XCTAssertTrue(text.contains("\\|"),
                      "expected | to be escaped as \\|, got:\n\(text)")
        roundTrip(scene)
    }

    func testTextWithBackslashIsEscapedAndRoundTrips() {
        let scene = RIPScene(commands: [.text("a\\b\\c")])
        let text = RIPWriter.encode(scene)
        XCTAssertTrue(text.contains("\\\\"),
                      "expected \\ to be escaped as \\\\, got:\n\(text)")
        roundTrip(scene)
    }

    func testTextWithTrailingBackslashRoundTrips() {
        // The classic three-backslash gotcha: a payload ending in `\` is
        // emitted as `\\` in the source which must survive line breaks.
        let scene = RIPScene(commands: [.text("end-with-backslash\\")])
        roundTrip(scene)
    }

    func testTextWithAllEscapeCharactersRoundTrips() {
        let scene = RIPScene(commands: [
            .textXY(x: 100, y: 100, string: "mix !pipe|back\\slash and trail\\"),
        ])
        roundTrip(scene)
    }

    // MARK: - Level 1 round-trips

    func testMouseFieldRoundTripWithEscapesInBothStrings() {
        let scene = RIPScene(commands: [
            .mouse(num: 1,
                   x0: 10, y0: 20, x1: 100, y1: 60,
                   click: 1, clear: 0,
                   text: "click!me",
                   hostCommand: "RUN\\foo|bar"),
        ])
        roundTrip(scene)
    }

    func testButtonStyleAndButtonRoundTrip() {
        let scene = RIPScene(commands: [
            .buttonStyle(width: 80, height: 24, orientation: 0, flags: 0x1234,
                         bevelSize: 2, dfore: 15, dback: 0, bright: 15, dark: 8,
                         surface: 7, gborder: 0, gcorner: 0, uline: 1, corner: 0,
                         reserved: 0, label: "Press Me"),
            .button(x0: 10, y0: 10, x1: 90, y1: 34, hotkey: 0, flags: 0,
                    label: "OK!"),
        ])
        roundTrip(scene)
    }

    func testBeginRegionEndTextRoundTrip() {
        let scene = RIPScene(commands: [
            .beginText(x0: 0, y0: 0, x1: 639, y1: 349, reserved: 0),
            .regionText(flags: 0, string: "Hello, region!"),
            .endText,
        ])
        roundTrip(scene)
    }

    func testGetPutImageAndCopyRegionRoundTrip() {
        let scene = RIPScene(commands: [
            .getImage(x0: 0, y0: 0, x1: 50, y1: 50, reserved: 0),
            .putImage(x: 100, y: 100, mode: 1, reserved: 0),
            .copyRegion(x0: 0, y0: 0, x1: 50, y1: 50, destPage: 0, destX: 200, destY: 100),
        ])
        roundTrip(scene)
    }

    func testIconFilenameRoundTrip() {
        let scene = RIPScene(commands: [
            .writeIcon(filename: "MYICON.ICN"),
            .loadIcon(x: 10, y: 10, mode: 0, clipboard: 0, reserved: 0,
                      filename: "MYICON.ICN"),
        ])
        roundTrip(scene)
    }

    func testDefineAndQueryRoundTrip() {
        let scene = RIPScene(commands: [
            .define(id: 1, flags: 0, string: "macro body"),
            .query(flags: 0, string: "what is your name?"),
        ])
        roundTrip(scene)
    }

    func testReadSceneAndFileQueryRoundTrip() {
        let scene = RIPScene(commands: [
            .readScene(filename: "OTHER.RIP"),
            .fileQuery(filename: "DATA.BIN", reserved: 0),
        ])
        roundTrip(scene)
    }

    func testKillMouseFieldsRoundTrip() {
        roundTrip(RIPScene(commands: [.killMouseFields]))
    }

    // MARK: - Level 9 round-trips

    func testEnterBlockModeAndNoMoreRoundTrip() {
        let scene = RIPScene(commands: [
            .enterBlockMode(mode: 0, fileType: 1, reserved: 0, filename: "FILE.BIN"),
            .noMore,
        ])
        roundTrip(scene)
    }

    // MARK: - Opaque cases are skipped, not emitted

    func testUnknownAndAnsiSenseAreSkipped() {
        let scene = RIPScene(commands: [
            .ansiSense(.query),
            .unknown(level: 0, char: "Q", raw: ""),
        ])
        // Both should be skipped — encoded output is empty.
        XCTAssertEqual(RIPWriter.encode(scene), "")
    }

    // MARK: - Long-line continuation

    func testLongPolygonWrapsAtRightMargin() throws {
        // 50 points × 6 chars = 300 chars + prefix; well past any reasonable
        // physical line width. Each physical line should be ≤ 76 cols.
        let pts = (0..<50).map { RIPPoint(x: $0, y: $0 * 2) }
        let scene = RIPScene(commands: [.polyline(points: pts)])
        let text = RIPWriter.encode(scene)
        // Every physical line in the encoded output should be at most
        // `defaultLineWidth` cols of content, plus an optional trailing
        // continuation `\`. We assert ≤ defaultLineWidth + 1.
        for line in text.split(separator: "\n") {
            XCTAssertLessThanOrEqual(line.count, RIPWriter.defaultLineWidth + 1,
                                     "physical line too long: \(line)")
        }
        // And round-trip survives the continuations.
        roundTrip(scene)
    }
}
