# SwiftRIP

Pure-Swift reader and writer for RIPscrip 1.54 (Remote Imaging Protocol Script) — the BBS-era graphics protocol from TeleGrafix Communications. Renders into a native 640x350 EGA palette framebuffer with optional nearest-neighbor scaling and an anti-aliasing pass for modern displays. No external dependencies.

## Status

**Alpha.** Package scaffold and protocol reference are in place; parser, renderer, and writer phases are not yet shipped. The public API surface (`RIPParser`, `RIPDocument`, `RIPRenderer`, `RIPFramebuffer`, `RIPEncoder`, `RIPError`) is reserved but not yet implemented. Pin to a commit SHA — no tags have been cut.

Test count and a feature-status badge will land alongside the first parser commit.

## What it does (intended scope)

RIPscrip is a vector-graphics command stream wrapped in `!|...|` delimiters and carried inline with ANSI/ASCII terminal data over a serial connection. It was designed for 1992-era 2400-9600 baud BBS sessions and targeted EGA-class hardware (640x350, 16 colors). SwiftRIP implements the published 1.54 specification by TeleGrafix Communications.

### Feature matrix

| Subsystem | Coverage | Status |
|-----------|----------|--------|
| Command **parser** — every Level 0..9 verb in the 1.54 spec | 100% spec coverage planned | not yet implemented |
| **Renderer** — every command that produces visible graphics | 100% spec coverage planned | not yet implemented |
| **Writer** — emit a 1.54-compliant command stream from a `RIPDocument` | 100% spec coverage planned | not yet implemented |
| Mouse fields, Button styles, Define/Query, Host Command Templates, Pop-Up Pick Lists | parsed + structurally represented, **not executed** (no BBS host) | spec-honest 100% format coverage |
| Read Scene, File Query, Enter Block Mode (Zmodem) | parsed + structurally represented, **not executed** (no remote peer) | spec-honest 100% format coverage |
| Spec version | RIPscrip 1.54 (TeleGrafix Communications, 1993) | — |

The "100% spec coverage" claim is honest in this sense: SwiftRIP will parse every command the protocol defines, model it as a Swift value, and render every command that draws visible pixels. The interactive subsystems (mouse fields, buttons, query strings, command templates, block-mode file transfer) have no remote peer in the SwiftRIP context — SwiftRIP is a renderer, not a terminal — so those commands are parsed and structurally preserved without side effects. This is documented explicitly in [`Reference/RIPscrip-Format.md`](Reference/RIPscrip-Format.md).

## Why a new implementation

The reference implementations (RIPterm, RIPaint, RIPlay, raver) are DOS-era C / Pascal codebases that bake in a 16-bit segmented memory model, BGI/EGA hardware assumptions, and modem I/O concerns that are foreign to a modern Apple platform. SwiftRIP is implemented from the 1992-1993 specification — not by porting any existing code — and is designed to render into a `CGImage` (or a raw RGBA8 buffer for non-Apple consumers).

The protocol-level invariant SwiftRIP preserves is the native 640x350 EGA framebuffer. Modern up-scaling and anti-aliasing happen as a separate composition pass on top of an authentic-resolution intermediate, so the "pixel-accurate 1992" look and the "smoothed for retina" look are both first-class options rather than coupled rendering choices.

## Requirements

Swift 6.0+. Builds for iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+. Foundation only — no third-party dependencies. The CoreGraphics bridge is conditional on `canImport(CoreGraphics)` so non-Apple Swift platforms can consume the raw `RIPFramebuffer` without pulling in graphics frameworks.

## Installation

### Swift Package Manager (GitHub)

```swift
dependencies: [
    .package(url: "https://github.com/prestige-exe/SwiftRIP.git", branch: "main")
]
```

Then add `"SwiftRIP"` to your target's `dependencies` array. Pin to a commit SHA in production until a tagged release exists:

```swift
.package(url: "https://github.com/prestige-exe/SwiftRIP.git", revision: "<sha>")
```

### Swift Package Manager (local checkout)

When developing against SwiftRIP alongside a host app, point the dependency at your local checkout:

```swift
dependencies: [
    .package(path: "../SwiftRIP")
]
```

## Parse

`RIPParser` returns a `RIPDocument` — an immutable sequence of `RIPCommand` cases with their decoded arguments. The document is the canonical representation of a RIPscrip stream; rendering happens as a second step.

```swift
import SwiftRIP

let url = URL(fileURLWithPath: "/path/to/scene.rip")
let data = try Data(contentsOf: url)

// Optional cheap sniff before paying full parse cost.
guard RIPParser.isLikelyRIP(data) else {
    throw MyError.notRIP
}

let document = try RIPParser.decode(data: data)

print("commands:", document.commands.count)
print("spec level reached:", document.maxCommandLevel)   // 0..9

for command in document.commands {
    switch command {
    case .line(let x0, let y0, let x1, let y1):
        print("line", x0, y0, "->", x1, y1)
    case .color(let foreground):
        print("color ->", foreground)
    case .text(let s):
        print("text:", s)
    default:
        break
    }
}
```

