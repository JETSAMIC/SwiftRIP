import XCTest
@testable import SwiftRIP

final class MegaNumTests: XCTestCase {

    // MARK: - Encoding

    func testEncodeKnownValues() {
        XCTAssertEqual(MegaNum.encode(0, width: 1), "0")
        XCTAssertEqual(MegaNum.encode(0, width: 2), "00")
        XCTAssertEqual(MegaNum.encode(0, width: 3), "000")
        XCTAssertEqual(MegaNum.encode(5, width: 2), "05")
        XCTAssertEqual(MegaNum.encode(15, width: 1), "F")
        XCTAssertEqual(MegaNum.encode(15, width: 2), "0F")
        XCTAssertEqual(MegaNum.encode(35, width: 1), "Z")
        XCTAssertEqual(MegaNum.encode(36, width: 2), "10")
        XCTAssertEqual(MegaNum.encode(100, width: 2), "2S")
        XCTAssertEqual(MegaNum.encode(349, width: 2), "9P")
        XCTAssertEqual(MegaNum.encode(639, width: 3), "0HR")
        XCTAssertEqual(MegaNum.encode(1295, width: 2), "ZZ")
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
        XCTAssertEqual(try MegaNum.decode("000", width: 3), 0)
        XCTAssertEqual(try MegaNum.decode("0HR", width: 3), 639)
    }

    func testDecodeIsCaseInsensitive() throws {
        XCTAssertEqual(try MegaNum.decode("zz", width: 2), 1295)
        XCTAssertEqual(try MegaNum.decode("hR", width: 2), 639)
    }

    // MARK: - Round trip

    func testRoundTrip() throws {
        for value in [0, 1, 5, 15, 35, 36, 100, 349, 639, 1295, 46655] {
            for width in 1...5 where MegaNum.encode(value, width: width).count == width || value >= Int(pow(36.0, Double(width))) {
                let encoded = MegaNum.encode(value, width: width)
                if encoded.count == width {
                    XCTAssertEqual(try MegaNum.decode(Substring(encoded), width: width), value)
                }
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
        XCTAssertThrowsError(try MegaNum.decode("$$", width: 2)) { error in
            XCTAssertEqual(error as? MegaNum.DecodeError, .invalidDigit("$"))
        }
    }

    // MARK: - Variable-width tail

    func testVariableWidthDecode() {
        XCTAssertEqual(MegaNum.decode("0"), 0)
        XCTAssertEqual(MegaNum.decode("ZZZ"), 36 * 36 * 35 + 36 * 35 + 35)
        XCTAssertNil(MegaNum.decode(""))
        XCTAssertNil(MegaNum.decode("0!"))
    }
}
