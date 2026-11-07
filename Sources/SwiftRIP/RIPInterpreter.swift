// RIPInterpreter — execute RIPscrip commands against a `RIPCanvas` and a
// `RIPGraphicsState`.
//
// What is rendered (RIPscrip 1.54 semantics):
//
//   * Every Level 0 drawing command, honouring the viewport (relative
//     coordinates + clipping; ignored while the viewport is disabled), the
//     write mode where the spec says the command uses it (lines, rectangles,
//     polygon outlines, poly-lines, Beziers, text), line patterns where the
//     spec says they apply and line thickness 1/3.
//   * Erase window / erase view / erase EOL / reset windows as pixel clears.
//   * Level 1 text regions, GET_IMAGE / PUT_IMAGE clipboard, COPY_REGION and
//     buttons (plain and clipboard buttons with their special effects).
//
// What is recorded but not executed (no host, no file system): mouse
// fields and mouse buttons (as hit regions), LOAD_ICON, WRITE_ICON,
// DEFINE, QUERY, READ_SCENE, FILE_QUERY, ENTER_BLOCK_MODE, NO_MORE, ANSI
// auto-sense and unknown commands. See `RIPSceneInteractive`.

import Foundation

/// A clickable region created by `1M` RIP_MOUSE or by a `1U` mouse button.
public struct RIPMouseRegion: Equatable, Sendable {
    /// Where the region came from.
    public enum Kind: Equatable, Sendable {
        /// `1M` RIP_MOUSE.
        case mouseField
        /// `1U` RIP_BUTTON with the mouse-button style flag.
        case button
    }

    /// Region source.
    public let kind: Kind
    /// Left edge, absolute screen pixels (inclusive).
    public let x0: Int
    /// Top edge, absolute screen pixels (inclusive).
    public let y0: Int
    /// Right edge, absolute screen pixels (inclusive).
    public let x1: Int
    /// Bottom edge, absolute screen pixels (inclusive).
    public let y1: Int
    /// Host command to send on click (raw, including `^M`-style notation).
    public let hostCommand: String
    /// Invert the region while it is pressed.
    public let invertsWhenClicked: Bool
    /// Mouse field: zoom/clear the text window; button: reset the screen.
    public let resetsOnClick: Bool
    /// Button hot key (ASCII code, 255 = any key); `nil` for mouse fields.
    public let hotkey: Int?
}

/// Commands that a terminal would act on but a renderer cannot, collected
/// while rendering a scene.
public struct RIPSceneInteractive: Equatable, Sendable {
    /// Active mouse regions in creation order (the most recent one is
    /// scanned first on a click). At most 128 regions are kept, as the spec
    /// limits; later ones are dropped. Cleared by RIP_RESET_WINDOWS and
    /// RIP_KILL_MOUSE_FIELDS.
    public internal(set) var mouseRegions: [RIPMouseRegion] = []
    /// `1D` RIP_DEFINE commands.
    public internal(set) var defines: [RIPCommand] = []
    /// `1<ESC>` RIP_QUERY commands.
    public internal(set) var queries: [RIPCommand] = []
    /// `1R` RIP_READ_SCENE commands.
    public internal(set) var reads: [RIPCommand] = []
    /// `1F` RIP_FILE_QUERY commands.
    public internal(set) var fileQueries: [RIPCommand] = []
    /// `9<ESC>` RIP_ENTER_BLOCK_MODE commands.
    public internal(set) var blockModes: [RIPCommand] = []
    /// `1W` RIP_WRITE_ICON commands.
    public internal(set) var writeIcons: [RIPCommand] = []
    /// `1I` RIP_LOAD_ICON commands (icons are not loaded or drawn).
    public internal(set) var loadIcons: [RIPCommand] = []
    /// ANSI auto-sense sequences, in order.
    public internal(set) var ansiSenses: [RIPAnsiSense] = []
    /// Commands not defined by RIPscrip 1.54.
    public internal(set) var unknowns: [RIPCommand] = []
    /// `true` once `#` RIP_NO_MORE has been seen.
    public internal(set) var noMore: Bool = false

