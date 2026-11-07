// RIPCommand — typed representation of every RIPscrip 1.54 command.
//
// Each case carries the arguments the 1.54 specification defines, in order
// and with the specification's names. Numeric arguments are the decoded
// MegaNum values (no clamping or validation is applied by the parser — that
// is the renderer's job). Text arguments have already been un-escaped
// (`\!`, `\|` and `\\` become `!`, `|` and `\`).
//
// Coordinates of commands that "use the viewport" are relative to the
// upper-left corner of the current graphics viewport, exactly as on the wire.

import Foundation

/// A single parsed RIPscrip 1.54 command.
///
/// The enum is exhaustive over the Level 0, Level 1 and Level 9 commands of
/// the RIPscrip 1.54 specification. Two extra cases carry data that is not a
/// drawing command: ``ansiSense(_:)`` for the out-of-band ANSI auto-sense
/// sequences and ``unknown(level:command:arguments:)`` for commands that are
/// syntactically valid but not defined by 1.54 (for example sub-level
/// commands such as `!|15L`).
///
/// Unless stated otherwise, every numeric argument is a two-digit MegaNum on
/// the wire, so its parsed value is in `0...1295`.
public enum RIPCommand: Equatable, Sendable {

    // MARK: - Level 0

    /// `w` RIP_TEXT_WINDOW — define the TTY text window in character cells.
    ///
    /// `wrap` (1 digit) is 1 to wrap/scroll, 0 to truncate. `size` (1 digit)
    /// selects the cell size: 0 = 8x8, 1 = 7x8, 2 = 8x14, 3 = 7x14, 4 = 16x14.
    /// All-zero coordinates make the text window invisible.
    case textWindow(x0: Int, y0: Int, x1: Int, y1: Int, wrap: Int, size: Int)
    /// `v` RIP_VIEWPORT — define the graphics viewport in absolute pixels
    /// (inclusive corners). All-zero coordinates disable graphics output.
    case viewport(x0: Int, y0: Int, x1: Int, y1: Int)
    /// `*` RIP_RESET_WINDOWS — clear the screen, reset both windows, delete
    /// mouse regions and the clipboard, and restore the default palette.
    case resetWindows
    /// `e` RIP_ERASE_WINDOW — clear the text window to color 0.
    case eraseWindow
    /// `E` RIP_ERASE_VIEW — clear the graphics viewport to color 0.
    case eraseView
    /// `g` RIP_GOTOXY — move the text cursor (0-based character cell).
    case gotoXY(x: Int, y: Int)
    /// `H` RIP_HOME — move the text cursor to the window's upper-left cell.
    case home
    /// `>` RIP_ERASE_EOL — clear from the text cursor to the end of its line.
    case eraseEOL
    /// `c` RIP_COLOR — set the drawing color (palette index 0...15).
    case color(Int)
    /// `Q` RIP_SET_PALETTE — sixteen master-palette values (0...63), one per
    /// palette index.
    case setPalette([Int])
    /// `a` RIP_ONE_PALETTE — set palette index `slot` (0...15) to master
    /// palette value `value` (0...63).
    case onePalette(slot: Int, value: Int)
    /// `W` RIP_WRITE_MODE — 0 = copy (overwrite), 1 = XOR.
    case writeMode(Int)
    /// `m` RIP_MOVE — move the graphics drawing position.
    case move(x: Int, y: Int)
    /// `T` RIP_TEXT — draw text at the drawing position.
    case text(String)
    /// `@` RIP_TEXT_XY — draw text at `(x, y)`.
    case textXY(x: Int, y: Int, string: String)
    /// `Y` RIP_FONT_STYLE — font 0...10, direction 0 (horizontal) or 1
    /// (vertical), size 1...10 and a reserved value.
    case fontStyle(font: Int, direction: Int, size: Int, reserved: Int)
    /// `X` RIP_PIXEL — plot one pixel in the drawing color.
    case pixel(x: Int, y: Int)
    /// `L` RIP_LINE — draw a line.
    case line(x0: Int, y0: Int, x1: Int, y1: Int)
    /// `R` RIP_RECTANGLE — draw a rectangle outline between opposing corners.
    case rectangle(x0: Int, y0: Int, x1: Int, y1: Int)
    /// `B` RIP_BAR — fill a rectangle with the fill color/pattern (no border).
    case bar(x0: Int, y0: Int, x1: Int, y1: Int)
    /// `C` RIP_CIRCLE — aspect-corrected circle outline; `radius` in pixels.
    case circle(x: Int, y: Int, radius: Int)
    /// `O` RIP_OVAL — elliptical arc from `startAngle` counter-clockwise to
    /// `endAngle` (degrees, 0 = 3 o'clock).
    case oval(x: Int, y: Int, startAngle: Int, endAngle: Int, xrad: Int, yrad: Int)
    /// `o` RIP_FILLED_OVAL — filled ellipse with an outline.
    case filledOval(x: Int, y: Int, xrad: Int, yrad: Int)
    /// `A` RIP_ARC — aspect-corrected circular arc (degrees, counter-clockwise).
    case arc(x: Int, y: Int, startAngle: Int, endAngle: Int, radius: Int)
    /// `V` RIP_OVAL_ARC — elliptical arc (degrees, counter-clockwise).
    case ovalArc(x: Int, y: Int, startAngle: Int, endAngle: Int, xrad: Int, yrad: Int)
    /// `I` RIP_PIE_SLICE — filled, aspect-corrected circular pie slice.
    case pieSlice(x: Int, y: Int, startAngle: Int, endAngle: Int, radius: Int)
    /// `i` RIP_OVAL_PIE_SLICE — filled elliptical pie slice.
    case ovalPieSlice(x: Int, y: Int, startAngle: Int, endAngle: Int, xrad: Int, yrad: Int)
    /// `Z` RIP_BEZIER — cubic Bezier through control points 0...3, drawn as
    /// `count` straight segments.
    case bezier(x0: Int, y0: Int, x1: Int, y1: Int, x2: Int, y2: Int, x3: Int, y3: Int, count: Int)
    /// `P` RIP_POLYGON — closed polygon outline (spec: 2...512 points).
    case polygon(points: [RIPPoint])
    /// `p` RIP_FILL_POLYGON — filled polygon (even-odd rule) with outline.
    case fillPolygon(points: [RIPPoint])
    /// `l` RIP_POLYLINE — open poly-line (spec: 2...512 points).
    case polyline(points: [RIPPoint])
    /// `F` RIP_FILL — flood fill from `(x, y)` up to palette index `border`.
    case fill(x: Int, y: Int, border: Int)
    /// `=` RIP_LINE_STYLE — style 0...4, 16-bit user pattern (4-digit
    /// MegaNum, used when `style == 4`) and thickness (1 or 3).
    case lineStyle(style: Int, userPattern: Int, thickness: Int)
    /// `S` RIP_FILL_STYLE — predefined fill pattern 0...11 and fill color.
    case fillStyle(pattern: Int, color: Int)
    /// `s` RIP_FILL_PATTERN — custom 8x8 fill pattern (eight row bytes, top
    /// row first, most-significant bit leftmost) and fill color.
    case fillPattern(bytes: [UInt8], color: Int)
    /// `#` RIP_NO_MORE — end of the RIPscrip scene.
    case noMore

