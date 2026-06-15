import XCTest
@testable import SwiftRIP

/// Helper: encode an integer as a `width`-digit MegaNum string for use in
/// constructing test fixtures. The expectation values can then be the
/// literal integers, removing the manual base-36 math from the test author.
private func MN(_ value: Int, _ width: Int) -> String {
    MegaNum.encode(value, width: width)
}

final class ParserTests: XCTestCase {

    private func parse(_ s: String) throws -> [RIPCommand] {
        try RIPParser.parse(s).commands
    }

    // MARK: - Level 0: state-setting & cursor

    func testResetWindows() throws {
        XCTAssertEqual(try parse("!|*\n"), [.resetWindows])
    }

    func testTextWindow() throws {
        let s = "!|w" + MN(1, 2) + MN(1, 2) + MN(10, 2) + MN(5, 2) + MN(0, 1) + MN(1, 1) + "\n"
        XCTAssertEqual(try parse(s),
                       [.textWindow(x0: 1, y0: 1, x1: 10, y1: 5, wrap: 0, size: 1)])
    }

    func testViewport() throws {
        let s = "!|v" + MN(0, 3) + MN(0, 3) + MN(639, 3) + MN(349, 3) + "\n"
        XCTAssertEqual(try parse(s),
                       [.viewport(x0: 0, y0: 0, x1: 639, y1: 349)])
    }

    func testEraseAndHomeAndEOL() throws {
        XCTAssertEqual(try parse("!|e\n"), [.eraseWindow])
        XCTAssertEqual(try parse("!|E\n"), [.eraseView])
        XCTAssertEqual(try parse("!|H\n"), [.home])
        XCTAssertEqual(try parse("!|>\n"), [.eraseEOL])
    }

    func testColor() throws {
        XCTAssertEqual(try parse("!|c" + MN(15, 2) + "\n"), [.color(15)])
        XCTAssertEqual(try parse("!|c" + MN(0x1F, 2) + "\n"), [.color(0x1F)])
    }

    func testGotoXYAndMove() throws {
        XCTAssertEqual(try parse("!|g" + MN(1, 3) + MN(639, 3) + "\n"),
                       [.gotoXY(x: 1, y: 639)])
        XCTAssertEqual(try parse("!|m" + MN(639, 3) + MN(349, 3) + "\n"),
                       [.move(x: 639, y: 349)])
    }

    func testWriteMode() throws {
        XCTAssertEqual(try parse("!|W0\n"), [.writeMode(0)])
        XCTAssertEqual(try parse("!|W1\n"), [.writeMode(1)])
    }

    // MARK: - Palette

    func testSetPalette() throws {
        let s = "!|Q" + (0..<16).map { MN($0, 2) }.joined() + "\n"
        let cmds = try parse(s)
        XCTAssertEqual(cmds.count, 1)
        if case let .setPalette(values) = cmds[0] {
            XCTAssertEqual(values, Array(0..<16))
        } else {
            XCTFail("expected setPalette, got \(cmds[0])")
        }
    }

    func testOnePalette() throws {
        XCTAssertEqual(try parse("!|a" + MN(5, 1) + MN(0x1F, 2) + "\n"),
                       [.onePalette(slot: 5, value: 0x1F)])
    }

    // MARK: - Drawing primitives

    func testPixelLineRectBar() throws {
        XCTAssertEqual(try parse("!|X" + MN(10, 3) + MN(11, 3) + "\n"),
                       [.pixel(x: 10, y: 11)])
        XCTAssertEqual(try parse("!|L" + MN(0, 3) + MN(10, 3) + MN(36, 3) + MN(40, 3) + "\n"),
                       [.line(x0: 0, y0: 10, x1: 36, y1: 40)])
        XCTAssertEqual(try parse("!|R" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + "\n"),
                       [.rectangle(x0: 0, y0: 0, x1: 216, y1: 216)])
        XCTAssertEqual(try parse("!|B" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + "\n"),
                       [.bar(x0: 0, y0: 0, x1: 216, y1: 216)])
    }

