// RIPPalette — 64-color EGA master and 16-color RIP default mapping.
//
// EGA's color registers index a 64-color master table (six bits of intensity:
// rR gG bB). The RIPscrip spec inherits this model: the active palette is a
// 16-entry array, each entry being one of the 64 master values. The default
// RIP palette is the standard EGA boot palette (black, blue, green, cyan,
// red, magenta, brown, lightgray, darkgray, lightblue, lightgreen,
// lightcyan, lightred, lightmagenta, yellow, white).
//
// The 64 RGB values are computed from the standard EGA intensity rule:
//
//     bit 5: r' (low red)      bit 2: r (high red)
//     bit 4: g' (low green)    bit 1: g (high green)
//     bit 3: b' (low blue)     bit 0: b (high blue)
//
//   level = (high<<1 | low) * 0x55  — 0=0x00, 1=0x55, 2=0xAA, 3=0xFF
//
// This is the canonical EGA palette derivation and is in the public domain.

import Foundation

/// Static lookup tables and small mutators for the RIPscrip palette system.
public enum RIPPalette {

    /// Default RGB triplet type. Each component is 0..255.
    public struct RGB: Equatable, Sendable {
        public let r: UInt8
        public let g: UInt8
        public let b: UInt8

        public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
            self.r = r; self.g = g; self.b = b
        }
    }

    /// 64-entry master table — index by an EGA register value (0..63) to get
    /// an RGB triplet.
    public static let master: [RGB] = {
        var out: [RGB] = []
        out.reserveCapacity(64)
        for v in 0..<64 {
            // r bit 2, g bit 1, b bit 0 are the "high" intensity bits.
            // r' bit 5, g' bit 4, b' bit 3 are the "low" intensity bits.
            let rHi = (v >> 2) & 1
            let gHi = (v >> 1) & 1
            let bHi = (v >> 0) & 1
            let rLo = (v >> 5) & 1
            let gLo = (v >> 4) & 1
            let bLo = (v >> 3) & 1
            let r = UInt8((rHi << 1 | rLo) * 0x55)
            let g = UInt8((gHi << 1 | gLo) * 0x55)
            let b = UInt8((bHi << 1 | bLo) * 0x55)
            out.append(RGB(r, g, b))
        }
        return out
    }()

    /// Default RIPscrip 16-color palette, expressed as 64-color master
    /// indices. Matches the EGA BIOS default and the spec's color name
    /// table:
    ///
    ///   0 black       8 darkgray
    ///   1 blue        9 lightblue
    ///   2 green      10 lightgreen
    ///   3 cyan       11 lightcyan
    ///   4 red        12 lightred
    ///   5 magenta    13 lightmagenta
    ///   6 brown      14 yellow
    ///   7 lightgray  15 white
    public static let default16: [UInt8] = [
        0,   // 0  black        rgb 00,00,00 — register  0
        1,   // 1  blue         rgb 00,00,AA — register  1
        2,   // 2  green        rgb 00,AA,00 — register  2
        3,   // 3  cyan         rgb 00,AA,AA — register  3
        4,   // 4  red          rgb AA,00,00 — register  4
        5,   // 5  magenta      rgb AA,00,AA — register  5
        20,  // 6  brown        rgb AA,55,00 — register 20 (low-green high-red)
        7,   // 7  lightgray    rgb AA,AA,AA — register  7
        56,  // 8  darkgray     rgb 55,55,55 — register 56 (all low)
        57,  // 9  lightblue    rgb 55,55,FF — register 57
        58,  // 10 lightgreen   rgb 55,FF,55 — register 58
        59,  // 11 lightcyan    rgb 55,FF,FF — register 59
        60,  // 12 lightred     rgb FF,55,55 — register 60
        61,  // 13 lightmagenta rgb FF,55,FF — register 61
        62,  // 14 yellow       rgb FF,FF,55 — register 62
        63   // 15 white        rgb FF,FF,FF — register 63
    ]

    /// Replace all 16 palette slots at once (spec `Q` command).
    public static func setAll(_ values: [Int], on state: inout RIPGraphicsState) {
        precondition(values.count == 16, "setPalette requires 16 entries")
        var p = state.palette
        for i in 0..<16 {
            p[i] = UInt8(clamping: values[i])
        }
        state.palette = p
    }

    /// Replace one palette slot (spec `a` command).
    public static func setOne(slot: Int, value: Int, on state: inout RIPGraphicsState) {
        guard (0..<16).contains(slot) else { return }
        var p = state.palette
        p[slot] = UInt8(clamping: value)
        state.palette = p
    }

    /// Resolve a palette index (0..15) to a 24-bit RGB triplet using the
    /// state's active palette and the 64-color master table.
    public static func resolve(_ index: UInt8, in palette: [UInt8]) -> RGB {
        let slot = Int(index) & 0x0F
        let register = Int(palette[slot]) & 0x3F
        return master[register]
    }
}