    // MARK: - Level 1

    /// `1M` RIP_MOUSE — rectangular hot region. `num` is obsolete (should be
    /// 0), `click` (1 digit) inverts the region while pressed, `clear`
    /// (1 digit) zooms the text window to full screen and clears it, and
    /// `reserved` is a 5-digit MegaNum. `hostCommand` is sent on click
    /// (`^M`-style control-character notation is preserved verbatim).
    case mouse(num: Int, x0: Int, y0: Int, x1: Int, y1: Int, click: Int, clear: Int, reserved: Int, hostCommand: String)
    /// `1K` RIP_KILL_MOUSE_FIELDS — forget every mouse region.
    case killMouseFields
    /// `1T` RIP_BEGIN_TEXT — start a formatted text region.
    case beginText(x0: Int, y0: Int, x1: Int, y1: Int, reserved: Int)
    /// `1t` RIP_REGION_TEXT — one line of region text; `justify` (1 digit)
    /// is 1 for full left/right justification.
    case regionText(justify: Int, string: String)
    /// `1E` RIP_END_TEXT — end the formatted text region.
    case endText
    /// `1C` RIP_GET_IMAGE — copy a rectangle to the clipboard
    /// (`reserved` is 1 digit).
    case getImage(x0: Int, y0: Int, x1: Int, y1: Int, reserved: Int)
    /// `1P` RIP_PUT_IMAGE — paste the clipboard at `(x, y)`. `mode`: 0 copy,
    /// 1 XOR, 2 OR, 3 AND, 4 NOT. `reserved` is 1 digit.
    case putImage(x: Int, y: Int, mode: Int, reserved: Int)
    /// `1W` RIP_WRITE_ICON — write the clipboard to an icon file
    /// (`reserved` is 1 digit).
    case writeIcon(reserved: Int, filename: String)
    /// `1I` RIP_LOAD_ICON — load and stamp an `.ICN` file. `mode` as for
    /// ``putImage(x:y:mode:reserved:)``; `clipboard` (1 digit) also copies the
    /// icon to the clipboard.
    case loadIcon(x: Int, y: Int, mode: Int, clipboard: Int, reserved: Int, filename: String)
    /// `1B` RIP_BUTTON_STYLE — define how subsequent buttons look and behave.
    case buttonStyle(RIPButtonStyle)
    /// `1U` RIP_BUTTON — create a button using the current button style.
    /// `flags` (1 digit): 1 = drawn selected, 2 = default button. `reserved`
    /// is 1 digit. `text` is the raw `icon<>label<>host-command` block; see
    /// ``RIPButtonText``.
    case button(x0: Int, y0: Int, x1: Int, y1: Int, hotkey: Int, flags: Int, reserved: Int, text: String)
    /// `1D` RIP_DEFINE — define a text variable. `flags` is a 3-digit
    /// MegaNum (1 = save to database, 2 = non-blank, 4 = non-interactive).
    case define(flags: Int, reserved: Int, text: String)
    /// `1<ESC>` RIP_QUERY — query text variables. `mode` (1 digit): 0 now,
    /// 1 on graphics-window click, 2 on text-window click. `reserved` is
    /// 3 digits.
    case query(mode: Int, reserved: Int, text: String)
    /// `1G` RIP_COPY_REGION — copy screen rows `y0...y1` (columns aligned to
    /// 8 pixels) to scan line `destLine`. Absolute screen coordinates.
    case copyRegion(x0: Int, y0: Int, x1: Int, y1: Int, reserved: Int, destLine: Int)
    /// `1R` RIP_READ_SCENE — play back a local `.RIP` file (`reserved` is an
    /// 8-digit MegaNum).
    case readScene(reserved: Int, filename: String)
    /// `1F` RIP_FILE_QUERY — ask whether a local file exists. `mode` 0...4
    /// selects the reply format; `reserved` is 4 digits.
    case fileQuery(mode: Int, reserved: Int, filename: String)