    func testCircleOvalArc() throws {
        XCTAssertEqual(try parse("!|C" + MN(180, 3) + MN(360, 3) + MN(180, 3) + "\n"),
                       [.circle(x: 180, y: 360, radius: 180)])
        XCTAssertEqual(try parse("!|O" + MN(180, 3) + MN(180, 3) + MN(0, 3) + MN(360, 3) + MN(180, 3) + MN(180, 3) + "\n"),
                       [.oval(x: 180, y: 180, startAngle: 0, endAngle: 360, xrad: 180, yrad: 180)])
        XCTAssertEqual(try parse("!|A" + MN(180, 3) + MN(180, 3) + MN(0, 3) + MN(360, 3) + MN(180, 3) + "\n"),
                       [.arc(x: 180, y: 180, startAngle: 0, endAngle: 360, radius: 180)])
    }

    func testFilledOvalPieSlice() throws {
        XCTAssertEqual(try parse("!|o" + MN(180, 3) + MN(180, 3) + MN(72, 3) + MN(108, 3) + "\n"),
                       [.filledOval(x: 180, y: 180, xrad: 72, yrad: 108)])
        XCTAssertEqual(try parse("!|I" + MN(180, 3) + MN(180, 3) + MN(0, 3) + MN(360, 3) + MN(180, 3) + "\n"),
                       [.pieSlice(x: 180, y: 180, startAngle: 0, endAngle: 360, radius: 180)])
        XCTAssertEqual(try parse("!|i" + MN(180, 3) + MN(180, 3) + MN(0, 3) + MN(360, 3) + MN(180, 3) + MN(180, 3) + "\n"),
                       [.ovalPieSlice(x: 180, y: 180, startAngle: 0, endAngle: 360, xrad: 180, yrad: 180)])
        XCTAssertEqual(try parse("!|V" + MN(180, 3) + MN(180, 3) + MN(0, 3) + MN(360, 3) + MN(180, 3) + MN(180, 3) + "\n"),
                       [.ovalArc(x: 180, y: 180, startAngle: 0, endAngle: 360, xrad: 180, yrad: 180)])
    }

    func testBezier() throws {
        let s = "!|Z" + MN(0, 3) + MN(10, 3) + MN(36, 3) + MN(36, 3) + MN(180, 3) + MN(180, 3) + MN(36, 3) + MN(36, 3) + MN(10, 2) + "\n"
        XCTAssertEqual(try parse(s),
                       [.bezier(x0: 0, y0: 10, x1: 36, y1: 36, x2: 180, y2: 180, x3: 36, y3: 36, count: 10)])
    }

    // MARK: - Polygons + polyline

    func testPolygonAndFillPolygonAndPolyline() throws {
        let pts = MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3)
        let expected: [RIPPoint] = [RIPPoint(x: 0, y: 0), RIPPoint(x: 216, y: 0), RIPPoint(x: 216, y: 216)]

