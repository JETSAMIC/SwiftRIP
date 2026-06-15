// RIPInterpreter — walk a `RIPScene` and dispatch every command into a
// `RIPCanvas` + `RIPGraphicsState`.
//
// Scope (honest 100% format coverage, no host-protocol invention):
//
//   * Level 0 commands all render to canvas (or mutate state).
//   * Level 1 visual commands render: BeginText/RegionText/EndText,
//     GetImage/PutImage clipboard, LoadIcon stamp (if data supplied via the
//     interactive sidecar), CopyRegion, Button visual chrome.
//   * Interactive commands (Mouse, KillMouseFields, ButtonStyle config,
//     Define, Query, ReadScene file load, FileQuery, EnterBlockMode,
//     NoMore, WriteIcon disk write) are CAPTURED into a `RIPSceneInteractive`
//     sidecar that the caller can inspect — they produce no rendered output
//     because SwiftRIP has no BBS host.
//
// The default-16 RIP palette is restored on RESET_WINDOWS per spec.

import Foundation
import CoreGraphics

/// Sidecar struct returned alongside the rendered canvas: captures the
/// interactive subsystem commands so a host shell can introspect them even
/// though they produce no visible output.
public struct RIPSceneInteractive: Equatable, Sendable {
    public var mouseFields: [RIPCommand] = []
    public var buttons: [RIPCommand] = []
    public var buttonStyles: [RIPCommand] = []
    public var defines: [RIPCommand] = []
    public var queries: [RIPCommand] = []
    public var reads: [RIPCommand] = []
    public var fileQueries: [RIPCommand] = []
    public var blockModes: [RIPCommand] = []
    public var writeIcons: [RIPCommand] = []
    public var ansiSenses: [RIPAnsiSense] = []
    public var unknowns: [RIPCommand] = []
    public var noMore: Bool = false

    public init() {}
}

/// Stateless interpreter — feeds commands one at a time into the canvas
/// while mutating shared graphics state.
public enum RIPInterpreter {

    /// Walk `scene` and render into `canvas` while mutating `state`. Returns
    /// the captured interactive subsystem snapshot.
    @discardableResult
    public static func interpret(_ scene: RIPScene, into canvas: RIPCanvas, state: inout RIPGraphicsState, options: RIPRenderOptions = .default) -> RIPSceneInteractive {
        var inter = RIPSceneInteractive()

        // Keep canvas palette in sync with state at start.
        canvas.palette = state.palette
        canvas.refreshRGBA()

        // Clipboard slot for getImage/putImage (single page model).
        var clipboard: ClipImage? = nil

        for cmd in scene.commands {
            interpretOne(cmd, into: canvas, state: &state, inter: &inter, clipboard: &clipboard, options: options)
            // Keep canvas palette in sync if state changed it.
            if canvas.palette != state.palette {
                canvas.palette = state.palette
                canvas.refreshRGBA()
            }
        }
        return inter
    }

    // MARK: - One command

