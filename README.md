# SwiftRIP

Pure-Swift parser, writer and renderer for TeleGrafix **RIPscrip 1.54** (Remote Imaging Protocol Script), the vector graphics language of 1990s bulletin board systems.

SwiftRIP decodes `.RIP` files and captured BBS sessions into typed commands, encodes commands back into RIPscrip text, and renders scenes into the native 640x350 16-color EGA framebuffer — as a `CGImage` on Apple platforms, optionally scaled with hard-edged pixel replication and smoothing, or played back command by command. No dependencies.

## Requirements

- Swift 6.0+ / Xcode 16+
- iOS 17+, iPadOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ (verified against the 27.3 SDKs)

Parsing, writing and framebuffer rendering use Foundation only; `CGImage` output, scaling and animation are compiled when `CoreGraphics` is available.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/JETSAMIC/SwiftRIP.git", from: "0.1.0")
]
```

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "SwiftRIP", package: "SwiftRIP")
])
```

## Quick start

```swift
import SwiftRIP

// Decode: raw bytes of a .RIP file or a captured session.
let rip = "!|*|c0E|S0101|B0A0A5K1O|@0K0UWelcome\\!\r\n"
let scene = try SwiftRIP.decode(Data(rip.utf8))

// Render to a CGImage at 2x with chunky EGA pixels.
var options = RIPRenderOptions()
options.targetSize = CGSize(width: 1280, height: 700)
options.antiAliasing = false
let image: CGImage? = SwiftRIP.render(scene, options: options)

// Framebuffer, final state and mouse regions.
let result = SwiftRIP.renderResult(scene)
print(result.framebuffer.colorIndex(x: 15, y: 15) as Any)   // 1 (blue bar)
print(result.interactive.mouseRegions.count)               // 0

// Encode back to RIPscrip text.
let text = try SwiftRIP.encode(scene)
```

See the DocC catalog (`Sources/SwiftRIP/SwiftRIP.docc`) for a longer guide, including progressive playback with `SwiftRIP.renderFrames(_:options:)`.

## Spec coverage

Against the RIPscrip 1.54 specification (TeleGrafix, July 1993). "Parsed" means decoded to a typed `RIPCommand` and re-encodable by `RIPWriter`; every command is parsed.

| Feature | Status |
|---------|--------|
| `!\|` framing at line start, `SOH \|` / `STX \|` anywhere, `\|` delimiters, level and sub-level digits | Supported |
| Backslash line continuation, `\\` / `\\\` end-of-line rules, `\!` `\\|` `\\` escapes | Supported |
| MegaNum arguments, spec widths, variable-width last parameter, trailing text ignored | Supported |
| ANSI auto-sense `ESC[!` / `ESC[0!` / `ESC[1!` (disable) / `ESC[2!` (enable) | Supported (reported; disable/enable honoured; no reply sent) |
| Text window, viewport, reset, erase window / view / EOL, goto / home | Supported (viewport-relative coordinates, clipping, disabled-viewport rule) |
| Colors, `Q` / `a` palette (64-color EGA master), write mode copy / XOR | Supported |
| Pixel, line, rectangle, bar, polygon, filled polygon (even-odd), poly-line, Bezier with segment count | Supported |
| Circle, arc, pie slice (aspect-corrected), oval, oval arc, filled oval, oval pie slice | Supported |
| Line styles (4 predefined + custom 16-bit), thickness 1 / 3, 12 fill patterns + custom 8x8 | Supported |
| Flood fill (`F`) | Supported (scanline, bounded) |
| Fonts: 8x8 bitmap + 10 stroke fonts, direction, size 1-10, drawing-position update | Partial — clean-room glyph approximations, not BGI glyph shapes or metrics; ASCII 32-126 only |
| Text regions `1T` / `1t` / `1E` with justification | Supported |
| Clipboard `1C` get image, `1P` put image (copy / XOR / OR / AND / NOT), `1G` copy region | Supported |
| Buttons `1B` / `1U` | Partial — plain and clipboard buttons, bevel / recess / sunken / chisel, auto-stamp, label placement, justification and drop shadow, mouse region; no icon images, hot icons, hot-key underline / highlight, selected / default state, radio / check-box behaviour, explode |
| Mouse fields `1M` / `1K` | Recorded as `RIPMouseRegion`s (global coordinates, 128 limit) |
| Icons `1I` / `1W`, `.ICN` files | Parsed and recorded only (no `.ICN` reader / writer) |
| `1D` define, `1<ESC>` query, `1R` read scene, `1F` file query, `9<ESC>` block mode, `#` no more | Parsed and recorded only (no host / file system) |
| Text variables, pick lists, host-command templates | Preserved verbatim in command text; not interpreted |
| Raw ASCII / ANSI text outside RIPscrip lines | Skipped (no TTY emulation) |

## Limitations

- **Fonts are approximations.** BGI's stroke fonts and the PC ROM 8x8 font are not redistributable, so glyph shapes and advance widths differ from RIPterm; characters outside ASCII 32-126 draw nothing.
- **No icons.** `.ICN` files are not read; `LOAD_ICON` draws nothing and icon buttons render without their image.
- **No terminal.** SwiftRIP does not emulate the TTY text window, send host commands, answer queries or transfer files.
- **Work budget.** `RIPRenderOptions.pixelBudget` (default 200 million work units — pixel writes plus off-screen rasterizer steps; about 900 full-screen flood fills, roughly 1.5 s on Apple silicon) stops hostile scripts; `RIPRenderResult.isTruncated` reports it. Set it to `nil` to disable.
- Out-of-range argument values, unspecified behaviour and spec errata are handled as documented in [`Reference/RIPscrip-Format.md`](Reference/RIPscrip-Format.md) §6 and §8; §9 is the detailed implementation-status table.

## References

- [`Reference/RIPscrip-Format.md`](Reference/RIPscrip-Format.md) — the comprehensive RIPscrip 1.54 specification used by SwiftRIP: every command layout, enumeration tables, algorithms, de-facto behaviour, robustness guidance and errata.
- *RIPscrip Graphics Protocol Specification*, Revision 1.54 (TeleGrafix Communications, Inc., 1993), and Revision 1.53 — archived in the JETSAMIC `specs` repository (`art/ripscrip-1.54.txt`, `art/ripscrip-1.53.md`, `art/ripscrip-1.54-template.txt`).

SwiftRIP is implemented from the published specification; it contains no code or font data from RIPterm, RIPaint or Borland's BGI.

## License

MIT — see [LICENSE](LICENSE).

## RIPscrip acknowledgement

This product uses RIPscrip. RIPscrip, RIPaint, RIPdraw and RIPterm are trademarks of TeleGrafix Communications, Inc. SwiftRIP is not affiliated with or endorsed by TeleGrafix Communications, Inc.