    /// An empty record.
    public init() {}
}

/// Executes commands one at a time; shared by static and animated rendering.
final class RIPInterpreter {

    /// Coordinates and sizes are clamped to this magnitude before any
    /// arithmetic so values from the public API cannot overflow.
    static let coordinateLimit = 8192

    let canvas: RIPCanvas
    private(set) var state: RIPGraphicsState
    private(set) var interactive = RIPSceneInteractive()
    var clipboard: ClipImage?
    let pixelBudget: Int?
    private(set) var isTruncated = false

    init(canvas: RIPCanvas, state: RIPGraphicsState = RIPGraphicsState(), pixelBudget: Int? = nil) {
        self.canvas = canvas
        self.state = state
        self.pixelBudget = pixelBudget
        canvas.palette = state.palette
    }

    /// Execute one command. Returns `false` (and executes nothing) once the
    /// pixel budget is exhausted.
    @discardableResult
    func step(_ command: RIPCommand) -> Bool {
        if let budget = pixelBudget, canvas.pixelWrites >= budget {
            isTruncated = true
            return false
        }
        execute(command)
        canvas.palette = state.palette
        return true
    }

    /// Execute every command of `scene`, stopping early if the budget runs out.
    func run(_ scene: RIPScene) {
        for command in scene.commands where !step(command) {
            break
        }
    }

    // MARK: - Helpers

    @inline(__always)
    static func clamp(_ v: Int) -> Int {
        Swift.min(Swift.max(v, -coordinateLimit), coordinateLimit)
    }

    @inline(__always)
    static func clampSize(_ v: Int) -> Int {
        Swift.min(Swift.max(v, 0), coordinateLimit)
    }

    /// Viewport rectangle, or `nil` while the viewport is disabled.
    var viewportClip: ClipRect? {
        switch state.viewport {
        case .disabled:
            return nil
        case let .rect(x0, y0, x1, y1):
            return ClipRect(x0: x0, y0: y0, x1: x1, y1: y1).intersection(canvas.screen)
        }
    }

    /// Convert viewport-relative coordinates to absolute pixels.
    @inline(__always)
    func absolute(_ x: Int, _ y: Int, in clip: ClipRect) -> (Int, Int) {
        (Self.clamp(clip.x0 + Self.clamp(x)), Self.clamp(clip.y0 + Self.clamp(y)))
    }

    static func color(_ v: Int) -> UInt8 { UInt8(truncatingIfNeeded: v & 0x0F) }

    var linePen: Pen {
        Pen(color: state.drawColor, mode: state.writeMode, mask: state.lineStyle.mask,
            thickness: state.lineThickness)
    }

    /// Solid pen in copy mode with the current thickness (circles, arcs, pie
    /// slice outlines: "uses line thickness, not line patterns").
    var outlinePen: Pen {
        Pen(color: state.drawColor, mode: .copy, mask: 0xFFFF, thickness: state.lineThickness)
    }

    var fillSpec: FillSpec { FillSpec(rows: state.fillPattern.rows, color: state.fillColor) }

    /// EGA 640x350 on a 4:3 display: a pixel is 350/480 as tall as it is wide.
    static func aspectRadius(_ r: Int) -> Int { (r * 350 + 240) / 480 }

    // MARK: - Dispatch

