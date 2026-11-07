// RIPRenderOptions — knobs for rendering a scene to an image.
//
// The renderer always draws into the native 640x350 EGA framebuffer. The
// options control an optional composition pass (nearest-neighbour scaling
// to a target size, then optional smoothing), static versus incremental
// playback, and the work budget that bounds rendering time for untrusted
// input.

import Foundation

/// Options for ``SwiftRIP/render(_:options:)``, ``SwiftRIP/renderResult(_:options:)``
/// and ``SwiftRIP/renderFrames(_:options:)``.
public struct RIPRenderOptions: Equatable, Sendable {

    /// Static versus incremental playback.
    public enum AnimationMode: Equatable, Sendable {
        /// One final image with every command applied.
        case `static`
        /// Emit an image after every `framesPerCommand` commands (must be > 0).
        case animated(framesPerCommand: Int)

        /// One frame per command.
        public static var animated: AnimationMode { .animated(framesPerCommand: 1) }
    }

    /// Playback mode used by ``SwiftRIP/renderFrames(_:options:)``. Default
    /// `.static`.
    public var animation: AnimationMode = .static

    /// Output size of the composition pass in pixels, or `nil` (default) for
    /// the native 640x350 image. Non-nil sizes are produced by
    /// nearest-neighbour scaling (each source pixel maps to whole output
    /// pixels), optionally followed by smoothing. Each dimension is clamped
    /// to 1...16384.
    public var targetSize: CGSize?

    /// Smooth the scaled image (downscale to half size and back with high
    /// quality interpolation). Only applies when ``targetSize`` is set.
    /// Default `true`.
    public var antiAliasing: Bool = true

    /// Maximum amount of rendering work — pixel writes plus rasterizer steps
    /// that land off screen (clipped line steps, polygon edges per scan line,
    /// arc points) — before the renderer stops executing further commands,
    /// or `nil` for no limit.
    ///
    /// Every command's work is bounded by the screen area, but a hostile
    /// script can repeat expensive commands (full-screen flood fills, screen
    /// clears) thousands of times. When the budget is exhausted the
    /// remaining commands are skipped and ``RIPRenderResult/isTruncated`` is
    /// `true`. The default, ``defaultPixelBudget``, is far above what real
    /// scenes need (about 900 full-screen fills).
    public var pixelBudget: Int? = RIPRenderOptions.defaultPixelBudget

    /// Default ``pixelBudget``: 200 million work units.
    public static let defaultPixelBudget = 200_000_000

    /// Default options: static, native size, anti-aliasing on (no effect at
    /// native size), default pixel budget.
    public init() {}

    /// Default options.
    public static let `default` = RIPRenderOptions()
}
