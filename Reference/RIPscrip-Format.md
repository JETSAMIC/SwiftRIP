# RIPscrip 1.54 Format Specification

The authoritative SwiftRIP reference for the TeleGrafix **RIPscrip** graphics
protocol, revision 1.54 (July 19th, 1993), with the RIPscrip 1.53 differences
and the RIPscrip 1.54 "template" companion document folded in. It restates the
original documents in a reader/renderer-oriented form, adds the byte-level
detail, algorithms and de-facto behaviour the originals leave implicit, and
lists every error found in them (§8).

The original texts are archived verbatim in the JETSAMIC `specs` repository:
`art/ripscrip-1.54.txt`, `art/ripscrip-1.54-template.txt` and the Markdown
transcription `art/ripscrip-1.53.md`. Where this document and the original
disagree, §8 explains why.

> **Revision history of this document.**
> *2026-11 (b)* — restructured into the full JETSAMIC spec layout: per-command
> field tables with state use/change, complete enumeration tables (fill
> pattern bitmaps, the 64-colour EGA table, font files and metrics, descender
> table), algorithms for tokenizing, rendering, buttons, host commands and
> templates, `.ICN` encode/decode, robustness guidance and a full errata list
> (including a wrong byte in the 1.54 `.ICN` example that the previous
> revision of this document repeated).
> *2026-11 (a)* — rewritten from the 1.54 text, replacing an earlier document
> that described a format that is not RIPscrip (3-digit coordinates, missing
> `|` delimiters, invented command letters; see §8.4).

## Contents

