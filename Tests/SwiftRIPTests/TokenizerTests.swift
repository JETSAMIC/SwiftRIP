import XCTest
@testable import SwiftRIP

final class TokenizerTests: XCTestCase {

    func testEmptyInput() {
        let stream = RIPTokenizer.tokenize("")
        XCTAssertTrue(stream.tokens.isEmpty)
        XCTAssertTrue(stream.ansiSenses.isEmpty)
    }

    func testNoRIPFrame() {
        let stream = RIPTokenizer.tokenize("just regular text\r\nno RIP here\n")
        XCTAssertTrue(stream.tokens.isEmpty)
    }

    func testSingleCommand() {
        let stream = RIPTokenizer.tokenize("!|c0F\r\n")
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "c0F")
    }

    func testMultipleCommandsPerLine() {
        // Two commands concatenated on one logical line: Color 15 then GotoXY.
        let stream = RIPTokenizer.tokenize("!|c0Fg001002\n")
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "c0Fg001002")
    }

    func testMultipleLines() {
        let input = "!|c0F\r\n!|g001002\r\n!|*\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 3)
        XCTAssertEqual(stream.tokens[0].payload, "c0F")
        XCTAssertEqual(stream.tokens[1].payload, "g001002")
        XCTAssertEqual(stream.tokens[2].payload, "*")
    }

    // MARK: - Line continuation

    func testLineContinuationLF() {
        let input = "!|TLong text \\\nmore text|\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "TLong text more text|")
    }

    func testLineContinuationCRLF() {
        let input = "!|TLong text \\\r\nmore text|\r\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "TLong text more text|")
    }

    func testLiteralBackslashEOLDouble() {
        // Two backslashes at EOL = one literal `\` + REAL line break.
        let input = "!|c01\\\\\n!|c02\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 2)
        XCTAssertEqual(stream.tokens[0].payload, "c01\\\\")
        XCTAssertEqual(stream.tokens[1].payload, "c02")
    }

    func testLiteralBackslashEOLTriple() {
        // Three backslashes at EOL = one literal `\\` (escaped) + continuation.
        let input = "!|Ta\\\\\\\nb|\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "Ta\\\\b|")
    }

    // MARK: - Escape sequences (preserved through tokenizer)

    func testEscapedPipe() {
        // `\|` should NOT terminate the line; preserved verbatim.
        let input = "!|Tha\\|llo|\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "Tha\\|llo|")
    }

    func testEscapedBang() {
        let input = "!|Tha\\!llo|\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "Tha\\!llo|")
    }

    // MARK: - Alternate start markers

    func testSOHStartMarker() {
        let input = "\u{01}|c0F\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "c0F")
    }

    func testSTXStartMarker() {
        let input = "\u{02}!|c0F\n"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.tokens.count, 1)
        XCTAssertEqual(stream.tokens[0].payload, "c0F")
    }

    // MARK: - ANSI auto-sense

    func testANSISenseQuery() {
        let input = "\u{1B}[!"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertTrue(stream.tokens.isEmpty)
        XCTAssertEqual(stream.ansiSenses.count, 1)
        XCTAssertEqual(stream.ansiSenses[0].sense, .query)
    }

    func testANSISenseAllFour() {
        let input = "\u{1B}[!\u{1B}[0!\u{1B}[1!\u{1B}[2!"
        let stream = RIPTokenizer.tokenize(input)
        XCTAssertEqual(stream.ansiSenses.count, 4)
        XCTAssertEqual(stream.ansiSenses.map(\.sense), [.query, .enable, .enable2x, .disable])
    }
}