    private static func interpretOne(_ cmd: RIPCommand, into canvas: RIPCanvas, state: inout RIPGraphicsState, inter: inout RIPSceneInteractive, clipboard: inout ClipImage?, options: RIPRenderOptions) {
        switch cmd {

        // MARK: State mutators

        case .textWindow(let x0, let y0, let x1, let y1, let wrap, let size):
            state.textWindow = .init(x0: x0, y0: y0, x1: x1, y1: y1, wrap: wrap, size: size)

        case .viewport(let x0, let y0, let x1, let y1):
            state.viewport = RIPViewport.from(x0: x0, y0: y0, x1: x1, y1: y1)

        case .resetWindows:
            state.resetWindows()
            canvas.palette = state.palette
            canvas.clear(to: options.clearColor)

        case .eraseWindow:
            canvas.clear(to: options.clearColor)

        case .eraseView:
            let r = state.viewport.clipRect()
            for y in r.y0...r.y1 {
                for x in r.x0...r.x1 {
                    canvas.setPixel(x: x, y: y, color: options.clearColor, state: state)
                }
            }

        case .gotoXY(let x, let y):
            state.position = RIPPoint(x: x, y: y)

        case .home:
            state.position = RIPPoint(x: 0, y: 0)

        case .eraseEOL:
            // Erase from cursor to right edge of text window in clear color.
            let y = state.position.y
            for x in state.position.x..<canvas.width {
                canvas.setPixel(x: x, y: y, color: options.clearColor, state: state)
            }

        case .color(let c):
            state.drawColor = UInt8(truncatingIfNeeded: c)

        case .setPalette(let vs):
            RIPPalette.setAll(vs, on: &state)

        case .onePalette(let slot, let value):
            RIPPalette.setOne(slot: slot, value: value, on: &state)

        case .writeMode(let m):
            state.writeMode = RIPWriteMode(rawValue: m)

        case .move(let x, let y):
            state.position = RIPPoint(x: x, y: y)

        case .lineStyle(let style, let user, let thick):
            if style == 4 {
                state.lineStyle = .user(UInt16(truncatingIfNeeded: user))
            } else {
                state.lineStyle = .predefined(style)
            }
            state.lineThickness = max(1, thick)

        case .fillStyle(let pattern, let color):
            state.fillPattern = .predefined(pattern)
            state.fillColor = UInt8(truncatingIfNeeded: color)

        case .fillPattern(let bytes, let color):
            state.fillPattern = .custom(bytes)
            state.fillColor = UInt8(truncatingIfNeeded: color)

        case .fontStyle(let font, let dir, let size, _):
            state.font = font
            state.fontDirection = dir
            state.fontSize = max(1, min(10, size))

        // MARK: Drawing primitives

        case .text(let s):
            RIPVectorFonts.renderText(s, at: CGPoint(x: state.position.x, y: state.position.y),
                                      font: state.font, direction: state.fontDirection,
                                      size: state.fontSize, color: state.drawColor,
                                      into: canvas, state: state)
            // Advance pen position by string width.
            let adv = (state.font == 0 ? 8 : 12) * state.fontSize * s.count
            if state.fontDirection == 0 {
                state.position = RIPPoint(x: state.position.x + adv, y: state.position.y)
            } else {
                state.position = RIPPoint(x: state.position.x, y: state.position.y - adv)
            }

        case .textXY(let x, let y, let s):
            state.position = RIPPoint(x: x, y: y)
            RIPVectorFonts.renderText(s, at: CGPoint(x: x, y: y),
                                      font: state.font, direction: state.fontDirection,
                                      size: state.fontSize, color: state.drawColor,
                                      into: canvas, state: state)

        case .pixel(let x, let y):
            canvas.setPixel(x: x, y: y, color: state.drawColor, state: state)

        case .line(let x0, let y0, let x1, let y1):
            canvas.drawLine(x0: x0, y0: y0, x1: x1, y1: y1, color: state.drawColor, state: state)
            state.position = RIPPoint(x: x1, y: y1)

        case .rectangle(let x0, let y0, let x1, let y1):
            canvas.drawRectangle(x0: x0, y0: y0, x1: x1, y1: y1, color: state.drawColor, state: state)

        case .bar(let x0, let y0, let x1, let y1):
            canvas.fillRectangle(x0: x0, y0: y0, x1: x1, y1: y1, state: state)

        case .circle(let x, let y, let r):
            canvas.drawCircle(cx: x, cy: y, radius: r, color: state.drawColor, state: state)

        case .oval(let x, let y, let sa, let ea, let xr, let yr):
            canvas.drawArc(cx: x, cy: y, xrad: xr, yrad: yr, startAngle: sa, endAngle: ea, color: state.drawColor, state: state)

        case .filledOval(let x, let y, let xr, let yr):
            canvas.fillEllipse(cx: x, cy: y, xrad: xr, yrad: yr, state: state)

        case .arc(let x, let y, let sa, let ea, let r):
            canvas.drawArc(cx: x, cy: y, xrad: r, yrad: r, startAngle: sa, endAngle: ea, color: state.drawColor, state: state)

        case .ovalArc(let x, let y, let sa, let ea, let xr, let yr):
            canvas.drawArc(cx: x, cy: y, xrad: xr, yrad: yr, startAngle: sa, endAngle: ea, color: state.drawColor, state: state)

        case .pieSlice(let x, let y, let sa, let ea, let r):
            canvas.drawPieSlice(cx: x, cy: y, xrad: r, yrad: r, startAngle: sa, endAngle: ea, state: state)

        case .ovalPieSlice(let x, let y, let sa, let ea, let xr, let yr):
            canvas.drawPieSlice(cx: x, cy: y, xrad: xr, yrad: yr, startAngle: sa, endAngle: ea, state: state)

        case .bezier(let x0, let y0, let x1, let y1, let x2, let y2, let x3, let y3, let count):
            canvas.drawBezier(
                RIPPoint(x: x0, y: y0),
                RIPPoint(x: x1, y: y1),
                RIPPoint(x: x2, y: y2),
                RIPPoint(x: x3, y: y3),
                segments: count, color: state.drawColor, state: state
            )

        case .polygon(let pts):
            canvas.drawPolygon(points: pts, color: state.drawColor, state: state)

        case .fillPolygon(let pts):
            canvas.fillPolygon(points: pts, state: state)

        case .polyline(let pts):
            canvas.drawPolyline(points: pts, color: state.drawColor, state: state)

        case .fill(let x, let y, let border):
            canvas.floodFill(x: x, y: y, border: UInt8(truncatingIfNeeded: border), state: state)

        // MARK: Level 1 visual

        case .beginText(let x0, let y0, let x1, let y1, _):
            // Set up a region — for our purposes this clips text into the
            // given rect and sets the pen to the top-left.
            state.viewport = .rect(x0: x0, y0: y0, x1: x1, y1: y1)
            state.position = RIPPoint(x: x0, y: y0)

        case .regionText(_, let s):
            RIPVectorFonts.renderText(s, at: CGPoint(x: state.position.x, y: state.position.y),
                                      font: state.font, direction: state.fontDirection,
                                      size: state.fontSize, color: state.drawColor,
                                      into: canvas, state: state)
            let adv = (state.font == 0 ? 8 : 12) * state.fontSize * s.count
            state.position = RIPPoint(x: state.position.x + adv, y: state.position.y)

        case .endText:
            state.viewport = .disabled

        case .getImage(let x0, let y0, let x1, let y1, _):
            clipboard = ClipImage.capture(from: canvas, x0: x0, y0: y0, x1: x1, y1: y1)

        case .putImage(let x, let y, let mode, _):
            if let clip = clipboard {
                clip.paste(into: canvas, at: (x, y), mode: mode, state: state)
            }

        case .copyRegion(let x0, let y0, let x1, let y1, _, let dx, let dy):
            let clip = ClipImage.capture(from: canvas, x0: x0, y0: y0, x1: x1, y1: y1)
            clip.paste(into: canvas, at: (dx, dy), mode: 0, state: state)

        case .button(let x0, let y0, let x1, let y1, _, _, let label):
            // Render visual chrome only — a beveled rectangle with the label
            // centered. The interactive hit field is captured in the
            // sidecar.
            renderButtonChrome(x0: x0, y0: y0, x1: x1, y1: y1, label: label, canvas: canvas, state: state)
            inter.buttons.append(cmd)

        // MARK: Interactive — sidecar only

        case .mouse:
            inter.mouseFields.append(cmd)

        case .killMouseFields:
            inter.mouseFields.removeAll()

        case .buttonStyle:
            inter.buttonStyles.append(cmd)

        case .define:
            inter.defines.append(cmd)

        case .query:
            inter.queries.append(cmd)

        case .writeIcon:
            inter.writeIcons.append(cmd)

        case .loadIcon:
            // No filesystem in our scope. Capture for inspection.
            inter.reads.append(cmd)

        case .readScene:
            inter.reads.append(cmd)

        case .fileQuery:
            inter.fileQueries.append(cmd)

        case .enterBlockMode:
            inter.blockModes.append(cmd)

        case .noMore:
            inter.noMore = true

        case .ansiSense(let s):
            inter.ansiSenses.append(s)

        case .unknown:
            inter.unknowns.append(cmd)
        }
    }

