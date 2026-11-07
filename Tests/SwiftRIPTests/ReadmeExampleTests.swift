// ReadmeExampleTests — the README / DocC quick-start code, compiled and
// checked so the documentation cannot drift from the API.

import XCTest
import CoreGraphics
import SwiftRIP

final class ReadmeExampleTests: XCTestCase {

    func testQuickStart() throws {
        // Decode: raw bytes of a .RIP file or a captured session.
        let rip = "!|*|c0E|S0101|B0A0A5K1O|@0K0UWelcome\\!\r\n"
        let scene = try SwiftRIP.decode(Data(rip.utf8))

        // Render to a CGImage at 2x with chunky EGA pixels.
        var options = RIPRenderOptions()
        options.targetSize = CGSize(width: 1280, height: 700)
        options.antiAliasing = false
        let image: CGImage? = SwiftRIP.render(scene, options: options)

        // Framebuffer, final state and mouse regions.
        let result = SwiftRIP.renderResult(scene)
        XCTAssertEqual(result.framebuffer.colorIndex(x: 15, y: 15), 1)
        XCTAssertEqual(result.interactive.mouseRegions.count, 0)

        // Encode back to RIPscrip text.
        let text = try SwiftRIP.encode(scene)

        XCTAssertEqual(image?.width, 1280)
        XCTAssertEqual(text, "!|*\r\n!|c0E\r\n!|S0101\r\n!|B0A0A5K1O\r\n!|@0K0UWelcome\\!\r\n")
    }

    func testGettingStartedWriteExample() throws {
        let scene = RIPScene(commands: [
            .resetWindows,
            .color(14),
            .fillStyle(pattern: 1, color: 1),
            .bar(x0: 10, y0: 10, x1: 200, y1: 60),
            .textXY(x: 20, y: 30, string: "Welcome!"),
        ])
        let text = try SwiftRIP.encode(scene)
        XCTAssertEqual(text, "!|*\r\n!|c0E\r\n!|S0101\r\n!|B0A0A5K1O\r\n!|@0K0UWelcome\\!\r\n")
    }

    func testGettingStartedPlayback() async throws {
        let scene = try SwiftRIP.decode("!|c0E|B00001010|L00002020\r\n")
        var options = RIPRenderOptions()
        options.animation = .animated(framesPerCommand: 2)
        var frames = 0
        for await frame in try SwiftRIP.renderFrames(scene, options: options) {
            XCTAssertEqual(frame.width, 640)
            frames += 1
        }
        XCTAssertEqual(frames, 2)
    }
}