1. [Overview](#1-overview)
2. [Conventions](#2-conventions)
3. [Wire format and command layouts](#3-wire-format-and-command-layouts)
4. [Enumerations, flags and tables](#4-enumerations-flags-and-tables)
5. [Algorithms](#5-algorithms)
6. [Semantics and de-facto behaviour](#6-semantics-and-de-facto-behaviour)
7. [Robustness guidance for readers](#7-robustness-guidance-for-readers)
8. [Errata](#8-errata)
9. [Implementation status](#9-implementation-status)
10. [References, attribution and provenance](#10-references-attribution-and-provenance)

---

## 1. Overview

### 1.1 What RIPscrip is

RIPscrip ("Remote Imaging Protocol Script") is a compact, 7-bit ASCII vector
graphics language that a bulletin-board host interleaves with ordinary
ASCII/ANSI text. A RIPscrip-aware terminal recognises RIPscrip lines, executes
their commands against a 640x350, 16-colour EGA-style screen, and routes all
other bytes to a TTY text window with ANSI emulation. Besides drawing
primitives the language defines a clipboard, disk icons, clickable mouse
regions and buttons, formatted text regions, terminal-side text variables, a
host-command "template" system and auto-started file transfers.

The graphics model is that of Borland's BGI (Borland Graphics Interface): the
fill patterns, line styles, write modes, the eleven fonts, the image format and
the `putimage` combine modes are BGI's, and the 1.54 text describes `.ICN`
files as identical to BGI `getimage()` buffers.

### 1.2 History and versions

| Revision | Date | Notes |
|----------|------|-------|
| 1.0x | 1992–1993 | Early releases; `RIP_MOUSE`'s `num` field was meaningful ("used in the older RIPscrip v1.0"), obsolete since. No archived text. |
| 1.53.00 | May 12th, 1993 | Archived as `art/ripscrip-1.53.md`. Version reply `RIPSCRIPxxyyzz` (zz = revision). Pick-list length limit raised from 256 to 1024 bytes ("> v1.53" marks). |
| **1.54** | **July 19th, 1993** | Archived as `art/ripscrip-1.54.txt` (+ template document). Adds `l` RIP_POLYLINE, the per-command "Uses Viewport" rule, vendor codes in the version reply, the 128-region limit and last-in-first-out scan order, button-style flag tables, font metric and descender tables, chisel table, fill-pattern bitmaps, the "seed pixel equals border" fill rule, syntax rule 13 (trailing backslashes), the `.ICN` file layout and many text variables. Change marks `> v1.54` in the right margin. |

TeleGrafix later published RIPscrip 2.x and 3.x, which add commands,
resolutions and colour depths. They are out of scope; a 1.54 reader treats
their unknown commands as unknown (§6.13).

### 1.3 Programs

* **TeleGrafix Communications, Inc.** (Huntington Beach, California): RIPterm
  (terminal, vendor code 1), RIPaint and RIPdraw (scene editors), and the
  RIP2C / RIP2PAS host development libraries named in the 1.54 introduction.
* **Mustang Software**: Qmodem Pro (vendor code 2).
* BBS host software of the period emitted RIPscrip menus; TeleGrafix's own
  support board, ArenaBBS, ran The Major BBS (1.54 contact block).

### 1.4 Telling versions apart

A `.RIP` file carries **no signature and no version field**. Version
information exists only on a live connection:

* The host sends `ESC [ !` (§3.10). A 1.54 terminal answers
  `RIPSCRIP` + major (2 digits) + minor (2 digits) + vendor code (1 digit) +
  vendor sub-version (1 digit), e.g. `RIPSCRIP015410` for RIPterm 1.54. A 1.53
  terminal answers `RIPSCRIP` + major + minor + revision (2 digits), e.g.
  `RIPSCRIP015300`.
* The text variable `$RIPVER$` returns the same string.

Content can only be dated by the commands it uses: `l` RIP_POLYLINE is 1.54;
everything else in this document except the items listed for 1.54 in §1.2
already existed in 1.53.

**Sniffing.** A stream is likely RIPscrip if a physical line starts with `!|`
followed by a command character from §3.6 (common scene openers are `!|*`,
`!|1K`, `!|e`, `!|v`, `!|w`), or if it contains `SOH |` / `STX |`.

### 1.5 File types

| Extension / name | Content |
|------------------|---------|
| `.RIP` | RIPscrip scene: text with RIPscrip lines (this document). |
| `.ICN` | Icon: BGI image buffer (§3.11). Used by RIP_LOAD_ICON, RIP_WRITE_ICON, icon buttons. |
| `.HIC` | "Hot icon": the pressed image of an icon button, same format as `.ICN` (button flag 4096). |
| `.HLP` | Help file delivered by block transfer type 3. Format not documented. |
| `RIPTERM.SAV`, `RIPTERM0.SAV`…`RIPTERM9.SAV` | RIPterm screen saves (`$SAVE$`, `$SAVEn$`). Private format. |
| `RIPCLIB.BRD` | RIPterm clipboard save (`$SCB$`). Private format. |

No MIME type or Uniform Type Identifier was ever registered; files are
commonly served as `text/plain` or `application/octet-stream`.

---

## 2. Conventions

### 2.1 Characters and line breaks

* RIPscrip commands use printable 7-bit ASCII only, so they survive X.25 and
  7-bit links. The exceptions are the start markers SOH (0x01) and STX
  (0x02) and the command character ESC (0x1B) of RIP_QUERY and
  RIP_ENTER_BLOCK_MODE.
* **Text arguments** (labels, file names, host commands) are bytes. On real
  systems bytes 0x80–0xFF are CP437 (IBM PC code page 437); the 1.54
  descender table (§4.5.3) is indexed by CP437 code. A reader should keep text
  arguments as raw bytes or decode them with a 1:1 byte mapping.
* Lines end with CR LF on DOS hosts. A reader should accept CR LF, LF and CR.
  A line break always ends a RIPscrip line unless it is a continuation
  (§3.3).

### 2.2 MegaNums

Every numeric argument is an unsigned integer in base 36 ("Hexa-Tri-Decimal",
nicknamed **MegaNum**) with digits `0`–`9` = 0–9 and `A`–`Z` = 10–35, most
significant digit first, left-padded with `0` to the argument's fixed width.
There is no sign, no separator and no terminator.

| Width | Range | Used by (1.54) |
|------:|-------|----------------|
| 1 | 0…35 | `wrap`, `size`, `clk`, `clr`, `justify`, `clipboard`, button `flags`, query `mode`, block `mode` / `proto`, several `res` |
| 2 | 0…1 295 | every coordinate, radius, angle, colour, palette value, count, style, mode and font field |
| 3 | 0…46 655 | RIP_DEFINE `flags`, RIP_QUERY `res` |
| 4 | 0…1 679 615 | RIP_LINE_STYLE `user_pat`, RIP_BUTTON_STYLE `flags`, RIP_FILE_QUERY / RIP_ENTER_BLOCK_MODE `res` |
| 5 | 0…60 466 175 | RIP_MOUSE `res` |
| 6 | 0…2 176 782 335 | RIP_BUTTON_STYLE `res` |
| 8 | 0…2 821 109 907 455 | RIP_READ_SCENE `res` |

Examples: `0F` = 15, `0K` = 20, `1K` = 56, `HR` = 639, `9P` = 349,
`ZZ` = 1295, `73` = 255, `0XPM` = 43690 (`AAAA` hex), `1BLC` = 61680
(`F0F0` hex). The original never says whether lower-case digits are valid;
writers must emit upper case, readers should accept both (§6.2).

### 2.3 Coordinates, angles and colours

* Graphics coordinates are EGA pixels: `x` 0…639 left to right, `y` 0…349 top
  to bottom, origin top-left, all rectangles inclusive.
* Commands that "use the viewport" take coordinates **relative to the
  viewport's upper-left corner** and are clipped to it (§5.4).
  RIP_COPY_REGION and the RIP_VIEWPORT command itself use absolute
  coordinates.
* Text-window coordinates are character cells, 0-based.
* Angles are whole degrees, 0 at three o'clock, increasing counter-clockwise
  (90 = twelve o'clock).
* A **colour** argument is an index 0…15 into the 16-entry active palette; a
  palette **value** is an index 0…63 into the 64-colour EGA master palette
  (§4.4). Colour 0 is the background colour.

### 2.4 Notation in this document

* `Off` is the 0-based character offset of a field counted from the first
  character after the command character; `W` is its width in MegaNum digits;
  `text` marks the trailing text argument.
* `<ESC>` is byte 0x1B; `^M` is caret notation for a control character (here
  CR) as written inside host commands.
* Borland names (`COPY_PUT`, `SOLID_FILL`, `TRIPLEX_FONT`…) identify the BGI
  equivalent of a RIPscrip value.

### 2.5 Terminology

| Term | Meaning |
|------|---------|
| RIPscrip line | A logical line that starts with a start marker (§3.2) and contains one or more commands. |
| Command | Optional level digits, a command character and its arguments, introduced by `\|`. |
| Level | 0 when the character after `\|` is not `1`–`9`; otherwise the digits before the command character (`1`, `9`, sub-levels `15`, `123`…). |
| Viewport | The graphics window: an absolute inclusive pixel rectangle, or disabled. |
| Text window | The TTY window for non-RIPscrip text, in character cells, or invisible. |
| Drawing position | The BGI "current position" used by RIP_TEXT, relative to the viewport. |
| Clipboard | One stored image (RIP_GET_IMAGE, RIP_LOAD_ICON, button auto-stamp). |
| Mouse field / mouse button | A clickable rectangle from RIP_MOUSE / from a RIP_BUTTON with flag 1024; collectively "mouse regions". |
| Button group | 0…35; groups make radio or check-box sets and own one template each. |
| Host command | The text sent to the host when a region is clicked or a query runs; may contain control characters, text variables, pick lists and (buttons only) template blocks (§5.13). |
| Text variable | `$NAME$` placeholder expanded by the terminal (§4.12). |

---

## 3. Wire format and command layouts

### 3.1 Stream grammar

```abnf
stream        = *( rip-line / ansi-sense / text-byte )
rip-line      = start-marker command *( "|" command ) line-end
start-marker  = "!|"            ; only at the beginning of a physical line
              / %x01 "|"        ; SOH |, anywhere
              / %x02 "|"        ; STX |, anywhere
command       = level cmd-char arguments
level         = "" / %x31-39 *8DIGIT       ; 0 to 9 digits, first one 1-9
cmd-char      = %x21-2F / %x3A-7B / %x7D-7E  ; printable, not a digit or "|"
              / %x1B                       ; RIP_QUERY, RIP_ENTER_BLOCK_MODE
arguments     = *megadigit [ text ]         ; layout fixed per command
megadigit     = DIGIT / %x41-5A             ; (a-z tolerated, see 6.2)
text          = *( escaped / %x00-FF except "|" and line breaks )
escaped       = "\" ( "!" / "|" / "\" )
line-end      = CR LF / LF / CR / end-of-stream
ansi-sense    = %x1B "[" [ "0" / "1" / "2" ] "!"
```

The `|` that ends a start marker is also the first command delimiter, so
`!|c02|L02030405` holds two commands. Bytes that are not part of a RIPscrip
line or an auto-sense sequence are text for the TTY window.

### 3.2 Start markers, delimiters and levels (1.54 rules 1–4, 8–9, 12)

1. `!|` starts a RIPscrip line only in column 0. Elsewhere it is literal text;
   this stops users injecting graphics into chat or messages.
2. `SOH |` or `STX |` starts a RIPscrip line in any column. Hosts use this
   because users normally cannot type control characters.
3. Each command is introduced by `|`. A `|` inside a text argument must be
   written `\|`.
4. After `|`: if the next character is `1`–`9`, digits up to the first
   non-digit form the level (`1L` is level 1 command `L`, `15L` is level 1
   sub-level 5 command `L`, at most nine digits as in `123456789x`); otherwise
   that character is the level-0 command character. `!|L`, `!|1L` and `!|15L`
   are three different commands.
5. Commands are case-sensitive: `c`/`C`, `o`/`O`, `p`/`P`, `t`/`T` differ.

### 3.3 Escapes and line continuation (rules 5, 11, 13)

* In a text argument `\!` is `!`, `\|` is `|` and `\\` is `\`.
* A backslash immediately before a line break continues the RIPscrip line on
  the next physical line; the backslash and the line break are removed and
  nothing else is (leading spaces of the next line are content).
* A literal backslash at the end of a line is written `\\`; a literal
  backslash followed by a continuation is `\\\`. In general a run of *N*
  backslashes before a line break is *N* div 2 literal backslashes, plus a
  continuation if *N* is odd (algorithm in §5.2).

Rule 13 example: `!|@2233this is a text line with a literal \\\` + line break
+ `used in the message` draws "this is a text line with a literal \used in the
message" at MegaNum (22, 33) = (74, 111).

### 3.4 Argument decoding (rules 6 and 10)

* Numeric arguments follow the command character with no delimiters, each with
  the fixed width given below.
* A text argument is always last and runs to the next unescaped `|` or the end
  of the logical line.
* **Variable-width last parameter.** The last numeric parameter of a command
  without a text argument may be written with fewer digits than its width; the
  spec's own example `!|cA` is colour 10. Decode it from however many MegaNum
  digits are present. [decision] An entirely absent last parameter reads as 0,
  which the 1.54 RIP_BEGIN_TEXT example needs (E3).
* **Trailing text is ignored.** Characters after a command's arguments, up to
  the next `|`, are ignored and the command is still executed.
* Commands with no arguments (`*`, `e`, `E`, `H`, `>`, `#`, `1K`, `1E`) ignore
  anything after the command character.

### 3.5 State model

The "Uses"/"Changes" columns below refer to this state. Initial values are
those of a freshly initialised BGI screen (`graphdefaults()`), which is what a
terminal shows before the first RIP_RESET_WINDOWS; "Reset" is what
RIP_RESET_WINDOWS restores.

| State | Abbrev. | Initial value | Reset by `*` |
|-------|---------|---------------|--------------|
| Draw colour | DC | 15 | no |
| Line pattern (style + user mask) | LP | solid `FFFF` | no |
| Line thickness | LT | 1 | no |
| Fill colour | FC | 15 | no |
| Fill pattern | FP | 1 solid | no |
| Write mode | WM | copy | no |
| Font, direction, size | FS | 0, horizontal, 1 | no |
| Viewport | VP | (0,0)–(639,349) | yes, full screen |
| Drawing position | POS | (0,0) | no (unspecified) |
| Palette | PAL | default (§4.4) | yes |
| Text window | TW | (0,0)–(79,42), size 0, wrap 1 | yes, full 80x43 |
| Text cursor | TC | (0,0) | yes, home |
| Clipboard | CB | empty | yes, erased |
| Mouse regions | MR | none | yes, deleted |
| Button style | BS | none | no |
| Text region | TR | none | (SwiftRIP: yes) |
| Deferred query | DQ | none | unspecified |
| Templates 0…35, user variables | TPL, VAR | empty | no |

### 3.6 Command summary

Uses-flags are copied from the 1.54 per-command headers (Y = "YES"); the
"Changes" column is derived from the command descriptions.

| Cmd | Symbol | Argument widths | Digits | DC | LP | LT | FC | FP | WM | FS | VP | Changes |
|-----|--------|-----------------|-------:|----|----|----|----|----|----|----|----|---------|
| `w` | RIP_TEXT_WINDOW | 2 2 2 2 1 1 | 10 | | | | | | | | | TW, TC |
| `v` | RIP_VIEWPORT | 2 2 2 2 | 8 | | | | | | | | | VP |
| `*` | RIP_RESET_WINDOWS | — | 0 | | | | | | | | | screen, VP, TW, TC, PAL, CB, MR |
| `e` | RIP_ERASE_WINDOW | — | 0 | | | | | | | | | screen, TC |
| `E` | RIP_ERASE_VIEW | — | 0 | | | | | | | | | screen |
| `g` | RIP_GOTOXY | 2 2 | 4 | | | | | | | | | TC |
| `H` | RIP_HOME | — | 0 | | | | | | | | | TC |
| `>` | RIP_ERASE_EOL | — | 0 | | | | | | | | | screen |
| `c` | RIP_COLOR | 2 | 2 | Y | | | | | | | | DC |
| `Q` | RIP_SET_PALETTE | 2 ×16 | 32 | Y | | | | | | | | PAL |
| `a` | RIP_ONE_PALETTE | 2 2 | 4 | Y | | | | | | | | PAL |
| `W` | RIP_WRITE_MODE | 2 | 2 | | | | | | Y | | | WM |
| `m` | RIP_MOVE | 2 2 | 4 | | | | | | | | Y | POS |
| `T` | RIP_TEXT | text | — | Y | | | | | Y | Y | Y | screen, POS |
| `@` | RIP_TEXT_XY | 2 2 text | 4+ | Y | | | | | Y | Y | Y | screen, POS |
| `Y` | RIP_FONT_STYLE | 2 2 2 2 | 8 | | | | | | | Y | | FS |
| `X` | RIP_PIXEL | 2 2 | 4 | Y | | | | | | | Y | screen |
| `L` | RIP_LINE | 2 2 2 2 | 8 | Y | Y | Y | | | Y | | Y | screen |
| `R` | RIP_RECTANGLE | 2 2 2 2 | 8 | Y | Y | Y | | | Y | | Y | screen |
| `B` | RIP_BAR | 2 2 2 2 | 8 | | | | Y | Y | | | Y | screen |
| `C` | RIP_CIRCLE | 2 2 2 | 6 | Y | | Y | | | | | Y | screen |
| `O` | RIP_OVAL | 2 2 2 2 2 2 | 12 | Y | | Y | | | | | Y | screen |
| `o` | RIP_FILLED_OVAL | 2 2 2 2 | 8 | Y | | Y | Y | Y | | | Y | screen |
| `A` | RIP_ARC | 2 2 2 2 2 | 10 | Y | | Y | | | | | Y | screen |
| `V` | RIP_OVAL_ARC | 2 2 2 2 2 2 | 12 | Y | | Y | | | | | Y | screen |
| `I` | RIP_PIE_SLICE | 2 2 2 2 2 | 10 | Y | | Y | Y | Y | | | Y | screen |
| `i` | RIP_OVAL_PIE_SLICE | 2 2 2 2 2 2 | 12 | Y | | Y | Y | Y | | | Y | screen |
| `Z` | RIP_BEZIER | 2 ×9 | 18 | Y | Y | Y | | | Y | | Y | screen |
| `P` | RIP_POLYGON | 2 + 4n | 2+4n | Y | Y | Y | | | Y | | Y | screen |
| `p` | RIP_FILL_POLYGON | 2 + 4n | 2+4n | Y | Y | Y | Y | Y | Y | | Y | screen |
| `l` | RIP_POLYLINE (1.54) | 2 + 4n | 2+4n | Y | Y | Y | | | Y | | Y | screen |
| `F` | RIP_FILL | 2 2 2 | 6 | | | | Y | Y | | | Y | screen |
| `=` | RIP_LINE_STYLE | 2 4 2 | 8 | | Y | Y | | | | | | LP, LT |
| `S` | RIP_FILL_STYLE | 2 2 | 4 | | | | Y | Y | | | | FP, FC |
| `s` | RIP_FILL_PATTERN | 2 ×9 | 18 | | | | Y | Y | | | | FP, FC |
| `#` | RIP_NO_MORE | — | 0 | | | | | | | | | — |
| `1M` | RIP_MOUSE | 2 2 2 2 2 1 1 5 text | 17+ | | | | | | | | Y | MR |
| `1K` | RIP_KILL_MOUSE_FIELDS | — | 0 | | | | | | | | | MR |
| `1T` | RIP_BEGIN_TEXT | 2 2 2 2 2 | 10 | | | | | | | | Y | TR |
| `1t` | RIP_REGION_TEXT | 1 text | 1+ | Y | | | | | Y | Y | Y | screen, TR |
| `1E` | RIP_END_TEXT | — | 0 | | | | | | | | Y | TR |
| `1C` | RIP_GET_IMAGE | 2 2 2 2 1 | 9 | | | | | | | | Y | CB |
| `1P` | RIP_PUT_IMAGE | 2 2 2 1 | 7 | | | | | | | | Y | screen |
| `1W` | RIP_WRITE_ICON | 1 text | 1+ | | | | | | | | | disk |
| `1I` | RIP_LOAD_ICON | 2 2 2 1 2 text | 9+ | | | | | | | | Y | screen, CB |
| `1B` | RIP_BUTTON_STYLE | 2 2 2 4 2 2 2 2 2 2 2 2 2 2 6 | 36 | | | | | | | | | BS |
| `1U` | RIP_BUTTON | 2 2 2 2 2 1 1 text | 12+ | | | | | | | Y | Y | screen, MR, CB, BS, TPL |
| `1D` | RIP_DEFINE | 3 2 text | 5+ | | | | | | | | | VAR |
| `1<ESC>` | RIP_QUERY | 1 3 text | 4+ | | | | | | | | | DQ, host |
| `1G` | RIP_COPY_REGION | 2 2 2 2 2 2 | 12 | | | | | | | | (no) | screen |
| `1R` | RIP_READ_SCENE | 8 text | 8+ | Y | Y | Y | Y | Y | Y | Y | | everything (§3.8) |
| `1F` | RIP_FILE_QUERY | 2 4 text | 6+ | | | | | | | | | host |
| `9<ESC>` | RIP_ENTER_BLOCK_MODE | 1 1 2 4 text `<>` | 8+ | | | | | | | | | link |

### 3.7 Level 0 commands

Every coordinate field below is a 2-digit MegaNum (0…1295); only 0…639 / 0…349
are on screen.

#### `w` RIP_TEXT_WINDOW — define the TTY text window

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x0 | left column (inclusive) |
| 2 | 2 | y0 | top row (inclusive) |
| 4 | 2 | x1 | right column (inclusive) |
| 6 | 2 | y1 | bottom row (inclusive) |
| 8 | 1 | wrap | 1: wrap at the right margin and scroll; 0: truncate at the right margin, no scrolling, cursor stays at the margin |
| 9 | 1 | size | cell font 0…4 (§4.6) |

Example `!|w00001B0M10` = columns 0–47, rows 0–22, wrap, 8x8 cells.
All four corners zero makes the window invisible: non-RIPscrip bytes are
discarded. Redefining a window identical in `x0 y0 x1 y1 size` (wrap may
differ) keeps the cursor; any other definition homes it. The text window and
the viewport may overlap.

#### `v` RIP_VIEWPORT — define the graphics viewport

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x0 | left, absolute pixels |
| 2 | 2 | y0 | top |
| 4 | 2 | x1 | right (inclusive) |
| 6 | 2 | y1 | bottom (inclusive) |

All zero disables the viewport: every command whose VP flag is Y is parsed and
ignored. Otherwise `x0 < x1` and `y0 < y1` are required. Output of viewport
commands is clipped to the rectangle and their coordinates are relative to
`(x0, y0)` (§5.4).

#### `*` RIP_RESET_WINDOWS — reset to full screen

No arguments. Sets the text window to 80x43 (size 0), homes the text cursor,
sets the viewport to (0,0)–(639,349), clears the whole screen to colour 0,
deletes all mouse fields and mouse buttons, erases the clipboard and restores
the default palette. Drawing attributes (DC, LP, LT, FC, FP, WM, FS) and the
button style are not mentioned and are kept (§6.4).

#### `e` RIP_ERASE_WINDOW — clear the text window

No arguments. Fills the text window's pixels with colour 0 (also where it
overlaps the viewport) and homes the cursor. Ignored when the text window is
invisible.

#### `E` RIP_ERASE_VIEW — clear the viewport

No arguments. Fills the viewport with colour 0 (also where it overlaps the text
window). Ignored when the viewport is disabled. Does not move POS.

#### `g` RIP_GOTOXY — move the text cursor

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | column, 0-based, relative to the text window |
| 2 | 2 | y | row, 0-based |

Equivalent to ANSI `ESC [ y+1 ; x+1 H`. Ignored when the text window is
invisible. Moves the text cursor only, never POS.

#### `H` RIP_HOME — text cursor to the window's upper-left cell

No arguments. Only meaningful when the text window is active.

#### `>` RIP_ERASE_EOL — erase to end of text line

No arguments. Clears from the text cursor (inclusive) to the right edge of the
text window on the cursor's row, in colour 0 (unlike ANSI `ESC[K`, which uses
the ANSI background colour).

#### `c` RIP_COLOR — set the drawing colour

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | color | palette index 0…15 (variable width: `!\|cA` = 10) |

Sets DC: the colour of lines, outlines, arcs, pixels and RIPscrip text (not ANSI
text). Does not affect fills.

#### `Q` RIP_SET_PALETTE — set all 16 palette entries

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0, 2, …, 30 | 2 each | c1…c16 | master value 0…63 for palette entries 0…15 |

Already-drawn pixels change colour immediately (palette cycling). Example
`!|Q000102030405060708090A0B0C0D0E0F` maps entry *n* to master value *n*.

#### `a` RIP_ONE_PALETTE — set one palette entry

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | color | palette entry 0…15 |
| 2 | 2 | value | master value 0…63 |

Example `!|a051B` sets entry 5 to master value 47.

#### `W` RIP_WRITE_MODE — set the write mode

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | mode | 0 copy (`COPY_PUT`), 1 XOR (`XOR_PUT`) — §4.1 |

#### `m` RIP_MOVE — set the drawing position

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | viewport-relative |
| 2 | 2 | y | viewport-relative |

Sets POS without drawing (BGI `moveto`). VP = Y: ignored while the viewport is
disabled.

#### `T` RIP_TEXT — draw text at the drawing position

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | — | text | characters to draw (escapes removed) |

Draws in DC with the current font, direction and size and the write mode; POS
is the text's upper-left corner (BGI `LEFT_TEXT`/`TOP_TEXT` justification).
Afterwards POS is just right of the last character, so a following `T`
continues the text. Other drawing commands never move POS.

#### `@` RIP_TEXT_XY — draw text at a position

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | viewport-relative |
| 2 | 2 | y | viewport-relative |
| 4 | — | text | characters to draw |

RIP_MOVE followed by RIP_TEXT; leaves POS after the text.

#### `Y` RIP_FONT_STYLE — select font, direction and size

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | font | 0…10 (§4.5) |
| 2 | 2 | direction | 0 horizontal, 1 vertical (rotated 90° counter-clockwise) |
| 4 | 2 | size | 1 normal … 10 (×10 for font 0) |
| 6 | 2 | res | reserved, 0 |

Example `!|Y01000400` = Triplex, horizontal, size 4.

#### `X` RIP_PIXEL — plot one pixel

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | viewport-relative |
| 2 | 2 | y | viewport-relative |

Plots DC. WM = no: always copy.

#### `L` RIP_LINE — draw a line

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x0 | start |
| 2 | 2 | y0 | |
| 4 | 2 | x1 | end |
| 6 | 2 | y1 | |

DC, line pattern (most significant bit at the start point), thickness and
write mode. Does not move POS.

#### `R` RIP_RECTANGLE — draw a rectangle outline

Fields as RIP_LINE: any two opposite corners. If `x0 = x1` or `y0 = y1` a single
line is drawn. Not filled. Uses DC, LP, LT, WM.

#### `B` RIP_BAR — fill a rectangle

Fields as RIP_LINE (opposite corners). Fills with FC and FP; draws no border.
WM = no.

#### `C` RIP_CIRCLE — circle outline

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x_center | |
| 2 | 2 | y_center | |
| 4 | 2 | radius | horizontal radius in pixels |

Aspect-corrected so the circle looks round on a 4:3 display (§5.7). DC and
thickness; never the line pattern; copy mode.

#### `O` RIP_OVAL — elliptical arc

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | centre |
| 2 | 2 | y | centre |
| 4 | 2 | st_ang | start angle, degrees |
| 6 | 2 | end_ang | end angle, degrees |
| 8 | 2 | x_rad | horizontal radius (half the width) |
| 10 | 2 | y_rad | vertical radius (half the height) |

Counter-clockwise from `st_ang` to `end_ang`; 0 and 360 give a full ellipse.
DC and thickness, no pattern, no aspect correction. Identical in effect to
RIP_OVAL_ARC.

#### `o` RIP_FILLED_OVAL — filled ellipse

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x_center | |
| 2 | 2 | y_center | |
| 4 | 2 | x_rad | |
| 6 | 2 | y_rad | |

Interior in FC/FP, outline in DC with thickness (no pattern).

#### `A` RIP_ARC — circular arc

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | centre |
| 2 | 2 | y | centre |
| 4 | 2 | start_ang | |
| 6 | 2 | end_ang | |
| 8 | 2 | radius | |

Counter-clockwise from start to end; `0`→`360` is a full circle; equal angles
draw nothing. Aspect-corrected like RIP_CIRCLE; thickness, no pattern.

#### `V` RIP_OVAL_ARC — elliptical arc

Fields as RIP_OVAL (`x y st_ang e_ang radx rady`). No aspect correction.

#### `I` RIP_PIE_SLICE — filled circular sector

Fields as RIP_ARC. The arc's end points are joined to the centre with two
straight lines; the interior is filled with FC/FP and the outline drawn in DC
with thickness (no pattern). Aspect-corrected.

#### `i` RIP_OVAL_PIE_SLICE — filled elliptical sector

Fields as RIP_OVAL_ARC; otherwise as RIP_PIE_SLICE, without aspect correction.

#### `Z` RIP_BEZIER — cubic Bezier curve

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x1 | start point (on the curve) |
| 2 | 2 | y1 | |
| 4 | 2 | x2 | first control point (pulls the curve) |
| 6 | 2 | y2 | |
| 8 | 2 | x3 | second control point |
| 10 | 2 | y3 | |
| 12 | 2 | x4 | end point (on the curve) |
| 14 | 2 | y4 | |
| 16 | 2 | cnt | number of straight segments |

Drawn as `cnt` line segments (§5.8) with DC, LP, LT and WM; computed in double
precision. In XOR mode the shared end points of consecutive segments cancel,
leaving gaps (documented behaviour).

#### `P` RIP_POLYGON, `p` RIP_FILL_POLYGON, `l` RIP_POLYLINE

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | npoints | 2…512 |
| 2 + 4k | 2 | x(k+1) | vertex k+1, k = 0…npoints-1 |
| 4 + 4k | 2 | y(k+1) | |

* `P`: closed outline (the last vertex joins the first automatically), DC, LP,
  LT, WM; not filled.
* `p`: the same outline plus an interior filled with FC/FP by the **even-odd
  rule** (regions covered an even number of times stay unfilled). The fill
  ignores the write mode; the outline uses it.
* `l` (new in 1.54): open poly-line, the last vertex is not joined to the
  first.

Example `!|P03010105090905` = triangle (1,1) (5,9) (9,5).

#### `F` RIP_FILL — flood fill

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | seed point |
| 2 | 2 | y | |
| 4 | 2 | border | colour 0…15 that stops the fill |

Every pixel connected to the seed that is not the border colour is painted with
FC/FP; the border is unchanged. If the seed already has the border colour
nothing happens. An unenclosed fill stops at the viewport edges.

#### `=` RIP_LINE_STYLE — line pattern and thickness

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | style | 0…4 (§4.2) |
| 2 | 4 | user_pat | 16-bit custom pattern, used only when style = 4 |
| 6 | 2 | thick | 1 or 3 pixels |

Example `!|=01000001` = dotted, thin.

#### `S` RIP_FILL_STYLE — predefined fill pattern and colour

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | pattern | 0…11 (§4.3) |
| 2 | 2 | color | fill colour 0…15 |

Replaces any custom pattern. Set pattern bits take FC, clear bits colour 0;
pattern 0 fills entirely with colour 0.

#### `s` RIP_FILL_PATTERN — custom 8x8 fill pattern and colour

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0, 2, …, 14 | 2 each | c1…c8 | rows top to bottom; bit 7 = leftmost pixel; 0…255 |
| 16 | 2 | col | fill colour 0…15 |

Replaces any predefined pattern (BGI `setfillpattern`, `USER_FILL`).

#### `#` RIP_NO_MORE — end of RIPscrip data

No arguments. Tells the terminal that the scene is complete so it can enable
mouse regions and process queued clicks. Hosts should send it three or more
times for noise immunity; terminals should also assume it after a quiet
period (recommended at least one second after the last RIPscrip command; plain
text does not restart the timer).

### 3.8 Level 1 commands

#### `1M` RIP_MOUSE — define a mouse field

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | num | obsolete (RIPscrip 1.0 field number); write `00` |
| 2 | 2 | x0 | upper-left corner (must be upper-left), viewport-relative |
| 4 | 2 | y0 | |
| 6 | 2 | x1 | lower-right corner (must be lower-right) |
| 8 | 2 | y1 | |
| 10 | 1 | clk | 1: invert the region while the button is held |
| 11 | 1 | clr | 1: zoom the text window to full screen and clear it on click |
| 12 | 5 | res | reserved, `00000` |
| 17 | — | text | host command sent on a left click (§5.13) |

Example `!|1M00001122331100000host command^M`. The region is stored in
absolute screen coordinates, so it stays correct after the viewport changes.
Mouse fields and mouse buttons share one table of at most 128 entries and are
hit-tested most recent first.

#### `1K` RIP_KILL_MOUSE_FIELDS — delete all mouse regions

No arguments. Deletes mouse fields and mouse buttons; graphics stay. Scenes
should start with it.

#### `1T` RIP_BEGIN_TEXT — start a text region

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x1 | region left, viewport-relative |
| 2 | 2 | y1 | region top |
| 4 | 2 | x2 | region right |
| 6 | 2 | y2 | region bottom |
| 8 | 2 | res | reserved, `00` |

Must be followed by one or more RIP_REGION_TEXT and one RIP_END_TEXT.

#### `1t` RIP_REGION_TEXT — one line of region text

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 1 | justify | 0 left-aligned; 1 justified to both margins |
| 1 | — | text | one pre-wrapped line |

Each line is drawn below the previous one in DC with the current font, size and
write mode; the font direction is ignored (always horizontal). A line that
would fall below the region is discarded (no scrolling). The host does the word
wrapping. Justification: §5.10.

#### `1E` RIP_END_TEXT — end the text region

No arguments.

#### `1C` RIP_GET_IMAGE — copy a rectangle to the clipboard

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x0 | upper-left (must be), viewport-relative |
| 2 | 2 | y0 | |
| 4 | 2 | x1 | lower-right (must be) |
| 6 | 2 | y1 | |
| 8 | 1 | res | reserved, 0 |

Invalid coordinates make the command a no-op; otherwise the clipboard is
replaced.

#### `1P` RIP_PUT_IMAGE — paste the clipboard

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | upper-left of the paste, viewport-relative |
| 2 | 2 | y | |
| 4 | 2 | mode | 0 copy, 1 XOR, 2 OR, 3 AND, 4 NOT (§4.7) |
| 6 | 1 | res | reserved, 0 |

Ignored when the clipboard is empty or the image's right edge would be off
screen.

#### `1W` RIP_WRITE_ICON — save the clipboard as an icon file

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 1 | res | reserved, 0 |
| 1 | — | filename | no drive or path; an existing file is overwritten |

Writes the clipboard in `.ICN` format (§3.11). Ignored when the clipboard is
empty.

#### `1I` RIP_LOAD_ICON — draw an icon file

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x | upper-left, viewport-relative |
| 2 | 2 | y | |
| 4 | 2 | mode | as RIP_PUT_IMAGE |
| 6 | 1 | clipboard | 1: also copy the icon to the clipboard |
| 7 | 2 | res | reserved, **`10`** (unlike other reserved fields) |
| 9 | — | filename | no path; `.ICN` is appended when there is no extension |

Example `!|1I001101010button.icn`. Not drawn if it would go off screen. If the
file cannot be loaded, a box saying so should be drawn instead.

#### `1B` RIP_BUTTON_STYLE — define the button style

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | wid | fixed width of plain buttons; 0 with hgt 0 = sized by RIP_BUTTON |
| 2 | 2 | hgt | fixed height |
| 4 | 2 | orient | label position 0…4 (§4.8.1) |
| 6 | 4 | flags | flag word 1 (§4.8.2) |
| 10 | 2 | bevsize | bevel thickness in pixels (flag 512); named `size` in the header |
| 12 | 2 | dfore | label colour |
| 14 | 2 | dback | label drop-shadow colour (flag 32) |
| 16 | 2 | bright | highlight colour of effects |
| 18 | 2 | dark | shadow colour of effects |
| 20 | 2 | surface | plain-button surface colour |
| 22 | 2 | grp_no | button group 0…35 |
| 24 | 2 | flags2 | flag word 2 (§4.8.3) |
| 26 | 2 | uline_col | hot-key underline / highlight colour |
| 28 | 2 | corner_col | colour of bevel / recess corners |
| 30 | 6 | res | reserved, `000000` |

Example `!|1B0A0A010274030F080F080700010E07000000`: 10x10, label left, flags
2848 (underline hot key + bevel + plain + drop shadow), bevel 3, label white
on dark grey, bright white, dark dark grey, surface light grey, group 0,
check-box group, underline yellow, corners light grey. Draws nothing.

#### `1U` RIP_BUTTON — create a button

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x0 | upper-left of the base image, viewport-relative |
| 2 | 2 | y0 | |
| 4 | 2 | x1 | lower-right; only for dynamically sized plain buttons, else 0 |
| 6 | 2 | y1 | |
| 8 | 2 | hotkey | ASCII code that activates the button; 255 = any key |
| 10 | 1 | flags | 1 drawn selected, 2 default button (§4.8.4) |
| 11 | 1 | res | reserved, 0 |
| 12 | — | text | `[icon-file][<>label[<>host-command]]` (§3.12) |

Example `!|1U010100003200iconfile<>Label<>HostCmd^m` (hot key 110, `n`).
Rendering, effects and behaviour: §5.12. Mouse buttons (style flag 1024) count
against the 128-region limit; other buttons are unlimited.

#### `1D` RIP_DEFINE — define a text variable

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 3 | flags | 1 save to database, 2 non-blank, 4 non-interactive (§4.11) |
| 3 | 2 | res | reserved, `00` |
| 5 | — | text | `identifier[,width]:[?question?][default]` (§3.12) |

Example `!|1D00700text_var,60:?question?default data`.

#### `1<ESC>` RIP_QUERY — query text variables / send a host command

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 1 | mode | 0 now, 1 on a graphics-window click, 2 on a text-window click |
| 1 | 3 | res | reserved, `000` |
| 4 | — | text | host command (§5.13); `$OFF$` cancels a deferred query |

The command character is ESC so that users, who normally cannot type ESC,
cannot query another user's terminal. Modes 1 and 2 arm a deferred query that
runs on each click that does not hit a mouse region; in mode 2 coordinate
variables return text cells (2 digits) instead of pixels (4 digits).

#### `1G` RIP_COPY_REGION — copy screen rows vertically

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | x0 | left, **absolute** pixels |
| 2 | 2 | y0 | top |
| 4 | 2 | x1 | right |
| 6 | 2 | y1 | bottom |
| 8 | 2 | res | reserved |
| 10 | 2 | dest_line | destination scan line of the top row |

Copies rows `y0…y1` to start at `dest_line` (vertical only; the destination
may overlap the source but may not start on the same line). Columns are
widened to 8-pixel boundaries (§5.11). Ignored if the result would be partly
off screen. The source is not cleared. Not clipped to the viewport (may write
over the text window).

#### `1R` RIP_READ_SCENE — play a local `.RIP` file

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 8 | res | reserved, `00000000` |
| 8 | — | filename | local file |

Suspends the incoming stream, plays the file (which starts at a line
beginning), then resumes. State changed by the file persists. Must be the last
command on its line.

#### `1F` RIP_FILE_QUERY — ask whether a local file exists

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 2 | mode | reply format 0…4 (§4.13) |
| 2 | 4 | res | reserved, `0000` |
| 6 | — | filename | file to look for |

The terminal answers immediately.

### 3.9 Level 9

#### `9<ESC>` RIP_ENTER_BLOCK_MODE — start a file transfer

| Off | W | Name | Meaning |
|----:|--:|------|---------|
| 0 | 1 | mode | 0 download (host to terminal), 1 upload |
| 1 | 1 | proto | 0…7 (§4.14) |
| 2 | 2 | file_type | 0…5, ignored for uploads (§4.14) |
| 4 | 4 | res | reserved, `0000` |
| 8 | — | filename | optional for batch protocols, required otherwise |
| — | — | `<>` | mandatory terminator, also when there is no file name |

Examples: `!|9<ESC>01010000filename.icn<>` (download, Xmodem-CRC),
`!|9<ESC>07040000<>` (download, Zmodem, composite dynamic; see erratum
E13). Must be the last command on its line; the protocol starts on the next
line. A terminal with data security enabled asks before an upload; a refused
upload is answered with ten CAN (0x18) bytes at 0.1 s intervals.

### 3.10 ANSI auto-sense sequences

Sent by the host as ordinary (non-RIPscrip) data:

| Bytes | Meaning |
|-------|---------|
| `1B 5B 21` (`ESC [ !`) | Query version. Reply `RIPSCRIPxxyyvs` (§1.4); non-RIPscrip terminals ignore it. |
| `1B 5B 30 21` (`ESC [ 0 !`) | Same as `ESC [ !`. |
| `1B 5B 31 21` (`ESC [ 1 !`) | Disable RIPscrip: RIPscrip lines are shown as raw text. |
| `1B 5B 32 21` (`ESC [ 2 !`) | Enable RIPscrip processing. |

### 3.11 `.ICN` icon file layout

A BGI `getimage()` buffer for a 16-colour (4-plane) mode. All integers are
little-endian.

| Off | Size | Type | Name | Meaning |
|----:|-----:|------|------|---------|
| 0 | 2 | uint16 LE | width − 1 | image width minus one |
| 2 | 2 | uint16 LE | height − 1 | image height minus one |
| 4 | *h*·4·*b* | bytes | planes | for each row top to bottom: plane 3, plane 2, plane 1, plane 0, each *b* = ⌈*w*/8⌉ bytes |
| 4 + *h*·4·*b* | 1 | byte | trash | undefined, ignore on read, write 0 |

Within a plane row, bit 7 of the first byte is the leftmost pixel; padding bits
are "don't care" (write 0). Pixel colour = (p3·8) + (p2·4) + (p1·2) + p0, a
palette index. Total size = 5 + 4·*h*·⌈*w*/8⌉. The original notes that in
256-colour modes a row has eight planes; RIPscrip 1.54 only uses 16 colours.

Worked example (corrected, see E8): 6x2 pixels
`00 01 02 04 08 0F / 03 05 08 03 02 01` →
`05 00 01 00  0C 14 24 44  20 40 98 D4  00`.

### 3.12 Structured text arguments

**RIP_BUTTON text:** up to three blocks separated by the two characters `<>`:
`icon-file`, `label`, `host-command`. The delimiter is required between blocks
and not before the first; any block may be empty. All valid forms:
`icon<>label<>host`, `<>label<>host`, `icon<>label<>`, `icon<>label`,
`<><>host`, `<>label<>`, `<>label`, `icon<><>`, `icon<>`, `icon`, `<><><>`,
`<><>`, `<>`. A missing `.ICN` extension is appended to `icon-file`. Further
`<>` after the second delimiter belong to the host command. The host command
may be split into command blocks with `[...]` prefixes (§5.13.5).

**RIP_DEFINE text:** `identifier[,width]:[?question?][default]`

| Part | Rule |
|------|------|
| identifier | 1–12 characters `A–Z a–z 0–9 _`; must not start with a digit or `_` |
| `,width` | optional field width 1–60; default 60 |
| `:` | required; ends the identifier part (`NAME,width:` alone is valid) |
| `?question?` | optional prompt, delimited by `?` |
| default | optional default value: the rest of the text |

**RIP_ENTER_BLOCK_MODE text:** `[filename]<>`; anything after the first `<>`
is ignored.

---

## 4. Enumerations, flags and tables

Readers should accept any value of a field and apply §6.3 to values the
original does not define. "Reserved" fields should be written as stated and
ignored on read.

### 4.1 Write modes (`W`) and image modes (`1P`, `1I`)

| Value | `W` (lines, text) | `1P` / `1I` | BGI |
|------:|-------------------|-------------|-----|
| 0 | copy | copy | `COPY_PUT` |
| 1 | XOR (drawing twice erases) | XOR | `XOR_PUT` |
| 2 | — | OR | `OR_PUT` |
| 3 | — | AND | `AND_PUT` |
| 4 | — | NOT (paste the inverted image) | `NOT_PUT` |

### 4.2 Line styles and thickness (`=`)

| Style | Name (BGI) | 16-bit pattern | Binary |
|------:|------------|---------------:|--------|
| 0 | solid (`SOLID_LINE`) | `FFFF` | 1111111111111111 |
| 1 | dotted (`DOTTED_LINE`) | `3333` | 0011001100110011 |
| 2 | centred (`CENTER_LINE`) | `1E3F` | 0001111000111111 |
| 3 | dashed (`DASHED_LINE`) | `1F1F` | 0001111100011111 |
| 4 | user (`USERBIT_LINE`) | `user_pat` | e.g. `AAAA` = `0XPM`, `F0F0` = `1BLC` |

The most significant bit is plotted at the line's start point. Thickness 1
(`NORM_WIDTH`) or 3 (`THICK_WIDTH`). Circles, ovals, arcs and pie slices use
the thickness but never the pattern.

### 4.3 Fill patterns (`S`)

Set bits use the fill colour, clear bits colour 0. Bit 7 of each row is the
leftmost pixel; patterns are anchored to the screen origin (§5.9).

| # | Name (Borland BGI constant) | Rows, hex (top row first) | Rows as `s` MegaNums |
|--:|------|------|------|
| 0 (`00`) | Background (`EMPTY_FILL`) | `00 00 00 00 00 00 00 00` | `0000000000000000` |
| 1 (`01`) | Solid (`SOLID_FILL`) | `FF FF FF FF FF FF FF FF` | `7373737373737373` |
| 2 (`02`) | Line (`LINE_FILL`) | `FF FF 00 00 FF FF 00 00` | `7373000073730000` |
| 3 (`03`) | Light slash (`LTSLASH_FILL`) | `01 02 04 08 10 20 40 80` | `010204080G0W1S3K` |
| 4 (`04`) | Normal slash (`SLASH_FILL`) | `E0 C1 83 07 0E 1C 38 70` | `685D3N070E0S1K34` |
| 5 (`05`) | Normal backslash (`BKSLASH_FILL`) | `F0 78 3C 1E 0F 87 C3 E1` | `6O3C1O0U0F3R5F69` |
| 6 (`06`) | Light backslash (`LTBKSLASH_FILL`) | `A5 D2 69 B4 5A 2D 96 4B` | `4L5U2X502I194623` |
| 7 (`07`) | Light hatch (`HATCH_FILL`) | `FF 88 88 88 FF 88 88 88` | `733S3S3S733S3S3S` |
| 8 (`08`) | Heavy cross hatch (`XHATCH_FILL`) | `81 42 24 18 18 24 42 81` | `3L1U100O0O101U3L` |
| 9 (`09`) | Interleaving line (`INTERLEAVE_FILL`) | `CC 33 CC 33 CC 33 CC 33` | `5O1F5O1F5O1F5O1F` |
| 10 (`0A`) | Widely spaced dot (`WIDE_DOT_FILL`) | `80 00 08 00 80 00 08 00` | `3K0008003K000800` |
| 11 (`0B`) | Closely spaced dot (`CLOSE_DOT_FILL`) | `88 00 22 00 88 00 22 00` | `3S000Y003S000Y00` |
| 12 | User pattern (`USER_FILL`) | set only by `s` RIP_FILL_PATTERN | — |

```text
 0 background      1 solid           2 line            3 light slash
   ........          ########          ########          .......#
   ........          ########          ########          ......#.
   ........          ########          ........          .....#..
   ........          ########          ........          ....#...
   ........          ########          ########          ...#....
   ........          ########          ########          ..#.....
   ........          ########          ........          .#......
   ........          ########          ........          #.......

 4 normal slash    5 normal bkslash  6 light bkslash   7 light hatch
   ###.....          ####....          #.#..#.#          ########
   ##.....#          .####...          ##.#..#.          #...#...
   #.....##          ..####..          .##.#..#          #...#...
   .....###          ...####.          #.##.#..          #...#...
   ....###.          ....####          .#.##.#.          ########
   ...###..          #....###          ..#.##.#          #...#...
   ..###...          ##....##          #..#.##.          #...#...
   .###....          ###....#          .#..#.##          #...#...

 8 heavy x-hatch   9 interleaving   10 wide dot       11 close dot
   #......#          ##..##..          #.......          #...#...
   .#....#.          ..##..##          ........          ........
   ..#..#..          ##..##..          ....#...          ..#...#.
   ...##...          ..##..##          ........          ........
   ...##...          ##..##..          #.......          #...#...
   ..#..#..          ..##..##          ........          ........
   .#....#.          ##..##..          ....#...          ..#...#.
   #......#          ..##..##          ........          ........
```

### 4.4 Palette

#### 4.4.1 EGA master palette

A master value is six bits `r g b R G B` (bit 5 … bit 0). For each channel the
upper-case bit contributes `0xAA` and the lower-case bit `0x55`:

```text
red   = 0xAA * bit2 + 0x55 * bit5
green = 0xAA * bit1 + 0x55 * bit4
blue  = 0xAA * bit0 + 0x55 * bit3
```

| Value | RGB | Value | RGB | Value | RGB | Value | RGB |
|--:|---|--:|---|--:|---|--:|---|
| 0 (`00`) | `000000` | 16 (`0G`) | `005500` | 32 (`0W`) | `550000` | 48 (`1C`) | `555500` |
| 1 (`01`) | `0000AA` | 17 (`0H`) | `0055AA` | 33 (`0X`) | `5500AA` | 49 (`1D`) | `5555AA` |
| 2 (`02`) | `00AA00` | 18 (`0I`) | `00FF00` | 34 (`0Y`) | `55AA00` | 50 (`1E`) | `55FF00` |
| 3 (`03`) | `00AAAA` | 19 (`0J`) | `00FFAA` | 35 (`0Z`) | `55AAAA` | 51 (`1F`) | `55FFAA` |
| 4 (`04`) | `AA0000` | 20 (`0K`) | `AA5500` | 36 (`10`) | `FF0000` | 52 (`1G`) | `FF5500` |
| 5 (`05`) | `AA00AA` | 21 (`0L`) | `AA55AA` | 37 (`11`) | `FF00AA` | 53 (`1H`) | `FF55AA` |
| 6 (`06`) | `AAAA00` | 22 (`0M`) | `AAFF00` | 38 (`12`) | `FFAA00` | 54 (`1I`) | `FFFF00` |
| 7 (`07`) | `AAAAAA` | 23 (`0N`) | `AAFFAA` | 39 (`13`) | `FFAAAA` | 55 (`1J`) | `FFFFAA` |
| 8 (`08`) | `000055` | 24 (`0O`) | `005555` | 40 (`14`) | `550055` | 56 (`1K`) | `555555` |
| 9 (`09`) | `0000FF` | 25 (`0P`) | `0055FF` | 41 (`15`) | `5500FF` | 57 (`1L`) | `5555FF` |
| 10 (`0A`) | `00AA55` | 26 (`0Q`) | `00FF55` | 42 (`16`) | `55AA55` | 58 (`1M`) | `55FF55` |
| 11 (`0B`) | `00AAFF` | 27 (`0R`) | `00FFFF` | 43 (`17`) | `55AAFF` | 59 (`1N`) | `55FFFF` |
| 12 (`0C`) | `AA0055` | 28 (`0S`) | `AA5555` | 44 (`18`) | `FF0055` | 60 (`1O`) | `FF5555` |
| 13 (`0D`) | `AA00FF` | 29 (`0T`) | `AA55FF` | 45 (`19`) | `FF00FF` | 61 (`1P`) | `FF55FF` |
| 14 (`0E`) | `AAAA55` | 30 (`0U`) | `AAFF55` | 46 (`1A`) | `FFAA55` | 62 (`1Q`) | `FFFF55` |
| 15 (`0F`) | `AAAAFF` | 31 (`0V`) | `AAFFFF` | 47 (`1B`) | `FFAAFF` | 63 (`1R`) | `FFFFFF` |

#### 4.4.2 Default 16-colour palette

Restored by RIP_RESET_WINDOWS. Corrected table (the original swaps two master
values, erratum E1):

| Index | Name | Master value | RGB |
|------:|------|-------------:|-----|
| `00` | Black (always the background colour) | 0 (`00`) | `000000` |
| `01` | Blue | 1 (`01`) | `0000AA` |
| `02` | Green | 2 (`02`) | `00AA00` |
| `03` | Cyan | 3 (`03`) | `00AAAA` |
| `04` | Red | 4 (`04`) | `AA0000` |
| `05` | Magenta | 5 (`05`) | `AA00AA` |
| `06` | Brown | **20 (`0K`)** | `AA5500` |
| `07` | Light gray | **7 (`07`)** | `AAAAAA` |
| `08` | Dark gray | 56 (`1K`) | `555555` |
| `09` | Light blue | 57 (`1L`) | `5555FF` |
| `0A` | Light green | 58 (`1M`) | `55FF55` |
| `0B` | Light cyan | 59 (`1N`) | `55FFFF` |
| `0C` | Light red | 60 (`1O`) | `FF5555` |
| `0D` | Light magenta | 61 (`1P`) | `FF55FF` |
| `0E` | Yellow | 62 (`1Q`) | `FFFF55` |
| `0F` | White | 63 (`1R`) | `FFFFFF` |

As a `Q` command: `!|Q000102030405` `0K07` `1K1L1M1N1O1P1Q1R`.

### 4.5 Fonts (`Y`)

#### 4.5.1 Font numbers

| # | Font | Kind | BGI constant | Borland file |
|--:|------|------|--------------|--------------|
| 0 | Default 8x8 | bitmap (ROM font) | `DEFAULT_FONT` | built in |
| 1 | Triplex | stroke | `TRIPLEX_FONT` | `TRIP.CHR` |
| 2 | Small | stroke | `SMALL_FONT` | `LITT.CHR` |
| 3 | Sans Serif | stroke | `SANS_SERIF_FONT` | `SANS.CHR` |
| 4 | Gothic (Old English) | stroke | `GOTHIC_FONT` | `GOTH.CHR` |
| 5 | Script | stroke | `SCRIPT_FONT` | `SCRI.CHR` |
| 6 | Simplex | stroke | `SIMPLEX_FONT` | `SIMP.CHR` |
| 7 | Triplex Script | stroke | `TRIPLEX_SCR_FONT` | `TSCR.CHR` |
| 8 | Complex | stroke | `COMPLEX_FONT` | `LCOM.CHR` |
| 9 | European | stroke | `EUROPEAN_FONT` | `EURO.CHR` |
| 10 (`0A`) | Bold | stroke | `BOLD_FONT` | `BOLD.CHR` |

Direction 0 = `HORIZ_DIR`, 1 = `VERT_DIR` (text rotated 90° counter-clockwise,
reading bottom to top). Size 1 is normal; 2…10 magnify. The bitmap font
replicates pixels (size *n* = *n*x*n* blocks, 8*n* pixels per character),
which looks jagged above size 1.

#### 4.5.2 Font metrics (RIP_BUTTON_STYLE section)

Scan lines from the top of the character cell to: **T** the top of the
tallest character, **W** the crest of lower-case letters ("bow"), **B** the
baseline, **D** the lowest descender pixel. Used to centre button labels.
Values marked * are suspected typos (erratum E22); the bracketed value is the
one consistent with the font's own scaling.

| Size | 0 Default T/W/B/D | 1 Triplex | 2 Small | 3 Sans Serif | 4 Gothic | 5 Script |
|-----:|---|---|---|---|---|---|
| 1 | 0/2/6/7 | 6/10/18/22 | 2/3/5/6 | 7/11/19/23 | 7/11/19/23 | 10/17/22/29 |
| 2 | 0/4/13/15 | 6/11/20/24 | 2/4/6/7 | 7/12/21/25 | 7/12/21/25 | 10/18/24/32 |
| 3 | 0/6/20/23 | 8/13/23/28 | 2/3/6/7 | 9/14/24/29 | 9/14/24/29 | 12/21/27/36 |
| 4 | 0/8/27/31 | 10/17/31/38 | 3/5/9/11 | 11/18/32/39 | 11/18/32/39 | 16/28/37/49 |
| 5 | 0/10/34/39 | 13/23/41/50 | 4/7/12/14 | 14/24/42/51 | 14/24/42/51 | 21/37/49/65 |
| 6 | 0/12/41/47 | 16/28/51/62 | 5/9/15/18 | 18/30/53/64 | 18/30/53/64 | 26/46/61/80 |
| 7 | 0/14/48/55 | 20/34/62/76 | 6/10/13* [18]/22 | 22/36/64/78 | 22/36/64/78 | 32/56/74/98 |
| 8 | 0/16/55/63 | 25/42/77/94 | 7/12/22/27 | 28/45/80/97 | 28/45/80/97 | 40/70/92/122 |
| 9 | 0/18/62/71 | 30/51/93/114 | 9/15/27/33 | 33/54/96/117 | 33/54/96/117 | 48/84/111/147 |
| 10 | 0/20/69/79 | 40/67/124/152 | 12/20/36/44 | 74*/102*/158*/186* [44/72/128/156] | 44/72/128/156 | 63/111/147/195 |

| Size | 6 Simplex | 7 Triplex Script | 8 Complex | 9 European | 10 Bold |
|-----:|---|---|---|---|---|
| 1 | 9/13/21/25 | 5/9/17/21 | 8/12/20/24 | 7/14/32/38 | 11/17/35/39 |
| 2 | 9/14/23/27 | 5/10/19/23 | 8/13/22/26 | 7/15/35/41 | 13/19/39/43 |
| 3 | 11/16/26/31 | 7/12/22/27 | 10/15/25/30 | 9/18/40/47 | 14/22/44/49 |
| 4 | 14/21/35/42 | 9/16/30/37 | 13/20/34/41 | 12/24/54/64 | 19/29/59/66 |
| 5 | 18/28/46/56 | 12/22/40/49 | 17/27/45/54 | 16/32/72/85 | 27/39/79/88 |
| 6 | 23/35/58/69 | 15/27/50/61 | 22/34/57/68 | 20/40/96* [≈89]/106 | 33/49/99/110 |
| 7 | 28/42/70/84 | 19/33/61/75 | 27/41/69/83 | 25/49/109/129 | 39/59/119/133 |
| 8 | 35/52/87/104 | 24/41/77/93 | 34/51/86/103 | 31/61/136/161 | 49/74/149/166 |
| 9 | 42/63/105/126 | 29/50/92/113 | 41/62/104/125 | 38/74/164/194 | 59/89/179/200 |
| 10 | 56/84/140/168 | 39/67/123/151 | 54/83/139/167 | 51/99/219/259 | 79/199* [119]/239/267 |

#### 4.5.3 Descender table

`low_char[c]` is 1 when CP437 character *c* reaches below the baseline; used
to drop the hot-key underline and (flag 8192) to centre labels. Set entries:

| Codes | Characters |
|-------|------------|
| 81 | `Q` |
| 103, 106, 112, 113, 121 | `g j p q y` |
| 128, 135 | `Ç ç` |
| 152, 159 | `ÿ ƒ` |
| 171, 172 | `½ ¼` |
| 176–223 | the shade and box-drawing block `░` … `▀` |
| 230 | `µ` |
| 244 | `⌠` |

All other entries (including `,` `;` `_`) are 0.

### 4.6 Text window cell sizes (`w` size) and `$TWFONT$`

| `size` | Cell (px) | Columns × rows | x range | y range | `$TWFONT$` |
|------:|-----------|---------------|---------|---------|-----------:|
| 0 | 8x8 | 80 × 43 | 0–79 | 0–42 | 1 |
| 1 | 7x8 | 91 × 43 ("MicroANSI") | 0–90 | 0–42 | 2 |
| 2 | 8x14 | 80 × 25 | 0–79 | 0–24 | 3 |
| 3 | 7x14 | 91 × 25 ("MicroANSI") | 0–90 | 0–24 | 4 |
| 4 | 16x14 | 40 × 25 | 0–39 | 0–24 | 5 |

`$TWFONT$` returns 0 when there is no text window, so its codes are the
`size` codes plus one.

### 4.7 Image combine modes

See §4.1. NOT pastes the bitwise inverse of each source pixel (`~s`, i.e.
15 − *s* in four planes) and ignores the destination.

### 4.8 Buttons

#### 4.8.1 Label orientation (`orient`)

| Value | Label position |
|------:|----------------|
| 0 | above the button |
| 1 | left of the button |
| 2 | centred on the button |
| 3 | right of the button |
| 4 | below the button |

#### 4.8.2 Style flags, word 1 (`flags`, 4 digits)

Columns Icon/Clip/Plain/Mouse/No-mouse say whether the flag is allowed for
that kind of button (from the 1.54 table).

| Bit value | Meaning | Icon | Clip | Plain | Mouse | No-mouse |
|----------:|---------|:----:|:----:|:-----:|:-----:|:--------:|
| 1 | Clipboard button: the clipboard (pasted in copy mode) is the base image; ignored if the clipboard is empty | N | Y | N | Y | Y |
| 2 | Invertable: inverted while clicked (effects included, recess excluded) | Y | Y | Y | Y | N |
| 4 | Reset screen (as `*`) after a click, before the host command | Y | Y | Y | Y | N |
| 8 | Chisel effect (§5.12) | Y | Y | Y | Y | Y |
| 16 | Recessed effect | Y | Y | Y | Y | Y |
| 32 | Drop-shadow the label | Y | Y | Y | Y | Y |
| 64 | Auto-stamp ("auto-clip") the image onto the clipboard | Y | Y | Y | Y | Y |
| 128 | Icon button: base image from the icon file, stamped in copy mode | Y | N | N | Y | Y |
| 256 | Plain button: base image is a rectangle in `surface` | N | N | Y | Y | Y |
| 512 | Bevel effect, `bevsize` pixels | Y | Y | Y | Y | Y |
| 1024 | Mouse button (clickable) | Y | Y | Y | Y | N |
| 2048 | Underline the hot key in the label (`uline_col`) | Y | Y | Y | Y | N |
| 4096 | Hot icons: show `<icon>.HIC` while pressed | Y | N | N | Y | N |
| 8192 | Include descenders when centring the label vertically (top / centre / bottom labels) | Y | Y | Y | Y | Y |
| 16384 | Radio group: one selected button per group | Y | Y | Y | Y | N |
| 32768 | Sunken effect | Y | Y | Y | Y | Y |

Exactly one of 1 / 128 / 256 should be set. Values above 65535 are undefined.

#### 4.8.3 Style flags, word 2 (`flags2`, 2 digits)

| Bit value | Meaning | Icon | Clip | Plain | Mouse | No-mouse |
|----------:|---------|:----:|:----:|:-----:|:-----:|:--------:|
| 1 | Check-box group (excludes radio, flag 16384) | Y | Y | Y | Y | N |
| 2 | Highlight the hot-key character in `uline_col` | Y | Y | Y | Y | N |
| 4 | Explode: XOR-zoom a dotted rectangle out to full screen on click (optional) | Y | Y | Y | Y | N |
| 8 | Left-justify top / centre / bottom labels (indent 10 px, 20 with chisel) | Y | Y | Y | Y | Y |
| 16 | Right-justify top / centre / bottom labels (same indents) | Y | Y | Y | Y | Y |

#### 4.8.4 Button instance flags (`1U` `flags`, 1 digit)

| Bit value | Meaning |
|----------:|---------|
| 1 | Draw as already selected (radio / check-box) |
| 2 | Default button, activated by Enter |

#### 4.8.5 Chisel inset

| Button height (px) | X inset | Y inset |
|--------------------|--------:|--------:|
| 0–11 | 1 | 1 |
| 12–24 | 3 | 2 |
| 25–39 | 4 | 3 |
| 40–74 | 6 | 5 |
| 75–149 | 7 | 5 |
| 150–199 | 8 | 6 |
| 200–249 | 10 | 7 |
| 250–299 | 11 | 8 |
| 300 and over | 13 | 9 |

### 4.9 Mouse field switches (`1M`)

`clk` 1 = invert while pressed, 0 = no feedback. `clr` 1 = zoom the text window
to full screen and clear it when clicked (for host areas without RIPscrip), 0 =
nothing.

### 4.10 Region text justification (`1t`)

0 = left-aligned only; 1 = justify to both margins.

### 4.11 RIP_DEFINE flags

| Bit value | Meaning |
|----------:|---------|
| 1 | Save the variable to the terminal's database (persistent) |
| 2 | A blank answer is not allowed |
| 4 | Non-interactive: if the variable exists nothing is asked (a default in the command updates it); if it does not exist the definition becomes interactive anyway |

Without flag 4 the terminal shows the current value (or asks for one) and the
user confirms or edits it. Without flag 1 the value lives in memory for the
session.

### 4.12 Text variables

Names are case-sensitive in practice (always upper case). "Active" variables
perform an action and expand to nothing. A terminal that does not implement a
built-in must still recognise it and expand it to nothing rather than prompt
the user for it.

| Variable | Kind | Result (1.54) |
|----------|------|---------------|
| `$RIPVER$` | value | `RIPSCRIP` + version + vendor digits, e.g. `RIPSCRIP015410` |
| `$DATE$` | value | `MM/DD/YY` |
| `$MONTH$` | value | full month name, `December` |
| `$MONTHNUM$` | value | `01`–`12` |
| `$DAY$` | value | `01`–`31` |
| `$DOY$` | value | day of year `001`–`366` |
| `$YEAR$` | value | 2-digit year |
| `$FYEAR$` | value | 4-digit year |
| `$TIME$` | value | `HH:MM:SS`, 24-hour |
| `$HOUR$` | value | `01`–`12` |
| `$MHOUR$` | value | `00`–`23` |
| `$MIN$` | value | `00`–`59` |
| `$SEC$` | value | `00`–`59` |
| `$AMPM$` | value | `AM` / `PM` |
| `$DATETIME$` | value | Unix `ctime` style, `Sat Dec 19 14:38:50 1993` |
| `$TIMEZONE$` | value | zone name (`PST`) or `NONE` |
| `$DOW$` | value | `Sunday` … `Saturday` |
| `$ADOW$` | value | `Sun` … `Sat` |
| `$WDAY$` | value | `0`–`6`, 0 = Sunday |
| `$WOY$` | value | week of year `00`–`53`, weeks start Sunday |
| `$WOYM$` | value | week of year `00`–`53`, weeks start Monday |
| `$BEEP$` | active | 1000 Hz for 75 ms, then 75 ms silence |
| `$BLIP$` | active | 50 Hz for 25 ms, then 10 ms silence |
| `$MUSIC$` | active | 4 × (1300, 1200, 1100, 1000, 900, 800, 700, 850, 950 Hz, 10 ms each) |
| `$ALARM$` | active | 3 × (320 Hz 200 ms, 160 Hz 425 ms) |
| `$PHASER$` | active | sweep 2500 → 50 Hz in 20 Hz steps, 2 ms each (descending; E14) |
| `$REVPHASER$` | active | sweep 50 → 2500 Hz in 20 Hz steps, 2 ms each (ascending) |
| `$X$`, `$Y$` | value | mouse x / y, 4 digits `0000`–`9999` |
| `$XY$` | value | `XXXX:YYYY` |
| `$XYM$` | value | `XXXX:YYYY:LMR`, buttons 1 = pressed |
| `$M$` | value | `LMR` |
| `$MSTAT$` | value | `YES` / `NO` mouse installed |
| `$RESET$` | active | RIP_RESET_WINDOWS |
| `$SAVEALL$` / `$RESTOREALL$` | active | `$STW$ $SCB$ $SMF$ $SAVE$` / `$RTW$ $RCB$ $RMF$ $RESTORE$` |
| `$EGW$` | active | erase the graphics window |
| `$SAVE$`, `$SAVE0$`–`$SAVE9$` | active | save the 640x350 screen and viewport to `RIPTERM.SAV` / `RIPTERMn.SAV` |
| `$RESTORE$`, `$RESTORE0$`–`$RESTORE9$` | active | restore them; the numbered forms delete the file afterwards |
| `$SMF$` / `$RMF$` | active | save / restore all mouse regions (one saved set; restorable repeatedly) |
| `$MKILL$` | active | RIP_KILL_MOUSE_FIELDS |
| `$ETW$` / `$DTW$` | active | erase / disable the text window |
| `$STW$` / `$RTW$` | active | save / restore text-window geometry, cursor, ANSI attributes, cursor state, scroll margins and system font (not contents) |
| `$TWIN$` | value | `YES` / `NO` text window exists and is enabled |
| `$TWFONT$` | value | 0 none, 1…5 (§4.6) |
| `$TWH$`, `$TWW$` | value | text window height (1–43) / width (1–91), 0 if none |
| `$TWX0$`, `$TWY0$`, `$TWX1$`, `$TWY1$` | value | text window corners in cells |
| `$CURX$`, `$CURY$` | value | text cursor within the window |
| `$CON$` / `$COFF$` | active | text cursor on / off (reset by `*`) |
| `$CURSOR$` | value | `YES` / `NO` |
| `$SCB$` / `$RCB$` | active | save / restore the clipboard and its last location (`RIPCLIB.BRD`) |
| `$PCB$` | active | paste the clipboard where it was clipped (or where the icon was stamped) |
| `$STATBAR$` | value | `YES` / `NO` |
| `$SBARON$` / `$SBAROFF$` | active | status bar on / off |
| `$VT102ON$` / `$VT102OFF$` | active | VT-102 key mode: F1–F10 `ESC[M`…`ESC[V`, PgUp `ESC[I`, PgDn `ESC[G`, Home `ESC[H`, End `ESC[F`, Ins `ESC[L`, arrows `ESC[A`–`ESC[D` |
| `$DWAYON$` / `$DWAYOFF$` | active | Doorway keyboard mode (Marshall Dudley's Doorway) |
| `$HKEYON$` / `$HKEYOFF$` | active | button hot keys on / off |
| `$TABON$` / `$TABOFF$` | active | Tab cycles mouse regions on / off |
| `$APP0$`–`$APP9$` | active | run external application slot *n* (0 = text editor by convention) |

Special forms (not names): `$?$` template insertion, `$?x$` template embedding
(§5.13.6), `$>file$` local playback (§5.13.3). Any other `$NAME$` is a user
variable (§5.13.2).

### 4.13 RIP_QUERY and RIP_FILE_QUERY modes

| Query `mode` | When processed |
|-------------:|----------------|
| 0 | immediately |
| 1 | on each click in the graphics window outside all mouse regions |
| 2 | on each click in the text window outside all mouse regions (coordinates in cells) |

| File query `mode` | Reply when missing | Reply when present |
|------------------:|--------------------|--------------------|
| 0 | `0` | `1` (no CR) |
| 1 | `0` CR | `1` CR |
| 2 | `0` CR | `1.`*size* CR, e.g. `1.20345` |
| 3 | `0` CR | `1.`*size*`.`*MM/DD/YY*`.`*HH:MM:SS* CR |
| 4 | `0` CR | `1.`*FILENAME.EXT*`.`*size*`.`*date*`.`*time* CR |

Sizes are decimal.

### 4.14 Block transfer

| `proto` | Protocol | File name required |
|--------:|----------|:------------------:|
| 0 | Xmodem (checksum) | yes |
| 1 | Xmodem (CRC) | yes |
| 2 | Xmodem-1K | yes |
| 3 | Xmodem-1K (G) | yes |
| 4 | Kermit | yes |
| 5 | Ymodem (batch) | no |
| 6 | Ymodem-G | no |
| 7 | Zmodem (crash recovery) | no |

| `file_type` | Content |
|------------:|---------|
| 0 | RIP files: display |
| 1 | RIP files: store |
| 2 | ICN files: store in the icon directories |
| 3 | HLP file: store, load when needed |
| 4 | Composite dynamic (batch only): file each received file by extension; `.RIP` stored, not played |
| 5 | Active dynamic (batch only): as 4, and `.RIP` files are played as they arrive |

### 4.15 Vendor codes (version reply)

| Code | Vendor |
|-----:|--------|
| 0 | generic RIPscrip terminal |
| 1 | RIPterm (TeleGrafix) |
| 2 | Qmodem Pro (Mustang Software) |

### 4.16 Reserved fields

| Command | Field | Write |
|---------|-------|-------|
| `Y` | res:2 | `00` |
| `1M` | res:5 | `00000` |
| `1T` | res:2 | `00` |
| `1C`, `1P`, `1W`, `1U` | res:1 | `0` |
| `1I` | res:2 | **`10`** |
| `1B` | res:6 | `000000` |
| `1D` | res:2 | `00` |
| `1<ESC>` | res:3 | `000` |
| `1G` | res:2 | `00` |
| `1R` | res:8 | `00000000` |
| `1F`, `9<ESC>` | res:4 | `0000` |

Readers ignore reserved values. `1M`'s `num` (obsolete) is written `00`.

---

## 5. Algorithms

### 5.1 MegaNum

```text
decode(digits):                      # digits = 1..width characters
    v = 0
    for ch in digits:
        d = 0..9 for '0'..'9', 10..35 for 'A'..'Z' (and 'a'..'z', see 6.2)
        otherwise -> invalid argument
        v = v * 36 + d
    return v

encode(v, width):                    # 0 <= v < 36^width
    s = ""
    repeat width times: s = DIGITS[v mod 36] + s; v = v div 36
    return s                          # upper case, zero padded
```

Check values: `encode(639, 2) = "HR"`, `decode("1BLC") = 61680`.

### 5.2 Tokenizing a byte stream

```text
at_line_start = true; rip_enabled = true
while bytes remain:
    if byte is ESC and the next bytes are "[!", "[0!", "[1!" or "[2!":
        report the auto-sense; "[1!" -> rip_enabled = false, "[2!" -> true
        at_line_start = false; continue
    if rip_enabled and ((at_line_start and "!|") or "SOH |" or "STX |"):
        skip the marker; payload = read_logical_line(); handle(payload)
        at_line_start = true; continue
    send the byte to the TTY window (ANSI emulation)
    at_line_start = (byte is CR or LF)

read_logical_line():
    out = ""
    loop:
        if end of input: return out
        b = next byte
        if b == '\':
            n = length of the run of backslashes starting here
            if the run is followed by CR, LF or CR LF:
                append (n div 2) times "\\" to out    # still escaped pairs
                consume the run and the line break
                if n is odd: continue                  # continuation
                return out
            append the run unchanged; continue
        if b is CR or LF: consume CR LF / LF / CR; return out
        append b
```

The payload keeps `\!`, `\|`, `\\` escaped so the command splitter can tell a
delimiter from a literal.

### 5.3 Splitting and decoding commands

```text
split(payload):                       # the marker's '|' is already consumed
    commands = []; start = 0; i = 0
    while i < len(payload):
        if payload[i] == '\': i += 2; continue          # escape pair
        if payload[i] == '|': commands += payload[start..i); start = i + 1
        i += 1
    commands += payload[start..]
    drop commands that are empty or only blanks

decode(command):
    level = leading digits (first must be 1-9, else the "digit" is a level-0
            command character that is invalid; see 6.13)
    ch = next character; layout = table 3.6 for (level, ch) or unknown
    for each numeric field (width w):
        last_variable = (field is last) and (layout has no text field)
        take up to w MegaNum digits; if last_variable accept 0 < k < w digits
        fewer than w digits otherwise -> truncated command
        a non-MegaNum character inside a field -> invalid command
    text field = rest of the command with \!, \| and \\ unescaped
                 (other "\x" pairs kept as is)
    for commands without text: ignore the rest (rule 6)
```

### 5.4 Viewport mapping and clipping

For a command with VP = Y: if the viewport is disabled, do nothing at all
(state included, e.g. RIP_MOVE does not move POS). Otherwise every coordinate
(x, y) maps to absolute (vx0 + x, vy0 + y) and every pixel written is clipped
to the viewport rectangle (BGI `setviewport(..., clip=1)`). Radii and angles
are not mapped. RIP_MOUSE and RIP_BUTTON regions are converted to absolute
coordinates when they are stored.

### 5.5 Lines, patterns and thickness

* Lines are rasterised with Bresenham's algorithm from the start to the end
  point, both inclusive.
* The 16-bit pattern is consumed from bit 15 down to bit 0, one bit per
  plotted pixel along the major axis, restarting at bit 15 for every line
  segment (BGI restarts the pattern per `line` call); a 1 bit plots, a 0 bit
  leaves the pixel.
* Thickness 3 draws the line three times, offset −1, 0, +1 perpendicular to
  the major axis (BGI `THICK_WIDTH`).
* XOR mode XORs the colour index into each plotted pixel; a pixel plotted twice
  by one primitive cancels. Consecutive Bezier segments share end points,
  hence the documented gaps. [decision] SwiftRIP draws rectangle edges without
  overlapping corners; poly-line and polygon segments share their vertices
  like Bezier segments do, so XOR leaves one-pixel gaps there too.

### 5.6 Polygons and filled shapes

* `P`/`p` join vertex *n* back to vertex 1; `l` does not.
* `p` fills by scanning each row, intersecting it with every edge (half-open
  in y), sorting the crossings and filling between pairs (even-odd rule), with
  the fill pattern in copy mode; then draws the outline with the line settings.
* Filled ovals and pie slices fill the interior first, then draw the outline
  in DC with the thickness, solid, copy mode.
* RIP_BAR fills the inclusive rectangle; no outline.

### 5.7 Circles, arcs and aspect ratio

Angles are normalised to 0…359; the arc runs counter-clockwise from start to
end; if end ≤ start after normalisation the arc wraps through 0, and equal
original values draw nothing while a span that is a non-zero multiple of 360
(e.g. 0→360) is a full ellipse. A point at angle θ is
`(cx + rx·cos θ, cy − ry·sin θ)` (screen y grows downward).

Circle, arc and pie slice are "aspect-ratio aware" for the 640x350 EGA screen
on a 4:3 monitor: the vertical radius is `ry = radius × aspect` where the
geometric pixel aspect is 350/480 ≈ 0.729 (a 640x350 picture fills a 4:3 tube,
so pixels are 480/350 times taller than wide). Ovals take explicit radii and
are never corrected. See §6.7 for the BGI value.

### 5.8 Bezier curve

```text
for i in 0..cnt:
    t = i / cnt
    x(t) = (1-t)^3*x1 + 3(1-t)^2*t*x2 + 3(1-t)*t^2*x3 + t^3*x4    # doubles
    y(t) likewise
    P[i] = (round(x(t)), round(y(t)))
draw line P[i-1] -> P[i] for i = 1..cnt   (line pattern, thickness, write mode)
```

`cnt` = 0 draws nothing. The original requires double precision ("do not use
Turbo Pascal REALs").

### 5.9 Pattern fills and flood fill

* A fill pixel at absolute (x, y) takes FC if bit `7 − (x mod 8)` of row
  `y mod 8` is set, else colour 0. Patterns are anchored to the screen origin,
  not to the shape or viewport (BGI behaviour), so adjacent fills line up.
* Flood fill (BGI `floodfill` border semantics): starting at the seed, visit
  4-connected pixels inside the viewport whose colour is not `border`, each at
  most once, and paint them with the pattern. Visiting by "not yet visited"
  rather than "not yet fill-coloured" keeps the fill terminating even when the
  pattern contains the border colour or colour 0.

### 5.10 Text placement and region justification

* RIP_TEXT / RIP_TEXT_XY: top-left of the first character at POS; POS advances
  by the text width for horizontal text.
* Region text: the first line's top is the region top; each line's top is the
  previous top plus the line height of the current font and size. A line whose
  bottom would pass the region bottom is skipped.
* Justification of a line with *k* ≥ 2 words: let *W* be the region width,
  *w* the sum of the word widths; distribute `W − w` pixels over the `k − 1`
  gaps as evenly as possible (earlier gaps get the extra pixel), so the last
  word ends exactly at the right margin. Lines that do not fit, or have one
  word, are drawn left-aligned. (1.53 also exempted the last line of a
  paragraph and indented lines; 1.54 leaves that to the host.)

### 5.11 Clipboard operations

* GET_IMAGE: map both corners through the viewport; reject if the rectangle is
  inverted or leaves the screen; otherwise store the pixels (palette indexes)
  and remember the location (used by `$PCB$`).
* PUT_IMAGE: reject if the clipboard is empty or `x + width − 1 > 639`;
  otherwise combine each pixel with the destination by the mode (§4.1),
  clipped to the viewport.
* COPY_REGION (absolute coordinates):

```text
left  = x0 rounded down to a multiple of 8
right = last pixel of the byte that contains x1  ((x1 div 8) * 8 + 7)
reject if y0 > y1, dest == y0, or rows dest .. dest + (y1 - y0) leave 0..349
copy rows y0..y1, columns left..right, to rows starting at dest
(copy through a temporary so overlap works; the source stays)
```

The original's example "X0 = 14, X1 = 38 become 8 and 40" is the half-open
boundary form of the same rule (pixels 8…39); see §6.9 for `x1` already on a
boundary.

### 5.12 Buttons

Rendering one RIP_BUTTON with the current style (all coordinates absolute
after viewport mapping):

```text
if no style: ignore
base image:
    clipboard button (1): paste the clipboard at (x0, y0) in copy mode;
                          base = its rectangle; no clipboard -> ignore button
    icon button (128):    stamp <icon>.ICN at (x0, y0) in copy mode
    plain button (256):   base = (x0, y0, x0+wid-1, y0+hgt-1) if wid, hgt > 0
                          else (x0, y0, x1, y1); fill it with surface
sunken (32768): one-pixel ring 1 px inside base, dark top/left, bright
                bottom/right (inverted bevel); overwrites the image
chisel (8):     inset (ix, iy) from 4.8.5 by base height; a rectangle in dark
                at the inset and one in bright offset by (+1, +1) (a
                drop-shadowed groove); overwrites the image
bevel (512):    rings 1..bevsize px outside base, bright top/left, dark
                bottom/right, corner_col at the two mixed corners;
                image = base grown by bevsize on every side
auto-stamp (64): copy image (base + bevel, no recess, no label) to the
                clipboard; afterwards in the current style clear icon, plain,
                chisel, bevel, auto-stamp and sunken and set clipboard
recessed (16):  black one-pixel ring around image, then an inverted bevel
                ring outside it (image grown by 2); never part of the image,
                the clipboard or the mouse region
label: position by orient relative to the image (above/left/centre/right/
       below); flags2 8/16 indent 10 px (20 with chisel) from the left/right
       edge for top/centre/bottom labels; flag 8192 includes descenders
       (D instead of B in 4.5.2) when centring vertically; drop shadow (32):
       draw in dback at (+1, +1), then in dfore at the position
hot key: first occurrence of the hotkey character in the label underlined
         (2048) or highlighted (flags2 2) in uline_col; the underline sits
         lower for characters with descenders (4.5.3)
mouse button (1024): add a region = image (bevel included, recess excluded)
         with the host command, hot key and invert/reset flags
```

Clicking a mouse button: invert it while held (flag 2), show `.HIC` (4096,
falling back to the icon pasted in NOT mode), optionally explode (flags2 4),
reset the screen if flag 4, then process the host command (§5.13); radio
buttons deselect the other selected button of their group; check boxes toggle.

### 5.13 Host-command processing

Host commands appear in RIP_MOUSE text, the third block of RIP_BUTTON text and
RIP_QUERY text. Processing happens when the command is *used* (click or
query), never when it is received. "What can go where" (template document):

| Feature | Button host cmds | Mouse fields | Query | Button labels | `@` / `T` text |
|---------|:---:|:---:|:---:|:---:|:---:|
| Templates | Y | N | N | N | N |
| Built-in value variables | Y | Y | Y | Y | Y |
| Active variables | Y | Y | Y | N | N |
| Pick lists | Y | Y | Y | N | N |
| Control characters | Y | Y | Y | N | N |
| Local RIP playback | Y | Y | Y | N | N |

(Per the chart, built-in value variables are also expanded in button labels
and in RIP_TEXT / RIP_TEXT_XY strings when they are drawn.)

#### 5.13.1 Control characters

`^X` or `` `X `` (backquote, for hosts that use `^`) becomes the control
character `X & 0x1F`: `^@` NUL, `^G` BEL, `^H` BS, `^L` FF, `^M` CR, `^[`
ESC, `^S` / `^Q` XOFF / XON; lower-case letters work (`^m` = CR). Arrow keys
are `^[[A` up, `^[[B` down, `^[[C` right, `^[[D` left, `^[[H` home, `^[[K`
end, `^[[L` control-home. Some hosts let `^^` stand for a literal caret (host
convention, not defined by RIPscrip). The real ESC byte, never `^[`, is used as
the RIP_QUERY / block-mode command character.

#### 5.13.2 Text variables

`$NAME$` is replaced by its value (§4.12). Names of user variables follow the
RIP_DEFINE identifier rule. If a user variable is undefined the terminal pops
up `Enter <name>` (or the RIP_DEFINE question) and sends the answer; defined
variables are sent without asking unless the definition was interactive.
Unknown built-ins must not prompt.

#### 5.13.3 Local playback

`$>FILE$` or `$>FILE.EXT$` queues a local file for playback on the local screen
(never sent to the host); `.RIP` files execute (and can define mouse regions),
other files are displayed as text/ANSI. Search order: the current host's icon
directory, then `ICONS\`. Playback starts after the current host command has
been completely processed, in the order queued.

#### 5.13.4 Pick lists

```text
pick-list = "((" ["*"] [question] "::" entry *( "," entry ) "))"
entry     = response ["@" description]
```

The terminal shows `question` (default "Choose one of the following:") and the
entries (descriptions when given) and inserts the chosen response. `*` makes a
choice mandatory; otherwise Esc inserts nothing. Up to 20 entries; total length
256 bytes before RIPterm 1.53, 1024 bytes from 1.53. `_x_` or `~x~` around a
character marks the hot key (only the first counts; a missing closing marker
highlights the rest of the text); markers in a response are sent to the host.
`!`, `|` and `\` inside a list need the RIPscrip escapes `\!`, `\|`, `\\`.

#### 5.13.5 Command blocks

A button host command is a sequence of blocks, each introduced by an optional
bracket prefix:

| Prefix | Block type |
|--------|------------|
| none (first block only) or `[]` | direct host command: processed and sent |
| `[g:]` | template definition for group *g* (`0`–`9`, `A`–`Z`) |
| `[g1g2…gn]` | template chain through *g1* … *gn* (1–36 ids, repeats allowed) |

```text
blocks = split host command before every "[" that starts a prefix matching
         \[([0-9A-Z]:|[0-9A-Z]*)\]
for each block in order:
    direct      -> expand (5.13.1-5.13.4, 5.13.6) and send
    definition  -> remember text as the button's definition for group g
                   (if a button has several for one group, the last wins)
    chain       -> v = expand(text)
                   for g in g1..gn:
                       t = active template of g
                       if t is empty: radio group -> ask the user to pick a
                          radio button and abort; otherwise -> send nothing
                          for this block
                       v = expand(t) with every "$?$" replaced by v
                   send v
```

The precise rule for recognising a prefix is not documented; the pattern above
is what the documented examples require and keeps `^[[A` (no closing `]`
after an id) as text.

#### 5.13.6 Templates and groups

* Each button group 0…35 owns one template. A definition block takes effect
  when its button is clicked or drawn pre-selected, not when received.
* **Radio group** (style flag 16384): the active template is the definition of
  the selected button.
* **Check-box group** (flags2 1): the active template is the concatenation of
  the definitions of all selected buttons **in the order the buttons were
  defined**, recomputed on every toggle; empty when none are selected.
* **Plain group**: the definition of the most recently clicked button.
* **Embedding** `$?g$` in any host command (or template) inserts template *g*.
  First-level embedded text is expanded (variables, lists, control characters,
  its own `$?h$`); text embedded at the second level is inserted raw, with no
  further processing, which bounds recursion. An empty check-box template
  embeds as nothing; an empty radio template makes the terminal ask the user
  to choose; an undefined plain template embeds as nothing.
* Variables in templates are expanded when the template is used (a `$TIME$` in
  a template gives the time of the click that uses it).
* The final string sent to the host is truncated to 4096 bytes (the main text
  says 0–4095 characters; E20).
* Before processing, RIPterm copies the host command if it contains `$RMF$`,
  `$>`, `$APP`, `$RESET$` or `$MKILL$`, because those may destroy the mouse
  table that holds the string being processed. Implementations must likewise
  not process a host command in place in storage that its own actions can free.

Worked chain (template document): `[1:]red green $?$ blue`,
`[E:]LOUD QUIET $?$ YELL`, `[3:]soft $?$ hard smooth gritty`, then
`[1E3](host command)` sends
`soft LOUD QUIET red green (host command) blue YELL hard smooth gritty`.

### 5.14 `.ICN` encode and decode

```text
decode(bytes):
    require len >= 4
    w = u16le(bytes[0..2]) + 1; h = u16le(bytes[2..4]) + 1
    b = ceil(w / 8); need = 4 + h * 4 * b      (+1 trash byte, optional)
    require len >= need
    for y in 0..h-1:
        for plane p in [3, 2, 1, 0]:
            row = bytes[4 + (y*4 + (3-p)) * b ..][0..b]
            for x in 0..w-1:
                if row[x div 8] bit (7 - x mod 8) is set: pixel[y][x] |= 1 << p
    return w, h, pixels

encode(w, h, pixels):          # pixels are palette indexes 0..15
    u16le(w-1), u16le(h-1), then rows as above with zero padding bits,
    then one byte 0
```

---

## 6. Semantics and de-facto behaviour

Each item names its source: **[1.54]** the specification text, **[tmpl]** the
template document, **[BGI]** documented Borland Graphics Interface behaviour
that RIPterm builds on, **[decision]** a reader choice where the sources are
silent (SwiftRIP's choice is stated).

### 6.1 Byte handling

* [decision] Text arguments are bytes. SwiftRIP decodes `Data` as ISO-8859-1 so
  every byte survives and error offsets are byte offsets; a renderer that draws
  bytes ≥ 0x80 should treat them as CP437.
* [decision] CR, LF and CR LF all end a line (DOS hosts send CR LF; captures
  often have LF).
* [decision] `STX !|` is accepted as well as `STX |`; some hosts emit it.

### 6.2 MegaNum case

[decision] The original only shows upper-case digits. Lower-case letters are
accepted as the same digits (RIPscrip is generated by tools that emit upper
case, so this only rescues hand-edited files); writers emit upper case.

### 6.3 Out-of-range values

The wire allows 0…1295 where the original defines fewer values. [decision]
(SwiftRIP): colours use the low 4 bits; palette values the low 6 bits;
RIP_ONE_PALETTE with an entry > 15 is ignored; fill patterns > 11 render
solid; line styles > 4 render solid; thickness ≥ 3 is 3 and anything else 1;
write modes other than 1 are copy; image modes other than 1…4 are copy; fonts
> 10 fall back to 0; font size is clamped to 1…10 (0 included); text window
sizes > 4 use 8x8 cells; RIP_FILL_PATTERN rows keep their low 8 bits;
polygons with fewer than 2 points draw nothing, more than 512 points (up to
the wire limit 1295) are accepted; Bezier counts are capped at 4096 (never
reachable with 2 digits).

### 6.4 Reset scope

[1.54] RIP_RESET_WINDOWS lists windows, cursor, screen, mouse regions,
clipboard and palette. It does not mention drawing attributes. [decision]
SwiftRIP keeps DC, LP, LT, FC, FP, WM, FS, POS and the button style, and ends
any open text region. Scenes that rely on defaults should set them explicitly.

### 6.5 Initial state

[BGI] Before the first reset a terminal shows BGI's defaults
(`graphdefaults()`): drawing colour 15 (the maximum colour), solid fill in
colour 15, solid thin lines, copy mode, default font horizontal size 1,
left/top text justification, full-screen viewport, position (0,0). SwiftRIP
starts from that state and the RIP_RESET_WINDOWS windows.

### 6.6 Viewport rules

* [1.54] A disabled viewport makes VP commands no-ops, including RIP_MOVE,
  RIP_MOUSE, RIP_BUTTON, RIP_GET_IMAGE and the text-region commands.
* [decision] A viewport with `x0 > x1` or `y0 > y1` is normalised (corners
  ordered) and clamped to the screen rather than rejected.
* [1.54] RIP_ERASE_VIEW, RIP_ERASE_WINDOW and RIP_COPY_REGION ignore the
  viewport's clip; COPY_REGION also ignores its origin.

### 6.7 Aspect ratio

[1.54] says circles are "truly circular" on the 640x350 EGA screen.
[decision] SwiftRIP uses the geometric 350/480. Borland's EGA driver reports
its own aspect ratio through `getaspectratio()` (commonly given as
7750:10000); a renderer that must match RIPterm pixel for pixel may prefer
that value.

### 6.8 Text

* [1.54] Graphics text uses DC, the write mode, the font and the size. [BGI]
  `outtext` ignores the write mode; RIPterm's flag table says text uses it, so
  SwiftRIP honours it.
* [BGI] Only horizontal `outtext` advances the current position; vertical text
  leaves it. [1.54] says the position is "set immediately to the right of the
  drawn text" without distinguishing direction. SwiftRIP follows BGI.
* [decision] SwiftRIP's fonts are clean-room approximations (no BGI glyph data
  can be redistributed); their advance widths and heights are not the metrics
  of §4.5.2.

### 6.9 RIP_COPY_REGION boundaries

[1.54] gives only the example "14 and 38 become 8 and 40". [decision] SwiftRIP
treats `x1` as an inclusive pixel and copies through the end of its byte, so
`x1` = 38 copies to pixel 39 (the example) and `x1` = 40 copies to pixel 47
(pixel 40 is requested, so its whole byte is copied).

### 6.10 Mouse regions

* [1.54] At most 128 mouse fields and mouse buttons together; scanned most
  recent first. [decision] SwiftRIP drops regions beyond 128.
* [1.54] Corners must be given upper-left / lower-right; [decision] readers
  should not rely on it when hit-testing (normalise or test both orders).

### 6.11 Pre-selected buttons

[1.54] contradicts itself (E11): RIP_BUTTON says the host command of a
selected button is *not* sent when drawn; the radio and check-box flag
descriptions say it *is* processed when drawn. [tmpl] settles the part that
matters: drawing a button pre-selected activates its template definitions.
[decision] Activate definitions; do not send direct blocks.

### 6.12 `$TWFONT$` and text-window size codes

[1.54] `$TWFONT$` counts fonts 1…5 while RIP_TEXT_WINDOW's `size` is 0…4 for
the same cells (§4.6). Not an error, but a trap for implementers.

### 6.13 Unknown commands

[1.54] reserves the command space ("literally trillions" of commands; RIPscrip
2.x/3.x use it). [decision] A syntactically valid command whose level and
character are not in §3.6 is skipped (SwiftRIP reports it as `unknown` with
its raw arguments so it can be re-emitted). A leading digit `0` cannot start a
level; SwiftRIP reports such commands as unknown rather than failing.

### 6.14 Raw text

[1.54] Bytes outside RIPscrip lines go to the TTY window with ANSI emulation.
SwiftRIP does not emulate the text window; it skips them.

---

## 7. Robustness guidance for readers

Every field of a RIPscrip stream is untrusted. In particular:

* **Bound all work per command.** Coordinates are at most 1295, so every
  primitive is bounded, but a script can repeat expensive commands (full-screen
  flood fills, 1295-point polygons, large thick ellipses) without limit and can
  draw entirely off screen. Count work (pixels written plus rasterizer steps
  that write nothing) and stop at a budget. SwiftRIP defaults to 200 million
  units (about 900 full-screen flood fills, roughly 1.5 s on Apple silicon)
  and reports truncation.
* **Arithmetic.** Viewport offset + coordinate, radius × aspect, Bezier
  intermediates and `x + width` must not overflow; clamp inputs from public
  APIs before arithmetic.
* **Flood fill** must not recurse per pixel (stack depth) and must mark visited
  pixels, not test for the fill colour, or patterned fills loop forever.
* **Arcs:** compute the number of steps from the span and radius and cap it.
* **Truncation.** A command cut short before its fixed-width fields end is
  malformed; the last field of a command without text may legitimately be
  short (§3.4). A stream may end inside a RIPscrip line or after a
  continuation backslash: treat end of input as the end of the line.
* **Invalid digits.** A non-MegaNum character inside a fixed-width field is
  malformed. Readers may skip the command or reject the stream; SwiftRIP throws
  a typed error with the command name and byte offset so corruption is visible.
* **Line length.** Continuations can make a logical line arbitrarily long; do
  not pre-allocate from untrusted lengths and process lines incrementally if
  memory matters.
* **Point counts.** `npoints` is at most 1295; read exactly that many pairs and
  fail on truncation instead of allocating from the count blindly.
* **Text arguments** may contain any byte except unescaped `|` and line
  breaks; never interpret them as file paths without sanitising (RIP_LOAD_ICON,
  RIP_WRITE_ICON, RIP_READ_SCENE, RIP_FILE_QUERY, `$>file$` must stay inside
  the icon directory: reject drive letters, `\`, `/`, `..`).
* **Host interaction** (queries, file queries, block transfers, `$APPn$`,
  uploads) is a security boundary: a renderer should not perform it, and a
  terminal should confirm uploads and application launches with the user.
* **`.ICN` files:** validate `4 + h·4·⌈w/8⌉ ≤ file length` before reading;
  width and height come from 16-bit fields (≤ 65536) so cap the pixel count;
  ignore the trash byte.
* **Templates and embedding** must keep the 4096-byte cap and the two-level
  embedding limit to avoid exponential growth; check-box concatenation must
  also be capped.

---

## 8. Errata

### 8.1 RIPscrip 1.54 (`art/ripscrip-1.54.txt`)

| # | Location | Error | Correction / evidence |
|---|----------|-------|-----------------------|
| E1 | RIP_SET_PALETTE and RIP_ONE_PALETTE default-palette tables | Brown listed as master "7 (06)" and Light Gray as "20 (0K)". | Brown is 20 (`0K`, AA5500), Light Gray is 7 (`07`, AAAAAA): the EGA bit layout gives these colours, the row names only fit the standard EGA BIOS palette `{0,1,2,3,4,5,20,7,56…63}`, and "7 (06)" is self-inconsistent (`06` = 6). Also in 1.53. |
| E2 | RIP_OVAL example | `1E1A18003G150Z` lacks `!\|O` and has 14 digits for 12. | Probably `!\|O1E1A18003G15` + junk (ignored by rule 6). |
| E3 | RIP_BEGIN_TEXT example | `!\|1T00110011` has 8 digits; the layout has 10 (`res:2`). | `!\|1T0011001100`; a reader decodes the short form as `res` = 0 (§3.4). Also in 1.53. |
| E4 | RIP_FILL_PATTERN example | `!\|s11223344556677880F` gives rows `77` = 259 and `88` = 296, which do not fit in 8 bits. | Use values ≤ `73`; readers keep the low 8 bits. Also in 1.53. |
| E5 | RIP_FILL_STYLE, pattern 04 diagram, row 5 | `0E` listed as decimal 15, MegaNum `0F`. | 14, `0E` (bitmap `....###.`). |
| E6 | RIP_FILL_STYLE, pattern 05 diagram, row 1 | `F0` listed as MegaNum `60`. | `6O` (240 = 6·36 + 24). |
| E7 | RIP_FILL_STYLE, pattern 05 diagram title | Titled "LIGHT BACKSLASH FILL". | It is NORMAL BACKSLASH FILL (pattern 6 is the light one). |
| E8 | `.ICN` example | Plane 0 of row 1 (`110101` padded) given as `C4h`, in the derivation (H) and at offset `0B`. | `11010100` = **`D4h`**. Previous revisions of this document repeated `C4`. |
| E9 | RIP_FONT_STYLE note | "The fonts 1 - 4 are smooth scalable vector fonts." | Fonts 1–10 are stroke fonts (the table above it says so); 1–4 is the older BGI font set. |
| E10 | RIP_BUTTON_STYLE header | Argument list says `size:2`; Format line and text say `<bevsize>`; flag 512 text says `<size>`. | One field, offset 10, bevel size. |
| E11 | RIP_BUTTON flags vs. button-style flags 16384 / flags2 1 | "The Host Command WILL NOT be automatically sent … when a selected Button is drawn" vs. "that host command is processed at the time of its initial drawing". | Contradiction; see §6.11. |
| E12 | RIP_QUERY, paragraph after the mode table | "clicks the mouse either in the text window, or in the graphics window respectively" reverses the table. | Mode 1 = graphics window, mode 2 = text window. |
| E13 | RIP_ENTER_BLOCK_MODE examples | "Without a filename, using Z-Modem: `!\|9<escape>06040000<>`" — protocol digit 6 is Ymodem-G. The "with a filename" example `01010000filename.icn` declares file type 1 (RIP store) for an icon. The argument header line is garbled (`[filename:2] <>`). The dynamic-mode paragraph says files are "uploaded" while describing downloads. | Zmodem is `!\|9<ESC>07040000<>`; an icon download would use file type `02`. |
| E14 | `$PHASER$` / `$REVPHASER$` | `$PHASER$` "makes an ascending tone" but its loop sweeps 2500→50 Hz; `$REVPHASER$` is called descending but sweeps 50→2500 Hz. The text also refers to `$REVPHASERS$`. | Follow the code: `$PHASER$` descends, `$REVPHASER$` ascends; the name is `$REVPHASER$`. |
| E15 | `$RESTORE$` | "To restore the entire context … `$RESTALL$`". | `$RESTOREALL$`. |
| E16 | `$RIPVER$` | Description and example return `RIPSCRIP015300` (1.53 format) in the 1.54 document. | A 1.54 RIPterm returns `RIPSCRIP015410` (§1.4). |
| E17 | Text-variable query example | `$FULL_NAME$^m$COMPANY$^m$ST_ADDR$^m$CITY$, $STATE$ $ZIP^m` lacks the closing `$` of `$ZIP$`. | `$ZIP$^m`. Also in 1.53. |
| E18 | Radio-button screenshot note | "Refer to Section 5.3.7." | The document has no numbered sections. |
| E19 | RIP_LOAD_ICON | "go off the right or left edge of the screen". | Presumably right or bottom edge (the upper-left corner is given). |
| E20 | Templates (main text vs. template document) | "0-4095 characters" vs. "truncated to exactly 4096 bytes". | Treat 4096 bytes as the cap including any terminator; SwiftRIP does not process host commands. |
| E21 | Fill-style table | "There are twelve (12) predefined fill patterns" and BGI's `USER_FILL` (12) is not mentioned. | Pattern 12 is the user pattern set by `s` (§4.3). |
| E22 | Font metric tables | Small size 7 Base 13 (sizes 6/8 are 15/22; the font's ×2 scale of size 4 gives 18). Sans Serif size 10 row 74/102/158/186 (every other size equals Gothic's row; ×4/3 of size 9 gives 44/72/128/156 = Gothic's size 10). European size 6 Base 96 (×1.65 of size 4 gives ≈89; Drop 106 fits). Bold size 10 Bow 199 (×4/3 of size 9's 89 gives 119; the other three columns fit ×4/3 exactly). | Use the bracketed values in §4.5.2 if consistency matters. |

### 8.2 Template document (`art/ripscrip-1.54-template.txt`)

| # | Location | Error | Correction |
|---|----------|-------|------------|
| T1 | "Tiptoe through the templates" | `[5:]This is template #6's definition`. | Template #5. |
| T2 | Text-variable examples 3 and 4 | Host commands use `$?4$`, which is never defined; the results show the time from template 2. | `$?2$`. |
| T3 | "Processing of templates" | "another button (group #0) which uses the template for the radio button group 3". | Group #2 (the example defines group 2). |

### 8.3 RIPscrip 1.53 (`art/ripscrip-1.53.md`)

E1–E4, E9, E10, E12–E15 and E17–E22 occur in the 1.53 text as well (the
button-flag contradiction E11 does not; E5–E8 and E16 concern material that
1.53 lacks or states correctly for itself). The JETSAMIC Markdown transcription
of 1.53 additionally had CP437 box-drawing characters in the radio-button
screenshots mis-decoded as Mac Roman (`…ÕÕÕª` for `╔═══╗`); corrected in the
specs repository.

### 8.4 Previously circulating descriptions

An earlier SwiftRIP reference (replaced 2026-11) described: 3-digit coordinates;
commands concatenated without `|`; `f` for RIP_FILL_PATTERN; `9NoMore`,
`1?` and `9<` command characters; swapped `1C` / `1G`; a fabricated "verbatim"
licence text; a `\"` escape; reversed ANSI auto-sense meanings; wrong
fill-pattern bytes. None of these are RIPscrip 1.54. The first rewrite kept
the 1.54 `.ICN` example's `C4` byte (E8).

---

## 9. Implementation status

SwiftRIP 0.1.0 against this document; consistent with the README coverage
table. "Recorded" means parsed into `RIPCommand`, re-encodable by `RIPWriter`
and surfaced in `RIPSceneInteractive`, but not executed.

| Section | Feature | Status |
|---------|---------|--------|
| §3.1–3.3 | Start markers (`!\|` at line start, `SOH \|`, `STX \|`, `STX !\|`), `\|` delimiters, level and sub-level digits, escapes, continuation incl. rule 13 | Supported |
| §3.4, §5.1 | MegaNum fields of every width, variable-width last parameter, trailing text ignored | Supported |
| §3.6 | Every level 0, 1 and 9 command | Parsed and written |
| §3.10 | ANSI auto-sense | Supported: reported; `ESC[1!` / `ESC[2!` honoured; no reply is sent |
| §3.7 `w v * e E g H >` | Windows and cursors | Supported (text window as pixel areas; no TTY text) |
| §3.7 `c Q a W` | Colours, palette, write mode | Supported |
| §3.7 `m T @ Y` | Position and text | Partial: layout and position rules supported; fonts are approximations (ASCII 32–126 only, metrics of §4.5.2 not used) |
| §3.7 `X L R B P p l Z` | Pixels, lines, rectangles, bars, polygons, poly-lines, Beziers | Supported |
| §3.7 `C O o A V I i` | Circles, arcs, ovals, pie slices | Supported (aspect 350/480, §6.7) |
| §3.7 `= S s F` | Line styles, fill styles and patterns, flood fill | Supported |
| §3.7 `#` | No more | Recorded (`noMore`) |
| §3.8 `1M 1K` | Mouse fields | Recorded as global `RIPMouseRegion`s, 128 limit, LIFO order preserved |
| §3.8 `1T 1t 1E` | Text regions with justification | Supported (line height from the approximated fonts) |
| §3.8 `1C 1P 1G` | Clipboard get / put (5 modes), copy region | Supported |
| §3.8 `1W 1I`, §3.11, §5.14 | Icons and `.ICN` files | Recorded only; no `.ICN` reader or writer, no "load failed" box |
| §3.8 `1B 1U`, §5.12 | Buttons | Partial: plain and clipboard buttons, fixed and dynamic size, bevel / recess / sunken / chisel, auto-stamp, label orientation, left / right justification, drop shadow, mouse region. Not supported: icon images, hot icons, hot-key underline / highlight, descender-adjusted centring, selected / default state, radio / check-box behaviour, explode, invert on click |
| §3.8 `1D 1<ESC> 1R 1F`, §3.9 | Define, query, read scene, file query, block mode | Recorded only (no host, no file system) |
| §4.12, §5.13 | Text variables, pick lists, control characters, command blocks, templates, local playback | Not interpreted; host-command text preserved verbatim |
| §6.14 | Raw ASCII / ANSI text | Skipped (no TTY emulation) |
| §7 | Work budget | Supported (`RIPRenderOptions.pixelBudget`, `isTruncated`) |

---

## 10. References, attribution and provenance

### 10.1 Sources

* TeleGrafix Communications, Inc., *RIPscrip Graphics Protocol Specification,
  "Remote Imaging Protocol"*, Revision 1.54, July 19th, 1993. JETSAMIC `specs`
  repository, `art/ripscrip-1.54.txt`.
* TeleGrafix Communications, Inc., RIPscrip 1.54 host-command template
  document. `art/ripscrip-1.54-template.txt`.
* TeleGrafix Communications, Inc., *RIPscrip Graphics Protocol
  Specification*, Revision 1.53.00, May 12th, 1993. Markdown transcription in
  `art/ripscrip-1.53.md`.
* Borland International, *Turbo C / Borland C++ Library Reference*, Borland
  Graphics Interface chapter (`graphdefaults`, `setlinestyle`, `setfillstyle`,
  `setfillpattern`, `settextstyle`, `getimage` / `putimage`,
  `getaspectratio`), for the BGI constants and behaviour cited in §4–§6.
* IBM, *Enhanced Graphics Adapter* technical reference, for the 6-bit
  `rgbRGB` palette register layout.

### 10.2 Licence terms of the RIPscrip language

The 1.54 text ("Use of the RIPscrip language") states that TeleGrafix makes
the language publicly available and freely licensed for use in other products,
that it is not public domain and TeleGrafix keeps the copyright, and that a
product using RIPscrip must say so, with the trademark statement, in its
"About box" and documentation. In TeleGrafix's words: "RIPscrip, RIPaint,
RIPdraw, and RIPterm are trademarks of TeleGrafix Communications, Inc." and
"You may not use RIPterm, RIPaint, RIPdraw, or RIPterm in the name of your
product." SwiftRIP's README carries the statement; no SwiftRIP name uses a
TeleGrafix product name.

### 10.3 Provenance

This document was written from the public documents listed above and from
black-box reasoning about their examples (every example was decoded and
checked; §8 lists the ones that do not decode as described). Numeric tables
(fill patterns, palette, metrics, descenders, chisel insets, flag values) are
facts restated from the originals and checked arithmetically. No third-party
source code was copied; SwiftRIP contains no RIPterm, RIPaint or BGI code or
font data.
