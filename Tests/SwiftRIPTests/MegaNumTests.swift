import XCTest
@testable import SwiftRIP

final class MegaNumTests: XCTestCase {

    // MARK: - Encoding

    func testEncodeKnownValues() throws {
        XCTAssertEqual(try MegaNum.encode(0, width: 1), "0")
        XCTAssertEqual(try MegaNum.encode(0, width: 2), "00")
        XCTAssertEqual(try MegaNum.encode(0, width: 3), "000")
        XCTAssertEqual(try MegaNum.encode(5, width: 2), "05")
        XCTAssertEqual(try MegaNum.encode(15, width: 1), "F")
        XCTAssertEqual(try MegaNum.encode(15, width: 2), "0F")
        XCTAssertEqual(try MegaNum.encode(35, width: 1), "Z")
        XCTAssertEqual(try MegaNum.encode(36, width: 2), "10")
        XCTAssertEqual(try MegaNum.encode(100, width: 2), "2S")
        XCTAssertEqual(try MegaNum.encode(349, width: 2), "9P")
        XCTAssertEqual(try MegaNum.encode(639, width: 2), "HR")
        XCTAssertEqual(try MegaNum.encode(1295, width: 2), "ZZ")
    }

    /// Values from the RIPscrip 1.54 RIP_LINE_STYLE and RIP_FILL_STYLE tables.
    func testSpecTableValues() throws {
        XCTAssertEqual(try MegaNum.encode(43690, width: 4), "0XPM")   // AAAA
        XCTAssertEqual(try MegaNum.encode(61680, width: 4), "1BLC")   // F0F0
        XCTAssertEqual(try MegaNum.encode(255, width: 2), "73")
        XCTAssertEqual(try MegaNum.decode("3K", width: 2), 128)
        XCTAssertEqual(try MegaNum.decode("5O", width: 2), 204)
    }

    func testEncodeRejectsOutOfRange() {
        XCTAssertThrowsError(try MegaNum.encode(1296, width: 2)) { error in
            XCTAssertEqual(error as? MegaNum.DecodeError, .valueOutOfRange(value: 1296, width: 2))
        }
        XCTAssertThrowsError(try MegaNum.encode(-1, width: 2))
        XCTAssertThrowsError(try MegaNum.encode(1, width: 0))
    }

    func testMaxValue() {
        XCTAssertEqual(MegaNum.maxValue(width: 1), 35)
        XCTAssertEqual(MegaNum.maxValue(width: 2), 1295)
        XCTAssertNil(MegaNum.maxValue(width: 0))
        XCTAssertNil(MegaNum.maxValue(width: 40))
    }

    // MARK: - Decoding

    func testDecodeKnownValues() throws {
        XCTAssertEqual(try MegaNum.decode("00", width: 2), 0)
        XCTAssertEqual(try MegaNum.decode("05", width: 2), 5)
        XCTAssertEqual(try MegaNum.decode("0F", width: 2), 15)
        XCTAssertEqual(try MegaNum.decode("Z", width: 1), 35)
        XCTAssertEqual(try MegaNum.decode("10", width: 2), 36)
        XCTAssertEqual(try MegaNum.decode("2S", width: 2), 100)
        XCTAssertEqual(try MegaNum.decode("HR", width: 2), 639)
        XCTAssertEqual(try MegaNum.decode("ZZ", width: 2), 1295)
        XCTAssertEqual(try MegaNum.decode("0HR", width: 3), 639)
    }

    func testDecodeIsCaseInsensitive() throws {
        XCTAssertEqual(try MegaNum.decode("zz", width: 2), 1295)
        XCTAssertEqual(try MegaNum.decode("hR", width: 2), 639)
    }

    func testDecodeOverflowThrows() {
        let huge = Substring(String(repeating: "Z", count: 20))
        XCTAssertThrowsError(try MegaNum.decode(huge, width: 20)) { error in
            XCTAssertEqual(error as? MegaNum.DecodeError, .overflow)
        }
        XCTAssertNil(MegaNum.decode(huge))
    }

    // MARK: - Round trip

    func testRoundTrip() throws {
        for value in [0, 1, 5, 15, 35, 36, 100, 349, 639, 1295, 46655] {
            for width in 1...5 where value <= MegaNum.maxValue(width: width)! {
                let encoded = try MegaNum.encode(value, width: width)
                XCTAssertEqual(encoded.count, width)
                XCTAssertEqual(try MegaNum.decode(Substring(encoded), width: width), value)
            }
        }
    }

    // MARK: - Errors

    func testWidthMismatch() {
        XCTAssertThrowsError(try MegaNum.decode("0", width: 2)) { error in
            XCTAssertEqual(error as? MegaNum.DecodeError, .widthMismatch(expected: 2, got: 1))
        }
        XCTAssertThrowsError(try MegaNum.decode("000", width: 2)) { error in
            XCTAssertEqual(error as? MegaNum.DecodeError, .widthMismatch(expected: 2, got: 3))
        }
    }

    func testInvalidDigit() {
        XCTAssertThrowsError(try MegaNum.decode("0!", width: 2)) { error in
            XCTAssertEqual(error as? MegaNum.DecodeError, .invalidDigit("!"))
        }
    }

    func testVariableWidthDecode() {
        XCTAssertEqual(MegaNum.decode("0"), 0)
        XCTAssertEqual(MegaNum.decode("ZZZ"), 36 * 36 * 35 + 36 * 35 + 35)
        XCTAssertNil(MegaNum.decode(""))
        XCTAssertNil(MegaNum.decode("0!"))
    }
}
