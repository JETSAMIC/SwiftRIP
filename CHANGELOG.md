# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Proposed initial release

### Added

- RIPscrip 1.54 parser (`RIPParser`, `SwiftRIP.decode`) for every Level 0,
  Level 1 and Level 9 command, with `!|` / `SOH |` / `STX |` framing, `|`
  delimiters, level and sub-level digits, backslash continuation, escapes,
  variable-width last parameters and ANSI auto-sense sequences
  (`ESC[1!` / `ESC[2!` disable and enable RIPscrip processing).
- Writer (`RIPWriter`, `SwiftRIP.encode`) emitting spec-width MegaNums,
  escaped text and safe backslash continuations; throws `RIPWriteError`
  for values that do not fit.
- Renderer into the native 640x350 16-color EGA framebuffer
  (`RIPFramebuffer`) with viewport-relative coordinates and clipping,
  write modes, line styles and thickness, 12 fill patterns plus custom
  patterns, flood fill, aspect-corrected circles / arcs / pie slices,
  Beziers, polygons, text with the bitmap and stroke fonts, text regions,
  clipboard get / put / copy region, and plain / clipboard buttons.
- `RIPRenderResult` with the final `RIPGraphicsState` and
  `RIPSceneInteractive` (mouse regions in global coordinates and the
  non-graphical commands).
- `CGImage` output with nearest-neighbour scaling and optional smoothing,
  and progressive playback via `RIPAnimationFrames`.
- `RIPRenderOptions.pixelBudget` bounding render time for hostile scripts.
- DocC catalog, Swift Package Index manifest and CI workflow.

### Known limitations

- Fonts are clean-room approximations of the BGI fonts (ASCII 32-126).
- `.ICN` icon files are not read; icon buttons render without images.
- Host interaction (mouse clicks, queries, text variables, file transfer)
  is recorded, not executed.