    private func execute(_ command: RIPCommand) {
        switch command {

        // MARK: Windows and cursors
        case let .textWindow(x0, y0, x1, y1, wrap, size):
            let w = RIPTextWindow(x0: Self.clampSize(x0), y0: Self.clampSize(y0),
                                  x1: Self.clampSize(x1), y1: Self.clampSize(y1),
                                  wrap: wrap, size: (0...4).contains(size) ? size : 0)
            let old = state.textWindow
            let identical = old.x0 == w.x0 && old.y0 == w.y0 && old.x1 == w.x1 && old.y1 == w.y1 && old.size == w.size
            state.textWindow = w
            if !identical { state.textCursor = RIPPoint(x: 0, y: 0) }

        case let .viewport(x0, y0, x1, y1):
            state.viewport = RIPViewport.from(x0: x0, y0: y0, x1: x1, y1: y1)

        case .resetWindows:
            canvas.clear(to: 0)
            state.textWindow = .fullScreen
            state.textCursor = RIPPoint(x: 0, y: 0)
            state.viewport = .fullScreen
            state.palette = RIPPalette.default16
            state.textRegion = nil
            clipboard = nil
            interactive.mouseRegions.removeAll()

        case .eraseWindow:
            guard let r = textWindowRect() else { return }
            canvas.fillRect(x0: r.x0, y0: r.y0, x1: r.x1, y1: r.y1, fill: Self.background, clip: canvas.screen)
            state.textCursor = RIPPoint(x: 0, y: 0)

        case .eraseView:
            guard let clip = viewportClip else { return }
            canvas.fillRect(x0: clip.x0, y0: clip.y0, x1: clip.x1, y1: clip.y1, fill: Self.background, clip: clip)

        case let .gotoXY(x, y):
            guard state.textWindow.isActive else { return }
            let w = state.textWindow
            state.textCursor = RIPPoint(x: Swift.min(Self.clampSize(x), Swift.max(0, w.x1 - w.x0)),
                                        y: Swift.min(Self.clampSize(y), Swift.max(0, w.y1 - w.y0)))

        case .home:
            state.textCursor = RIPPoint(x: 0, y: 0)

        case .eraseEOL:
            guard let r = textWindowRect() else { return }
            let cell = state.textWindow.cellSize
            let top = r.y0 + state.textCursor.y * cell.height
            canvas.fillRect(x0: r.x0 + state.textCursor.x * cell.width, y0: top,
                            x1: r.x1, y1: top + cell.height - 1, fill: Self.background,
                            clip: r)

        // MARK: Colors and styles
        case let .color(c):
            state.drawColor = Self.color(c)

        case let .setPalette(values):
            for (slot, value) in values.prefix(16).enumerated() {
                state.palette[slot] = UInt8(truncatingIfNeeded: value & 0x3F)
            }

        case let .onePalette(slot, value):
            guard (0..<16).contains(slot) else { return }
            state.palette[slot] = UInt8(truncatingIfNeeded: value & 0x3F)

        case let .writeMode(m):
            state.writeMode = RIPWriteMode(rawValue: m)

        case let .lineStyle(style, user, thick):
            switch style {
            case 0...3: state.lineStyle = .predefined(style)
            case 4: state.lineStyle = .user(UInt16(truncatingIfNeeded: user))
            default: state.lineStyle = .predefined(0)
            }
            state.lineThickness = thick >= 3 ? 3 : 1

        case let .fillStyle(pattern, color):
            state.fillPattern = .predefined((0...11).contains(pattern) ? pattern : 1)
            state.fillColor = Self.color(color)

        case let .fillPattern(bytes, color):
            state.fillPattern = .custom(RIPFillPattern.custom(bytes).rows)
            state.fillColor = Self.color(color)

        case let .fontStyle(font, direction, size, _):
            state.font = (0...10).contains(font) ? font : 0
            state.fontDirection = direction == 1 ? 1 : 0
            state.fontSize = Swift.max(1, Swift.min(10, size))

        // MARK: Drawing
        case let .move(x, y):
            guard viewportClip != nil else { return }
            state.position = RIPPoint(x: Self.clamp(x), y: Self.clamp(y))

        case let .text(s):
            guard let clip = viewportClip else { return }
            drawText(s, at: state.position, clip: clip)

        case let .textXY(x, y, s):
            guard let clip = viewportClip else { return }
            drawText(s, at: RIPPoint(x: Self.clamp(x), y: Self.clamp(y)), clip: clip)

        case let .pixel(x, y):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x, y, in: clip)
            canvas.plot(ax, ay, state.drawColor, .copy, clip)

        case let .line(x0, y0, x1, y1):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x0, y0, in: clip)
            let (bx, by) = absolute(x1, y1, in: clip)
            canvas.line(ax, ay, bx, by, pen: linePen, clip: clip)

