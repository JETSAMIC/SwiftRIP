// RIPAnimationTests — incremental playback of a `RIPScene` through
// `RIPAnimationFrames`.
//
// The animated path must:
//   * yield exactly one frame per batch of `framesPerCommand` commands
//   * throw `RIPAnimationError.notAnimated` when called with `.static`
//   * compose every frame through the same scale + AA pipeline as the
//     static path

import XCTest
import CoreGraphics
@testable import SwiftRIP

final class RIPAnimationTests: XCTestCase {

    /// Build a 10-command scene that draws a diagonal of pixels — every
    /// command is visually distinct so frame N differs from frame N-1.
    private func tenCommandScene() -> RIPScene {
        var commands: [RIPCommand] = [.color(15)]
        for i in 0..<9 {
            commands.append(.pixel(x: i * 10, y: i * 10))
        }
        return RIPScene(commands: commands)
    }

    func testAnimatedPlaybackYieldsOneFramePerCommand() async throws {
        var opts = RIPRenderOptions()
        opts.animation = .animated(framesPerCommand: 1)
        let scene = tenCommandScene()
        let frames = try SwiftRIP.renderFrames(scene, options: opts)

        var count = 0
        for await frame in frames {
            count += 1
            // Every frame is the native 640x350 image (targetSize == nil).
            XCTAssertEqual(frame.width, 640)
            XCTAssertEqual(frame.height, 350)
        }
        XCTAssertEqual(count, 10,
            "framesPerCommand=1 on a 10-command scene must yield exactly 10 frames")
    }

    func testAnimatedPlaybackBatchesFrames() async throws {
        var opts = RIPRenderOptions()
        opts.animation = .animated(framesPerCommand: 3)
        let scene = tenCommandScene()
        let frames = try SwiftRIP.renderFrames(scene, options: opts)

        var count = 0
        for await _ in frames {
            count += 1
        }
        // 10 commands / 3 per batch = 4 frames (3+3+3+1).
        XCTAssertEqual(count, 4)
    }

    func testStaticModeThrowsOnRenderFrames() {
        let scene = tenCommandScene()
        let opts = RIPRenderOptions.default // .static
        XCTAssertThrowsError(try SwiftRIP.renderFrames(scene, options: opts)) { err in
            XCTAssertEqual(err as? RIPAnimationError, .notAnimated)
        }
    }

    func testInvalidFramesPerCommandThrows() {
        let scene = tenCommandScene()
        var opts = RIPRenderOptions()
        opts.animation = .animated(framesPerCommand: 0)
        XCTAssertThrowsError(try SwiftRIP.renderFrames(scene, options: opts)) { err in
            XCTAssertEqual(err as? RIPAnimationError, .invalidFramesPerCommand(0))
        }
    }

    func testAnimatedFramesHonorTargetSize() async throws {
        var opts = RIPRenderOptions()
        opts.animation = .animated(framesPerCommand: 1)
        opts.targetSize = CGSize(width: 1280, height: 700)
        opts.antiAliasing = false
        let scene = RIPScene(commands: [.color(15), .pixel(x: 10, y: 10)])
        let frames = try SwiftRIP.renderFrames(scene, options: opts)
        var count = 0
        for await frame in frames {
            XCTAssertEqual(frame.width, 1280)
            XCTAssertEqual(frame.height, 700)
            count += 1
        }
        XCTAssertEqual(count, 2)
    }
}
