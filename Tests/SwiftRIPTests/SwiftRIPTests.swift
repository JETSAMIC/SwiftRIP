import XCTest
@testable import SwiftRIP

final class SwiftRIPTests: XCTestCase {
    func testPlaceholder() {
        // Placeholder smoke test to keep the test target alive until the
        // parser/renderer/writer phases ship. Asserts the umbrella namespace
        // is importable and the package builds cleanly.
        XCTAssertTrue(true)
    }
}
