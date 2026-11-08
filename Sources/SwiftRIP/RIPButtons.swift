// RIPButtons — rendering of `1U` RIP_BUTTON with the current `1B`
// RIP_BUTTON_STYLE.
//
// Supported: plain buttons (surface-color rectangle), clipboard buttons
// (clipboard pasted in copy mode; ignored when the clipboard is empty), fixed
// and dynamic sizing, the bevel, recessed, sunken and chisel effects (chisel
// insets from the spec's table), label orientation (above / left / center /
// right / below), left/right label justification, label drop shadow and the
// mouse-button hit region, and auto-stamp ("auto-clip": the first button's
// image, effects included but recess and label excluded, replaces the
// clipboard and the style becomes a plain clipboard-button style).
//
// Not supported: icon images (icon buttons get effects and label around
// the RIP_BUTTON rectangle but no image — SwiftRIP does not read `.ICN`
// files), hot-icons, hot-key underline/highlight, the "selected" state,
// radio / check-box behaviour and the explode effect.
// Effect geometry and label spacing approximate RIPterm.

import Foundation

extension RIPInterpreter {

    /// Chisel inset (x, y) for a button of the given height (RIPscrip 1.54
    /// RIP_BUTTON_STYLE chisel table).
    static func chiselInset(height: Int) -> (Int, Int) {
        switch height {
        case ..<12: return (1, 1)
        case 12...24: return (3, 2)
        case 25...39: return (4, 3)
        case 40...74: return (6, 5)
        case 75...149: return (7, 5)
        case 150...199: return (8, 6)
        case 200...249: return (10, 7)
        case 250...299: return (11, 8)
        default: return (13, 9)
        }
    }

    /// The style that RIPscrip 1.54 leaves in effect after an auto-stamp
    /// (flag 64) button: icon and plain become clipboard, and the chisel,
    /// bevel, auto-stamp and sunken flags are cleared.
    static func styleAfterAutoStamp(_ style: RIPButtonStyle) -> RIPButtonStyle {
        typealias F = RIPButtonStyle.Flag
        var next = style
        let cleared = F.icon | F.plain | F.chisel | F.bevel | F.autoStamp | F.sunken
        next.flags = (style.flags & ~cleared) | F.clipboard
        return next
    }

