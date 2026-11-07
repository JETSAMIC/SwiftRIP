# RIPscrip 1.54 Format Reference

Implementation reference for SwiftRIP, summarising the *RIPscrip Graphics
Protocol Specification, Revision 1.54* (TeleGrafix Communications, Inc.,
July 19th, 1993). The authoritative text is in the JETSAMIC specs
repository (`art/ripscrip-1.54.txt`, with `art/ripscrip-1.53.md` and
`art/ripscrip-1.54-template.txt`); where this summary and the
specification disagree, the specification wins.

> **Revision note (2026-11).** An earlier version of this document described
> a format that is not RIPscrip 1.54: 3-digit coordinates, commands
> concatenated without `|`, `f` for RIP_FILL_PATTERN, `9NoMore`, `1?` / `9<`
> command characters, swapped `1C`/`1G`, a fabricated "verbatim" licence
> text, a `\"` escape, reversed ANSI auto-sense meanings and wrong fill
> pattern bytes. It has been rewritten from the 1.54 text; every table below
> was checked against it.

## Contents

1. [General structure](#1-general-structure)
2. [MegaNums](#2-meganums)
3. [ANSI auto-sense sequences](#3-ansi-auto-sense-sequences)
4. [Screen, viewport and text window](#4-screen-viewport-and-text-window)
5. [Palette](#5-palette)
6. [Command reference](#6-command-reference)
7. [Fill patterns and line styles](#7-fill-patterns-and-line-styles)
8. [Fonts](#8-fonts)
9. [Buttons](#9-buttons)
10. [Mouse regions and host commands](#10-mouse-regions-and-host-commands)
11. [Icon (.ICN) files](#11-icon-icn-files)
12. [Implementation decisions and spec errata](#12-implementation-decisions-and-spec-errata)
13. [Licence terms](#13-licence-terms)

---

## 1. General structure

RIPscrip is a 7-bit ASCII script mixed with ordinary text and ANSI. The
spec's syntax rules (numbered as in the spec):

1. A RIPscrip line starts at the **beginning of a line**. `!|` in the middle
   of a line is literal text.
2. A RIPscrip line begins with `!`.
3. Every command is preceded by the delimiter `|` (the `|` of `!|` is the
   first one).
4. Several commands may share a line, separated by `|`:
   `!|c02|L02030405`.
5. Lines may be split with a backslash immediately before the line break:

   ```
   !|c02|L02030405|P0901020102010201020102\
   0102010201020102
   ```
6. Text after a command's arguments on the same line is ignored (the
   command is still executed). Lines not starting with `!|` are raw text for
   the TTY text window.
7. There is a graphics window (viewport) and a text window.
8. After `|`, a digit `1`-`9` is the command **level**; further digits are
   sub-levels (`!|L` level 0, `!|1L` level 1, `!|15L` level 1 sub-level 5,
   up to `!|123456789x`).
9. The command type character follows the level digits; it is any
   printable non-digit character (two commands use ESC, see §6).
10. Arguments follow without delimiters. Numeric arguments are fixed-width
    MegaNums; a text argument is always last. **A variable-width numeric
    parameter may be used as the last parameter** — the spec's own example
    `!|cA` is color 10 with a one-digit argument.
11. `!` and `|` inside text are written `\!` and `\|`; a literal backslash
    is `\\`.
12. A RIPscrip line may start in any column if `!` is replaced by Ctrl-A
    (SOH) or Ctrl-B (STX): `^A|...` / `^B|...`.
13. A literal backslash at the end of a line must be `\\`; a literal
    backslash followed by a continuation is `\\\`.

Line breaks are CR LF on DOS hosts; LF and CR alone are accepted by
SwiftRIP. SwiftRIP's writer emits CR LF by default.

**Decoding bytes.** RIPscrip is a byte stream (text arguments may contain
CP437 bytes on real systems). SwiftRIP decodes `Data` as ISO-8859-1, one
character per byte, so no byte is lost and error offsets are byte offsets.

## 2. MegaNums

Numbers are unsigned base-36 ("Hexa-Tri-Decimal") using `0-9A-Z`, most
significant digit first, left-zero-padded to the argument's width. A
`:n` width holds `0 ... 36^n - 1`:

| Width | Range | Used for |
|------:|-------|----------|
| 1 | 0...35 | wrap, size, flags, modes, reserved |
| 2 | 0...1295 | **every coordinate, radius, angle, color, count** |
| 3 | 0...46655 | RIP_DEFINE flags, RIP_QUERY reserved |
| 4 | 0...1679615 | line-style user pattern, button flags, reserved |
| 5 / 6 / 8 | | reserved fields of 1M / 1B / 1R |

Examples: `0F` = 15, `HR` = 639, `9P` = 349, `ZZ` = 1295, `0XPM` = 43690
(`AAAA` hex), `1BLC` = 61680 (`F0F0` hex). Input is case-insensitive.

## 3. ANSI auto-sense sequences

Sent by a host outside RIPscrip lines:

| Sequence | Meaning |
|----------|---------|
| `ESC [ !` | Query version. A terminal replies `RIPSCRIPxxyyvs` — major, minor (2 digits each), vendor code, vendor sub-version; e.g. `RIPSCRIP015410` for RIPterm 1.54. Vendor codes: 0 generic, 1 RIPterm, 2 Qmodem Pro. |
| `ESC [ 0 !` | Same as `ESC [ !`. |
| `ESC [ 1 !` | **Disable** RIPscrip processing; RIPscrip lines become raw text. |
| `ESC [ 2 !` | **Enable** RIPscrip processing. |

## 4. Screen, viewport and text window

* Graphics coordinates are EGA pixels, 640 x 350, origin top-left,
  `x` 0...639, `y` 0...349.
* **Viewport** (`v`): inclusive absolute rectangle; all-zero disables it.
  The 1.54 per-command table includes "Uses Viewport": a command that uses
  the viewport is drawn inside it (its coordinates are relative to the
  viewport's upper-left corner, BGI style) and is clipped to it; "if the
  viewport is not defined (0,0,0,0), then the command is parsed, but
  completely ignored". RIP_RESET_WINDOWS sets the full 640x350 viewport.
  RIP_COPY_REGION is "one of the only graphical output commands that does
  not adhere to the viewport" and uses absolute coordinates.
* **Text window** (`w`): character cells, inclusive; all-zero makes it
  invisible. `size` selects the cell: 0 = 8x8 (80x43), 1 = 7x8 (91x43),
  2 = 8x14 (80x25), 3 = 7x14 (91x25), 4 = 16x14 (40x25). `wrap` 1 wraps
  and scrolls, 0 truncates. Re-defining an identical window (same corners
  and size; `wrap` may differ) does not move the cursor; otherwise the
  cursor goes to the upper-left cell. RIP_GOTOXY / RIP_HOME / RIP_ERASE_EOL
  move or use the text cursor, not the graphics drawing position.
* **Aspect ratio.** RIP_CIRCLE, RIP_ARC and RIP_PIE_SLICE "understand aspect
  ratios ... based on the EGA 640x350 resolution": the vertical radius is
  scaled by 350/480 (EGA pixels on a 4:3 display). Oval commands take
  explicit x/y radii and are not corrected.

## 5. Palette

The 16-entry RIPscrip palette maps color numbers 0...15 to the 64 EGA
master colors. An EGA value is six bits `r'g'b'RGB` (bit 5 ... bit 0):
upper-case bits contribute 0xAA and primed bits 0x55 to their channel.

| Color | Name | Master value | RGB |
|------:|------|-------------:|-----|
| 00 | Black (always the background color) | 0 | 00 00 00 |
| 01 | Blue | 1 | 00 00 AA |
| 02 | Green | 2 | 00 AA 00 |
| 03 | Cyan | 3 | 00 AA AA |
| 04 | Red | 4 | AA 00 00 |
| 05 | Magenta | 5 | AA 00 AA |
| 06 | Brown | 20 | AA 55 00 |
| 07 | Light Gray | 7 | AA AA AA |
| 08 | Dark Gray | 56 | 55 55 55 |
| 09 | Light Blue | 57 | 55 55 FF |
| 0A | Light Green | 58 | 55 FF 55 |
| 0B | Light Cyan | 59 | 55 FF FF |
| 0C | Light Red | 60 | FF 55 55 |
| 0D | Light Magenta | 61 | FF 55 FF |
| 0E | Yellow | 62 | FF FF 55 |
| 0F | White | 63 | FF FF FF |

(See §12 for the spec's typo in this table.) `Q` replaces all sixteen
entries, `a` one entry; already-drawn pixels change color immediately
(palette cycling). RIP_RESET_WINDOWS restores the default palette.

## 6. Command reference

Widths are MegaNum digits; `text` is the trailing text argument. "WM" =
uses the write mode, "VP" = uses the viewport, "Pat" = uses the line
pattern, "Thk" = uses the line thickness (from the spec's per-command
tables). The **SwiftRIP** column states what the renderer does.

### Level 0

| Cmd | Symbol | Arguments | WM | VP | Pat | Thk | SwiftRIP |
|-----|--------|-----------|----|----|-----|-----|----------|
| `w` | RIP_TEXT_WINDOW | x0:2 y0:2 x1:2 y1:2 wrap:1 size:1 | | | | | state |
| `v` | RIP_VIEWPORT | x0:2 y0:2 x1:2 y1:2 | | | | | state |
| `*` | RIP_RESET_WINDOWS | — | | | | | rendered |
| `e` | RIP_ERASE_WINDOW | — | | | | | rendered (text-window cells) |
| `E` | RIP_ERASE_VIEW | — | | | | | rendered |
| `g` | RIP_GOTOXY | x:2 y:2 | | | | | state (text cursor) |
| `H` | RIP_HOME | — | | | | | state |
| `>` | RIP_ERASE_EOL | — | | | | | rendered |
| `c` | RIP_COLOR | color:2 | | | | | state |
| `Q` | RIP_SET_PALETTE | c1:2 ... c16:2 | | | | | state |
| `a` | RIP_ONE_PALETTE | color:2 value:2 | | | | | state |
| `W` | RIP_WRITE_MODE | mode:2 (0 copy, 1 XOR) | | | | | state |
| `m` | RIP_MOVE | x:2 y:2 | | Y | | | state |
| `T` | RIP_TEXT | text | Y | Y | | | rendered |
| `@` | RIP_TEXT_XY | x:2 y:2 text | Y | Y | | | rendered |
| `Y` | RIP_FONT_STYLE | font:2 direction:2 size:2 res:2 | | | | | state |
| `X` | RIP_PIXEL | x:2 y:2 | | Y | | | rendered |
| `L` | RIP_LINE | x0:2 y0:2 x1:2 y1:2 | Y | Y | Y | Y | rendered |
| `R` | RIP_RECTANGLE | x0:2 y0:2 x1:2 y1:2 | Y | Y | Y | Y | rendered |
| `B` | RIP_BAR | x0:2 y0:2 x1:2 y1:2 | | Y | | | rendered |
| `C` | RIP_CIRCLE | x_center:2 y_center:2 radius:2 | | Y | | Y | rendered |
| `O` | RIP_OVAL | x:2 y:2 st_ang:2 end_ang:2 x_rad:2 y_rad:2 | | Y | | Y | rendered |
| `o` | RIP_FILLED_OVAL | x_center:2 y_center:2 x_rad:2 y_rad:2 | | Y | | Y | rendered |
| `A` | RIP_ARC | x:2 y:2 start_ang:2 end_ang:2 radius:2 | | Y | | Y | rendered |
| `V` | RIP_OVAL_ARC | x:2 y:2 st_ang:2 e_ang:2 radx:2 rady:2 | | Y | | Y | rendered |
| `I` | RIP_PIE_SLICE | x:2 y:2 start_ang:2 end_ang:2 radius:2 | | Y | | Y | rendered |
| `i` | RIP_OVAL_PIE_SLICE | x:2 y:2 st_ang:2 e_ang:2 radx:2 rady:2 | | Y | | Y | rendered |
| `Z` | RIP_BEZIER | x1:2 y1:2 x2:2 y2:2 x3:2 y3:2 x4:2 y4:2 cnt:2 | Y | Y | Y | Y | rendered |
| `P` | RIP_POLYGON | npoints:2 (x:2 y:2) x npoints | Y | Y | Y | Y | rendered |
| `p` | RIP_FILL_POLYGON | npoints:2 (x:2 y:2) x npoints | Y (outline) | Y | Y | Y | rendered |
| `l` | RIP_POLYLINE (1.54) | npoints:2 (x:2 y:2) x npoints | Y | Y | Y | Y | rendered |
| `F` | RIP_FILL | x:2 y:2 border:2 | | Y | | | rendered |
| `=` | RIP_LINE_STYLE | style:2 user_pat:4 thick:2 | | | | | state |
| `S` | RIP_FILL_STYLE | pattern:2 color:2 | | | | | state |
| `s` | RIP_FILL_PATTERN | c1:2 ... c8:2 col:2 | | | | | state |
| `#` | RIP_NO_MORE | — | | | | | recorded |

Semantics worth noting:

* Angles are degrees, 0 = 3 o'clock, increasing counter-clockwise; drawing
  goes counter-clockwise from start to end. `0` to `360` is a full circle;
  equal angles draw nothing.
* RIP_RECTANGLE takes any two opposing corners; a degenerate rectangle is a
  single line. RIP_BAR fills with the fill pattern and draws no border.
* RIP_FILLED_OVAL / pie slices: interior in the fill color and pattern,
  outline in the drawing color and thickness (no line pattern).
* RIP_FILL_POLYGON fills with the even-odd rule; the fill does not use the
  write mode, the outline does. Polygons take 2...512 points.
* RIP_BEZIER draws `cnt` straight segments using double-precision
  arithmetic; segments use the line pattern, thickness and write mode
  (XOR leaves gaps where segments meet).
* RIP_FILL floods from `(x, y)` up to the `border` color; the border is not
  changed; if the seed pixel already is the border color nothing happens;
  an unenclosed fill stops at the viewport edges.
* RIP_TEXT and RIP_TEXT_XY leave the drawing position just after the text;
  other drawing commands (including RIP_LINE) do not move it.
* RIP_RESET_WINDOWS: full-screen text window (80x43) and viewport, cursor
  home, screen cleared to color 0, mouse regions and clipboard deleted,
  default palette restored.

### Level 1

| Cmd | Symbol | Arguments | VP | SwiftRIP |
|-----|--------|-----------|----|----------|
| `1M` | RIP_MOUSE | num:2 x0:2 y0:2 x1:2 y1:2 clk:1 clr:1 res:5 text | Y | recorded as a mouse region |
| `1K` | RIP_KILL_MOUSE_FIELDS | — | | clears mouse regions |
| `1T` | RIP_BEGIN_TEXT | x1:2 y1:2 x2:2 y2:2 res:2 | Y | rendered |
| `1t` | RIP_REGION_TEXT | justify:1 text | Y | rendered |
| `1E` | RIP_END_TEXT | — | Y | rendered |
| `1C` | RIP_GET_IMAGE | x0:2 y0:2 x1:2 y1:2 res:1 | Y | rendered (clipboard) |
| `1P` | RIP_PUT_IMAGE | x:2 y:2 mode:2 res:1 | Y | rendered |
| `1W` | RIP_WRITE_ICON | res:1 filename | | recorded |
| `1I` | RIP_LOAD_ICON | x:2 y:2 mode:2 clipboard:1 res:2 filename | Y | recorded (no icon loading) |
| `1B` | RIP_BUTTON_STYLE | wid:2 hgt:2 orient:2 flags:4 size:2 dfore:2 dback:2 bright:2 dark:2 surface:2 grp_no:2 flags2:2 uline_col:2 corner_col:2 res:6 | | state |
| `1U` | RIP_BUTTON | x0:2 y0:2 x1:2 y1:2 hotkey:2 flags:1 res:1 text | Y | partially rendered (§9) |
| `1D` | RIP_DEFINE | flags:3 res:2 text | | recorded |
| `1`ESC | RIP_QUERY | mode:1 res:3 text | | recorded |
| `1G` | RIP_COPY_REGION | x0:2 y0:2 x1:2 y1:2 res:2 dest_line:2 | no (absolute) | rendered |
| `1R` | RIP_READ_SCENE | res:8 filename | | recorded |
| `1F` | RIP_FILE_QUERY | mode:2 res:4 filename | | recorded |

* **RIP_MOUSE**: `num` is obsolete (00); `clk` 1 inverts the region while
  pressed; `clr` 1 zooms the text window to full screen and clears it;
  `res` must be `00000`; the text is the host command (`^M` notation for
  control characters). The region must be given upper-left / lower-right
  and is stored in global (absolute) coordinates. Regions are scanned last
  in, first out; at most 128 mouse fields and mouse buttons combined.
* **RIP_BEGIN_TEXT / REGION_TEXT / END_TEXT**: lines are pre-wrapped by the
  host; each line is drawn below the previous one; a line that falls off
  the bottom is discarded (no scrolling); font direction is ignored
  (always horizontal); `justify` 1 pads the gaps between words so the line
  reaches both margins.
* **RIP_GET_IMAGE**: upper-left / lower-right corners; invalid coordinates
  ignore the command; the clipboard is replaced.
* **RIP_PUT_IMAGE / RIP_LOAD_ICON modes**: 0 copy, 1 XOR, 2 OR, 3 AND,
  4 NOT (paste the inverse). PUT_IMAGE is ignored if the image's right edge
  would be off screen. LOAD_ICON's `res` should be `10`; a missing `.ICN`
  extension is appended; `clipboard` 1 also copies the icon to the
  clipboard; a load failure should display a box.
* **RIP_COPY_REGION**: copies rows `y0...y1` to scan line `dest_line`
  (vertical moves only). X0 is rounded down and X1 up to 8-pixel
  boundaries ("X0=14, X1=38 become 8 and 40"). The destination may overlap
  but not start on the same line; if it would be partially off-screen the
  command is ignored. The source is not cleared.
* **RIP_DEFINE** text: `identifier[,width]:[?question?][default]`; flags 1
  save to database, 2 no blank response, 4 non-interactive.
* **RIP_QUERY** modes: 0 process now, 1 on a graphics-window click, 2 on a
  text-window click; `$OFF$` cancels a deferred query.
* **RIP_READ_SCENE** must be the last command on its line.
* **RIP_FILE_QUERY** modes 0...4 select the reply (`0`/`1`, with CR, with
  size, with size/date/time, with name/size/date/time).

### Level 9

| Cmd | Symbol | Arguments | SwiftRIP |
|-----|--------|-----------|----------|
| `9`ESC | RIP_ENTER_BLOCK_MODE | mode:1 proto:1 file_type:2 res:4 [filename] `<>` | recorded |

`mode` 0 download, 1 upload. `proto`: 0 Xmodem checksum, 1 Xmodem CRC,
2 Xmodem-1K, 3 Xmodem-1K (G), 4 Kermit (these need a filename), 5 Ymodem
batch, 6 Ymodem-G, 7 Zmodem. `file_type`: 0 RIP display, 1 RIP store,
2 ICN store, 3 HLP store, 4 composite dynamic, 5 active dynamic. The
command always ends with `<>` and must be the last command on its line.

## 7. Fill patterns and line styles

`S` patterns (row bytes, top row first, MSB = leftmost pixel). Set bits
use the fill color; clear bits use the background color 0. Pattern 0
fills with the background color.

| # | Name | Rows (hex) |
|--:|------|-----------|
| 0 | Background | 00 00 00 00 00 00 00 00 |
| 1 | Solid | FF FF FF FF FF FF FF FF |
| 2 | Line | FF FF 00 00 FF FF 00 00 |
| 3 | Light slash | 01 02 04 08 10 20 40 80 |
| 4 | Normal slash | E0 C1 83 07 0E 1C 38 70 |
| 5 | Normal backslash | F0 78 3C 1E 0F 87 C3 E1 |
| 6 | Light backslash | A5 D2 69 B4 5A 2D 96 4B |
| 7 | Light hatch | FF 88 88 88 FF 88 88 88 |
| 8 | Heavy cross hatch | 81 42 24 18 18 24 42 81 |
| 9 | Interleaving line | CC 33 CC 33 CC 33 CC 33 |
| 10 | Widely spaced dot | 80 00 08 00 80 00 08 00 |
| 11 | Closely spaced dot | 88 00 22 00 88 00 22 00 |

`s` (RIP_FILL_PATTERN) supplies eight such rows plus the fill color and
overrides `S` (and vice versa). Patterns are aligned to the screen grid.

`=` line styles (16-bit masks, MSB at the line's start point): 0 solid
`FFFF`, 1 dotted `3333`, 2 centered `1E3F`, 3 dashed `1F1F`, 4 custom
(`user_pat`, a 4-digit MegaNum). Thickness is 1 or 3 pixels. Circles,
ovals, arcs and pie slices use the thickness but never the pattern.

## 8. Fonts

| # | Font | Kind |
|--:|------|------|
| 0 | Default 8x8 | bitmap |
| 1 | Triplex | stroke |
| 2 | Small | stroke |
| 3 | Sans Serif | stroke |
| 4 | Gothic (Old English) | stroke |
| 5 | Script | stroke |
| 6 | Simplex | stroke |
| 7 | Triplex Script | stroke |
| 8 | Complex | stroke |
| 9 | European | stroke |
| 10 | Bold | stroke |

Direction 0 is horizontal, 1 vertical. Size 1 is normal, 2...10 magnify
(the bitmap font enlarges its pixels). The spec's RIP_BUTTON_STYLE section
tabulates per-font, per-size metrics (top / bow / base / drop scan lines)
and a 256-entry descender table used for label centring. These are BGI
fonts; SwiftRIP renders clean-room approximations (§12).

## 9. Buttons

`1B` fields: `wid`/`hgt` (fixed size of plain buttons; both 0 = size taken
from RIP_BUTTON's corners), `orient` (label 0 above, 1 left, 2 center,
3 right, 4 below), `flags`, `size` (bevel thickness), `dfore` (label),
`dback` (label drop shadow), `bright` / `dark` / `surface` (effects and
plain surface), `grp_no` (0...35, radio / check-box group and template
number), `flags2`, `uline_col`, `corner_col`, `res:6`.

`flags`: 1 clipboard button, 2 invertable, 4 reset screen after click,
8 chisel, 16 recessed, 32 drop-shadow label, 64 auto-stamp onto clipboard,
128 icon button, 256 plain button, 512 bevel, 1024 mouse button,
2048 underline hot key, 4096 hot icons (`.HIC`), 8192 adjust vertical
centring, 16384 radio group, 32768 sunken.

`flags2`: 1 check-box group, 2 highlight hot key, 4 explode, 8 left-justify
label, 16 right-justify label (indent 10 pixels, 20 with chisel).

Effects: bevel draws `size` pixels outside the image (x0/y0 -size,
x1/y1 +size); recessed draws a black one-pixel outline plus an inverted
one-pixel bevel outside everything (-2/+2, never part of the image);
sunken draws an inverted one-pixel bevel one pixel inside the image;
chisel draws a drop-shadowed line inside the image at an inset taken from
this table:

| Button height | X inset | Y inset |
|--------------:|--------:|--------:|
| 0-11 | 1 | 1 |
| 12-24 | 3 | 2 |
| 25-39 | 4 | 3 |
| 40-74 | 6 | 5 |
| 75-149 | 7 | 5 |
| 150-199 | 8 | 6 |
| 200-249 | 10 | 7 |
| 250-299 | 11 | 8 |
| 300- | 13 | 9 |

`1U` arguments: upper-left `x0,y0`; `x1,y1` only for dynamically sized
plain buttons; `hotkey` ASCII code (255 = any key); `flags` 1 selected,
2 default; `res` 0. The text is `[icon-file][<>label][<>host-command]`
(any block may be empty, e.g. `<>label`, `<><>host`). Host commands can be
split into blocks with `[]`, define templates `[5:]...`, feed templates
`[0372]...` (see `ripscrip-1.54-template.txt`).

## 10. Mouse regions and host commands

Host commands (RIP_MOUSE text, button host-command block, RIP_QUERY) may
contain control characters as `^X` or `` `X `` (`^M` carriage return,
`^[` escape...), text variables `$NAME$` (built-in values such as `$DATE$`,
active variables such as `$BEEP$`, user variables created with
RIP_DEFINE), local playback `$>FILE.RIP$`, pop-up pick lists
`((question::choice@description,...))` and templates. These are terminal
behaviours with no rendering effect; SwiftRIP preserves the text verbatim.

## 11. Icon (.ICN) files

Identical to the Borland BGI `getimage()` buffer:

* Header: `width - 1` and `height - 1` as 16-bit little-endian integers.
* For each scan line: one monochrome row per bit plane, in the order
  plane 3, plane 2, plane 1, plane 0; each row is `ceil(width / 8)` bytes,
  MSB = leftmost pixel, padded with zero bits.
* One trailing "trash" byte of undefined value.

Spec example: a 6x2 image with pixels `00 01 02 04 08 0F / 03 05 08 03 02
01` is `05 00 01 00 | 0C 14 24 44 | 20 40 98 C4 | 00`.

SwiftRIP does not read or write `.ICN` files.

## 12. Implementation decisions and spec errata

* **Palette table typo.** The RIP_SET_PALETTE / RIP_ONE_PALETTE tables give
  Brown as master value "7 (06)" and Light Gray as "20 (0K)". In the EGA
  colour model value 20 is brown and 7 is light gray, and the table's own
  color names only fit the standard EGA BIOS palette
  `{0,1,2,3,4,5,20,7,56,...,63}`; SwiftRIP uses that.
* **Examples with extra or missing digits.** The RIP_OVAL example
  (`1E1A18003G150Z`) lacks `!|O` and has two extra digits (ignored per
  rule 6); the RIP_BEGIN_TEXT example (`!|1T00110011`) omits `res:2`. A
  missing variable-width last parameter decodes as 0.
* **RIP_FILL_PATTERN example** `!|s11223344556677880F` has rows 259 and 296,
  which exceed 8 bits; SwiftRIP keeps the low 8 bits.
* **Out-of-range values** (the wire allows up to 1295 where the spec
  defines fewer values): colors use the low 4 bits, palette values the low
  6 bits; unknown fill patterns render solid, unknown line styles solid,
  thickness >= 3 is 3 and anything else 1; write modes other than 1 are
  copy; fonts > 10 fall back to 0; font size is clamped to 1...10; text
  window sizes > 4 use 8x8 cells; RIP_ONE_PALETTE with a color > 15 is
  ignored; polygons with fewer than 2 points draw nothing; Bezier counts
  <= 0 draw nothing.
* **`STX !|`** is accepted in addition to the spec's `STX |`.
* **Raw text and ANSI** outside RIPscrip lines is not rendered (no TTY
  emulation); RIP_ERASE_WINDOW / RIP_ERASE_EOL clear the text window's
  pixels.
* **Reset scope.** RIP_RESET_WINDOWS resets what the spec lists (windows,
  cursor, screen, mouse regions, clipboard, palette); drawing color, fill,
  line style, font and write mode are kept.
* **Work budget.** Every command is bounded by the screen area, but a
  script can repeat expensive commands. SwiftRIP stops after a configurable
  number of pixel writes (default 200 million, about 900 full-screen flood
  fills, roughly 1.5 s on Apple silicon) and reports truncation.

## 13. Licence terms

The specification's "USE OF THE RIPscrip LANGUAGE" section (verbatim):

> The RIPscrip language is made publicly available and is freely licensed
> by TeleGrafix Communications, Inc. By freely licensed, we mean that the
> language can be used in the creation of other products. It does not mean
> that RIPscrip is public domain. TeleGrafix maintains the copyright of the
> RIPscrip language.
>
> RIPscrip, RIPaint, RIPdraw, and RIPterm are trademarks of TeleGrafix
> Communications, Inc. If you make a product that uses RIPscrip, you must
> state in your program's "About Box" and documentation that this product
> uses RIPscrip and the trademark statement. You may not use RIPterm,
> RIPaint, RIPdraw, or RIPterm in the name of your product.

SwiftRIP's README carries the required statement; no SwiftRIP name or
symbol uses a TeleGrafix product name.