        XCTAssertEqual(try parse("!|P" + MN(3, 2) + pts + "\n"),
                       [.polygon(points: expected)])
        XCTAssertEqual(try parse("!|p" + MN(3, 2) + pts + "\n"),
                       [.fillPolygon(points: expected)])
        XCTAssertEqual(try parse("!|l" + MN(3, 2) + pts + "\n"),
                       [.polyline(points: expected)])
    }

    // MARK: - Fill / style

    func testFillFloodAndStyle() throws {
        XCTAssertEqual(try parse("!|F" + MN(180, 3) + MN(180, 3) + MN(7, 1) + "\n"),
                       [.fill(x: 180, y: 180, border: 7)])
        XCTAssertEqual(try parse("!|=" + MN(0, 2) + MN(0, 4) + MN(1, 2) + "\n"),
                       [.lineStyle(style: 0, userPattern: 0, thickness: 1)])
        XCTAssertEqual(try parse("!|S" + MN(0, 2) + MN(7, 2) + "\n"),
                       [.fillStyle(pattern: 0, color: 7)])
        let pattern: [UInt8] = [0xFF, 0xEF, 0xDF, 0xCF, 0xBF, 0xAF, 0x9F, 0x80]
        let patternStr = pattern.map { MN(Int($0), 2) }.joined()
        XCTAssertEqual(try parse("!|f" + patternStr + MN(7, 2) + "\n"),
                       [.fillPattern(bytes: pattern, color: 7)])
    }

    // MARK: - Text + font

    func testTextAndTextXY() throws {
        XCTAssertEqual(try parse("!|THello, World!|\n"),
                       [.text("Hello, World!")])
        XCTAssertEqual(try parse("!|@" + MN(1, 3) + MN(360, 3) + "Hello|\n"),
                       [.textXY(x: 1, y: 360, string: "Hello")])
    }

    func testTextWithEscapes() throws {
        XCTAssertEqual(try parse("!|Tpipe \\| bang \\! slash \\\\|\n"),
                       [.text("pipe | bang ! slash \\")])
    }

    func testFontStyle() throws {
        XCTAssertEqual(try parse("!|Y" + MN(1, 2) + MN(0, 2) + MN(2, 2) + MN(0, 2) + "\n"),
                       [.fontStyle(font: 1, direction: 0, size: 2, reserved: 0)])
    }

    // MARK: - Level 1

    func testBeginRegionEndText() throws {
        let bt = "!|1T" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + MN(0, 2) + "\n"
        let rt = "!|1t" + MN(2, 2) + "Hello|\n"
        let et = "!|1E\n"
        let cmds = try parse(bt + rt + et)
        XCTAssertEqual(cmds.count, 3)
        XCTAssertEqual(cmds[0], .beginText(x0: 0, y0: 0, x1: 216, y1: 216, reserved: 0))
        XCTAssertEqual(cmds[1], .regionText(flags: 2, string: "Hello"))
        XCTAssertEqual(cmds[2], .endText)
    }

    func testGetPutWriteLoadIcon() throws {
        XCTAssertEqual(try parse("!|1G" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + MN(0, 2) + "\n"),
                       [.getImage(x0: 0, y0: 0, x1: 216, y1: 216, reserved: 0)])
        XCTAssertEqual(try parse("!|1P" + MN(0, 3) + MN(216, 3) + MN(1, 1) + MN(0, 2) + "\n"),
                       [.putImage(x: 0, y: 216, mode: 1, reserved: 0)])
        XCTAssertEqual(try parse("!|1WLOGO.ICN|\n"),
                       [.writeIcon(filename: "LOGO.ICN")])
        XCTAssertEqual(try parse("!|1I" + MN(0, 3) + MN(216, 3) + MN(0, 1) + MN(1, 1) + MN(0, 2) + "LOGO.ICN|\n"),
                       [.loadIcon(x: 0, y: 216, mode: 0, clipboard: 1, reserved: 0, filename: "LOGO.ICN")])
    }

    func testButtonStyleAndButton() throws {
        let bs = "!|1B" + MN(216, 3) + MN(72, 3) + MN(0, 2) + MN(1, 4) + MN(1, 2) + MN(0, 2) + MN(0, 2) + MN(0xF, 2) + MN(8, 2) + MN(7, 2) + MN(7, 2) + MN(7, 2) + MN(7, 2) + MN(0, 2) + MN(0, 2) + "label|\n"
        let cmds = try parse(bs)
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0], .buttonStyle(width: 216, height: 72, orientation: 0, flags: 1, bevelSize: 1, dfore: 0, dback: 0, bright: 0xF, dark: 8, surface: 7, gborder: 7, gcorner: 7, uline: 7, corner: 0, reserved: 0, label: "label"))

        let bu = "!|1U" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + MN(0x41, 2) + MN(0, 3) + "Login|\n"
        XCTAssertEqual(try parse(bu),
                       [.button(x0: 0, y0: 0, x1: 216, y1: 216, hotkey: 0x41, flags: 0, label: "Login")])
    }

    func testMouseAndKillMouse() throws {
        let s = "!|1M" + MN(1, 2) + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + MN(1, 1) + MN(1, 1) + "HelloMouseField|GO MAIN|\n"
        XCTAssertEqual(try parse(s),
                       [.mouse(num: 1, x0: 0, y0: 0, x1: 216, y1: 216, click: 1, clear: 1, text: "HelloMouseField", hostCommand: "GO MAIN")])
        XCTAssertEqual(try parse("!|1K\n"), [.killMouseFields])
    }

    func testDefineQueryFileQuery() throws {
        XCTAssertEqual(try parse("!|1D" + MN(36, 3) + MN(0, 2) + "MyMacro|\n"),
                       [.define(id: 36, flags: 0, string: "MyMacro")])
        XCTAssertEqual(try parse("!|1?" + MN(0, 2) + "GET STATUS|\n"),
                       [.query(flags: 0, string: "GET STATUS")])
        XCTAssertEqual(try parse("!|1FREADER.TXT|" + MN(0, 2) + "\n"),
                       [.fileQuery(filename: "READER.TXT", reserved: 0)])
    }

    func testCopyRegionAndReadScene() throws {
        let s = "!|1C" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + MN(1, 1) + MN(36, 3) + MN(72, 3) + "\n"
        XCTAssertEqual(try parse(s),
                       [.copyRegion(x0: 0, y0: 0, x1: 216, y1: 216, destPage: 1, destX: 36, destY: 72)])
        XCTAssertEqual(try parse("!|1RNEXT.RIP|\n"),
                       [.readScene(filename: "NEXT.RIP")])
    }

    // MARK: - Level 9

    func testEnterBlockMode() throws {
        let s = "!|9<" + MN(1, 1) + MN(2, 2) + MN(0, 4) + "FILE.ICN|\n"
        XCTAssertEqual(try parse(s),
                       [.enterBlockMode(mode: 1, fileType: 2, reserved: 0, filename: "FILE.ICN")])
    }

    func testNoMore() throws {
        XCTAssertEqual(try parse("!|9NoMore\n"), [.noMore])
    }

    // MARK: - Multi-command line + escape interplay

    func testMultipleCommandsOnOneLine() throws {
        XCTAssertEqual(try parse("!|c" + MN(15, 2) + "g" + MN(1, 3) + MN(2, 3) + "\n"),
                       [.color(15), .gotoXY(x: 1, y: 2)])
    }

    func testRoundTripScene() throws {
        let s = "!|*\n" +
                "!|c" + MN(15, 2) + "\n" +
                "!|L" + MN(0, 3) + MN(0, 3) + MN(216, 3) + MN(216, 3) + "\n" +
                "!|THello|\n" +
                "!|9NoMore\n"
        let cmds = try parse(s)
        XCTAssertEqual(cmds.count, 5)
        XCTAssertEqual(cmds[0], .resetWindows)
        XCTAssertEqual(cmds[1], .color(15))
        XCTAssertEqual(cmds[2], .line(x0: 0, y0: 0, x1: 216, y1: 216))
        XCTAssertEqual(cmds[3], .text("Hello"))
        XCTAssertEqual(cmds[4], .noMore)
    }

    // MARK: - Errors

    func testTruncatedCommand() {
        XCTAssertThrowsError(try parse("!|g001\n")) { err in
            guard case RIPParseError.truncated = err else {
                XCTFail("expected truncated error, got \(err)")
                return
            }
        }
    }

    func testInvalidMegaNum() {
        XCTAssertThrowsError(try parse("!|c$$\n")) { err in
            guard case RIPParseError.invalidMegaNum = err else {
                XCTFail("expected invalidMegaNum error, got \(err)")
                return
            }
        }
    }
}
