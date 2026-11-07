import Foundation
@testable import SwiftRIP

/// Encode `value` as a `width`-digit MegaNum for building fixtures.
func MN(_ value: Int, _ width: Int = 2) -> String {
    try! MegaNum.encode(value, width: width)
}

/// Parse a single RIPscrip line body (`!|<body>`).
func parseBody(_ body: String) throws -> [RIPCommand] {
    try RIPParser.parse("!|" + body + "\r\n").commands
}

/// Execute commands against a fresh canvas and return the interpreter.
@discardableResult
func execute(_ commands: [RIPCommand], budget: Int? = nil) -> RIPInterpreter {
    let interpreter = RIPInterpreter(canvas: RIPCanvas(), pixelBudget: budget)
    interpreter.run(RIPScene(commands: commands))
    return interpreter
}

extension RIPInterpreter {
    /// Palette index at an absolute pixel.
    func px(_ x: Int, _ y: Int) -> UInt8 { canvas.index(x: x, y: y) }
}

/// Simple deterministic PRNG (SplitMix64) for fuzz tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