`RIPParser.decode(url:)` is a convenience wrapper that memory-maps the file via `Data(contentsOf:options:[.mappedIfSafe])` and forwards to `decode(data:)`.

## Render

`RIPRenderer` walks a `RIPDocument` and produces a `RIPFramebuffer` — a 640x350 (or N× scaled) tightly-packed RGBA8 buffer with explicit drawing-state semantics. The renderer never bakes in modern resolutions; up-scaling and optional anti-aliasing are applied as a separate composition step.

```swift
import SwiftRIP

let document = try RIPParser.decode(url: url)

// Native 640x350 EGA framebuffer — authentic 1992 output.
let native = try RIPRenderer.render(document)
print("size:", native.width, "x", native.height)        // 640 x 350

// 3x nearest-neighbor scale, no anti-aliasing — pixel-perfect upscale.
let scaled = try RIPRenderer.render(
    document,
    options: .init(scale: 3, antiAliased: false)
)
print("size:", scaled.width, "x", scaled.height)        // 1920 x 1050

// 3x scale with the anti-aliasing composition pass — smoothed for retina.
let smoothed = try RIPRenderer.render(
    document,
    options: .init(scale: 3, antiAliased: true)
)
```

### CoreGraphics

```swift
#if canImport(CoreGraphics)
import CoreGraphics

if let cg = native.cgImage() {
    // Hand to UIImage / NSImage / SwiftUI Image as needed.
    // `shouldInterpolate` defaults to false so the EGA pixel grid stays crisp;
    // pass `interpolate: true` if you want CoreGraphics to smooth on display.
}
#endif
```

### Animated playback

RIPscrip scenes are imperative — each command mutates a shared drawing state — so "animation" is a function of stepping through the command list rather than a baked frame sequence. `RIPRenderer.player(document:)` returns a stateful player that exposes `step()`, `stepToNext(predicate:)`, and `framebuffer` for time-sliced rendering.

```swift
let player = RIPRenderer.player(document: document, options: .init(scale: 2))
while !player.isFinished {
    try player.step()                  // advance one command
    // player.framebuffer.cgImage() now reflects the partial scene
}
```

Static playback (`RIPRenderer.render(document)`) is equivalent to running the player to completion and reading the final framebuffer.

### Drawing state

A `RIPRenderer` instance carries the same drawing-state model the 1992 reference renderer used. The state is observable from outside the renderer (via `RIPRenderer.state` on a player), which makes test assertions and per-command diagnostics easy:

```swift
public struct DrawingState {
    public var foreground: Int            // 0..15, current color
    public var background: Int            // 0..15, color 0 by convention
    public var lineStyle: LineStyle       // 4 predefined + custom 16-bit pattern
    public var lineThickness: Int         // 1 or 3 pixels
    public var writeMode: WriteMode       // copy / xor
    public var fillStyle: FillStyle       // 12 predefined + custom 8x8 pattern
    public var fillColor: Int             // 0..15
    public var font: FontStyle            // 1..10 scalable + 0 bitmap
    public var fontSize: Int              // 1..10 nominal
    public var fontDirection: Direction   // horizontal / vertical
    public var viewport: Rect             // current viewport clip
    public var textWindow: Rect           // text-mode region (sub-window)
    public var cursor: Point              // current pen position
}
```

`RIPParser` does not run this state machine — that is the renderer's job. The parser only decodes the bytes into typed commands. This separation lets the writer round-trip a parsed document without dragging a renderer along, and lets adopters drive their own state machine if they want to (for example, a tool that draws RIPscrip into Metal instead of CoreGraphics).

## Write

`RIPEncoder.encode(_:)` takes a `RIPDocument` and emits a 1.54-compliant command stream as `Data` (UTF-8 with `!|...|` framing and `\r\n` line continuations). The encoder is symmetric with the parser: `parse(encode(document)) == document` for every supported command.

```swift
import SwiftRIP

let document = RIPDocument(commands: [
    .resetWindows,
    .color(7),
    .filledRectangle(0, 0, 639, 349),
    .color(15),
    .textXY(40, 40, "HELLO RIP")
])

let stream = try RIPEncoder.encode(document)
try stream.write(to: URL(fileURLWithPath: "/tmp/hello.rip"))
```

A `RIPEncoder.encode(commands:)` overload skips the `RIPDocument` wrapper for ad-hoc emission.

## Modernization options

`RIPRenderer.Options` exposes the levers a modern host wants without compromising the authentic 640x350 base:

- `scale: Int` — integer nearest-neighbor scale (1, 2, 3, …). Output dimensions are `640 * scale` x `350 * scale`. Default `1`.
- `antiAliased: Bool` — when true, applies an anti-aliasing composition pass *after* native-resolution rendering. The native framebuffer is unchanged; AA is purely an output filter. Default `false` (off by default to match the pixel-authentic 1992 look on first launch).
- `aspect: Aspect` — `.native` (no correction, 1.83:1) or `.corrected` (4:3 letterboxed; the EGA hardware itself rendered the 640x350 framebuffer with non-square pixels on a 4:3 display). Default `.native`. Circles are always rendered with the spec-mandated aspect compensation regardless of this option — `aspect` only governs the final composition shape.
- `palette: RIPPalette` — defaults to the canonical EGA 16-color palette. Override to swap in a custom 16-entry palette (the `SetPalette` and `OnePalette` commands still take effect on top of whatever you pass).