        case let .rectangle(x0, y0, x1, y1):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x0, y0, in: clip)
            let (bx, by) = absolute(x1, y1, in: clip)
            drawRectangle(ax, ay, bx, by, pen: linePen, clip: clip)

        case let .bar(x0, y0, x1, y1):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x0, y0, in: clip)
            let (bx, by) = absolute(x1, y1, in: clip)
            canvas.fillRect(x0: ax, y0: ay, x1: bx, y1: by, fill: fillSpec, clip: clip)

        case let .circle(x, y, r):
            guard let clip = viewportClip else { return }
            let (cx, cy) = absolute(x, y, in: clip)
            let rx = Self.clampSize(r)
            canvas.ellipse(cx: cx, cy: cy, rx: rx, ry: Self.aspectRadius(rx), color: state.drawColor,
                           thickness: state.lineThickness, clip: clip)

        case let .oval(x, y, sa, ea, xr, yr), let .ovalArc(x, y, sa, ea, xr, yr):
            guard let clip = viewportClip else { return }
            let (cx, cy) = absolute(x, y, in: clip)
            drawArc(cx: cx, cy: cy, rx: Self.clampSize(xr), ry: Self.clampSize(yr), start: sa, end: ea, clip: clip)

        case let .arc(x, y, sa, ea, r):
            guard let clip = viewportClip else { return }
            let (cx, cy) = absolute(x, y, in: clip)
            let rx = Self.clampSize(r)
            drawArc(cx: cx, cy: cy, rx: rx, ry: Self.aspectRadius(rx), start: sa, end: ea, clip: clip)

        case let .filledOval(x, y, xr, yr):
            guard let clip = viewportClip else { return }
            let (cx, cy) = absolute(x, y, in: clip)
            let rx = Self.clampSize(xr), ry = Self.clampSize(yr)
            canvas.fillEllipse(cx: cx, cy: cy, rx: rx, ry: ry, fill: fillSpec, clip: clip)
            canvas.ellipse(cx: cx, cy: cy, rx: rx, ry: ry, color: state.drawColor,
                           thickness: state.lineThickness, clip: clip)

        case let .pieSlice(x, y, sa, ea, r):
            guard let clip = viewportClip else { return }
            let (cx, cy) = absolute(x, y, in: clip)
            let rx = Self.clampSize(r)
            drawPieSlice(cx: cx, cy: cy, rx: rx, ry: Self.aspectRadius(rx), start: sa, end: ea, clip: clip)

        case let .ovalPieSlice(x, y, sa, ea, xr, yr):
            guard let clip = viewportClip else { return }
            let (cx, cy) = absolute(x, y, in: clip)
            drawPieSlice(cx: cx, cy: cy, rx: Self.clampSize(xr), ry: Self.clampSize(yr), start: sa, end: ea, clip: clip)

        case let .bezier(x0, y0, x1, y1, x2, y2, x3, y3, count):
            guard let clip = viewportClip else { return }
            let p = [absolute(x0, y0, in: clip), absolute(x1, y1, in: clip),
                     absolute(x2, y2, in: clip), absolute(x3, y3, in: clip)]
            drawBezier(p, segments: Swift.min(count, 4096), clip: clip)

        case let .polygon(points):
            guard let clip = viewportClip, points.count >= 2 else { return }
            let abs = points.map { absolutePoint($0, clip) }
            drawPolyline(abs, closed: true, pen: linePen, clip: clip)

        case let .fillPolygon(points):
            guard let clip = viewportClip, points.count >= 2 else { return }
            let abs = points.map { absolutePoint($0, clip) }
            canvas.fillPolygon(abs, fill: fillSpec, clip: clip)
            drawPolyline(abs, closed: true, pen: linePen, clip: clip)

        case let .polyline(points):
            guard let clip = viewportClip, points.count >= 2 else { return }
            drawPolyline(points.map { absolutePoint($0, clip) }, closed: false, pen: linePen, clip: clip)

        case let .fill(x, y, border):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x, y, in: clip)
            canvas.floodFill(x: ax, y: ay, border: Self.color(border), fill: fillSpec, clip: clip)

        case .noMore:
            interactive.noMore = true

        // MARK: Level 1 — text regions
        case let .beginText(x0, y0, x1, y1, _):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x0, y0, in: clip)
            let (bx, by) = absolute(x1, y1, in: clip)
            state.textRegion = .init(x0: Swift.min(ax, bx), y0: Swift.min(ay, by),
                                     x1: Swift.max(ax, bx), y1: Swift.max(ay, by),
                                     nextY: Swift.min(ay, by))

        case let .regionText(justify, s):
            guard let clip = viewportClip, var region = state.textRegion else { return }
            drawRegionText(s, justify: justify == 1, region: &region, clip: clip)
            state.textRegion = region

        case .endText:
            state.textRegion = nil

        // MARK: Level 1 — clipboard and blocks
        case let .getImage(x0, y0, x1, y1, _):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x0, y0, in: clip)
            let (bx, by) = absolute(x1, y1, in: clip)
            guard ax <= bx, ay <= by, ax >= 0, ay >= 0, bx < canvas.width, by < canvas.height else { return }
            clipboard = canvas.copyBlock(x0: ax, y0: ay, x1: bx, y1: by)

        case let .putImage(x, y, mode, _):
            guard let clip = viewportClip, let image = clipboard else { return }
            let (ax, ay) = absolute(x, y, in: clip)
            guard ax + image.width - 1 < canvas.width else { return }
            canvas.paste(image, x: ax, y: ay, mode: mode, clip: clip)

        case let .copyRegion(x0, y0, x1, y1, _, dest):
            copyRegion(x0: x0, y0: y0, x1: x1, y1: y1, dest: dest)

        // MARK: Level 1 — buttons and mouse
        case let .buttonStyle(style):
            state.buttonStyle = style

        case let .button(x0, y0, x1, y1, hotkey, flags, _, text):
            guard let clip = viewportClip, let style = state.buttonStyle else { return }
            drawButton(x0: x0, y0: y0, x1: x1, y1: y1, hotkey: hotkey, flags: flags,
                       text: RIPButtonText(parsing: text), style: style, clip: clip)

        case let .mouse(_, x0, y0, x1, y1, click, clear, _, host):
            guard let clip = viewportClip else { return }
            let (ax, ay) = absolute(x0, y0, in: clip)
            let (bx, by) = absolute(x1, y1, in: clip)
            addMouseRegion(RIPMouseRegion(kind: .mouseField, x0: ax, y0: ay, x1: bx, y1: by,
                                          hostCommand: host, invertsWhenClicked: click == 1,
                                          resetsOnClick: clear == 1, hotkey: nil))

        case .killMouseFields:
            interactive.mouseRegions.removeAll()

        // MARK: Recorded only
        case .define: interactive.defines.append(command)
        case .query: interactive.queries.append(command)
        case .readScene: interactive.reads.append(command)
        case .fileQuery: interactive.fileQueries.append(command)
        case .enterBlockMode: interactive.blockModes.append(command)
        case .writeIcon: interactive.writeIcons.append(command)
        case .loadIcon: interactive.loadIcons.append(command)
        case let .ansiSense(sense): interactive.ansiSenses.append(sense)
        case .unknown: interactive.unknowns.append(command)
        }
    }

    // MARK: - Primitive helpers

    static let background = FillSpec(rows: RIPFillPattern.predefinedRows[0], color: 0)

    private func absolutePoint(_ p: RIPPoint, _ clip: ClipRect) -> RIPPoint {
        let (x, y) = absolute(p.x, p.y, in: clip)
        return RIPPoint(x: x, y: y)
    }

    /// Text window in absolute pixels, or `nil` if it is inactive.
    private func textWindowRect() -> ClipRect? {
        let w = state.textWindow
        guard w.isActive else { return nil }
        let cell = w.cellSize
        let r = ClipRect(x0: w.x0 * cell.width, y0: w.y0 * cell.height,
                         x1: (w.x1 + 1) * cell.width - 1, y1: (w.y1 + 1) * cell.height - 1)
            .intersection(canvas.screen)
        return r.isEmpty ? nil : r
    }

    func addMouseRegion(_ region: RIPMouseRegion) {
        guard interactive.mouseRegions.count < 128 else { return }
        interactive.mouseRegions.append(region)
    }

    func drawRectangle(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, pen: Pen, clip: ClipRect) {
        let lx = Swift.min(x0, x1), rx = Swift.max(x0, x1)
        let ty = Swift.min(y0, y1), by = Swift.max(y0, y1)
        if lx == rx || ty == by {
            canvas.line(lx, ty, rx, by, pen: pen, clip: clip)
            return
        }
        // Edges do not overlap at the corners, so XOR rectangles are exact.
        canvas.line(lx, ty, rx, ty, pen: pen, clip: clip)
        canvas.line(lx, by, rx, by, pen: pen, clip: clip)
        if by - ty >= 2 {
            canvas.line(lx, ty + 1, lx, by - 1, pen: pen, clip: clip)
            canvas.line(rx, ty + 1, rx, by - 1, pen: pen, clip: clip)
        }
    }

    private func drawPolyline(_ points: [RIPPoint], closed: Bool, pen: Pen, clip: ClipRect) {
        for i in 0..<(points.count - 1) {
            canvas.line(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, pen: pen, clip: clip)
        }
        if closed, let first = points.first, let last = points.last, points.count > 2 {
            canvas.line(last.x, last.y, first.x, first.y, pen: pen, clip: clip)
        }
    }

    private func drawBezier(_ p: [(Int, Int)], segments: Int, clip: ClipRect) {
        guard segments > 0 else { return }
        func point(_ t: Double) -> (Int, Int) {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            let x = a * Double(p[0].0) + b * Double(p[1].0) + c * Double(p[2].0) + d * Double(p[3].0)
            let y = a * Double(p[0].1) + b * Double(p[1].1) + c * Double(p[2].1) + d * Double(p[3].1)
            return (Int(x.rounded()), Int(y.rounded()))
        }
        var previous = p[0]
        for i in 1...segments {
            let current = point(Double(i) / Double(segments))
            canvas.line(previous.0, previous.1, current.0, current.1, pen: linePen, clip: clip)
            previous = current
        }
    }

    /// Points along an elliptical arc from `start` counter-clockwise to `end`
    /// (degrees, 0 = 3 o'clock). Equal angles yield no points; a span that
    /// is a non-zero multiple of 360 is a full ellipse.
    private func arcPoints(cx: Int, cy: Int, rx: Int, ry: Int, start: Int, end: Int) -> [RIPPoint] {
        guard start != end else { return [] }
        let s = ((start % 360) + 360) % 360
        let e = ((end % 360) + 360) % 360
        var span = (e - s + 360) % 360
        if span == 0 { span = 360 }
        let sRad = Double(s) * .pi / 180
        let spanRad = Double(span) * .pi / 180
        let steps = Swift.max(4, Swift.min(20_000, Int((spanRad * Double(Swift.max(rx, ry))).rounded(.up)) + 1))
        canvas.charge(steps + 1)
        var points: [RIPPoint] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = sRad + spanRad * Double(i) / Double(steps)
            points.append(RIPPoint(x: cx + Int((Double(rx) * cos(t)).rounded()),
                                   y: cy - Int((Double(ry) * sin(t)).rounded())))
        }
        return points
    }

    private func drawArc(cx: Int, cy: Int, rx: Int, ry: Int, start: Int, end: Int, clip: ClipRect) {
        let points = arcPoints(cx: cx, cy: cy, rx: rx, ry: ry, start: start, end: end)
        guard points.count >= 2 else { return }
        if cx + rx + 1 < clip.x0 || cx - rx - 1 > clip.x1 || cy + ry + 1 < clip.y0 || cy - ry - 1 > clip.y1 { return }
        let pen = outlinePen
        for i in 0..<(points.count - 1) {
            canvas.line(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, pen: pen, clip: clip)
        }
    }

    private func drawPieSlice(cx: Int, cy: Int, rx: Int, ry: Int, start: Int, end: Int, clip: ClipRect) {
        let arc = arcPoints(cx: cx, cy: cy, rx: rx, ry: ry, start: start, end: end)
        guard let first = arc.first, let last = arc.last else { return }
        let center = RIPPoint(x: cx, y: cy)
        canvas.fillPolygon([center] + arc, fill: fillSpec, clip: clip)
        let pen = outlinePen
        for i in 0..<(arc.count - 1) {
            canvas.line(arc[i].x, arc[i].y, arc[i + 1].x, arc[i + 1].y, pen: pen, clip: clip)
        }
        canvas.line(cx, cy, first.x, first.y, pen: pen, clip: clip)
        canvas.line(cx, cy, last.x, last.y, pen: pen, clip: clip)
    }

    /// Draw text at a viewport-relative position; horizontal text leaves the
    /// drawing position just after it, vertical text leaves it at `p`.
    private func drawText(_ s: String, at p: RIPPoint, clip: ClipRect) {
        let (ax, ay) = absolute(p.x, p.y, in: clip)
        RIPVectorFonts.renderText(s, x: ax, y: ay, font: state.font, direction: state.fontDirection,
                                  size: state.fontSize, color: state.drawColor, mode: state.writeMode,
                                  into: canvas, clip: clip)
        // As BGI's outtext(): only horizontal text advances the position.
        let advance = Self.clamp(RIPVectorFonts.width(of: s, font: state.font, size: state.fontSize))
        state.position = state.fontDirection == 0 ? RIPPoint(x: Self.clamp(p.x + advance), y: p.y) : p
    }

    private func drawRegionText(_ s: String, justify: Bool, region: inout RIPGraphicsState.TextRegion, clip: ClipRect) {
        let height = RIPVectorFonts.lineHeight(font: state.font, size: state.fontSize)
        defer { region.nextY = Self.clamp(region.nextY + height) }
        guard region.nextY + height - 1 <= region.y1 else { return }   // falls off: discarded
        let regionClip = ClipRect(x0: region.x0, y0: region.y0, x1: region.x1, y1: region.y1).intersection(clip)
        let top = region.nextY
        func draw(_ text: String, _ x: Int) {
            RIPVectorFonts.renderText(text, x: x, y: top, font: state.font, direction: 0,
                                      size: state.fontSize, color: state.drawColor,
                                      mode: state.writeMode, into: canvas, clip: regionClip)
        }
        let words = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let available = region.x1 - region.x0 + 1
        let textWidth = RIPVectorFonts.width(of: s, font: state.font, size: state.fontSize)
        guard justify, words.count > 1, textWidth < available, words.count <= available else {
            draw(s, region.x0)
            return
        }
        let wordsWidth = words.reduce(0) { $0 + RIPVectorFonts.width(of: $1, font: state.font, size: state.fontSize) }
        let gaps = words.count - 1
        let spare = available - wordsWidth
        var x = region.x0
        for (i, word) in words.enumerated() {
            draw(word, x)
            x += RIPVectorFonts.width(of: word, font: state.font, size: state.fontSize)
            if i < gaps { x += spare / gaps + (i < spare % gaps ? 1 : 0) }
        }
    }

    /// `1G` RIP_COPY_REGION: absolute coordinates, columns widened to 8-pixel
    /// boundaries, ignored if the destination would leave the screen or
    /// starts on the source's first line.
    private func copyRegion(x0: Int, y0: Int, x1: Int, y1: Int, dest: Int) {
        let (x0, y0, x1, y1, dest) = (Self.clamp(x0), Self.clamp(y0), Self.clamp(x1), Self.clamp(y1), Self.clamp(dest))
        guard x0 <= x1, y0 <= y1, dest != y0, y0 >= 0, dest >= 0 else { return }
        let left = Swift.max(0, (x0 / 8) * 8)
        let right = Swift.min(canvas.width - 1, (Swift.min(x1, canvas.width) / 8 + 1) * 8 - 1)
        let height = y1 - y0 + 1
        guard left <= right, y1 < canvas.height, dest + height - 1 < canvas.height else { return }
        let block = canvas.copyBlock(x0: left, y0: y0, x1: right, y1: y1)
        canvas.paste(block, x: left, y: dest, mode: 0, clip: canvas.screen)
    }
}
