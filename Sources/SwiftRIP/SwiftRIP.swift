// SwiftRIP — parser, writer and renderer for TeleGrafix RIPscrip 1.54
// (Remote Imaging Protocol Script) BBS vector graphics.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The SwiftRIP entry points: decode RIPscrip into a ``RIPScene``, encode a
/// scene back to RIPscrip text, and render a scene.
public enum SwiftRIP {

    /// Decode RIPscrip bytes (a `.RIP` file or captured BBS session).
    ///
    /// - Parameter data: Raw bytes, decoded as ISO-8859-1.
    /// - Returns: The parsed scene.
    /// - Throws: ``RIPParseError`` for malformed numeric arguments.
    public static func decode(_ data: Data) throws -> RIPScene {
        try RIPParser.parse(data)
    }

    /// Decode RIPscrip text.
    ///
    /// - Parameter text: RIPscrip source.
    /// - Returns: The parsed scene.
    /// - Throws: ``RIPParseError`` for malformed numeric arguments.
    public static func decode(_ text: String) throws -> RIPScene {
        try RIPParser.parse(text)
    }

    /// Encode a scene as RIPscrip 1.54 text with CRLF line endings.
    ///
    /// - Parameter scene: The scene to encode.
    /// - Returns: RIPscrip text that decodes back to the same commands (ANSI
    ///   auto-sense values are omitted).
    /// - Throws: ``RIPWriteError`` if a command cannot be represented.
    public static func encode(_ scene: RIPScene) throws -> String {
        try RIPWriter.encode(scene)
    }

    /// Execute a scene against a fresh 640x350 framebuffer.
    ///
    /// Only ``RIPRenderOptions/pixelBudget`` is used; the other options
    /// affect image composition (see ``RIPRenderResult/image(options:)``).
    /// Available on every platform (no CoreGraphics needed).
    ///
    /// - Parameters:
    ///   - scene: The scene to render.
    ///   - options: Render options.
    /// - Returns: Framebuffer, final drawing state, recorded interactive
    ///   commands and whether rendering stopped early.
    public static func renderResult(_ scene: RIPScene, options: RIPRenderOptions = .default) -> RIPRenderResult {
        let interpreter = RIPInterpreter(canvas: RIPCanvas(), pixelBudget: options.pixelBudget)
        interpreter.run(scene)
        return RIPRenderResult(framebuffer: interpreter.canvas.framebuffer, state: interpreter.state,
                               interactive: interpreter.interactive, isTruncated: interpreter.isTruncated)
    }

    #if canImport(CoreGraphics)
    /// Render a scene to an image.
    ///
    /// - Parameters:
    ///   - scene: The scene to render.
    ///   - options: Output size, smoothing and work budget.
    /// - Returns: A 640x350 image, or `options.targetSize` when set; `nil` if
    ///   the image could not be created.
    public static func render(_ scene: RIPScene, options: RIPRenderOptions = .default) -> CGImage? {
        renderResult(scene, options: options).image(options: options)
    }

    /// Render a scene progressively as an `AsyncSequence` of images.
    ///
    /// - Parameters:
    ///   - scene: The scene to play back.
    ///   - options: Must use ``RIPRenderOptions/AnimationMode/animated(framesPerCommand:)``.
    /// - Returns: The frame sequence.
    /// - Throws: ``RIPAnimationError/notAnimated`` for `.static` options and
    ///   ``RIPAnimationError/invalidFramesPerCommand(_:)`` for a batch size
    ///   below 1.
    public static func renderFrames(_ scene: RIPScene, options: RIPRenderOptions) throws -> RIPAnimationFrames {
        try RIPAnimationFrames.make(scene: scene, options: options)
    }
    #endif
}

/// The outcome of executing a scene: see ``SwiftRIP/renderResult(_:options:)``.
public struct RIPRenderResult: Equatable, Sendable {
    /// The native 640x350 palette-indexed framebuffer.
    public let framebuffer: RIPFramebuffer
    /// Drawing state after the last executed command.
    public let state: RIPGraphicsState
    /// Mouse regions and non-graphical commands recorded while rendering.
    public let interactive: RIPSceneInteractive
    /// `true` if rendering stopped early because the pixel budget ran out.
    public let isTruncated: Bool

    #if canImport(CoreGraphics)
    /// Compose the framebuffer into an image using `options.targetSize` and
    /// `options.antiAliasing`.
    ///
    /// - Parameter options: Composition options (default: native size).
    /// - Returns: The image, or `nil` if it could not be created.
    public func image(options: RIPRenderOptions = .default) -> CGImage? {
        RIPCompositor.compose(framebuffer, options: options)
    }
    #endif
}