    /// Draw one button. Returns `true` when the button auto-stamped its
    /// image onto the clipboard, so the caller must switch the current style
    /// to ``styleAfterAutoStamp(_:)``.
    @discardableResult
    func drawButton(x0: Int, y0: Int, x1: Int, y1: Int, hotkey: Int, flags: Int,
                    text: RIPButtonText, style: RIPButtonStyle, clip: ClipRect) -> Bool {
        typealias F = RIPButtonStyle.Flag
        let f = style.flags
        let (ax, ay) = absolute(x0, y0, in: clip)

        // Base image.
        var base: ClipRect
        if f & F.clipboard != 0 {
            guard let image = clipboard else { return false }
            base = ClipRect(x0: ax, y0: ay, x1: ax + image.width - 1, y1: ay + image.height - 1)
            canvas.paste(image, x: ax, y: ay, mode: 0, clip: clip)
        } else {
            if style.width > 0 && style.height > 0 {
                base = ClipRect(x0: ax, y0: ay,
                                x1: Self.clamp(ax + Self.clampSize(style.width) - 1),
                                y1: Self.clamp(ay + Self.clampSize(style.height) - 1))
            } else {
                let (bx, by) = absolute(x1, y1, in: clip)
                base = ClipRect(x0: Swift.min(ax, bx), y0: Swift.min(ay, by),
                                x1: Swift.max(ax, bx), y1: Swift.max(ay, by))
            }
            if f & F.plain != 0 {
                let solid = FillSpec(rows: RIPFillPattern.predefinedRows[1], color: Self.color(style.surfaceColor))
                canvas.fillRect(x0: base.x0, y0: base.y0, x1: base.x1, y1: base.y1, fill: solid, clip: clip)
            }
        }

        let bright = Self.color(style.brightColor)
        let dark = Self.color(style.darkColor)
        let corner = Self.color(style.cornerColor)

        func hline(_ xa: Int, _ xb: Int, _ y: Int, _ c: UInt8) {
            canvas.line(xa, y, xb, y, pen: Pen(color: c), clip: clip)
        }
        func vline(_ x: Int, _ ya: Int, _ yb: Int, _ c: UInt8) {
            canvas.line(x, ya, x, yb, pen: Pen(color: c), clip: clip)
        }
        /// A one-pixel bevel ring `d` pixels outside (negative: inside) `r`.
        func ring(_ r: ClipRect, _ d: Int, topLeft: UInt8, bottomRight: UInt8) {
            let x0 = r.x0 - d, y0 = r.y0 - d, x1 = r.x1 + d, y1 = r.y1 + d
            guard x0 <= x1, y0 <= y1 else { return }
            hline(x0, x1, y0, topLeft)
            vline(x0, y0, y1, topLeft)
            hline(x0, x1, y1, bottomRight)
            vline(x1, y0, y1, bottomRight)
        }

        // Effects that draw over the base image.
        if f & F.sunken != 0 {
            ring(base, -1, topLeft: dark, bottomRight: bright)
        }
        if f & F.chisel != 0 {
            let (ix, iy) = Self.chiselInset(height: base.y1 - base.y0 + 1)
            let inner = ClipRect(x0: base.x0 + ix, y0: base.y0 + iy, x1: base.x1 - ix - 1, y1: base.y1 - iy - 1)
            if !inner.isEmpty {
                drawRectangle(inner.x0, inner.y0, inner.x1, inner.y1, pen: Pen(color: dark), clip: clip)
                drawRectangle(inner.x0 + 1, inner.y0 + 1, inner.x1 + 1, inner.y1 + 1, pen: Pen(color: bright), clip: clip)
            }
        }

        // Effects that grow the button outward.
        var outer = base
        if f & F.bevel != 0 {
            let size = Swift.min(Self.clampSize(style.bevelSize), 350)
            if size > 0 {
                for d in 1...size {
                    ring(base, d, topLeft: bright, bottomRight: dark)
                    canvas.plot(base.x0 - d, base.y1 + d, corner, .copy, clip)
                    canvas.plot(base.x1 + d, base.y0 - d, corner, .copy, clip)
                }
                outer = ClipRect(x0: base.x0 - size, y0: base.y0 - size, x1: base.x1 + size, y1: base.y1 + size)
            }
        }
        let hitRect = outer

        // Auto-stamp: the image so far (base plus effects, without the
        // recess, which is never part of the button, and before the label)
        // replaces the clipboard.
        var stamped = false
        if f & F.autoStamp != 0 {
            let r = hitRect.intersection(canvas.screen)
            if !r.isEmpty {
                clipboard = canvas.copyBlock(x0: r.x0, y0: r.y0, x1: r.x1, y1: r.y1)
                stamped = true
            }
        }

        if f & F.recessed != 0 {
            ring(outer, 1, topLeft: 0, bottomRight: 0)
            ring(outer, 2, topLeft: dark, bottomRight: bright)
            outer = ClipRect(x0: outer.x0 - 2, y0: outer.y0 - 2, x1: outer.x1 + 2, y1: outer.y1 + 2)
        }

        // Label.
        if !text.label.isEmpty {
            let font = state.font, size = state.fontSize
            let tw = RIPVectorFonts.width(of: text.label, font: font, size: size)
            let th = RIPVectorFonts.lineHeight(font: font, size: size)
            let indent = f & F.chisel != 0 ? 20 : 10
            var lx: Int
            if style.flags2 & RIPButtonStyle.Flag2.leftJustifyLabel != 0 {
                lx = base.x0 + indent
            } else if style.flags2 & RIPButtonStyle.Flag2.rightJustifyLabel != 0 {
                lx = base.x1 - indent - tw + 1
            } else {
                lx = base.x0 + (base.x1 - base.x0 + 1 - tw) / 2
            }
            var ly = base.y0 + (base.y1 - base.y0 + 1 - th) / 2
            switch style.orientation {
            case 0: ly = outer.y0 - th - 2
            case 1: lx = outer.x0 - tw - 2
            case 3: lx = outer.x1 + 3
            case 4: ly = outer.y1 + 3
            default: break
            }
            lx = Self.clamp(lx)
            ly = Self.clamp(ly)
            if f & F.dropShadow != 0 {
                RIPVectorFonts.renderText(text.label, x: lx + 1, y: ly + 1, font: font, direction: 0, size: size,
                                          color: Self.color(style.dropShadowColor), mode: .copy,
                                          into: canvas, clip: clip)
            }
            RIPVectorFonts.renderText(text.label, x: lx, y: ly, font: font, direction: 0, size: size,
                                      color: Self.color(style.labelColor), mode: .copy,
                                      into: canvas, clip: clip)
        }

        if f & F.mouseButton != 0 {
            addMouseRegion(RIPMouseRegion(kind: .button, x0: hitRect.x0, y0: hitRect.y0,
                                          x1: hitRect.x1, y1: hitRect.y1, hostCommand: text.hostCommand,
                                          invertsWhenClicked: f & F.invertable != 0,
                                          resetsOnClick: f & F.resetScreen != 0, hotkey: hotkey))
        }
        return stamped
    }
}
