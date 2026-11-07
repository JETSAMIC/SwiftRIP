// RIPPalette — the 64-color EGA master palette and the default 16-color
// RIPscrip palette.
//
// An EGA palette register holds six bits `r'g'b'RGB` (bit 5 ... bit 0): the
// upper-case bits contribute 2/3 intensity (0xAA) and the primed bits 1/3
// (0x55) of their channel.
//
// Default palette: RIPscrip 1.54 lists the 16-color default palette in the
// RIP_SET_PALETTE section, but its "Master 64-Color" column swaps two
// entries (it gives Brown as 7 and Light Gray as 20 (0K)). Register 7 is
// light gray (AA,AA,AA) and register 20 is brown (AA,55,00) in the EGA
// colour model, and the color names in the same table (06 Brown, 07 Light
// Gray) only make sense with the standard EGA BIOS palette
// {0,1,2,3,4,5,20,7,56,57,58,59,60,61,62,63}, which is what RIPscrip
// terminals use. SwiftRIP follows the color names.

import Foundation

/// The EGA master palette and the default RIPscrip palette.
public enum RIPPalette {

    /// An 8-bit-per-channel RGB color.
    public struct RGB: Equatable, Hashable, Sendable {
        /// Red, 0...255.
        public let r: UInt8
        /// Green, 0...255.
        public let g: UInt8
        /// Blue, 0...255.
        public let b: UInt8

        /// Create a color.
        public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    /// The 64-color EGA master palette, indexed by register value 0...63.
    public static let master: [RGB] = (0..<64).map { v in
        func level(_ high: Int, _ low: Int) -> UInt8 {
            UInt8(((v >> high) & 1) * 0xAA + ((v >> low) & 1) * 0x55)
        }
        return RGB(level(2, 5), level(1, 4), level(0, 3))
    }

    /// The default 16-color RIPscrip palette as master-palette values
    /// (black, blue, green, cyan, red, magenta, brown, light gray, dark gray,
    /// light blue, light green, light cyan, light red, light magenta, yellow,
    /// white). Restored by RIP_RESET_WINDOWS.
    public static let default16: [UInt8] = [0, 1, 2, 3, 4, 5, 20, 7, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Resolve a palette index through a 16-entry palette to RGB.
    ///
    /// - Parameters:
    ///   - index: Palette index; only the low four bits are used.
    ///   - palette: A 16-entry palette of master values (low six bits used).
    ///     Missing entries resolve to black.
    /// - Returns: The RGB color.
    public static func resolve(_ index: UInt8, in palette: [UInt8]) -> RGB {
        let slot = Int(index & 0x0F)
        guard slot < palette.count else { return master[0] }
        return master[Int(palette[slot] & 0x3F)]
    }
}
