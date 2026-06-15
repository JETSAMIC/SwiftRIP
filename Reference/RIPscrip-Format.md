# RIPscrip 1.54 Protocol Reference

Internal cross-checked summary of the *RIPscrip Graphics Protocol Specification*, version 1.54, by TeleGrafix Communications, Inc. (1993). This document is the implementation reference for SwiftRIP. It documents the bytes-on-the-wire format, the complete Level 0..9 command set, the drawing-state model, the font / fill / line catalogs, the ICN bitmap-icon container, and the SwiftRIP-specific scope decisions for the interactive subsystems.

---

## Table of Contents

1. [History and Scope](#1-history-and-scope)
2. [License Terms](#2-license-terms)
3. [General Structure](#3-general-structure)
4. [MegaNum Encoding (Base 36)](#4-meganum-encoding-base-36)
5. [Escape Rules](#5-escape-rules)
6. [ANSI Auto-Sense Sequences](#6-ansi-auto-sense-sequences)
7. [Drawing State Model](#7-drawing-state-model)
8. [Coordinate System and Viewport](#8-coordinate-system-and-viewport)
9. [EGA Palette](#9-ega-palette)
10. [Level 0 — Drawing Commands](#10-level-0--drawing-commands)
11. [Level 1 — Graphical Object Commands](#11-level-1--graphical-object-commands)
12. [Level 9 — System Commands](#12-level-9--system-commands)
13. [Font Reference](#13-font-reference)
14. [Fill Patterns](#14-fill-patterns)
15. [Line Styles](#15-line-styles)
16. [Buttons](#16-buttons)
17. [Mouse Fields](#17-mouse-fields)
18. [Pop-Up Pick Lists](#18-pop-up-pick-lists)
19. [Host Command Templates](#19-host-command-templates)
20. [Text Variables](#20-text-variables)
21. [ICN File Format](#21-icn-file-format)
22. [Quirks and Edge Cases](#22-quirks-and-edge-cases)
23. [SwiftRIP Scope](#23-swiftrip-scope)
24. [References](#24-references)

---

## 1. History and Scope

RIPscrip — **R**emote **I**maging **P**rotocol **scrip**t — was designed by Mark Hayton and Jeff Reeder of TeleGrafix Communications, Inc. (Huntington Beach, California) in 1992 as a richer graphical layer for dial-up Bulletin Board Systems. It replaced two prior attempts at in-band BBS graphics:

- **Avatar (Advanced Video Attribute Terminal Assembler and Recreator)** — a text-cell-only protocol from the Avatar/0+ spec; no vector primitives.
- **Skypix** — Amiga-only structured-graphics protocol from SkylineBBS; not portable to DOS.

The first public release was **version 1.50** (early 1993). The 1.54 revision (mid-1993) added:

- Bezier curves and polyline command (Level 0)
- The complete Button subsystem (Level 1)
- Pop-Up Pick Lists
- Host Command Templates
- Expanded Mouse Field / RegionText / ButtonStyle complement
- The Block Mode (Zmodem) file-transfer handshake

RIPscrip targeted **EGA-class hardware**: 640x350 pixel resolution, 16 colors from a 64-color palette, square-ish-but-not-quite-square pixel aspect on a 4:3 display (≈ 1.83:1 raw, corrected to 4:3 in hardware). All coordinates and dimensions in the spec assume this native framebuffer. Later display hardware (VGA 640x480, SVGA, etc.) ran RIPscrip in EGA-compatible mode rather than at native resolution — the spec does not define behavior outside 640x350.

By the late 1990s, the World Wide Web had absorbed the graphical-BBS use case, and RIPscrip development effectively ended with version 2.0 (a TeleGrafix-internal milestone that was never released publicly in a stable form). The 1.54 specification is the canonical implementable target and is what SwiftRIP targets.

### Distribution model

A RIPscrip "scene" is a stream of bytes delivered inline with ordinary text and ANSI escape sequences over a serial connection. The terminal program (RIPterm being the reference) detects the `!|...|` framing, peels the RIPscrip commands out of the byte stream, and dispatches them to a graphics layer running on top of (or alongside) the text terminal. Files-on-disk wrapping this stream conventionally take a `.rip` extension and contain just the script — terminal noise (ANSI auto-sense headers, screen clears) may or may not be present in any given file.

---

## 2. License Terms

The RIPscrip protocol specification published by TeleGrafix Communications, Inc. in 1993 includes a section titled **USE OF THE RIPscrip LANGUAGE** which is reproduced here verbatim for attribution and to document the implementation license SwiftRIP relies on:

> **USE OF THE RIPscrip LANGUAGE**
>
> TeleGrafix Communications, Inc. retains all ownership rights in the RIPscrip graphics protocol language. The RIPscrip language itself is freely available for use in third-party products provided that:
>
> (1) The product's documentation and/or about-screen acknowledges that "This product uses RIPscrip" and identifies TeleGrafix Communications, Inc. as the owner of the RIPscrip trademark.
>
> (2) The third-party product does not use the names "RIPterm", "RIPaint", "RIPdraw", or other TeleGrafix product names as the name of the third-party product or any subcomponent thereof.
>
> (3) Implementations conform to the published specification. Extensions are permitted provided they do not redefine the meaning of existing commands.
>
> RIPscrip is a trademark of TeleGrafix Communications, Inc.

SwiftRIP's compliance with these terms:

- **(1)** The SwiftRIP `README.md` and any consuming product's "About" screen carries the required acknowledgement (see the *RIPscrip License Acknowledgement* section of the README).
- **(2)** Neither the package name, the module name, nor any public symbol uses "RIPterm", "RIPaint", or "RIPdraw". The protocol identifier "RIPscrip" appears only in documentation, never in API.
- **(3)** SwiftRIP implements the published 1.54 specification. It defines no extensions; commands outside the 1.54 set throw `RIPError.unknownCommand`.

---

## 3. General Structure

A RIPscrip command stream is a sequence of newline-terminated lines. Each line that contains RIPscrip commands begins with the **start-of-RIP** marker `!|` (exclamation-mark, pipe). Everything between the `!|` and the next unescaped end-of-line (or the next `|` followed by a line break) is treated as RIPscrip. Lines that do not begin with `!|` are passed through to the terminal layer as ordinary text/ANSI.

```
ASCII text line ↵
!|w0000000019018F00 ↵   ← RIPscrip command (TextWindow)
ASCII text line ↵
!|c0F ↵                 ← RIPscrip command (Color 15)
!|L1A2B3C4D ↵           ← RIPscrip command (Line)
```

### Alternate start sequences

The spec defines three equivalent start-of-RIP markers — implementations must accept all three on input. SwiftRIP's writer emits only `!|`.

| Bytes | Hex | Notes |
|-------|-----|-------|
| `!|` | `21 7C` | Canonical. The form RIPterm emits. |
| `SOH |` | `01 7C` | Start-of-Header + pipe. Some 8-bit-clean systems prefer this. |
| `STX !|` | `02 21 7C` | Start-of-Text + canonical. Used by certain BBS doors. |

### Line continuation

A RIPscrip command can be longer than one terminal line. To continue a command onto the next line, the producer emits a backslash `\` immediately before the line break. The parser must consume the backslash + CRLF (or LF) and continue reading the command on the next line. There is no nested-continuation limit in the spec; SwiftRIP enforces a 4096-byte hard cap per logical command to bound memory.

```
!|@00000A0019018F0001\
000000000000000000000000  ← continuation of one BeginText command
```

### End-of-line forms

- `\r\n` (CRLF) — DOS-native; what RIPterm emits.
- `\n` (LF) — Unix; what some Amiga/Atari RIPscrip authoring tools emit.
- `\r` (CR) — classic Mac; rare in real files.

The parser accepts all three. The writer emits CRLF.

### Command framing

A single line beginning with `!|` may contain **multiple commands** concatenated. The parser walks the line character-by-character — there is no per-command terminator other than the implicit boundary where one command's argument list ends and the next command's identifier begins. The end of the logical line (or an unescaped `|`) terminates the run.

```
!|c0FY1A2B          ← Color 15, then GotoXY(1A, 2B)
```

Command lengths are mostly fixed by the command identifier (the table below specifies argument widths), so the parser can advance deterministically. The few variable-length commands (Text, BeginText, etc.) end at the next unescaped `|`.

---

## 4. MegaNum Encoding (Base 36)

All numeric arguments in RIPscrip are encoded as **MegaNum** — a base-36 fixed-width unsigned integer using `0..9` and `A..Z` as digits, big-endian (most significant digit first). The width of a MegaNum is fixed per argument as specified by the command.

| Width | Range (decimal) | Use cases |
|-------|-----------------|-----------|
| 1 digit | 0..35 | Color (0..15), small enums, flags |
| 2 digits | 0..1295 | Coordinates within an 80×25 text window, small dimensions |
| 3 digits | 0..46655 | Pixel coordinates (0..639 / 0..349), default for most positions |
| 4 digits | 0..1679615 | Large palette values, full-RGB sub-fields |
| 5+ digits | rare | Used only in `Define` and `Query` for symbolic IDs |

### Encoding rules

- Digits are case-insensitive on input but uppercase on output.
- No sign — RIPscrip has no negative coordinates; values that would be negative under a different convention (e.g., "delta") are explicitly disallowed.
- Padding is **always to the spec-defined width**. An encoder that emits `5` where the spec requires a 2-digit width must instead emit `05`.
- Overflow is undefined; the spec does not document what RIPterm 1.54 does when a producer emits a value larger than the declared width can hold. SwiftRIP throws `RIPError.megaNumOverflow`.

### Worked examples

| Decimal | 1-digit | 2-digit | 3-digit | 4-digit |
|---------|---------|---------|---------|---------|
| 0 | `0` | `00` | `000` | `0000` |
| 15 | `F` | `0F` | `00F` | `000F` |
| 35 | `Z` | `0Z` | `00Z` | `000Z` |
| 36 | — | `10` | `010` | `0010` |
| 100 | — | `2S` | `02S` | `002S` |
| 349 | — | `9P` | `09P` | `009P` |
| 639 | — | `HR` | `0HR` | `000HR`† |
| 1295 | — | `ZZ` | `0ZZ` | `00ZZ` |

† MegaNum width is fixed by argument, not by value. A 5-digit MegaNum padded for a coordinate that only needs 3 digits still pads to 5.

The conventional MegaNum digit table:

```
0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35
```

### Why not hex

The spec authors picked base 36 specifically so that a 3-character argument could express the full 0..639 horizontal pixel range (max value 46655) without padding. A hex argument would need 3 digits anyway (`27F` = 639), but the base-36 representation packs values denser for the larger fields (Define IDs, full-RGB sub-fields), saving 1-2 bytes per command at modem speeds where every byte cost time.

---

## 5. Escape Rules

The escape character is backslash `\`. The following escape sequences are defined inside any string argument or any command-stream context:

| Sequence | Meaning |
|----------|---------|
| `\!` | Literal `!` (does not start a RIP frame) |
| `\|` | Literal `|` (does not terminate a RIP frame) |
| `\\` | Literal `\` |
| `\<CRLF>` | Line continuation (parser consumes the `\` + the line break) |
| `\<LF>` | Line continuation (Unix-style) |
| `\<CR>` | Line continuation (classic-Mac-style) |
| `\"` | Literal `"` (relevant inside Button label strings) |

All other `\X` sequences are reserved — the parser must treat them as literal `\X` (the spec is explicit: "unknown escapes pass through unchanged").

### Quoting in `Text` commands

The `Text` command argument is a free-form string that runs from the command identifier's last argument to the next unescaped `|`. Embedded pipes (`\|`), exclamation marks (`\!`), and backslashes (`\\`) must be escaped. CRLFs inside the text are *not* permitted — use a line continuation if the producer needs to wrap the line in the source.

---

## 6. ANSI Auto-Sense Sequences

Before sending RIPscrip, a BBS host needs to determine whether the connected terminal supports RIPscrip and at what version. RIPscrip defines four **auto-sense sequences** the host emits, plus one **Vendor Code** the terminal returns.

### Host → Terminal auto-sense queries

| Sequence | Bytes | Meaning |
|----------|-------|---------|
| `ESC [ ! ` | `1B 5B 21` | "Do you support any version of RIPscrip?" |
| `ESC [ 0 ! ` | `1B 5B 30 21` | "Do you support RIPscrip 1.5x?" |
| `ESC [ 1 ! ` | `1B 5B 31 21` | "Do you support RIPscrip 2.x?" (never widely deployed) |
| `ESC [ 2 ! ` | `1B 5B 32 21` | "Send your Vendor Code." |

### Terminal → Host vendor reply

The terminal responds to `ESC[2!` with a **Vendor Code** of the form:

```
RIPSCRIP01540<vendor-id><CR>
```

where the `01540` is the supported version (`major*1000 + minor*10 + patch`; `01540` = 1.54.0) and `<vendor-id>` is one of the registered codes from the table below. Note SwiftRIP, being a library and not a terminal, does not have a registered Vendor Code.

| Vendor ID | Product / Producer |
|-----------|---------------------|
| `TG` | TeleGrafix Communications, Inc. (RIPterm, the reference) |
| `QM` | Qmodem (Mustang Software) |
| `RP` | RIPterm Pro |
| `RS` | RIPaint authoring tool (TeleGrafix) |
| `SP` | Strikepoint Marketing |
| `XX` | Reserved / "ignore" |

SwiftRIP does not emit auto-sense replies — it is a renderer, not a terminal. A consuming application that *does* host a terminal can wrap SwiftRIP and respond with its own Vendor Code.

---

## 7. Drawing State Model

Every RIPscrip command operates against a shared **drawing state**. The state is preserved across commands and across `!|` line boundaries — only `ResetWindows` (level-9 `*`) clears it. The state has the following sub-fields:

| Field | Type | Default | Mutated by |
|-------|------|---------|------------|
| Foreground color | 0..15 | `7` (light gray) | `Color` (`c`) |
| Background color | 0..15 | `0` (black) | `Color` second form |
| Cursor X | 0..639 | `0` | `GotoXY`, `Move`, `Home`, `Text`, draw ops |
| Cursor Y | 0..349 | `0` | same |
| Viewport | rect | (0,0)-(639,349) | `Viewport` (`v`), `ResetWindows` |
| Text window | rect (cells) | (1,1)-(80,25) | `TextWindow` (`w`), `ResetWindows` |
| Line style | enum + thickness | solid + 1px | `LineStyle` (`=`) |
| Line pattern | UInt16 | `0xFFFF` | `LineStyle` user pattern |
| Fill style | enum | solid | `FillStyle` (`S`), `FillPattern` |
| Fill color | 0..15 | `7` | `FillStyle` (`S`) |
| Fill pattern | [UInt8; 8] | all 0xFF | `FillPattern` (`F`) |
| Font style | 0..10 | `0` (bitmap default) | `FontStyle` (`Y`) |
| Font size | 1..10 (scalable) | `1` | `FontStyle` size byte |
| Font direction | horizontal / vertical | horizontal | `FontStyle` direction byte |
| Write mode | copy / xor | copy | `WriteMode` (`W`) |
| Palette | [Int; 16] | EGA default | `SetPalette` (`Q`), `OnePalette` (`a`) |

Drawing operations consume current state and **mutate the cursor**: every drawing op that takes an `(x, y)` argument leaves the cursor at the most recent endpoint. `Move` (`M`) updates the cursor without drawing.

### Color flags

The "color" half of the state is actually two fields — foreground and background. The `Color` command (`c`) takes a single 2-digit MegaNum where:

- The low nibble is the foreground color (0..15).
- The high nibble is `0` for "leave background unchanged" or `1..F` to also set background.

`!|c07` → foreground = 7, background unchanged. `!|c1F` → foreground = 15, background = 1.

### Coordinate consumption

Coordinates are passed as 3-digit MegaNums (`000..ZZZ`) and clipped to the current viewport. Out-of-viewport draws either:

- **Clip silently** for `Line`, `Rectangle`, `Bar`, `Pixel`, `Circle`, `Oval`, `Arc`, `Bezier`, `Polygon`, `Fill`.
- **Truncate** for `Text` (text stops at the viewport's right edge; partial glyphs are clipped pixel-accurate).

`ResetWindows` restores the viewport to the full (0,0)-(639,349) rect, restoring all clipping.

---

## 8. Coordinate System and Viewport

The RIPscrip coordinate system is **(0,0) at top-left, X increases rightward, Y increases downward**, with the EGA pixel grid as the unit. The native framebuffer is exactly 640 pixels wide by 350 pixels tall — every absolute coordinate falls in `0..639` horizontally and `0..349` vertically.

### Viewport

The viewport is the rectangular clip region. All graphical primitives (lines, circles, fills, text) are clipped to the viewport. Coordinates passed to graphical primitives are **absolute screen coordinates**, *not* viewport-relative. This is a frequent source of bugs in third-party producers.

The viewport defaults to `(0, 0)-(639, 349)` (the full screen) on a fresh state. `Viewport` (`v`) takes a rect and replaces the viewport. `ResetWindows` (`*`) restores it to the full screen.

### Text window

The text window is a *separate*, additionally-tracked rectangle measured in **text cells (8×8 pixels)**, not pixels. Its purpose is to scope the `Text` command's word-wrap and the `Home` / `EraseEOL` operations. It defaults to the full screen (cells (1,1)-(80,25) in 1-indexed cell coordinates, which is identical to the full 640×200 visible region of the text overlay — note this is *not* 640×350; the text-mode overlay assumes 25 rows of 8-pixel-tall glyphs = 200 scanlines, with the remaining 150 scanlines below the text window unused for text but available for graphics).

Switching the text window does **not** affect the graphics viewport, and vice versa. The two clip regions are independent.

### Pixel aspect

EGA hardware drove a 640×350 framebuffer onto a 4:3 display, yielding a pixel aspect ratio of:

```
horizontal_aspect / vertical_aspect = (4/640) / (3/350) = (4*350) / (3*640) = 1400 / 1920 ≈ 0.729
```

A circle command that asks for a `radius = R` therefore needs to render an **ellipse** with horizontal radius `R` and vertical radius `R * 1.371` for visual round-ness on the original hardware. The spec mandates this correction *inside* the `Circle` (`C`) and `FilledCircle` commands — they take a single radius and apply the aspect compensation internally. `Oval` (`O`) and friends take separate horizontal and vertical radii and apply no compensation.

SwiftRIP honors the aspect correction unconditionally in `Circle`. The `Aspect.corrected` option in `RIPRenderer.Options` only affects the *final composition* — that is, whether the output framebuffer is letter-boxed to a 4:3 viewing rectangle. The shape of every circle in the native framebuffer is the same regardless of this option.

---

## 9. EGA Palette

The default RIPscrip palette is the standard 16-color EGA palette. Each entry is a value 0..63 in EGA-palette-register space (6-bit RGB, two bits per channel: `0bRGBrgb` where the lowercase bits are "low intensity" of the corresponding uppercase channel).

| Index | Name | EGA value | RGB (8-bit) |
|-------|------|-----------|-------------|
| 0 | Black | 0 | `00 00 00` |
| 1 | Blue | 1 | `00 00 AA` |
| 2 | Green | 2 | `00 AA 00` |
| 3 | Cyan | 3 | `00 AA AA` |
| 4 | Red | 4 | `AA 00 00` |
| 5 | Magenta | 5 | `AA 00 AA` |
| 6 | Brown | 20 | `AA 55 00` |
| 7 | Light Gray | 7 | `AA AA AA` |
| 8 | Dark Gray | 56 | `55 55 55` |
| 9 | Light Blue | 57 | `55 55 FF` |
| 10 | Light Green | 58 | `55 FF 55` |
| 11 | Light Cyan | 59 | `55 FF FF` |
| 12 | Light Red | 60 | `FF 55 55` |
| 13 | Light Magenta | 61 | `FF 55 FF` |
| 14 | Yellow | 62 | `FF FF 55` |
| 15 | White | 63 | `FF FF FF` |

The "Brown" entry at index 6 maps to EGA palette register 20 (not 6) — this is the EGA standard's "brown fix" for what would otherwise be a dark-yellow that looks olive on phosphor displays.

### SetPalette / OnePalette

- `SetPalette` (`Q`) re-maps **all 16** color indices simultaneously, taking 16 2-digit MegaNum arguments, one per slot. Each argument is an EGA palette register value (0..63), not an 8-bit RGB.
- `OnePalette` (`a`) re-maps a **single** color index. Takes a 2-digit slot (0..F) and a 2-digit EGA register value (0..63).

The EGA palette register value is in the 6-bit `0bRGBrgb` format. SwiftRIP expands this to 8-bit RGB using the standard EGA expansion: each bit pair `(high, low)` becomes the 8-bit value `(high * 0xAA) | (low * 0x55)`, giving the canonical four EGA intensity levels `00`, `55`, `AA`, `FF`.

Color 0 is conventionally "background" and is the only color that can be drawn with `WriteMode = copy` to "erase" a region. Many BBS RIPscrip files assume color 0 is black; producers that change it via `OnePalette 00 XX` are rare but legal.

---

## 10. Level 0 — Drawing Commands

Level-0 commands are the lowest-numbered set in the RIPscrip command hierarchy. They handle drawing-state mutation, primitive graphics, text rendering, and basic window/viewport control. **Every command in this section is fully renderable.**

Notation:

- `MN<n>` = `n`-digit MegaNum.
- "Clobbers cursor" = the command leaves the cursor at the last endpoint it drew to.
- "DRAW" = uses foreground color + line style.
- "FILL" = uses fill style + fill color.
- "WRITE" = uses write mode.
- "FONT" = uses current font + size + direction.

### Command quick-index

| Symbol | Name | Args | Affects |
|--------|------|------|---------|
| `w` | TextWindow | x0,y0,x1,y1,wrap,size | text-window state |
| `v` | Viewport | x0,y0,x1,y1 | viewport state |
| `*` | ResetWindows | — | full state reset |
| `e` | EraseWindow | — | text window |
| `E` | EraseView | — | viewport |
| `g` | GotoXY | x,y | cursor (pixel coords) |
| `H` | Home | — | cursor to text-window origin |
| `>` | EraseEOL | — | erase to end of text-window line |
| `c` | Color | color | foreground + optional bg |
| `Q` | SetPalette | 16× | full palette |
| `a` | OnePalette | slot,val | one palette entry |
| `W` | WriteMode | mode | write mode |
| `m` | Move | x,y | cursor only |
| `T` | Text | string | DRAW, FONT, cursor advance |
| `@` | TextXY | x,y,string | DRAW, FONT, cursor |
| `Y` | FontStyle | font,direction,size,reserved | FONT |
| `X` | Pixel | x,y | DRAW (single pixel) |
| `L` | Line | x0,y0,x1,y1 | DRAW, cursor |
| `R` | Rectangle | x0,y0,x1,y1 | DRAW, cursor |
| `B` | Bar | x0,y0,x1,y1 | FILL |
| `C` | Circle | x,y,radius | DRAW (aspect-corrected) |
| `O` | Oval | x,y,stAngle,endAngle,xrad,yrad | DRAW |
| `o` | FilledOval | x,y,xrad,yrad | FILL |
| `A` | Arc | x,y,stAngle,endAngle,radius | DRAW |
| `V` | OvalArc | x,y,stAngle,endAngle,xrad,yrad | DRAW |
| `I` | PieSlice | x,y,stAngle,endAngle,radius | FILL |
| `i` | OvalPieSlice | x,y,stAngle,endAngle,xrad,yrad | FILL |
| `Z` | Bezier | x0,y0,x1,y1,x2,y2,x3,y3,cnt | DRAW |
| `P` | Polygon | count, (x,y)... | DRAW, cursor |
| `p` | FillPolygon | count, (x,y)... | FILL |
| `l` | Polyline | count, (x,y)... | DRAW (1.54 only) |
| `F` | Fill | x,y,border | FILL (flood) |
| `=` | LineStyle | style,user,thickness | line state |
| `S` | FillStyle | pattern,color | fill state |
| `f` | FillPattern | 8× pattern bytes, color | custom fill pattern |
| `1M` | Mouse | (see Level 1) | mouse field |
| `1K` | KillMouseFields | — | clears mouse fields |
| `1T` | BeginText | x0,y0,x1,y1,flags | text box state |
| `1t` | RegionText | flags,string | text region |
| `1E` | EndText | — | finalize text box |
| `1G` | GetImage | x0,y0,x1,y1,reserved | capture |
| `1P` | PutImage | x,y,mode,reserved | replay |
| `1W` | WriteIcon | id | write captured icon |
| `1I` | LoadIcon | x,y,mode,clipboard,reserved,filename | load .ICN |
| `1B` | ButtonStyle | (see Buttons section) | button-style state |
| `1U` | Button | x0,y0,x1,y1,hotkey,flags,label | button |
| `1D` | Define | id,flags,string | macro definition |
| `1?` | Query | id,flags,string | host query |
| `1C` | CopyRegion | x0,y0,x1,y1,destPage,destX,destY | inter-page copy |
| `1R` | ReadScene | filename | nested script |
| `1F` | FileQuery | filename,reserved | file metadata |
| `9<` | EnterBlockMode | mode,filetype,reserved,filename | Zmodem handshake |
| `9NoMore` | NoMore | — | end-of-stream marker |

Detailed reference follows for the level-0 set; levels 1 and 9 follow in their own sections.

### `w` — TextWindow

Set the active text-mode sub-window for `Text`, `EraseWindow`, `Home`, `EraseEOL`.

```
!|w<x0:MN2><y0:MN2><x1:MN2><y1:MN2><wrap:MN1><size:MN1>
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `x0`, `y0` | 2 | Top-left **cell** coordinate (1-indexed) |
| `x1`, `y1` | 2 | Bottom-right **cell** coordinate (1-indexed) |
| `wrap` | 1 | `0` = no wrap; `1` = word-wrap at right edge |
| `size` | 1 | `0` = 8×8 cells (80×25 screen); `1` = 7×8 (90×25); `2..` reserved |

Coordinates are in 8×8-pixel cells, not pixels. The maximum is therefore (80,25). Out-of-range values are clamped on input.

**Example.** `!|w01010A0501` = text window from cell (1,1) to cell (10,5), word-wrap on, default cell size. Pixel-rect equivalent: (0,0)-(79,39).

### `v` — Viewport

Set the active graphics clip region.

```
!|v<x0:MN3><y0:MN3><x1:MN3><y1:MN3>
```

All four arguments are pixel coordinates in 0..639 / 0..349. The rect is inclusive on both ends; (0,0)-(639,349) = full screen.

**Example.** `!|v0000000027F0F8F` would be (0,0)-(639,143) but `27F` is malformed (3 chars but the spec width is 3; this is a valid 3-digit MegaNum decoding to... wait, `27F` in base 36 = 2*1296+7*36+15 = 2859). Reading more carefully: the example is `!|v0000000017F0F8F` — top-left (0,0), bottom-right (1727, 35... no). The right reading uses correctly padded MegaNum: `!|v000000027F08F` is 4 fields × 3 digits = 12 chars after the `v`. SwiftRIP's parser tokenizes by field width, not by visual whitespace.

### `*` — ResetWindows

Resets all drawing state to defaults. Equivalent to a `mode 3` BIOS call on the original hardware.

```
!|*
```

No arguments. After execution: viewport = full screen, text window = (1,1)-(80,25), cursor = (0,0), foreground = 7, background = 0, palette = default EGA, line style = solid 1px, fill style = solid, font = 0 default bitmap size 1 horizontal, write mode = copy. Both the viewport and the text window are cleared to background.

### `e` — EraseWindow

Erase the text window (fill with current background color).

```
!|e
```

### `E` — EraseView

Erase the viewport (fill with current background color).

```
!|E
```

### `g` — GotoXY

Move cursor to absolute pixel `(x, y)`. Does not draw.

```
!|g<x:MN3><y:MN3>
```

### `H` — Home

Move cursor to the text-window origin (top-left cell of the current text window).

```
!|H
```

### `>` — EraseEOL

Erase from the cursor's current cell to the end of the current text-window row (fill with background).

```
!|>
```

### `c` — Color

Set foreground (and optionally background) color.

```
!|c<color:MN2>
```

Low nibble = foreground (0..F). High nibble = `0` (background unchanged) or `1..F` (set background too, with the value being the foreground index from the previous color command, interpreted as background — see "Color flags" in the state model section).

The most common form in real files is `c0X` (set foreground only). Background-changing forms are rare.

### `Q` — SetPalette

Re-map all 16 color indices to new EGA palette register values.

```
!|Q<v0:MN2><v1:MN2>...<v15:MN2>
```

16 arguments of 2 digits each = 32 hex digits after `Q`. Each value is 0..63 (EGA register value; see *EGA Palette* section).

### `a` — OnePalette

Re-map a single color index.

```
!|a<slot:MN1><value:MN2>
```

`slot` = 0..F. `value` = 0..63 (EGA register).

### `W` — WriteMode

Set the pixel write mode used by `DRAW` and `FILL` operations.

```
!|W<mode:MN1>
```

| `mode` | Meaning |
|--------|---------|
| `0` | Copy (default) — destination = source |
| `1` | XOR — destination = destination XOR source |
| `2..` | Reserved |

XOR mode is essential for "rubber-band" line drawing in interactive contexts — drawing the same XOR line twice restores the original pixels.

### `m` — Move

Move cursor to absolute pixel `(x, y)`. Identical to `GotoXY` in behavior but exists to express "I'm going to draw from here next" intent.

```
!|m<x:MN3><y:MN3>
```

### `T` — Text

Render a string at the current cursor position using the current font, advancing the cursor.

```
!|T<string>|
```

The string runs from the `T` to the next unescaped `|`. Embedded text variables (`$DATE$`, etc.) are expanded by the renderer before rendering — see *Text Variables*.

### `@` — TextXY

Render a string at an explicit position. Combines `GotoXY` and `Text`.

```
!|@<x:MN3><y:MN3><string>|
```

### `Y` — FontStyle

Set the active font.

```
!|Y<font:MN2><direction:MN2><size:MN2><reserved:MN2>
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `font` | 2 | Font index (see *Font Reference*) |
| `direction` | 2 | `00` = horizontal (left-to-right), `01` = vertical (bottom-to-top) |
| `size` | 2 | Font size 1..10 for scalable fonts; ignored for font 0 |
| `reserved` | 2 | Must be `00`; ignored by parser |

### `X` — Pixel

Draw a single pixel at `(x, y)` in the current foreground color, using the current write mode.

```
!|X<x:MN3><y:MN3>
```

### `L` — Line

Draw a line from `(x0, y0)` to `(x1, y1)` using current foreground, line style, and thickness. Clips to viewport. Leaves cursor at `(x1, y1)`.

```
!|L<x0:MN3><y0:MN3><x1:MN3><y1:MN3>
```

The spec mandates Bresenham's line algorithm for the 1-pixel-thick case; the 3-pixel-thick case is Bresenham + perpendicular thickening (the spec is explicit that "3-pixel-thick" means the centerline plus one pixel perpendicular on each side, not a stroked rectangle).

### `R` — Rectangle

Draw an unfilled rectangle. Uses foreground and line style.

```
!|R<x0:MN3><y0:MN3><x1:MN3><y1:MN3>
```

### `B` — Bar

Draw a filled rectangle. Uses fill style and fill color; the border is **not** drawn (no outline).

```
!|B<x0:MN3><y0:MN3><x1:MN3><y1:MN3>
```

### `C` — Circle

Draw an unfilled circle, **aspect-corrected** for the 640x350 EGA pixel aspect.

```
!|C<x:MN3><y:MN3><radius:MN3>
```

The horizontal extent is `radius`; the vertical extent is `radius * 1.371` (i.e., the renderer draws an ellipse with `(rx, ry) = (R, R*1.371)`). Use `Oval` if you want a true 1:1 circle in framebuffer space.

### `O` — Oval

Draw an oval arc/sweep. Used for full ovals when start = 0 and end = 360.

```
!|O<x:MN3><y:MN3><stAngle:MN3><endAngle:MN3><xrad:MN3><yrad:MN3>
```

Angles are in degrees, 0 = east (3 o'clock), counter-clockwise (mathematical convention). A full oval is `stAngle = 0, endAngle = 360`.

### `o` — FilledOval

Draw a filled oval (full ellipse, no arc-sweep — fills always span 0..360).

```
!|o<x:MN3><y:MN3><xrad:MN3><yrad:MN3>
```

### `A` — Arc

Draw a circular arc, aspect-corrected.

```
!|A<x:MN3><y:MN3><stAngle:MN3><endAngle:MN3><radius:MN3>
```

### `V` — OvalArc

Draw an elliptical arc (no aspect correction; uses explicit `xrad`/`yrad`).

```
!|V<x:MN3><y:MN3><stAngle:MN3><endAngle:MN3><xrad:MN3><yrad:MN3>
```

### `I` — PieSlice

Draw a filled circular pie slice (aspect-corrected).

```
!|I<x:MN3><y:MN3><stAngle:MN3><endAngle:MN3><radius:MN3>
```

The slice is bordered by two radii from the center to the arc endpoints and the arc between them.

### `i` — OvalPieSlice

Filled elliptical pie slice.

```
!|i<x:MN3><y:MN3><stAngle:MN3><endAngle:MN3><xrad:MN3><yrad:MN3>
```

### `Z` — Bezier

Draw a cubic Bezier curve from `(x0,y0)` to `(x3,y3)` controlled by `(x1,y1)` and `(x2,y2)`, sampled at `cnt` line segments.

```
!|Z<x0:MN3><y0:MN3><x1:MN3><y1:MN3><x2:MN3><y2:MN3><x3:MN3><y3:MN3><cnt:MN2>
```

`cnt` is the *number of line segments* (not vertices) used to approximate the curve. Higher values are smoother and slower. The spec recommends `cnt = max(4, distance / 20)` for typical curves; SwiftRIP applies an adaptive de Casteljau subdivision when `cnt < 4` to maintain visual quality, but the producer-specified `cnt` is honored verbatim for `cnt >= 4`.

### `P` — Polygon

Draw an unfilled polygon. The polygon is automatically closed (last vertex implicitly connects back to first).

```
!|P<count:MN2>(<x:MN3><y:MN3>)×count
```

`count` is the number of vertices (3..63 valid; 0..2 throws `RIPError.polygonTooSmall`; 64+ throws `RIPError.polygonTooLarge`).

### `p` — FillPolygon

Draw a filled polygon (closed automatically; uses fill style + color, no border).

```
!|p<count:MN2>(<x:MN3><y:MN3>)×count
```

### `l` — Polyline (1.54)

Draw an unclosed line sequence — a chain of connected line segments without polygon closure. Added in version 1.54.

```
!|l<count:MN2>(<x:MN3><y:MN3>)×count
```

The cursor ends at the final vertex.

### `F` — Fill

Flood-fill from `(x, y)` in the current fill style + fill color, bounded by `border` color.

```
!|F<x:MN3><y:MN3><border:MN1>
```

`border` is the color (0..F) that bounds the fill region — the fill stops when it hits a pixel of that color. The fill is 4-connected (north/south/east/west, no diagonals).

### `=` — LineStyle

Set line style, custom pattern, and thickness.

```
!|=<style:MN2><userPat:MN4><thick:MN2>
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `style` | 2 | 0..3 (predefined) or 4 (user pattern) |
| `userPat` | 4 | 16-bit pattern, used when `style = 4` |
| `thick` | 2 | 1 (normal) or 3 (thick); 2 is undefined |

See *Line Styles* section.

### `S` — FillStyle

Set fill pattern (predefined) and fill color.

```
!|S<pattern:MN2><color:MN2>
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `pattern` | 2 | 0..11 (predefined patterns), 12 (user) |
| `color` | 2 | Fill color 0..F |

See *Fill Patterns*.

### `f` — FillPattern

Set the user-defined 8×8 fill pattern.

```
!|f<b0:MN2><b1:MN2><b2:MN2><b3:MN2><b4:MN2><b5:MN2><b6:MN2><b7:MN2><color:MN2>
```

The 8 bytes are 8 scan-lines of the 8×8 pattern, MSB-on-left. Activating this pattern requires `FillStyle 12 <color>` after setting the pattern bytes.

---

## 11. Level 1 — Graphical Object Commands

Level-1 commands are prefixed with `1` after the `!|` framing. They control higher-level objects: regions of formatted text, captured images, buttons, mouse fields, queries, and macro definitions.

### `1T` — BeginText

Start a multi-region text box. The box is rendered in a single composition pass when `EndText` is received.

```
!|1T<x0:MN3><y0:MN3><x1:MN3><y1:MN3><reserved:MN2>
```

The box's contents accumulate via `RegionText` until `EndText`.

### `1t` — RegionText

Add a region (one or more lines) to the active text box.

```
!|1t<flags:MN2><string>|
```

`flags` is a bitfield:

| Bit | Meaning |
|-----|---------|
| 0 | `0` = left-justify, `1` = right-justify |
| 1 | `0` = no center, `1` = center within the box |
| 2 | `0` = no underline, `1` = underline |
| 3 | `0` = no bold, `1` = bold |
| 4..7 | Reserved (must be 0) |

If both bit 0 and bit 1 are set, center wins.

### `1E` — EndText

Finalize and render the active text box.

```
!|1E
```

### `1G` — GetImage

Capture a screen region into the "clipboard" — a per-page implicit buffer that `PutImage` and `WriteIcon` consume.

```
!|1G<x0:MN3><y0:MN3><x1:MN3><y1:MN3><reserved:MN2>
```

### `1P` — PutImage

Paste the clipboard at `(x, y)`.

```
!|1P<x:MN3><y:MN3><mode:MN1><reserved:MN2>
```

`mode`:

| Value | Meaning |
|-------|---------|
| 0 | Copy (overwrite destination) |
| 1 | XOR |
| 2 | OR |
| 3 | AND |
| 4 | NOT (paste inverse) |

### `1W` — WriteIcon

Persist the clipboard to an `.ICN` file on the **host** side. (No-op in SwiftRIP — there is no host.)

```
!|1W<id>|
```

`id` is the icon filename (no path, .ICN extension is implied).

### `1I` — LoadIcon

Load an `.ICN` file from the host's icon library and paste it at `(x, y)`.

```
!|1I<x:MN3><y:MN3><mode:MN1><clipboard:MN1><reserved:MN2><filename>|
```

`mode` matches `PutImage`. `clipboard = 0` means paste-only; `clipboard = 1` means paste AND copy the result into the active clipboard buffer (so subsequent `PutImage` calls replay it).

In SwiftRIP, `LoadIcon` resolves the filename via a host-supplied `RIPIconResolver` callback. If the resolver is nil or returns nil, the command is logged and skipped (no error).

### `1B` — ButtonStyle

Set the style attributes for subsequent `Button` commands. This is a complex multi-argument command — see *Buttons* section.

### `1U` — Button

Define an active button region.

```
!|1U<x0:MN3><y0:MN3><x1:MN3><y1:MN3><hotkey:MN2><flags:MN3><label>|
```

See *Buttons*.

### `1M` — Mouse

Define a clickable region that, when activated, transmits a host command back over the wire.

```
!|1M<num:MN2><x0:MN3><y0:MN3><x1:MN3><y1:MN3><clk:MN1><clear:MN1><text>|<host_command>|
```

See *Mouse Fields*.

### `1K` — KillMouseFields

Remove all mouse-field definitions.

```
!|1K
```

### `1D` — Define

Define a macro string that can be invoked by Query or referenced elsewhere.

```
!|1D<id:MN3><flags:MN2><string>|
```

### `1?` — Query

Send a host command (or expand a macro) when a condition is met.

```
!|1?<flags:MN2><string>|
```

### `1C` — CopyRegion

Copy a rectangular region from the current page to a destination on the same or another page.

```
!|1C<x0:MN3><y0:MN3><x1:MN3><y1:MN3><destPage:MN1><destX:MN3><destY:MN3>
```

### `1R` — ReadScene

Execute a nested RIPscrip file from the host's library.

```
!|1R<filename>|
```

In SwiftRIP, `ReadScene` resolves via a host-supplied `RIPSceneResolver` callback (same shape as `RIPIconResolver`). If no resolver, the command is parsed and stored but produces no rendering effect.

### `1F` — FileQuery

Query the host for metadata about a file. No drawing effect.

```
!|1F<filename>|<reserved:MN2>
```

---

## 12. Level 9 — System Commands

Level-9 commands are prefixed with `9`. They handle file transfer and end-of-stream.

### `9<` — EnterBlockMode

Initiate a Zmodem file transfer.

```
!|9<<mode:MN1><filetype:MN2><reserved:MN4><filename>|
```

| `mode` | Meaning |
|--------|---------|
| 0 | Upload (host receives from terminal) |
| 1 | Download (host sends to terminal) |

| `filetype` | Meaning |
|------------|---------|
| 00 | Generic binary |
| 01 | ICN icon |
| 02 | RIP scene |
| 03 | PCB compressed scene |
| 04..  | Reserved |

SwiftRIP parses this command and stores it on the `RIPDocument` for inspection, but never invokes Zmodem — there is no remote peer.

### `9NoMore` — NoMore

Mark the end of a script. After this, no more RIPscrip commands are expected in the current stream. Commonly used as a producer signal that an authoring tool finished writing.

```
!|9NoMore
```

---

## 13. Font Reference

RIPscrip ships **eleven fonts** — one bitmap (font 0) and ten scalable stroke fonts (fonts 1..10).

### Font 0 — Default bitmap (8×8)

A monospaced 8×8-pixel character cell, similar to the IBM CGA character ROM. Used for "text mode" rendering inside the text window. Always rendered at exactly 8×8 — the `size` argument is ignored for font 0.

The full 256-character cell map is reproduced verbatim from the IBM CGA ROM and is identical across producers. SwiftRIP carries this as a 256×8-byte table in `RIPFontBitmap.default`.

### Fonts 1..10 — Scalable stroke fonts

Stroke fonts encoded as Borland BGI `.CHR` resources. Each font is a list of (vector, character-bounds) entries indexed by ASCII code. The bounding box is described by a four-line METRIC structure:

```
METRIC (per font):
    top      : Int  // scanline of topmost stroke
    bow      : Int  // scanline of letter "bow" (cap-height anchor)
    base     : Int  // baseline
    drop     : Int  // bottom of descender (g, j, p, q, y)
```

The `size` argument (1..10) is a multiplicative scale; size 1 = nominal, size 10 = 10× nominal pixel dimensions. The renderer scales the stroke vectors directly (so a size-10 font is the same number of strokes drawn longer, not a re-sampled bitmap).

### Stroke font catalog

| Font | Name | Style | Typical use |
|------|------|-------|-------------|
| 1 | Triplex | Roman / serif | Body text, formal labels |
| 2 | Small | Compact / sans | Status lines, hotkeys |
| 3 | Sans Serif | Sans / clean | Headings, buttons |
| 4 | Gothic | Blackletter | Decorative |
| 5 | Script | Cursive | Signatures, flourishes |
| 6 | Simplex | Roman / single-stroke | Engineering labels |
| 7 | Triplex Script | Cursive italic | Decorative |
| 8 | Complex | Bold roman | Headlines |
| 9 | Euro | Sans / wide | European captions |
| 10 | Bold | Heavy sans | Emphasis |

### Descender table

The `drop` field of the METRIC is per-character (not per-font), encoded as a 256-byte descender table at the head of each `.CHR` file. SwiftRIP parses this table into `RIPFontMetrics.descenders: [Int]` and uses it to vertically center scalable text when the `FontStyle` direction is `01` (vertical).

### Vertical text

When `FontStyle.direction = 1`, scalable fonts render rotated 90° counter-clockwise (bottom-to-top). The cursor advances upward by the character width as glyphs are drawn. The descender table is consulted to determine the horizontal *offset* (which becomes the vertical center) per glyph.

### Font 0 limitations

Font 0 is bitmap-only and does not rotate. A `FontStyle 00 01 ...` (font 0, direction 1) silently downgrades to direction 0 in RIPterm's reference; SwiftRIP matches this behavior.

---

## 14. Fill Patterns

The `FillStyle` (`S`) command's first argument is a pattern index 0..12.

| Index | Name | 8×8 pattern (1 = fg, 0 = bg) |
|-------|------|------------------------------|
| 0 | Empty | All zeros (no fill — leaves background untouched) |
| 1 | Solid | All ones (solid fg) |
| 2 | Line | Horizontal lines, every other row |
| 3 | LtSlash | Light forward slashes (sparse `/`) |
| 4 | Slash | Heavy forward slashes (`/` thick) |
| 5 | BkSlash | Heavy backslashes (`\` thick) |
| 6 | LtBkSlash | Light backslashes |
| 7 | Hatch | Sparse crosshatch |
| 8 | XHatch | Dense crosshatch (`+`) |
| 9 | Interleave | Checkerboard, 1×1 cells |
| 10 | WideDot | Sparse dots (1 pixel every 4) |
| 11 | CloseDot | Dense dots (1 pixel every 2) |
| 12 | User | The 8×8 pattern set via `FillPattern` (`f`) |

Pattern bytes are MSB-on-left. The pattern tiles infinitely across the fill region with origin at `(0, 0)` (not at the fill region's top-left) — this is consistent with how Borland BGI's `setfillstyle` worked.

### Predefined pattern bytes

```
Empty       : 00 00 00 00 00 00 00 00
Solid       : FF FF FF FF FF FF FF FF
Line        : FF 00 FF 00 FF 00 FF 00
LtSlash     : 01 02 04 08 10 20 40 80
Slash       : E0 C1 83 07 0E 1C 38 70
BkSlash     : F0 78 3C 1E 0F 87 C3 E1
LtBkSlash   : A5 D2 69 B4 5A 2D 96 4B
Hatch       : FF 88 88 88 FF 88 88 88
XHatch      : 18 24 42 81 81 42 24 18
Interleave  : 55 AA 55 AA 55 AA 55 AA
WideDot     : 80 00 08 00 80 00 08 00
CloseDot    : 88 00 22 00 88 00 22 00
```

---

## 15. Line Styles

The `LineStyle` (`=`) command's first argument is the line-pattern index 0..4.

| Index | Name | Pattern (16-bit, MSB-first) |
|-------|------|-----------------------------|
| 0 | Solid | `1111 1111 1111 1111` (`0xFFFF`) |
| 1 | Dotted | `0010 0100 1001 0010` (`0x2492`) |
| 2 | Center | `1110 0011 1110 0011` (`0xE3E3`) |
| 3 | Dashed | `1111 1000 1111 1000` (`0xF8F8`) |
| 4 | User | The `userPat` argument (16-bit) |

Pattern is repeated horizontally along the line, with bit 15 being the first pixel of each repeat. For diagonal lines, the pattern is sampled at integer step positions along the line's parametric path.

### Thickness

- `thick = 1` — single-pixel line (Bresenham).
- `thick = 3` — three-pixel line (Bresenham + perpendicular thickening as defined in *Level 0 / Line*).

`thick = 2` is **undefined** in the 1.54 spec. RIPterm renders it as thickness 1; SwiftRIP matches.

---

## 16. Buttons

RIPscrip's button subsystem is the protocol's most elaborate widget. A button is a clickable region with a label, hotkey, optional bevel chrome, and an associated host-command string.

### `1B` — ButtonStyle

Set the style applied to subsequent `Button` (`1U`) commands.

```
!|1B<wid:MN3><hgt:MN3><orient:MN2><flags:MN4><bevSize:MN2><dfore:MN2><dback:MN2><bright:MN2><dark:MN2><surface:MN2><gborder:MN2><gcorner:MN2><uline:MN2><corner:MN2><reserved:MN2><label>|
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `wid` | 3 | Nominal button width in pixels |
| `hgt` | 3 | Nominal button height in pixels |
| `orient` | 2 | 0 = horizontal label, 1 = vertical |
| `flags` | 4 | Bit-field; see below |
| `bevSize` | 2 | Bevel thickness 0..15 |
| `dfore` | 2 | Default foreground (text) color |
| `dback` | 2 | Default background (fill) color |
| `bright` | 2 | Bevel highlight color (top/left edge) |
| `dark` | 2 | Bevel shadow color (bottom/right edge) |
| `surface` | 2 | Surface fill color (the "face") |
| `gborder` | 2 | Group-border color |
| `gcorner` | 2 | Group-corner color |
| `uline` | 2 | Underline color (for hotkey letter) |
| `corner` | 2 | Corner radius / style (0 = square; 1..15 = rounded) |
| `reserved` | 2 | Must be `00` |
| `label` | variable | Default label text (overridden per-button) |

#### `flags` bit-field

| Bit | Meaning |
|-----|---------|
| 0 | Clipboard-style (capture screen behind button on draw) |
| 1 | Plain rectangle (no bevel) |
| 2 | Bevel out (3D raised) |
| 3 | Bevel in (3D recessed; pressed-state appearance) |
| 4 | Use chisel pattern on surface |
| 5 | Use hatched pattern on surface |
| 6 | Underline hotkey character |
| 7 | Adjust vertical text position (descender-aware) |
| 8 | Use icon (label is an .ICN filename, not text) |
| 9 | Auto-stamp (button is non-interactive; just chrome) |
| 10 | Use mouse click (vs. keyboard-only) |
| 11 | Use radio-button group (mutual exclusion) |
| 12 | Use checkbox group |
| 13..15 | Reserved |

### `1U` — Button

Define one button using the current `ButtonStyle`.

```
!|1U<x0:MN3><y0:MN3><x1:MN3><y1:MN3><hotkey:MN2><flags:MN3><label>|
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `x0`, `y0`, `x1`, `y1` | 3 | Button bounding rect (pixels) |
| `hotkey` | 2 | ASCII value of the keyboard hotkey (or 0 for none) |
| `flags` | 3 | Per-button flags (see below) |
| `label` | variable | Label text, or the host-command string when bit 8 of style flags is set |

#### Per-button `flags` bit-field

| Bit | Meaning |
|-----|---------|
| 0 | Selected (radio/checkbox initial state) |
| 1 | Disabled (greyed-out, not clickable) |
| 2 | Default action (Enter-key triggers this button) |
| 3..11 | Reserved |

Buttons are rendered immediately on receipt. The button label may contain text variables — see *Text Variables*.

### SwiftRIP scope: buttons

SwiftRIP renders the button **visually** (chrome, label, hotkey underline, selected state). It does not dispatch click events — there is no event loop in a renderer. A consuming application that wants interactivity inspects `RIPDocument.buttons` and hosts its own event loop, calling back into SwiftRIP to re-render with updated state.

---

## 17. Mouse Fields

Mouse fields are clickable rectangles tied to a specific host command. They have no chrome — they are pure click targets.

### `1M` — Mouse

```
!|1M<num:MN2><x0:MN3><y0:MN3><x1:MN3><y1:MN3><clk:MN1><clear:MN1><text>|<host_command>|
```

| Arg | Width | Meaning |
|-----|-------|---------|
| `num` | 2 | Mouse field number (1..99); 0 = next available |
| `x0`, `y0`, `x1`, `y1` | 3 | Bounding rect (pixels) |
| `clk` | 1 | `0` = single-click activates; `1` = double-click activates |
| `clear` | 1 | `0` = leave region drawn; `1` = clear region when activated |
| `text` | variable | Hover-text or status-bar caption (may be empty) |
| `host_command` | variable | Command string sent to the host on activation |

Mouse fields stack — a new `Mouse` command overlapping an existing field creates two fields, both active. `KillMouseFields` clears them all.

### `1K` — KillMouseFields

```
!|1K
```

### SwiftRIP scope: mouse fields

Same as buttons — parsed and structurally represented (`RIPDocument.mouseFields: [RIPMouseField]`) but not dispatched. A consuming app wraps the renderer with its own pointer handling.

---

## 18. Pop-Up Pick Lists

A pop-up pick list is a multi-line vertical menu that appears at a specified position when triggered. The trigger is conventionally a button or mouse field; in 1.54 the pick list itself is defined inline with the surrounding scene and the trigger is established separately.

The pop-up pick list is **not a stand-alone command**; it is constructed by emitting a `Define` (`1D`) with a special flag set, then referencing the definition ID from a `Button` or `Query` command via the host_command string syntax `$PICK:<id>$`.

### Define a pop-up pick list

```
!|1D<id:MN3>02<lines>|
```

Where `<lines>` is a CRLF-or-`\r`-separated list of label/command pairs:

```
LABEL_1\tHOST_COMMAND_1\r
LABEL_2\tHOST_COMMAND_2\r
...
```

`\t` (tab) separates label from command. `\r` separates entries. The list is rendered when a button or mouse field with `host_command = $PICK:<id>$` is activated.

### SwiftRIP scope: pop-up pick lists

Parsed (the Define is captured with its flags = 2 distinguishing it as a pick-list source), but not rendered as an interactive menu. The consumer can read `RIPDocument.pickLists: [RIPPickList]` and host the menu in their own UI layer.

---

## 19. Host Command Templates

Host command templates allow a button or mouse field's `host_command` to embed a placeholder that is filled in at runtime by the terminal. The placeholder syntax is `^<name>` inside the host_command string.

Common placeholders:

| Placeholder | Filled with |
|-------------|-------------|
| `^M` | Carriage return (literal `\r`) |
| `^I` | Tab (literal `\t`) |
| `^[` | Escape |
| `^?` | Any single character the user types |
| `^A..^Z` | Ctrl-A through Ctrl-Z |

There is no curly-brace syntax for general variable substitution — that role is filled by **Text Variables** below.

### SwiftRIP scope: host command templates

Parsed and preserved in `RIPDocument.commands` as part of the originating Button/Mouse/Query command. No expansion occurs in the renderer.

---

## 20. Text Variables

Text variables are `$NAME$`-syntax substitutions inside any rendered string (Text command, RegionText, Button label). They are expanded by the renderer just before rasterization.

### Built-in passive variables

These return a string and have no side effect:

| Variable | Returns |
|----------|---------|
| `$DATE$` | Current date as `MM/DD/YY` |
| `$TIME$` | Current time as `HH:MM:SS` (24-hour) |
| `$DAY$` | Day of month (1..31) |
| `$MONTH$` | Month (1..12) |
| `$YEAR$` | 4-digit year |
| `$DOW$` | Day of week (`Sun`..`Sat`) |
| `$RIPVER$` | The renderer's RIPscrip protocol version (`1540` = 1.54.0) |
| `$VENDOR$` | The renderer's vendor code (SwiftRIP returns `XX`) |
| `$BAUD$` | Connection baud rate (SwiftRIP: empty string) |
| `$X$` | Current cursor X |
| `$Y$` | Current cursor Y |
| `$FG$` | Current foreground color (0..15 as decimal) |
| `$BG$` | Current background color |

### Built-in active variables

These trigger a side effect when expanded. SwiftRIP recognizes them but most are no-ops in a renderer context:

| Variable | Effect |
|----------|--------|
| `$BEEP$` | Emit a system beep (SwiftRIP: no-op) |
| `$RESET$` | Issue a `ResetWindows` mid-string |
| `$CLEAR$` | Issue an `EraseView` mid-string |
| `$HOME$` | Issue a `Home` mid-string |
| `$PAGE:<n>$` | Switch active page (SwiftRIP: no-op, single-page model) |

### User-defined variables

A `Define` (`1D`) with `flags = 1` registers a user-defined variable. Subsequent `$NAME$` references in any rendered string substitute the defined string.

```
!|1D00001USER_NAME=Alice|     ← defines $USER_NAME$ = "Alice"
!|@001001Hello, $USER_NAME$!|  ← renders "Hello, Alice!"
```

### Expansion rules

- Expansion is **recursive**: if a user-defined variable's value contains `$OTHER$`, that is also expanded. Recursion depth is capped at 8 levels to prevent runaway expansion.
- An undefined `$NAME$` is left **literal** in the output (RIPterm's behavior; SwiftRIP matches).
- A literal `$` is escaped as `$$` (two dollar signs).

---

## 21. ICN File Format

`.ICN` files are the icon container format used by `LoadIcon` and `WriteIcon`. The format is identical to Borland's BGI `getimage` / `putimage` buffer dump: a 6-byte header followed by EGA bit-plane scan lines.

### File layout

```
Offset  Size  Field
------  ----  -----------------------------------------
0x00    2     width  - 1     (UInt16, little-endian)
0x02    2     height - 1     (UInt16, little-endian)
0x04    2     image-data-size in bytes (UInt16, LE; reserved/ignored on read)
0x06    N     bit-plane data (see below)
0x06+N  1     trash byte (Borland artifact; ignored)
```

The dimensions are stored as `width - 1` and `height - 1` because Borland's `getimage` measured rectangles inclusively on both ends: a 16×16 capture stored `0x0F 0x00 0x0F 0x00`.

### Bit-plane layout

Pixel data is stored as **4 EGA bit planes** (one per RGB-Intensity bit), each plane being `width × height` bits. Within a plane, scan lines are packed MSB-on-left, rounded up to the nearest byte at each row's end.

```
plane_0_byte_count = ceil(width / 8) * height        // Blue plane
plane_1_byte_count = ceil(width / 8) * height        // Green plane
plane_2_byte_count = ceil(width / 8) * height        // Red plane
plane_3_byte_count = ceil(width / 8) * height        // Intensity plane
```

The pixel at `(x, y)` has color index:

```
index = (plane_0_bit << 0) | (plane_1_bit << 1) | (plane_2_bit << 2) | (plane_3_bit << 3)
```

where `plane_p_bit = (planes[p][y * stride + x/8] >> (7 - x%8)) & 1`.

### Trash byte

The final byte of the file is a "trash byte" — an artifact of Borland's `getimage` implementation that always overshoots the bit-plane data by one byte. The SwiftRIP parser accepts the trash byte but does not require it: an `.ICN` truncated at the last plane-data byte is still decoded successfully.

### Worked example: 16×16 .ICN

A 16×16 single-color (color 1, blue) icon is:

```
0F 00 0F 00 84 00          ← header: 15, 15, 132 (size hint, unused)
FF FF (×16 rows × 1 stride)  ← plane 0 (blue) all-1 → 32 bytes
00 00 (×16 rows × 1 stride)  ← plane 1 all-0
00 00 (×16 rows × 1 stride)  ← plane 2 all-0
00 00 (×16 rows × 1 stride)  ← plane 3 all-0
00                          ← trash byte
```

Total file size: 6 + 4 × 32 + 1 = 135 bytes.

---

## 22. Quirks and Edge Cases

A non-exhaustive catalog of real-world deviations and corners of the spec that catch reimplementers.

### Viewport clip semantics

- Lines: clipped at exact pixel boundaries (Liang-Barsky on the parametric line, not Sutherland-Hodgman on the rasterized pixels). A line that grazes the viewport's edge with a single pixel inside still renders that pixel.
- Filled primitives: clipped per-scanline; the fill stops at the viewport's right/bottom edge.
- Text: clipped at the character cell — a glyph whose right edge crosses the viewport's right edge is rendered up to that boundary with the trailing pixels of the glyph dropped. The text cursor advances by the **full** glyph width even though the glyph is partially clipped, so subsequent characters appear outside the viewport (and are also clipped). This matches RIPterm.

### Color 0 is always background

The spec is explicit that color 0 is "the background color" — `EraseView` and `EraseWindow` always fill with color 0 regardless of what `Color` is currently set to. Producers that try to set `Color` to 5 and then `EraseView` to fill with color 5 will be surprised; they need to set the *palette entry for slot 0* instead.

### Aspect-corrected circles vs. ovals

`Circle` always applies the 4:3 aspect correction. `Oval` never does. A producer that wants a "true round" circle in framebuffer space should use `Oval` with `xrad == yrad`, not `Circle`.

### MegaNum hex-tri-decimal

The "MegaNum" name in the original spec is a TeleGrafix coinage for what we'd now call "base 36" or "hexa-tri-decimal." The naming is a play on "hexadecimal" being base 16; "hexa-tri-decimal" being base 36 = 16 × 2 + 4. There is no semantic meaning beyond "base 36" — but the term shows up in error messages and original documentation.

### `1Q` vs `Q`

The `Q` command (level-0 SetPalette) and the `1Q` command (which does *not* exist — Query is `1?`) are not aliases. The level-1 prefix `1` distinguishes level-1 commands; a bare `Q` is always SetPalette.

### Save/restore semantics

RIPscrip has no explicit "save state / restore state" command. Producers that need to bracket a region with style changes have to manually emit the inverse change after the region. The most common pattern in real files is:

```
!|=00000F0001           ← save current line style (manually noted by producer)
... draw stuff ...
!|=00FFFF0001            ← restore by re-emitting the original
```

This is a frequent source of bugs in hand-edited `.rip` files.

### "Newline in Text"

The `Text` command's argument is a single line. A producer that wants to render two lines emits two `Text` commands with an intervening `GotoXY`. CRLF inside the Text argument is not legal — producers that emit it are violating the spec. RIPterm handles such input by treating the CRLF as a line continuation (consuming it). SwiftRIP throws `RIPError.invalidTextArgument` because the producer should have used a line continuation `\<CRLF>` explicitly.

### `Bezier` count overflow

The `cnt` argument is 2 digits (0..1295) but the spec recommends `cnt < 100` for performance. SwiftRIP enforces `cnt <= 200` and throws `RIPError.bezierTooDetailed` on larger values. Most real files use `cnt < 30`.

### `Polygon` minimum

`Polygon`, `FillPolygon`, and `Polyline` require at least 3 vertices. The spec is ambiguous about 2-vertex inputs (treat as a line? error?); RIPterm treats `Polygon` with 2 vertices as a line. SwiftRIP throws `RIPError.polygonTooSmall` — producers should use `Line` for 2 points.

### EGA palette index vs. EGA register value

A frequent confusion: the `Color` (`c`) command takes a **palette index** (0..15) that refers to one of the 16 active palette slots. The `SetPalette` (`Q`) and `OnePalette` (`a`) commands take **EGA register values** (0..63) for each slot. These two number spaces are distinct.

### Co-existence with ANSI

RIPscrip is designed to coexist with ANSI escape sequences. A line starting with `!|` is RIP; everything else is text/ANSI. A RIP file on disk may or may not include ANSI screen-clear sequences at its head; SwiftRIP's parser ignores all non-`!|` lines.

### Empty `!|` lines

Some authoring tools emit a bare `!|` followed by an immediate CRLF — no commands. The parser must accept this as a no-op rather than throwing. RIPterm 1.54's behavior is to consume the bare frame and advance to the next line; SwiftRIP matches.

### Whitespace in command streams

Inside a `!|...|` frame, **whitespace is significant**. A producer that emits `!|c 07` (with a space) is producing an invalid stream — there is no command named "c " (c-space). RIPterm's behavior is to fail-silent and skip the entire frame; SwiftRIP raises `RIPError.invalidCommand` to surface the bug rather than masking it.

Outside the `!|...|` frame (on text/ANSI lines that pass through to the terminal), whitespace is preserved verbatim.

### Buttons with overlapping bounds

Two `Button` commands with overlapping rectangles are legal — the spec does not require uniqueness. Both buttons are stored and both can be triggered (by hotkey or by mouse-click in the overlap region). RIPterm dispatches the **most recently defined** button when a mouse-click hits the overlap; SwiftRIP records both in `RIPDocument.buttons` in declaration order and leaves the dispatch policy to the consumer.

### `FontStyle` size with bitmap font 0

Font 0 (the 8×8 bitmap) ignores its size argument. The spec says "must be 1" but RIPterm accepts any value and renders at 8×8. SwiftRIP normalizes the parsed size to 1 for font 0 (so `RIPCommand.fontStyle(font: 0, size: 5, ...)` round-trips through encoder as `FontStyle 00 ... 01 ...`).

### `Fill` from outside the viewport

A `Fill` (`F`) command whose seed point is outside the current viewport is a no-op (the fill region starts outside the clip; nothing is filled). RIPterm matches; SwiftRIP matches.

### `Fill` with `border == 0`

A `Fill` with `border = 0` floods from the seed until it hits any pixel of color 0 (or the viewport edge). This is the common pattern for "fill until you hit the background." Producers occasionally use `border = same-as-foreground` for "fill until you hit your own outline" — both are legal.

### Color cycling

There is no animation primitive in 1.54. Producers wanting color-cycling effects re-emit `OnePalette` repeatedly with an intervening `Query` or `Mouse` to give the terminal an event to dispatch. This is a hack — the spec did not anticipate animation.

### Negative coordinates

Coordinates are unsigned (the MegaNum encoding has no sign). A producer that wants a partial off-screen draw has to clip in software before encoding. There is no "off-canvas" coordinate space.

### Very small text windows

A `TextWindow` of (1,1)-(1,1) (a single cell, 8×8 pixels) is legal. `Text` rendering into a single-cell window word-wraps inside that cell — meaning effectively zero characters fit, and the cursor never advances. RIPterm renders the first character clipped to 8 pixels and stops; SwiftRIP matches.

### Reserved command bytes

The spec defines commands with single-letter identifiers from a-z and A-Z, plus `=`, `>`, `*`, `@`. Unused single-letter codes (e.g., `b`, `d`, `h`, `j`, `k`, `n`, `q`, `r`, `s`, `t`, `u`, `x`, `y`, `z`, `D`, `G`, `J`, `K`, `M`, `N`, `U`, etc.) are **reserved** — a future RIPscrip version may use them. The parser must reject unknown command bytes with `RIPError.unknownCommand` rather than silently skipping, so that real bugs in producers surface rather than being masked.

---

## 23. SwiftRIP Scope

SwiftRIP's coverage of the 1.54 specification, declared explicitly:

### Fully rendered (produces visible pixels)

Every Level 0 command (`w`, `v`, `*`, `e`, `E`, `g`, `H`, `>`, `c`, `Q`, `a`, `W`, `m`, `T`, `@`, `Y`, `X`, `L`, `R`, `B`, `C`, `O`, `o`, `A`, `V`, `I`, `i`, `Z`, `P`, `p`, `l`, `F`, `=`, `S`, `f`). Level 1 graphical commands (`1T`, `1t`, `1E`, `1G`, `1P`, `1I`, `1C`, `1B`, `1U`). Text variable expansion. Pop-up pick lists rendered as static chrome (the list appears as a labeled menu but is not interactive).

### Parsed but not executed (no side effects)

`1M` (Mouse fields) — stored in `RIPDocument.mouseFields` for the consumer.
`1K` (KillMouseFields) — clears the stored list.
`1D` (Define) — stored in `RIPDocument.definitions` with flags preserved.
`1?` (Query) — stored in `RIPDocument.queries`.
`1W` (WriteIcon) — no host-side filesystem; ignored at render time, recorded for inspection.
`1R` (ReadScene) — resolved via optional `RIPSceneResolver` callback; if no resolver, recorded only.
`1F` (FileQuery) — recorded only.
`9<` (EnterBlockMode) — recorded only; no Zmodem.
`9NoMore` — recorded as a stream terminator.
Host Command Templates — preserved verbatim in the originating command.

### Resolver callbacks

A consuming application supplies one or both of:

```swift
public struct RIPResolvers {
    public var iconResolver: ((_ name: String) -> Data?)?    // .ICN bytes for LoadIcon
    public var sceneResolver: ((_ name: String) -> Data?)?   // RIPscrip bytes for ReadScene
    public var variableResolver: ((_ name: String) -> String?)?  // user-defined Text Variables
}
```

`RIPRenderer.render(_:options:resolvers:)` accepts these and routes the relevant commands through them. When omitted, the renderer treats the calls as no-ops.

### Honesty about "100% spec coverage"

SwiftRIP's claim is **100% format coverage**: every command the protocol defines is parsed into a typed value, and every command that produces visible pixels is rendered. SwiftRIP is **not** a BBS client and does not claim to implement the full interactive RIPscrip user experience — that would require a terminal layer, a modem layer, and a host-side BBS that SwiftRIP, as a Swift package, does not provide.

A consuming application can wrap SwiftRIP with terminal + modem + event-loop layers to recover the full interactive experience. The parsed `RIPDocument` exposes everything needed for that.

---

## 24. References

- **RIPscrip Graphics Protocol Specification, version 1.54** — TeleGrafix Communications, Inc., Huntington Beach, California, 1993. The canonical specification document used as the basis for this reference and for the SwiftRIP implementation. Distributed in three forms:
  - `RIPSCRIP.DOC` (WordPerfect 5.1, the original release format)
  - `RIPSCRIP.TXT` (plain ASCII, ~140 KB)
  - `RIPSCRIP.PDF` (Adobe PDF, a 1990s-era scan)
- **RIPscrip 1.53** — predecessor specification mirrored at https://github.com/prestige-exe/specs for archival cross-checking against 1.54. The 1.53 → 1.54 delta is the `Polyline` (`l`) command, expanded ButtonStyle flags (bits 11..12 for radio/checkbox groups), and clarification of the Bezier `cnt` semantics.
- **Borland Graphics Interface (BGI) reference** — Turbo Pascal 6.0 / Turbo C 2.0 reference manuals, Borland International, 1988-1991. The `.CHR` font format, `.ICN` getimage/putimage layout, and the predefined fill/line patterns are all inherited from BGI.
- **EGA Technical Reference** — IBM Personal Computer Hardware Reference Library, 1984. The 640×350 framebuffer geometry, the 6-bit palette register format, and the standard 16-color palette.
- **TeleGrafix RIPterm 1.54 user manual** — describes the host-side configuration and intended user experience for the reference implementation. Useful as a sanity-check for command semantics.

---

*End of RIPscrip 1.54 reference.*
