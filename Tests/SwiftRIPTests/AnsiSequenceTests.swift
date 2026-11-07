import XCTest
@testable import SwiftRIP

/// RIPscrip 1.54 "ANSI SEQUENCES (AUTO-SENSING)".
final class AnsiSequenceTests: XCTestCase {

    func testEmitBytes() {
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .query),          [0x1B, 0x5B, 0x21])
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .queryAlternate), [0x1B, 0x5B, 0x30, 0x21])
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .disable),        [0x1B, 0x5B, 0x31, 0x21])
        XCTAssertEqual(RIPAnsiSequences.bytes(for: .enable),         [0x1B, 0x5B, 0x32, 0x21])
    }

    func testScanAllFour() {
        let bytes: [UInt8] = [0x1B, 0x5B, 0x21, 0x1B, 0x5B, 0x30, 0x21, 0x1B, 0x5B, 0x31, 0x21, 0x1B, 0x5B, 0x32, 0x21]
        let hits = RIPAnsiSequences.scan(Data(bytes))
        XCTAssertEqual(hits.map(\.sense), [.query, .queryAlternate, .disable, .enable])
        XCTAssertEqual(hits.map(\.offset), [0, 3, 7, 11])
    }

    func testVersionReply() {
        XCTAssertEqual(RIPAnsiSequences.versionReply(), "RIPSCRIP015400")
        XCTAssertEqual(RIPAnsiSequences.versionReply(vendor: 1, subVersion: 0), "RIPSCRIP015410")
        XCTAssertNil(RIPAnsiSequences.versionReply(vendor: 10))
    }

    func testSensesInsideFrameAreNotRecognized() {
        let bytes: [UInt8] = [0x21, 0x7C, 0x54, 0x1B, 0x5B, 0x21, 0x0D, 0x0A]
        XCTAssertTrue(RIPAnsiSequences.scan(Data(bytes)).isEmpty)
    }

    func testDisabledRIPLinesAreNotParsed() throws {
        let cmds = try RIPParser.parse("\u{1B}[1!\r\n!|c01\r\n\u{1B}[2!\r\n!|c02\r\n").commands
        XCTAssertEqual(cmds, [.ansiSense(.disable), .ansiSense(.enable), .color(2)])
    }
}