    // MARK: - Level 9

    /// `9<ESC>` RIP_ENTER_BLOCK_MODE — start a file transfer. `mode` (1 digit)
    /// 0 = download, 1 = upload; `transferProtocol` (1 digit) 0...7 (Xmodem ...
    /// Zmodem); `fileType` (2 digits) 0...5; `reserved` is 4 digits. The
    /// trailing `<>` terminator is not part of `filename`.
    case enterBlockMode(mode: Int, transferProtocol: Int, fileType: Int, reserved: Int, filename: String)

    // MARK: - Out-of-band

    /// ANSI auto-sense sequence found outside a RIPscrip line. It has no
    /// rendering effect; it is surfaced so a terminal can respond.
    case ansiSense(RIPAnsiSense)

    /// A syntactically valid command that RIPscrip 1.54 does not define.
    ///
    /// - `level`: the level/sub-level digits (empty for Level 0, `"1"`,
    ///   `"15"`, ...).
    /// - `command`: the command type character.
    /// - `arguments`: the remaining characters of the command exactly as
    ///   they appeared on the wire (still escaped), so the writer can
    ///   re-emit them losslessly.
    case unknown(level: String, command: Character, arguments: String)
}

/// A coordinate pair as it appears in a RIPscrip command.
public struct RIPPoint: Equatable, Hashable, Sendable {
    /// Horizontal coordinate in pixels.
    public let x: Int
    /// Vertical coordinate in pixels (grows downward).
    public let y: Int

