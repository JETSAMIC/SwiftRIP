// SwiftRIP — pure-Swift reader and renderer for TeleGrafix RIPscrip 1.54
// (Remote Imaging Protocol Script) vector graphics scenes.
//
// Public surface:
//
//   * `SwiftRIP.decode(_:)`  — bytes → `RIPScene`
//   * `SwiftRIP.render(_:)`  — scene → 640x350 `CGImage` snapshot
//   * `SwiftRIP.renderToCanvas(_:options:)` — scene → `(CGImage,
//     RIPSceneInteractive, RIPCanvas, RIPGraphicsState)` for callers that
//     want to introspect or composite.
//
// Interactive subsystems (Mouse Fields, Buttons, Queries, Templates, Pop-Up
// Pick Lists, Host Commands, Block Mode, Read Scene, File Query) are PARSED
// and captured into `RIPSceneInteractive` but produce no rendered output —
// SwiftRIP has no BBS host. See README.

import Foundation
import CoreGraphics

/// SwiftRIP's public façade. Pure functions that parse and render RIPscrip
/// scenes.
public enum SwiftRIP {

    /// Decode raw RIPscrip bytes into a typed `RIPScene`. The bytes are
    /// expected to be the contents of a `.rip` file or a captured BBS
    /// session frame.
    public static func decode(_ data: Data) throws -> RIPScene {
        try RIPParser.parse(data)
    }

    /// Decode a RIPscrip string (UTF-8 / ASCII text form).
    public static func decode(_ text: String) throws -> RIPScene {
        try RIPParser.parse(text)
    }

    /// Encode a `RIPScene` back into RIPscrip 1.54 text form. Round-trips
    /// against `decode` for all spec-defined commands; `.unknown` and
    /// `.ansiSense` cases are not part of the file format and are skipped.
    public static func encode(_ scene: RIPScene) -> String {
        RIPWriter.encode(scene)
    }

    /// Render a `RIPScene` to its native 640x350 `CGImage`. Returns `nil`
    /// if the underlying `CGImage` cannot be constructed (e.g. on a
    /// platform without CoreGraphics, which our package targets exclude).
    public static func render(_ scene: RIPScene, options: RIPRenderOptions = .default) -> CGImage? {
        let (image, _, _, _) = renderToCanvas(scene, options: options)
        return image
    }

    /// Render a `RIPScene` and return the canvas + final graphics state +
    /// interactive sidecar alongside the snapshot.
    public static func renderToCanvas(_ scene: RIPScene, options: RIPRenderOptions = .default) -> (CGImage?, RIPSceneInteractive, RIPCanvas, RIPGraphicsState) {
        let canvas = RIPCanvas()
        var state = RIPGraphicsState()
        canvas.palette = state.palette
        canvas.clear(to: options.clearColor)
        let inter = RIPInterpreter.interpret(scene, into: canvas, state: &state, options: options)
        return (canvas.cgImage(), inter, canvas, state)
    }
}