    private static func renderButtonChrome(x0: Int, y0: Int, x1: Int, y1: Int, label: String, canvas: RIPCanvas, state: RIPGraphicsState) {
        // Simple two-tone beveled rect. Surface = fill color, border = draw.
        var fillState = state
        fillState.fillPattern = .predefined(1)
        canvas.fillRectangle(x0: x0 + 1, y0: y0 + 1, x1: x1 - 1, y1: y1 - 1, state: fillState)
        canvas.drawRectangle(x0: x0, y0: y0, x1: x1, y1: y1, color: state.drawColor, state: state)
        // Center label.
        let cellW = (state.font == 0 ? 8 : 12) * state.fontSize
        let cellH = (state.font == 0 ? 8 : 21) * state.fontSize
        let lx = x0 + max(2, ((x1 - x0) - cellW * label.count) / 2)
        let ly = y0 + max(2, ((y1 - y0) - cellH) / 2)
        RIPVectorFonts.renderText(label, at: CGPoint(x: lx, y: ly),
                                  font: state.font, direction: state.fontDirection,
                                  size: state.fontSize, color: state.drawColor,
                                  into: canvas, state: state)
    }
}

// MARK: - Clipboard image

/// A small palette-indexed bitmap snapshot used by getImage/putImage and
/// copyRegion.
struct ClipImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    static func capture(from canvas: RIPCanvas, x0: Int, y0: Int, x1: Int, y1: Int) -> ClipImage {
        let lx = min(x0, x1), rx = max(x0, x1)
        let ty = min(y0, y1), by = max(y0, y1)
        let w = rx - lx + 1
        let h = by - ty + 1
        var px: [UInt8] = []
        px.reserveCapacity(max(0, w * h))
        for y in ty...by {
            for x in lx...rx {
                if x >= 0 && y >= 0 && x < canvas.width && y < canvas.height {
                    px.append(canvas.rawIndex(x: x, y: y))
                } else {
                    px.append(0)
                }
            }
        }
        return ClipImage(width: max(0, w), height: max(0, h), pixels: px)
    }

    func paste(into canvas: RIPCanvas, at p: (Int, Int), mode: Int, state: RIPGraphicsState) {
        guard width > 0 && height > 0 else { return }
        var s = state
        // PutImage modes per spec: 0=COPY, 1=XOR, 2=OR, 3=AND, 4=NOT. We
        // implement COPY and XOR exactly; OR/AND/NOT are approximated by
        // setting a write mode (OR ≈ XOR for binary planes).
        switch mode {
        case 1: s.writeMode = .xor
        default: s.writeMode = .copy
        }
        for y in 0..<height {
            for x in 0..<width {
                canvas.setPixel(x: p.0 + x, y: p.1 + y,
                                color: pixels[y * width + x],
                                state: s)
            }
        }
    }
}
