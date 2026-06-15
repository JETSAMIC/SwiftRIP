import XCTest
@testable import SwiftRIP

final class AnsiSequenceTests: XCTestCase {

    func testEmitBytes() {
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .query),    [0x1B, 0x5B, 0x21])
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .enable),   [0x1B, 0x5B, 0x30, 0x21])
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .enable2x), [0x1B, 0x5B, 0x31, 0x21])
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .disable),  [0x1B, 0x5B, 0x32, 0x21])
    }

    func testAbsorbAllFour() {
        let bytes: [UInt8] = [0x1B, 0x5B, 0x21,                                  // query
                              0x1B, 0x5B, 0x30, 0x21,                            // enable
                              0x1B, 0x5B, 0x31, 0x21,                            // enable2x
                              0x1B, 0x5B, 0x32, 0x21]                            // disable
        let hits = RIPAnsiSequences.scan(Data(bytes))
        XCTAssertEqual(hits.map(\.sense), [.query, .enable, .enable2x, .disable])
    }

    func testTokenizerSurfacesSenses() {
        let stream = RIPTokenizer.tokenize("\u{1B}[!\u{1B}[0!\u{1B}[1!\u{1B}[2!")
        XCTAssertEqual(stream.ansiSenses.map(\.sense),
                       [.query, .enable, .enable2x, .disable])
    }

    func testParserEmitsAnsiSenseCommands() throws {
        // ANSI sense outside the !| frame should produce ansiSense commands
        // interleaved with the parsed RIP commands in source order.
        let input = "\u{1B}[!\n!|*\n\u{1B}[2!\n"
        let cmds = try RIPParser.parse(input).commands
        XCTAssertEqual(cmds, [.ansiSense(.query), .resetWindows, .ansiSense(.disable)])
    }

    func testSensesInsideFrameAreNotRecognized() {
        // An escape byte inside a `!|...|` line is just data.
        let bytes: [UInt8] = [0x21, 0x7C,                                       // !|
                              0x54,                                              // T
                              0x1B, 0x5B, 0x21,                                  // ESC[! — INSIDE frame
                              0x7C,                                              // |
                              0x0A]                                              // \n
        let hits = RIPAnsiSequences.scan(Data(bytes))
        XCTAssertTrue(hits.isEmpty)
    }
}
