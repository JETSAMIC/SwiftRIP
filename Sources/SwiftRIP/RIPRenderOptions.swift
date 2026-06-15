// RIPRenderOptions — public knobs for the modernizations pass.
//
// SwiftRIP renders a `RIPScene` into a native 640x350 EGA framebuffer; the
// values declared here drive an OPTIONAL composition pass that scales the
// native canvas to a target display size, applies an optional anti-aliasing
// pass, and selects between a single-shot "static" render and a stepwise
// "animated" playback that surfaces the in-progress canvas after every N
// commands (the 1996-era sequential-draw feel).
//
// Defaults are intentionally conservative: STATIC mode + native 640x350
// (targetSize = nil) + anti-aliasing ON. Callers that want pixel-perfect
// chunky EGA flip `antiAliasing` to `false`; callers that want incremental
// playback flip `animation` to `.animated(framesPerCommand:)`.

import Foundation
import CoreGraphics

/// Public render options for SwiftRIP. Controls scale, anti-aliasing, and
/// static-vs-animated playback. All fields are independent — animation mode
/// composes the same nearest-neighbour + AA pipeline as the static path.
public struct RIPRenderOptions: Sendable {

    /// Static vs animated playback selector.
    public enum AnimationMode: Sendable, Equatable {
        /// Single final snapshot — every command applied instantly.
        case `static`
        /// Stepwise playback — surface a snapshot every `framesPerCommand`
        /// commands. `framesPerCommand=1` yields one frame per command;
        /// higher values batch commands for a coarser cadence.
        case animated(framesPerCommand: Int)

        public static var animated: AnimationMode { .animated(framesPerCommand: 1) }
    }

    /// Static (default) vs animated playback.
    public var animation: AnimationMode = .static

    /// Output size for the composition pass. `nil` = native 640x350 (no
    /// scaling, no AA pass). Non-nil triggers the nearest-neighbour scale
    /// followed by the optional AA pass.
    public var targetSize: CGSize? = nil

    /// Optional anti-aliasing pass applied AFTER nearest-neighbour scale.
    /// `true` (default) gives smoothed edges on modern displays; `false`
    /// preserves the chunky-EGA original. Has no effect when `targetSize`
    /// is `nil` (the native render is always nearest-neighbour).
    public var antiAliasing: Bool = true

    /// Tick multiplier for `.animated` playback. The compositor itself
    /// produces frames synchronously; this value is exposed so callers
    /// driving the sequence with `Task.sleep` or a `Timer` can pace
    /// emission (1.0 = native cadence, 2.0 = twice as fast, 0.5 = half).
    public var animationSpeed: Double = 1.0

    // MARK: - Existing knobs (preserved for the interpreter)

    /// Background palette index used by `eraseWindow` / `resetWindows`.
    public var clearColor: UInt8 = 0

    public init() {}
}

public extension RIPRenderOptions {
    /// Conservative defaults: static + native 640x350 + AA on.
    static let `default` = RIPRenderOptions()
}
