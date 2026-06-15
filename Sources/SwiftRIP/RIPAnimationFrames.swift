// RIPAnimationFrames — incremental playback of a `RIPScene` as an
// `AsyncSequence` of `CGImage` snapshots.
//
// The 1996-era sequential-draw feel of RIPscrip — lines walking across the
// canvas, then text, then chrome — is part of why these scenes look the
// way they do. Static rendering collapses every command instantly; this
// sequence surfaces the in-progress canvas after each batch so callers can
// drive a Timer / Task.sleep loop and reproduce that cadence.
//
// Frames are composed through the same scale + AA pipeline used by the
// static path, so the animation honours `targetSize` and `antiAliasing`
// just like a single-shot render.

import Foundation
import CoreGraphics

/// Errors thrown by the animation entry point on the public façade.
public enum RIPAnimationError: Error, Equatable, Sendable {
    /// Caller asked for `renderFrames` with `options.animation == .static`.
    case notAnimated
    /// `framesPerCommand` was zero or negative.
    case invalidFramesPerCommand(Int)
}

/// Asynchronous sequence of `CGImage` snapshots representing progressive
/// playback of a `RIPScene`. Each emitted frame is the in-progress canvas
/// after a batch of `framesPerCommand` commands have been applied.
///
/// The sequence is created via `SwiftRIP.renderFrames(_:options:)` when
/// `options.animation` is `.animated(framesPerCommand:)`.
public struct RIPAnimationFrames: AsyncSequence, Sendable {
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

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(scene: scene, options: options, framesPerCommand: framesPerCommand)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = CGImage

        let scene: RIPScene
        let options: RIPRenderOptions
        let framesPerCommand: Int

        private let canvas: RIPCanvas
        private let session: RIPInterpreter.Session
        private var cursor: Int = 0

        init(scene: RIPScene, options: RIPRenderOptions, framesPerCommand: Int) {
            self.scene = scene
            self.options = options
            self.framesPerCommand = framesPerCommand
            let canvas = RIPCanvas()
            let state = RIPGraphicsState()
            canvas.palette = state.palette
            canvas.clear(to: options.clearColor)
            self.canvas = canvas
            self.session = RIPInterpreter.Session(canvas: canvas, state: state, options: options)
        }

        public mutating func next() async -> CGImage? {
            guard cursor < scene.commands.count else { return nil }
            let stop = Swift.min(cursor + framesPerCommand, scene.commands.count)
            while cursor < stop {
                session.step(scene.commands[cursor])
                cursor += 1
            }
            return RIPCompositor.compose(canvas: canvas, options: options)
        }
    }
}

public extension SwiftRIP {
    /// Render a `RIPScene` as an `AsyncSequence` of `CGImage` snapshots
    /// reflecting incremental command playback. Throws
    /// `RIPAnimationError.notAnimated` when `options.animation` is
    /// `.static`. Use `options.animation = .animated(framesPerCommand:)`
    /// to control batch grain and `options.animationSpeed` to pace the
    /// emission loop on the caller side.
    static func renderFrames(_ scene: RIPScene, options: RIPRenderOptions = .default) throws -> RIPAnimationFrames {
        try RIPAnimationFrames.make(scene: scene, options: options)
    }
}
