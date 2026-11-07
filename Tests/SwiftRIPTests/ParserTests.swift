import XCTest
@testable import SwiftRIP

/// Framing, escaping and error behaviour of `RIPParser` (RIPscrip 1.54
/// "General Structure" rules).
final class ParserTests: XCTestCase {

    private func parse(_ s: String) throws -> [RIPCommand] {
        try RIPParser.parse(s).commands
    }

    // MARK: - Framing

    func testCommandsAreSeparatedByPipe() throws {
        XCTAssertEqual(try parse("!|c0F|L00001010|*\r\n"),
                       [.color(15), .line(x0: 0, y0: 0, x1: 36, y1: 36), .resetWindows])
    }

    /// Spec rule 6: unrecognized text after a command is ignored. Commands
    /// are not concatenated without a `|`.
    func testTrailingTextAfterCommandIsIgnored() throws {
        XCTAssertEqual(try parse("!|c0Fg0102\r\n"), [.color(15)])
        XCTAssertEqual(try parse("!|L00001010 some comment|c01\r\n"),
                       [.line(x0: 0, y0: 0, x1: 36, y1: 36), .color(1)])
    }

    func testSpecContinuationExample() throws {
        let input = "!|c02|L02030405|P0901020102010201020102\\\r\n0102010201020102\r\n"
        let cmds = try parse(input)
        XCTAssertEqual(cmds.count, 3)
        XCTAssertEqual(cmds[0], .color(2))
        XCTAssertEqual(cmds[1], .line(x0: 2, y0: 3, x1: 4, y1: 5))
        XCTAssertEqual(cmds[2], .polygon(points: Array(repeating: RIPPoint(x: 1, y: 2), count: 9)))
    }

    func testEmptyAndWhitespaceSegmentsAreSkipped() throws {
        XCTAssertEqual(try parse("!||c01|  |\r\n"), [.color(1)])
    }

    func testMidLineMarkerIsText() throws {
        XCTAssertEqual(try parse("Hi !|c01\r\n"), [])
    }

    func testRawTextLinesAreIgnored() throws {
        XCTAssertEqual(try parse("Welcome to the BBS\r\n!|c01\r\nmore text\r\n"), [.color(1)])
    }

    // MARK: - Variable-width last parameter (rule 10)

    func testVariableWidthLastParameter() throws {
        XCTAssertEqual(try parse("!|cA\r\n"), [.color(10)])
        XCTAssertEqual(try parse("!|cA|c0B\r\n"), [.color(10), .color(11)])
        XCTAssertEqual(try parse("!|L0001020\r\n"), [.line(x0: 0, y0: 1, x1: 2, y1: 0)])
    }

    // MARK: - Text and escapes (rule 11 / 13)

    func testTextEscapes() throws {
        XCTAssertEqual(try parse("!|Tpipe \\| bang \\! slash \\\\ other \\q\r\n"),
                       [.text("pipe | bang ! slash \\ other \\q")])
    }

    func testTextRunsToNextUnescapedPipe() throws {
        XCTAssertEqual(try parse("!|THello|c01\r\n"), [.text("Hello"), .color(1)])
    }

    func testSpecLiteralBackslashContinuationExample() throws {
        let input = "!|@2233this is a text line with a literal \\\\\\\r\nused in the message\r\n"
        XCTAssertEqual(try parse(input),
                       [.textXY(x: 74, y: 111, string: "this is a text line with a literal \\used in the message")])
    }

    func testBytesAbove0x7FArePreserved() throws {
        let bytes: [UInt8] = Array("!|T".utf8) + [0xDB, 0xB1] + [0x0D, 0x0A]
        let cmds = try RIPParser.parse(Data(bytes)).commands
        XCTAssertEqual(cmds, [.text("\u{DB}\u{B1}")])
    }

    func testButtonTextBlocks() {
        let t = RIPButtonText(parsing: "icon<>label<>host<>more")
        XCTAssertEqual(t, RIPButtonText(iconFile: "icon", label: "label", hostCommand: "host<>more"))
        XCTAssertEqual(RIPButtonText(parsing: "<>Label"), RIPButtonText(iconFile: "", label: "Label", hostCommand: ""))
        XCTAssertEqual(RIPButtonText(parsing: "icon"), RIPButtonText(iconFile: "icon", label: "", hostCommand: ""))
        XCTAssertEqual(RIPButtonText(parsing: "<><>cmd").hostCommand, "cmd")
        XCTAssertEqual(RIPButtonText(parsing: "a<>b<>c").rawValue, "a<>b<>c")
    }

    // MARK: - ANSI interleaving

    func testAnsiSensesInterleaveInSourceOrder() throws {
        let cmds = try parse("\u{1B}[!\r\n!|*\r\n\u{1B}[2!\r\n")
        XCTAssertEqual(cmds, [.ansiSense(.query), .resetWindows, .ansiSense(.enable)])
    }

    // MARK: - Errors

    func testTruncatedFixedArgumentThrows() {
        XCTAssertThrowsError(try parse("!|g0\r\n")) { error in
            XCTAssertEqual(error as? RIPParseError, .truncated(command: "g", offset: 0))
        }
        XCTAssertThrowsError(try parse("!|1M0000\r\n")) { error in
            XCTAssertEqual(error as? RIPParseError, .truncated(command: "1M", offset: 0))
        }
    }

    func testInvalidMegaNumThrows() {
        XCTAssertThrowsError(try parse("x\r\n!|L00$$1010\r\n")) { error in
            XCTAssertEqual(error as? RIPParseError, .invalidMegaNum(command: "L", text: "$$", offset: 3))
        }
    }

    func testLevelDigitsWithoutCommandThrow() {
        XCTAssertThrowsError(try parse("!|1\r\n")) { error in
            XCTAssertEqual(error as? RIPParseError, .truncated(command: "1", offset: 0))
        }
    }

    func testPolygonCountLargerThanPointsThrows() {
        XCTAssertThrowsError(try parse("!|P05000101\r\n"))
    }
}
