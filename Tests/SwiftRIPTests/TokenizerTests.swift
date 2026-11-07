import XCTest
@testable import SwiftRIP

final class TokenizerTests: XCTestCase {

    private func payloads(_ s: String) -> [String] {
        RIPTokenizer.tokenize(s).tokens.map(\.payload)
    }

    func testEmptyInput() {
        let stream = RIPTokenizer.tokenize("")
        XCTAssertTrue(stream.tokens.isEmpty)
        XCTAssertTrue(stream.ansiSenses.isEmpty)
    }

    func testNoRIPFrame() {
        XCTAssertEqual(payloads("just regular text\r\nno RIP here\n"), [])
    }

    func testSingleCommand() {
        XCTAssertEqual(payloads("!|c0F\r\n"), ["c0F"])
    }

    func testMultipleCommandsPerLineStayInOnePayload() {
        XCTAssertEqual(payloads("!|c0F|g0102\n"), ["c0F|g0102"])
    }

    func testMultipleLinesAndLineEndings() {
        XCTAssertEqual(payloads("!|c0F\r\n!|g0102\r!|*\n"), ["c0F", "g0102", "*"])
    }

    /// Spec rule 1: a RIPscrip line moved to the middle of a line is text.
    func testMidLineBangPipeIsLiteralText() {
        XCTAssertEqual(payloads("hello !|c0F\r\n"), [])
        XCTAssertEqual(payloads("hello\r\n!|c0F\r\n"), ["c0F"])
    }

    // MARK: - Line continuation (rules 5 and 13)

    func testSpecContinuationExample() {
        let input = "!|c02|L02030405|P0901020102010201020102\\\r\n0102010201020102\r\n"
        XCTAssertEqual(payloads(input), ["c02|L02030405|P09010201020102010201020102010201020102"])
    }

    func testLineContinuationLF() {
        XCTAssertEqual(payloads("!|TLong text \\\nmore text\n"), ["TLong text more text"])
    }

    func testLiteralBackslashEOLDouble() {
        // `\\` at EOL: one escaped literal backslash, then a real line break.
        XCTAssertEqual(payloads("!|Ta\\\\\n!|c02\n"), ["Ta\\\\", "c02"])
    }

    func testLiteralBackslashEOLTriple() {
        // Spec rule 13 example: `\\\` = literal backslash + continuation.
        let input = "!|@2233this is a text line with a literal \\\\\\\r\nused in the message\r\n"
        XCTAssertEqual(payloads(input), ["@2233this is a text line with a literal \\\\used in the message"])
    }

    // MARK: - Escapes are preserved for the parser

    func testEscapesPreserved() {
        XCTAssertEqual(payloads("!|Tha\\|llo\\!\n"), ["Tha\\|llo\\!"])
    }

    // MARK: - Alternate start markers (rule 12)

    func testSOHStartMarkerAnyColumn() {
        XCTAssertEqual(payloads("text \u{01}|c0F\n"), ["c0F"])
    }

    func testSTXStartMarkerAnyColumn() {
        XCTAssertEqual(payloads("text \u{02}|c0F\n"), ["c0F"])
        XCTAssertEqual(payloads("\u{02}!|c0F\n"), ["c0F"])
    }

    // MARK: - ANSI auto-sense

    func testANSISenses() {
        let stream = RIPTokenizer.tokenize("\u{1B}[!\u{1B}[0!\u{1B}[1!\u{1B}[2!")
        XCTAssertEqual(stream.ansiSenses.map(\.sense), [.query, .queryAlternate, .disable, .enable])
    }

    func testDisableSuppressesRIPUntilEnable() {
        let input = "\u{1B}[1!\r\n!|c01\r\n\u{1B}[2!\r\n!|c02\r\n"
        XCTAssertEqual(payloads(input), ["c02"])
    }

    func testDataIsDecodedByteForByte() {
        let bytes: [UInt8] = Array("!|T".utf8) + [0xB0, 0xDB, 0xFF] + [0x0D, 0x0A]
        let stream = RIPTokenizer.tokenize(Data(bytes))
        XCTAssertEqual(stream.tokens.first?.payload.unicodeScalars.map(\.value), [0x54, 0xB0, 0xDB, 0xFF])
    }
}
