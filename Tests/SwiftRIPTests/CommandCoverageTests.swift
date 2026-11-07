import XCTest
@testable import SwiftRIP

/// Every command of RIPscrip 1.54, decoded from the "Example:" line of its
/// section in the specification (with `<escape>` replaced by ESC and the
/// `^M` notation kept literally), so argument widths and order are checked
/// against the spec rather than against the encoder.
final class CommandCoverageTests: XCTestCase {

    private func check(_ body: String, _ expected: RIPCommand, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let commands = try parseBody(body)
            XCTAssertEqual(commands, [expected], "body: \(body)", file: file, line: line)
        } catch {
            XCTFail("\(body) threw \(error)", file: file, line: line)
        }
    }

    // MARK: - Level 0

    func testTextWindow() { check("w00001B0M10", .textWindow(x0: 0, y0: 0, x1: 47, y1: 22, wrap: 1, size: 0)) }
    func testViewport() { check("v00002E1M", .viewport(x0: 0, y0: 0, x1: 86, y1: 58)) }
    func testResetWindows() { check("*", .resetWindows) }
    func testEraseWindow() { check("e", .eraseWindow) }
    func testEraseView() { check("E", .eraseView) }
    func testGotoXY() { check("g0509", .gotoXY(x: 5, y: 9)) }
    func testHome() { check("H", .home) }
    func testEraseEOL() { check(">", .eraseEOL) }
    /// The spec's example uses a one-digit variable-width last parameter.
    func testColor() { check("cA", .color(10)) }
    func testSetPalette() {
        check("Q000102030405060708090A0B0C0D0E0F", .setPalette(Array(0...15)))
    }
    func testOnePalette() { check("a051B", .onePalette(slot: 5, value: 47)) }
    func testWriteMode() { check("W00", .writeMode(0)) }
    func testMove() { check("m0509", .move(x: 5, y: 9)) }
    func testText() { check("Thello world", .text("hello world")) }
    func testTextXY() { check("@0011hello world", .textXY(x: 0, y: 37, string: "hello world")) }
    func testFontStyle() { check("Y01000400", .fontStyle(font: 1, direction: 0, size: 4, reserved: 0)) }
    func testPixel() { check("X1122", .pixel(x: 37, y: 74)) }
    func testLine() { check("L00010A0E", .line(x0: 0, y0: 1, x1: 10, y1: 14)) }
    func testRectangle() { check("R00010A0E", .rectangle(x0: 0, y0: 1, x1: 10, y1: 14)) }
    func testBar() { check("B00010A0E", .bar(x0: 0, y0: 1, x1: 10, y1: 14)) }
    func testCircle() { check("C1E180M", .circle(x: 50, y: 44, radius: 22)) }
    func testOval() {
        // The spec's example omits the "!|O" prefix and carries two extra
        // digits after the six arguments, which are ignored (rule 6).
        check("O1E1A18003G150Z", .oval(x: 50, y: 46, startAngle: 44, endAngle: 0, xrad: 124, yrad: 41))
    }
    func testFilledOval() { check("o1G2B0M0G", .filledOval(x: 52, y: 83, xrad: 22, yrad: 16)) }
    func testArc() { check("A1E18003G15", .arc(x: 50, y: 44, startAngle: 0, endAngle: 124, radius: 41)) }
    func testOvalArc() {
        check("V1E18003G151Q", .ovalArc(x: 50, y: 44, startAngle: 0, endAngle: 124, xrad: 41, yrad: 62))
    }
    func testPieSlice() { check("I1E18003G15", .pieSlice(x: 50, y: 44, startAngle: 0, endAngle: 124, radius: 41)) }
    func testOvalPieSlice() {
        check("i1E18003G151Q", .ovalPieSlice(x: 50, y: 44, startAngle: 0, endAngle: 124, xrad: 41, yrad: 62))
    }
    func testBezier() {
        check("Z0A0B0C0D0E0F0G0H1G", .bezier(x0: 10, y0: 11, x1: 12, y1: 13, x2: 14, y2: 15, x3: 16, y3: 17, count: 52))
    }
    func testPolygon() {
        check("P03010105090905", .polygon(points: [RIPPoint(x: 1, y: 1), RIPPoint(x: 5, y: 9), RIPPoint(x: 9, y: 5)]))
    }
    func testFillPolygon() {
        check("p03010105050909", .fillPolygon(points: [RIPPoint(x: 1, y: 1), RIPPoint(x: 5, y: 5), RIPPoint(x: 9, y: 9)]))
    }
    func testPolyline() {
        check("l03010105090905", .polyline(points: [RIPPoint(x: 1, y: 1), RIPPoint(x: 5, y: 9), RIPPoint(x: 9, y: 5)]))
    }
    func testFill() { check("F25090F", .fill(x: 77, y: 9, border: 15)) }
    func testLineStyle() { check("=01000001", .lineStyle(style: 1, userPattern: 0, thickness: 1)) }
    func testFillStyle() { check("S050F", .fillStyle(pattern: 5, color: 15)) }
    func testFillPattern() {
        check("s11223344556677880F",
              .fillPattern(bytes: [37, 74, 111, 148, 185, 222, 3, 40], color: 15)) // 259, 296 truncate to 8 bits
    }
    func testNoMore() { check("#", .noMore) }

    // MARK: - Level 1

    func testMouse() {
        check("1M00001122331100000host command^M",
              .mouse(num: 0, x0: 0, y0: 37, x1: 74, y1: 111, click: 1, clear: 1, reserved: 0, hostCommand: "host command^M"))
    }
    func testKillMouseFields() { check("1K", .killMouseFields) }
    /// The spec's example omits the trailing `res:2`; a missing last numeric
    /// parameter decodes as 0.
    func testBeginText() { check("1T00110011", .beginText(x0: 0, y0: 37, x1: 0, y1: 37, reserved: 0)) }
    func testRegionText() {
        check("1t1This is a text line to be justified", .regionText(justify: 1, string: "This is a text line to be justified"))
    }
    func testEndText() { check("1E", .endText) }
    func testGetImage() { check("1C001122330", .getImage(x0: 0, y0: 37, x1: 74, y1: 111, reserved: 0)) }
    func testPutImage() { check("1P0011010", .putImage(x: 0, y: 37, mode: 1, reserved: 0)) }
    func testWriteIcon() { check("1W0filename.icn", .writeIcon(reserved: 0, filename: "filename.icn")) }
    func testLoadIcon() {
        check("1I001101010button.icn", .loadIcon(x: 0, y: 37, mode: 1, clipboard: 0, reserved: 36, filename: "button.icn"))
    }
    func testButtonStyle() {
        check("1B0A0A010274030F080F080700010E07000000", .buttonStyle(RIPButtonStyle(
            width: 10, height: 10, orientation: 1, flags: 2 * 1296 + 7 * 36 + 4, bevelSize: 3,
            labelColor: 15, dropShadowColor: 8, brightColor: 15, darkColor: 8, surfaceColor: 7,
            groupNumber: 0, flags2: 1, underlineColor: 14, cornerColor: 7, reserved: 0)))
    }
    func testButton() {
        check("1U010100003200iconfile<>Label<>HostCmd^m",
              .button(x0: 1, y0: 1, x1: 0, y1: 0, hotkey: 110, flags: 0, reserved: 0, text: "iconfile<>Label<>HostCmd^m"))
    }
    func testDefine() {
        check("1D00700text_var,60:?question?default data",
              .define(flags: 7, reserved: 0, text: "text_var,60:?question?default data"))
    }
    func testQuery() {
        check("1\u{1B}0000this is a query $COMMAND$^m", .query(mode: 0, reserved: 0, text: "this is a query $COMMAND$^m"))
    }
    func testCopyRegion() {
        check("1G080G140M0005", .copyRegion(x0: 8, y0: 16, x1: 40, y1: 22, reserved: 0, destLine: 5))
    }
    func testReadScene() { check("1R00000000testfile.rip", .readScene(reserved: 0, filename: "testfile.rip")) }
    func testFileQuery() { check("1F010000testfile.icn", .fileQuery(mode: 1, reserved: 0, filename: "testfile.icn")) }

    // MARK: - Level 9

    func testEnterBlockMode() {
        check("9\u{1B}00010000ICONFILE.ICN<>",
              .enterBlockMode(mode: 0, transferProtocol: 0, fileType: 1, reserved: 0, filename: "ICONFILE.ICN"))
        check("9\u{1B}06040000<>", .enterBlockMode(mode: 0, transferProtocol: 6, fileType: 4, reserved: 0, filename: ""))
    }

    // MARK: - Unknown / sub-level

    func testSubLevelCommandIsUnknown() {
        check("15Labc", .unknown(level: "15", command: "L", arguments: "abc"))
        check("9N", .unknown(level: "9", command: "N", arguments: ""))
    }
}
