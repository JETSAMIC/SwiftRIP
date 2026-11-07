import XCTest
@testable import SwiftRIP

/// `RIPWriter` output format and encode -> parse round trips.
final class RIPWriterTests: XCTestCase {

    private func roundTrip(_ commands: [RIPCommand], file: StaticString = #filePath, line: UInt = #line) {
        do {
            let text = try RIPWriter.encode(RIPScene(commands: commands))
            let parsed = try RIPParser.parse(text)
            XCTAssertEqual(parsed.commands, commands, "did not round-trip:\n\(text)", file: file, line: line)
        } catch {
            XCTFail("round trip threw \(error)", file: file, line: line)
        }
    }

    // MARK: - Format

    func testEncodeEmitsSpecWidths() throws {
        let scene = RIPScene(commands: [
            .line(x0: 0, y0: 1, x1: 10, y1: 14),
            .color(10),
            .viewport(x0: 0, y0: 0, x1: 639, y1: 349),
            .writeMode(1),
            .resetWindows,
        ])
        XCTAssertEqual(try RIPWriter.encode(scene),
                       "!|L00010A0E\r\n!|c0A\r\n!|v0000HR9P\r\n!|W01\r\n!|*\r\n")
    }

    func testLineEndingParameter() throws {
        let scene = RIPScene(commands: [.eraseWindow, .home])
        XCTAssertEqual(try RIPWriter.encode(scene, lineEnding: "\n"), "!|e\n!|H\n")
    }

    func testEscapeCommandCharacters() throws {
        let text = try RIPWriter.encode(RIPScene(commands: [.query(mode: 0, reserved: 0, text: "x")]))
        XCTAssertEqual(text, "!|1\u{1B}0000x\r\n")
        let block = try RIPWriter.encode(RIPScene(commands: [
            .enterBlockMode(mode: 0, transferProtocol: 7, fileType: 4, reserved: 0, filename: "")]))
        XCTAssertEqual(block, "!|9\u{1B}07040000<>\r\n")
    }

    func testTextIsEscaped() throws {
        let text = try RIPWriter.encode(RIPScene(commands: [.text("a!b|c\\d")]))
        XCTAssertEqual(text, "!|Ta\\!b\\|c\\\\d\r\n")
    }

    // MARK: - Errors