    /// Create a point.
    /// - Parameters:
    ///   - x: Horizontal coordinate in pixels.
    ///   - y: Vertical coordinate in pixels.
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// The arguments of `1B` RIP_BUTTON_STYLE.
///
/// On the wire the command is `!|1B` followed by 36 MegaNum digits:
/// `wid:2 hgt:2 orient:2 flags:4 size:2 dfore:2 dback:2 bright:2 dark:2
/// surface:2 grp_no:2 flags2:2 uline_col:2 corner_col:2 res:6`.
public struct RIPButtonStyle: Equatable, Hashable, Sendable {
    /// Fixed button width in pixels, or 0 for dynamically sized buttons.
    public var width: Int
    /// Fixed button height in pixels, or 0 for dynamically sized buttons.
    public var height: Int
    /// Label position: 0 above, 1 left, 2 center, 3 right, 4 below.
    public var orientation: Int
    /// First flag word (4-digit MegaNum); see the `Flag` constants.
    public var flags: Int
    /// Bevel thickness in pixels (used with ``Flag/bevel``).
    public var bevelSize: Int
    /// Label color.
    public var labelColor: Int
    /// Label drop-shadow color.
    public var dropShadowColor: Int
    /// Highlight color for special effects.
    public var brightColor: Int
    /// Shadow color for special effects.
    public var darkColor: Int
    /// Surface color of plain buttons.
    public var surfaceColor: Int
    /// Button group 0...35 (radio / check-box groups, templates).
    public var groupNumber: Int
    /// Second flag word; see the `Flag2` constants.
    public var flags2: Int
    /// Hot-key underline / highlight color.
    public var underlineColor: Int
    /// Bevel / recess corner color.
    public var cornerColor: Int
    /// Reserved (6-digit MegaNum).
    public var reserved: Int

    /// Create a button style. All values are taken verbatim.
    public init(width: Int, height: Int, orientation: Int, flags: Int, bevelSize: Int,
                labelColor: Int, dropShadowColor: Int, brightColor: Int, darkColor: Int,
                surfaceColor: Int, groupNumber: Int, flags2: Int, underlineColor: Int,
                cornerColor: Int, reserved: Int) {
        self.width = width
        self.height = height
        self.orientation = orientation
        self.flags = flags
        self.bevelSize = bevelSize
        self.labelColor = labelColor
        self.dropShadowColor = dropShadowColor
        self.brightColor = brightColor
        self.darkColor = darkColor
        self.surfaceColor = surfaceColor
        self.groupNumber = groupNumber
        self.flags2 = flags2
        self.underlineColor = underlineColor
        self.cornerColor = cornerColor
        self.reserved = reserved
    }

