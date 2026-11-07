// RIPAnimationFrames — incremental playback of a `RIPScene` as an
// `AsyncSequence` of images, reproducing the sequential-draw look of a
// RIPscrip scene arriving over a modem.

#if canImport(CoreGraphics)
import Foundation
import CoreGraphics

/// Errors thrown by ``SwiftRIP/renderFrames(_:options:)``.
public enum RIPAnimationError: Error, Equatable, Sendable {
    /// `options.animation` is `.static`.
    case notAnimated
    /// `framesPerCommand` was zero or negative.
    case invalidFramesPerCommand(Int)
}

/// An asynchronous sequence of images, one after every `framesPerCommand`
/// commands of a scene. Each image is composed with the same scaling and
/// smoothing options as a static render. Iteration ends after the last
/// command, when the pixel budget is exhausted, or when the consuming task
/// is cancelled.
public struct RIPAnimationFrames: AsyncSequence, Sendable {
    /// Each element is one composed frame.
    public typealias Element = CGImage

    let scene: RIPScene
    let options: RIPRenderOptions
    let framesPerCommand: Int

    static func make(scene: RIPScene, options: RIPRenderOptions) throws -> RIPAnimationFrames {
        switch options.animation {
        case .static:
            throw RIPAnimationError.notAnimated
        case .animated(let n):
            guard n > 0 else { throw RIPAnimationError.invalidFramesPerCommand(n) }
            return RIPAnimationFrames(scene: scene, options: options, framesPerCommand: n)
        }
    }

    /// Create an iterator that renders the scene from the beginning.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(scene: scene, options: options, framesPerCommand: framesPerCommand)
    }

    /// Iterator over ``RIPAnimationFrames``.
    public struct AsyncIterator: AsyncIteratorProtocol {
        /// Each element is one composed frame.
        public typealias Element = CGImage

        private let scene: RIPScene
        private let options: RIPRenderOptions
        private let framesPerCommand: Int
        private let interpreter: RIPInterpreter
        private var cursor = 0

        init(scene: RIPScene, options: RIPRenderOptions, framesPerCommand: Int) {
            self.scene = scene
            self.options = options
            self.framesPerCommand = framesPerCommand
            self.interpreter = RIPInterpreter(canvas: RIPCanvas(), pixelBudget: options.pixelBudget)
        }

        /// Apply the next batch of commands and return the resulting frame,
        /// or `nil` when playback is finished.
        public mutating func next() async -> CGImage? {
            guard cursor < scene.commands.count, !Task.isCancelled, !interpreter.isTruncated else { return nil }
            let stop = Swift.min(cursor + framesPerCommand, scene.commands.count)
            while cursor < stop {
                if !interpreter.step(scene.commands[cursor]) { break }
                cursor += 1
            }
            return RIPCompositor.compose(interpreter.canvas.framebuffer, options: options)
        }
    }
}
#endif