    func testOutOfRangeValueThrows() {
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.line(x0: 0, y0: 0, x1: 1296, y1: 0)]))) {
            XCTAssertEqual($0 as? RIPWriteError, .valueOutOfRange(command: "L", value: 1296, width: 2))
        }
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.pixel(x: -1, y: 0)])))
    }

    func testWrongListLengthsThrow() {
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.setPalette([1, 2, 3])]))) {
            XCTAssertEqual($0 as? RIPWriteError, .invalidArgumentCount(command: "Q", count: 3))
        }
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.fillPattern(bytes: [1], color: 1)])))
    }

    func testLineBreakInTextThrows() {
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.text("a\nb")]))) {
            XCTAssertEqual($0 as? RIPWriteError, .lineBreakInText(command: "T"))
        }
    }

    func testInvalidUnknownThrows() {
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.unknown(level: "", command: "|", arguments: "")])))
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: [.unknown(level: "x", command: "L", arguments: "")])))
    }

    // MARK: - Round trips

    func testLevel0RoundTrip() {
        roundTrip([
            .textWindow(x0: 1, y0: 1, x1: 79, y1: 42, wrap: 0, size: 4),
            .viewport(x0: 0, y0: 0, x1: 639, y1: 349),
            .resetWindows, .eraseWindow, .eraseView,
            .gotoXY(x: 12, y: 4), .home, .eraseEOL,
            .color(15),
            .setPalette((0..<16).map { ($0 * 3) % 64 }),
            .onePalette(slot: 7, value: 63),
            .writeMode(1),
            .move(x: 320, y: 175),
            .text("HELLO WORLD"),
            .textXY(x: 100, y: 100, string: "mix !pipe|back\\slash and trail\\"),
            .fontStyle(font: 10, direction: 1, size: 10, reserved: 0),
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
            .polygon(points: [RIPPoint(x: 0, y: 0), RIPPoint(x: 100, y: 50), RIPPoint(x: 200, y: 0)]),
            .fillPolygon(points: [RIPPoint(x: 0, y: 0), RIPPoint(x: 100, y: 50), RIPPoint(x: 200, y: 0)]),
            .polyline(points: [RIPPoint(x: 0, y: 0), RIPPoint(x: 100, y: 50)]),
            .fill(x: 1, y: 2, border: 15),
            .lineStyle(style: 4, userPattern: 0xF0F0, thickness: 3),
            .fillStyle(pattern: 11, color: 4),
            .fillPattern(bytes: [0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55], color: 9),
            .noMore,
        ])
    }

    func testLevel1And9RoundTrip() {
        roundTrip([
            .mouse(num: 0, x0: 10, y0: 20, x1: 100, y1: 60, click: 1, clear: 0, reserved: 0, hostCommand: "RUN\\foo|bar^M"),
            .killMouseFields,
            .beginText(x0: 0, y0: 0, x1: 639, y1: 349, reserved: 0),
            .regionText(justify: 1, string: "Hello, region!"),
            .endText,
            .getImage(x0: 0, y0: 0, x1: 50, y1: 50, reserved: 0),
            .putImage(x: 100, y: 100, mode: 4, reserved: 0),
            .writeIcon(reserved: 0, filename: "MYICON.ICN"),
            .loadIcon(x: 10, y: 10, mode: 0, clipboard: 1, reserved: 36, filename: "MYICON.ICN"),
            .buttonStyle(RIPButtonStyle(width: 80, height: 24, orientation: 2, flags: 0xFFFF, bevelSize: 2,
                                        labelColor: 15, dropShadowColor: 0, brightColor: 15, darkColor: 8,
                                        surfaceColor: 7, groupNumber: 35, flags2: 31, underlineColor: 1,
                                        cornerColor: 0, reserved: 0)),
            .button(x0: 10, y0: 10, x1: 90, y1: 34, hotkey: 255, flags: 3, reserved: 0, text: "icon<>OK!<>[0]GO^m"),
            .define(flags: 7, reserved: 0, text: "FULL_NAME,30:?What is your name?John"),
            .query(mode: 2, reserved: 0, text: "$OFF$"),
            .copyRegion(x0: 0, y0: 0, x1: 63, y1: 50, reserved: 0, destLine: 100),
            .readScene(reserved: 0, filename: "OTHER.RIP"),
            .fileQuery(mode: 4, reserved: 0, filename: "DATA.ICN"),
            .enterBlockMode(mode: 1, transferProtocol: 7, fileType: 5, reserved: 0, filename: "UP.ZIP"),
            .unknown(level: "15", command: "L", arguments: "0102\\|x"),
        ])
    }

    func testAnsiSenseIsSkipped() throws {
        XCTAssertEqual(try RIPWriter.encode(RIPScene(commands: [.ansiSense(.query)])), "")
    }

    // MARK: - Continuation folding

    func testLongCommandsFoldWithinWidth() throws {
        let pts = (0..<300).map { RIPPoint(x: $0, y: $0 * 2 % 350) }
        let commands: [RIPCommand] = [
            .polyline(points: pts),
            .text(String(repeating: "\\", count: 200)),
            .text(String(repeating: "a!", count: 100) + "\\"),
        ]
        let text = try RIPWriter.encode(RIPScene(commands: commands))
        for line in text.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.count, RIPWriter.defaultLineWidth, line)
        }
        roundTrip(commands)
        for width in [8, 9, 10, 13, 40] {
            let folded = try RIPWriter.encode(RIPScene(commands: commands), lineWidth: width)
            XCTAssertEqual(try RIPParser.parse(folded).commands, commands, "width \(width)")
        }
    }
}