    /// Bit values of ``flags`` (RIPscrip 1.54, "flags field #1").
    public enum Flag {
        /// Clipboard button: the clipboard is the button image.
        public static let clipboard = 1
        /// Invert the button while it is clicked.
        public static let invertable = 2
        /// Perform RIP_RESET_WINDOWS after the button is clicked.
        public static let resetScreen = 4
        /// Chisel special effect.
        public static let chisel = 8
        /// Recessed special effect.
        public static let recessed = 16
        /// Drop-shadow the label.
        public static let dropShadow = 32
        /// Auto-stamp the button image onto the clipboard.
        public static let autoStamp = 64
        /// Icon button: the image is loaded from an `.ICN` file.
        public static let icon = 128
        /// Plain button: a rectangle filled with the surface color.
        public static let plain = 256
        /// Bevel special effect.
        public static let bevel = 512
        /// The button is a clickable mouse button.
        public static let mouseButton = 1024
        /// Underline the hot key in the label.
        public static let underlineHotKey = 2048
        /// Icon buttons use "hot icons" (`.HIC`) while pressed.
        public static let hotIcons = 4096
        /// Include descenders when centering the label vertically.
        public static let adjustVerticalCentering = 8192
        /// The button belongs to a radio group.
        public static let radioGroup = 16384
        /// Sunken special effect.
        public static let sunken = 32768
    }

    /// Bit values of ``flags2`` (RIPscrip 1.54, "flags field #2").
    public enum Flag2 {
        /// The button is in a check-box group.
        public static let checkBox = 1
        /// Highlight the hot-key character.
        public static let highlightHotKey = 2
        /// Zoom out when clicked.
        public static let explode = 4
        /// Left-justify top/center/bottom labels.
        public static let leftJustifyLabel = 8
        /// Right-justify top/center/bottom labels.
        public static let rightJustifyLabel = 16
    }
}

/// The three `<>`-separated blocks of a `1U` RIP_BUTTON text parameter:
/// `[icon-file][<>text-label][<>host-command]`.
public struct RIPButtonText: Equatable, Hashable, Sendable {
    /// Icon file name (empty when the button is not an icon button).
    public var iconFile: String
    /// Label text (may be empty).
    public var label: String
    /// Host command sent when the button is clicked (may be empty). Any
    /// further `<>` sequences belong to the host command.
    public var hostCommand: String

    /// Create the blocks directly.
    public init(iconFile: String, label: String, hostCommand: String) {
        self.iconFile = iconFile
        self.label = label
        self.hostCommand = hostCommand
    }

    /// Split a raw `1U` text parameter at its first two `<>` delimiters.
    /// - Parameter text: The `text` argument of ``RIPCommand/button(x0:y0:x1:y1:hotkey:flags:reserved:text:)``.
    public init(parsing text: String) {
        var rest = Substring(text)
        func nextBlock() -> String {
            if let r = rest.range(of: "<>") {
                let block = String(rest[..<r.lowerBound])
                rest = rest[r.upperBound...]
                return block
            }
            let block = String(rest)
            rest = ""
            return block
        }
        iconFile = nextBlock()
        label = nextBlock()
        hostCommand = String(rest)
    }

    /// The raw text parameter (`icon<>label<>host`), omitting trailing empty
    /// blocks.
    public var rawValue: String {
        if hostCommand.isEmpty {
            return label.isEmpty ? iconFile : iconFile + "<>" + label
        }
        return iconFile + "<>" + label + "<>" + hostCommand
    }
}

/// The ANSI auto-sense sequences of RIPscrip 1.54. They are sent by a host
/// outside RIPscrip lines.
public enum RIPAnsiSense: Equatable, Hashable, Sendable {
    /// `ESC[!` — query the RIPscrip version (terminal replies `RIPSCRIPxxyyvs`).
    case query
    /// `ESC[0!` — same as ``query``.
    case queryAlternate
    /// `ESC[1!` — disable RIPscrip processing; RIPscrip lines become raw text.
    case disable
    /// `ESC[2!` — (re-)enable RIPscrip processing.
    case enable
}

/// A parsed RIPscrip scene: the commands of one input stream in source order.
public struct RIPScene: Equatable, Sendable {
    /// Commands in source order.
    public let commands: [RIPCommand]

    /// Create a scene from a list of commands.
    /// - Parameter commands: Commands in playback order.
    public init(commands: [RIPCommand]) {
        self.commands = commands
    }
}
