# Getting Started

Decode a RIPscrip file, render it, and write a scene back out.

## Decode

``SwiftRIP/SwiftRIP/decode(_:)-(Data)`` reads the raw bytes of a `.RIP`
file or captured session. Lines that do not start with `!|` (plain BBS
text) are skipped; ANSI auto-sense sequences are reported as
``RIPCommand/ansiSense(_:)``.

```swift
import SwiftRIP

let data = try Data(contentsOf: url)
let scene = try SwiftRIP.decode(data)

for command in scene.commands {
    if case let .line(x0, y0, x1, y1) = command {
        print("line", x0, y0, x1, y1)
    }
}
```

Malformed numeric arguments throw ``RIPParseError``; commands that are
well-formed but not part of RIPscrip 1.54 decode as
``RIPCommand/unknown(level:command:arguments:)``.

## Render

```swift
var options = RIPRenderOptions()
options.targetSize = CGSize(width: 1280, height: 700)   // 2x, chunky pixels
options.antiAliasing = false

let image: CGImage? = SwiftRIP.render(scene, options: options)
```

For the framebuffer, the final drawing state and the recorded mouse
regions, use ``SwiftRIP/SwiftRIP/renderResult(_:options:)``:

```swift
let result = SwiftRIP.renderResult(scene)
let colorIndex = result.framebuffer.colorIndex(x: 10, y: 20)
for region in result.interactive.mouseRegions {
    print(region.x0, region.y0, region.x1, region.y1, region.hostCommand)
}
if result.isTruncated {
    // The script exceeded RIPRenderOptions.pixelBudget.
}
```

## Play back progressively

```swift
var options = RIPRenderOptions()
options.animation = .animated(framesPerCommand: 4)
for await frame in try SwiftRIP.renderFrames(scene, options: options) {
    show(frame)
    try await Task.sleep(for: .milliseconds(16))
}
```

## Write

```swift
let scene = RIPScene(commands: [
    .resetWindows,
    .color(14),
    .fillStyle(pattern: 1, color: 1),
    .bar(x0: 10, y0: 10, x1: 200, y1: 60),
    .textXY(x: 20, y: 30, string: "Welcome!"),
])
let text = try SwiftRIP.encode(scene)
// "!|*\r\n!|c0E\r\n!|S0101\r\n!|B0A0A5K1O\r\n!|@0K0UWelcome\\!\r\n"
```

Values that do not fit their MegaNum field throw ``RIPWriteError``.
