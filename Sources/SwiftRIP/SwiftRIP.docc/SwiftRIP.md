# ``SwiftRIP``

Parse, write and render TeleGrafix RIPscrip 1.54 — the Remote Imaging
Protocol vector graphics of 1990s bulletin board systems.

## Overview

A RIPscrip scene is a stream of `!|`-prefixed text lines carrying
base-36 ("MegaNum") encoded drawing commands, mixed with ordinary BBS
text. SwiftRIP:

- decodes a stream into a ``RIPScene`` of typed ``RIPCommand`` values
  (every Level 0, Level 1 and Level 9 command of RIPscrip 1.54),
- encodes a scene back into RIPscrip text with ``RIPWriter``,
- renders a scene into the native 640x350 16-color EGA framebuffer
  (``RIPFramebuffer``) and, on Apple platforms, into a `CGImage` — scaled
  with nearest-neighbour replication and optional smoothing, or played back
  progressively with ``RIPAnimationFrames``.

Interactive features that need a BBS host or a file system (mouse fields,
queries, text variables, file transfers, icon files) are parsed and
recorded in ``RIPSceneInteractive`` but not executed.

Rendering untrusted scripts is bounded: every command's work is limited
by the screen area and ``RIPRenderOptions/pixelBudget`` caps the total.

## Topics

### Essentials

- <doc:GettingStarted>
- ``SwiftRIP/SwiftRIP``
- ``RIPScene``
- ``RIPCommand``

### Command Arguments

- ``RIPPoint``
- ``RIPButtonStyle``
- ``RIPButtonText``
- ``RIPAnsiSense``

### Parsing and Writing

- ``RIPParser``
- ``RIPParseError``
- ``RIPWriter``
- ``RIPWriteError``
- ``MegaNum``
- ``RIPAnsiSequences``
- ``RIPAnsiSenseHit``

### Rendering

- ``RIPRenderOptions``
- ``RIPRenderResult``
- ``RIPFramebuffer``
- ``RIPAnimationFrames``
- ``RIPAnimationError``

### Drawing State

- ``RIPGraphicsState``
- ``RIPFillPattern``
- ``RIPLineStyle``
- ``RIPWriteMode``
- ``RIPTextWindow``
- ``RIPViewport``
- ``RIPPalette``

### Interactive Commands

- ``RIPSceneInteractive``
- ``RIPMouseRegion``