The native framebuffer is always the same regardless of options; modernization happens as a deterministic composition pass on top.

## QuickLook integration (macOS / iOS)

The `Examples/RIPQuickLook/` folder ships a drop-in QuickLook plugin source set built on the modern `QLPreviewProvider` extension point. Once integrated into a host app, Finder spacebar previews (macOS) and Files.app previews (iOS) work for any `.rip` file on disk. The plugin registers the `com.telegrafix.rip` UTI under `QLSupportedContentTypes`, decodes via `RIPParser`, renders via `RIPRenderer`, re-encodes the framebuffer to PNG, and hands it back via `QLPreviewReply(dataOfContentType:contentSize:)`.

The plugin is not a Swift Package target — `.appex` bundles are an Xcode-project concept — so the layout is "sources + Info.plists you paste into a new extension target." See `Examples/RIPQuickLook/README.md` (lands alongside the renderer phase) for the full recipe, including the host-app UTI declaration that owns `com.telegrafix.rip` as an exported type.

## UTType / file association

RIPscrip has no canonical owner identifier (TeleGrafix never claimed one), so SwiftRIP exports `com.telegrafix.rip` as the SwiftRIP-recommended UTI. Adopters who embed SwiftRIP in a sandboxed app should declare:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.telegrafix.rip</string>
        <key>UTTypeDescription</key>
        <string>RIPscrip Vector Graphic</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.content</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>rip</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>application/x-ripscrip</string>
            </array>
        </dict>
    </dict>
</array>
```

RIPscrip is a script wrapped in ANSI/ASCII, so files-in-the-wild sometimes ship inside text-mode archives with a `.ans` extension. Don't conflate `.rip` with text-mode UTIs in your `CFBundleDocumentTypes` — give it its own `CFBundleTypeName` ("RIPscrip Vector") so the OS doesn't route an `.rip` open through a text-mode handler.

## Building from source

The package builds with the Xcode 17 beta toolchain. Set `DEVELOPER_DIR` so `swift build` and `swift test` find the right XCTest module:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

Stable Xcode also works as long as your toolchain provides Swift 6.0+. The package has no other build prerequisites.

## Contributing

Issues and pull requests welcome. Priority areas (in roughly the order they will be tackled):

- **Parser hardening.** Real-world RIPscrip files in the wild deviate from the spec in well-known ways (lenient whitespace handling, leftover ESC sequences, mid-stream Zmodem fragments). Bug reports against unusual files with the file attached are higher priority than new command variants.
- **Renderer fidelity.** Per-command pixel-level comparisons against the original RIPterm 1.54 reference renderer are the gold standard. If you have an RIP file plus a screenshot of how RIPterm rendered it, an issue with both attached is the most useful contribution.
- **Font metrics.** RIPscrip ships ten scalable stroke fonts plus a bitmap font; their METRIC tables (top / bow / base / drop scan-line offsets per character) need real-corpus validation.
- **ICN file fixtures.** `LoadIcon` / `WriteIcon` consume Borland BGI `.ICN` files. Real-world `.ICN` files for round-trip testing are welcome.

Please do **not** copy code from any existing RIPscrip implementation (RIPterm, RIPaint, RIPlay, raver, modern open-source ports). SwiftRIP is implemented from the published 1992-1993 spec, which TeleGrafix released for free implementation per its "USE OF THE RIPscrip LANGUAGE" section. We want this implementation to remain license-clean of any specific prior codebase.

Conventional-commit format (`noun(action): verb`) is used throughout the history.

## License

[MIT](LICENSE).

## RIPscrip License Acknowledgement

This product uses RIPscrip. RIPscrip is a trademark of TeleGrafix Communications, Inc. The RIPscrip language is freely licensed per its 1993 specification ("USE OF THE RIPscrip LANGUAGE" section, RIPscrip 1.54 protocol specification, TeleGrafix Communications, Inc.).

SwiftRIP is not affiliated with, endorsed by, or sponsored by TeleGrafix Communications, Inc. The names "RIPterm", "RIPaint", and "RIPdraw" are TeleGrafix product names and are intentionally not used as any SwiftRIP package, product, or symbol identifier.

## References

- [Reference/RIPscrip-Format.md](Reference/RIPscrip-Format.md) — the canonical 1.54 protocol summary used while implementing this package. Includes the full command reference, font metric tables, fill / line pattern catalog, ICN file layout, and SwiftRIP-specific scope notes.
- *RIPscrip Graphics Protocol Specification*, version 1.54 — TeleGrafix Communications, Inc., 1993. The original specification document.
- *RIPscrip Graphics Protocol Specification*, version 1.53 — mirrored at [github.com/prestige-exe/specs](https://github.com/prestige-exe/specs) for archival cross-checking against 1.54.
