// RobustnessTests — untrusted input must never crash, hang or take
// unbounded time: truncation at every byte, seeded mutation fuzzing and
// pathological scripts.

import XCTest
import CoreGraphics
@testable import SwiftRIP

final class RobustnessTests: XCTestCase {

    /// A scene exercising every command family, framing feature and escape.
    static let fixture: String = [
        "\u{1B}[!",
        "!|*|e|w00001B0M10|v00002E1M|g0509|H|>|cA|Q000102030405060708090A0B0C0D0E0F|a051B|W01|W00",
        "!|m0509|Thello \\! world \\| pipe \\\\|@0011hello world|Y01000400|X1122|L00010A0E|R00010A0E",
        "!|B00010A0E|C1E180M|O1E1A18003G15|o1G2B0M0G|A1E18003G15|V1E18003G151Q|I1E18003G15",
        "!|i1E18003G151Q|Z0A0B0C0D0E0F0G0H1G|P03010105090905|p03010105050909|l03010105090905",
        "!|F25090F|=04F0F003|S050F|s11223344556677880F|c02|L02030405|P0901020102010201020102\\",
        "0102010201020102",
        "!|1M00001122331100000host command^M|1K|1T00110011|1t1This is justified|1E|1C001122330",
        "!|1P0011010|1W0filename.icn|1I001101010button.icn|1B0A0A010274030F080F080700010E07000000",
        "!|1U010100003200iconfile<>Label<>HostCmd^m|1D00700text_var,60:?question?default data",
        "!|1\u{1B}0000this is a query $COMMAND$^m|1G080G140M0005|1R00000000testfile.rip",
        "!|1F010000testfile.icn|15Lsub-level|@2233literal \\\\\\",
        "continued",
        "\u{02}|9\u{1B}00010000ICONFILE.ICN<>",
        "!|#|#|#",
    ].joined(separator: "\r\n") + "\r\n"

    /// Parse; if that succeeds, check the writer round trip and (optionally)
    /// render with a small budget.
    private func exercise(_ data: Data, render: Bool, budget: Int = 200_000) {
        guard let scene = try? RIPParser.parse(data) else { return }
        defer { roundTrip(scene) }
        guard render else { return }
        let result = SwiftRIP.renderResult(scene, options: {
            var o = RIPRenderOptions()
            o.pixelBudget = budget
            return o
        }())
        XCTAssertEqual(result.framebuffer.indexed.count, 640 * 350)
    }

    private func roundTrip(_ scene: RIPScene) {
        if let text = try? RIPWriter.encode(scene) {
            XCTAssertEqual(try? RIPParser.parse(text).commands.filter { if case .ansiSense = $0 { false } else { true } },
                           scene.commands.filter { if case .ansiSense = $0 { false } else { true } })
        }
    }

    func testFixtureParsesCompletely() throws {
        let scene = try RIPParser.parse(Data(Self.fixture.utf8))
        XCTAssertEqual(scene.commands.count, 61)
        XCTAssertEqual(scene.commands.first, .ansiSense(.query))
        XCTAssertEqual(scene.commands.last, .noMore)
        let result = SwiftRIP.renderResult(scene)
        XCTAssertFalse(result.isTruncated)
        XCTAssertTrue(result.interactive.noMore)
        XCTAssertEqual(result.interactive.unknowns, [.unknown(level: "15", command: "L", arguments: "sub-level")])
        XCTAssertTrue(scene.commands.contains(.textXY(x: 74, y: 111, string: "literal \\continued")))
    }

    func testTruncationAtEveryByteOffset() {
        let bytes = Array(Self.fixture.utf8)
        for length in 0...bytes.count {
            exercise(Data(bytes[0..<length]), render: length % 16 == 0 || length == bytes.count)
        }
    }

    func testSeededMutationFuzz() {
        var rng = SplitMix64(seed: 0x5249_5053_4352_4950) // "RIPSCRIP"
        let base = Array(Self.fixture.utf8)
        let interesting: [UInt8] = Array("|!\\\r\n0Zz9#*1".utf8) + [0x1B, 0x01, 0x02, 0x00, 0xFF, 0x80]
        for iteration in 0..<3000 {
            var bytes = base
            for _ in 0..<Int.random(in: 1...8, using: &rng) {
                let i = Int.random(in: 0..<max(1, bytes.count), using: &rng)
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: if !bytes.isEmpty { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
                case 1: bytes.insert(interesting.randomElement(using: &rng)!, at: min(i, bytes.count))
                case 2: if !bytes.isEmpty { bytes.remove(at: i) }
                case 3: if !bytes.isEmpty { bytes[i] = interesting.randomElement(using: &rng)! }
                default:
                    let j = Int.random(in: 0..<max(1, bytes.count), using: &rng)
                    let lo = min(i, j), hi = min(max(i, j), lo + 64, bytes.count)
                    bytes.insert(contentsOf: bytes[lo..<hi], at: min(i, bytes.count))
                }
            }
            exercise(Data(bytes), render: iteration % 50 == 0)
        }
    }

    func testRandomBytesNeverCrashParser() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<300 {
            var bytes = Array("!|".utf8)
            for _ in 0..<Int.random(in: 0...400, using: &rng) {
                bytes.append(UInt8.random(in: 0...255, using: &rng))
            }
            _ = try? RIPParser.parse(Data(bytes))
            _ = RIPAnsiSequences.scan(Data(bytes))
        }
    }

    // MARK: - Pathological scripts

    /// Thousands of full-screen flood fills: each is bounded by the screen
    /// area and the pixel budget stops the script.
    func testThousandsOfFloodFillsHitTheBudget() {
        var lines: [String] = []
        for i in 0..<5000 {
            lines.append("!|S01" + MN(i % 2 == 0 ? 1 : 2) + "|F0A0A" + MN(i % 2 == 0 ? 2 : 1))
        }
        let scene = try! RIPParser.parse(lines.joined(separator: "\r\n"))
        var options = RIPRenderOptions()
        options.pixelBudget = 3_000_000
        let start = Date()
        let result = SwiftRIP.renderResult(scene, options: options)
        XCTAssertTrue(result.isTruncated)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testDefaultBudgetIsFinite() {
        XCTAssertNotNil(RIPRenderOptions.default.pixelBudget)
    }

    func testHugeTextCommandStopsAtClipEdge() {
        let long = String(repeating: "W", count: 1_000_000)
        let scene = try! RIPParser.parse("!|Y00000A00|@0000" + long + "\r\n")
        let result = SwiftRIP.renderResult(scene)
        XCTAssertFalse(result.isTruncated)
        XCTAssertLessThan(result.state.position.x, RIPInterpreter.coordinateLimit + 1)
    }

    func testExtremeGeometryIsBounded() {
        let maxPoints = (0..<1295).map { RIPPoint(x: ($0 * 7919) % 1296, y: ($0 * 104_729) % 1296) }
        let commands: [RIPCommand] = [
            .lineStyle(style: 4, userPattern: 1_679_615, thickness: 1295),
            .circle(x: 1295, y: 1295, radius: 1295),
            .oval(x: 0, y: 0, startAngle: 1295, endAngle: 0, xrad: 1295, yrad: 1295),
            .filledOval(x: 320, y: 175, xrad: 1295, yrad: 1295),
            .pieSlice(x: 320, y: 175, startAngle: 0, endAngle: 1295, radius: 1295),
            .ovalPieSlice(x: 0, y: 0, startAngle: 1, endAngle: 0, xrad: 1295, yrad: 1),
            .bezier(x0: 0, y0: 0, x1: 1295, y1: 1295, x2: 0, y2: 1295, x3: 1295, y3: 0, count: 1295),
            .polygon(points: maxPoints),
            .fillPolygon(points: maxPoints),
            .polyline(points: maxPoints),
            .fontStyle(font: 10, direction: 1, size: 1295, reserved: 0),
            .text(String(repeating: "@", count: 5000)),
            .textWindow(x0: 1295, y0: 1295, x1: 1295, y1: 1295, wrap: 1, size: 9),
            .eraseWindow, .eraseEOL, .gotoXY(x: 1295, y: 1295),
            .getImage(x0: 0, y0: 0, x1: 639, y1: 349, reserved: 0),
            .putImage(x: 0, y: 0, mode: 1295, reserved: 0),
            .copyRegion(x0: 0, y0: 0, x1: 1295, y1: 349, reserved: 0, destLine: 1295),
            .buttonStyle(RIPButtonStyle(width: 1295, height: 1295, orientation: 1295, flags: 1_679_615,
                                        bevelSize: 1295, labelColor: 1295, dropShadowColor: 1295, brightColor: 1295,
                                        darkColor: 1295, surfaceColor: 1295, groupNumber: 1295, flags2: 1295,
                                        underlineColor: 1295, cornerColor: 1295, reserved: 0)),
            .button(x0: 1295, y0: 1295, x1: 0, y1: 0, hotkey: 1295, flags: 35, reserved: 35, text: "a<>label<>c"),
        ]
        let start = Date()
        let result = SwiftRIP.renderResult(RIPScene(commands: commands))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertEqual(result.framebuffer.indexed.count, 640 * 350)
    }

    /// Values outside the wire format's range (only reachable through the
    /// public API) must not overflow or trap.
    func testIntExtremesFromPublicAPIDoNotTrap() {
        let big = Int.max, small = Int.min
        let commands: [RIPCommand] = [
            .viewport(x0: small, y0: small, x1: big, y1: big),
            .line(x0: small, y0: small, x1: big, y1: big),
            .rectangle(x0: big, y0: big, x1: small, y1: small),
            .bar(x0: small, y0: small, x1: big, y1: big),
            .circle(x: big, y: small, radius: big),
            .arc(x: 0, y: 0, startAngle: small, endAngle: big, radius: big),
            .ovalArc(x: 0, y: 0, startAngle: big, endAngle: small, xrad: small, yrad: big),
            .bezier(x0: big, y0: small, x1: big, y1: small, x2: big, y2: small, x3: big, y3: small, count: big),
            .polygon(points: [RIPPoint(x: big, y: big), RIPPoint(x: small, y: small), RIPPoint(x: big, y: small)]),
            .fillPolygon(points: [RIPPoint(x: big, y: big), RIPPoint(x: small, y: small), RIPPoint(x: big, y: small)]),
            .fill(x: big, y: small, border: big),
            .color(big), .writeMode(small), .lineStyle(style: big, userPattern: small, thickness: big),
            .fillStyle(pattern: small, color: small), .fillPattern(bytes: [], color: big),
            .fontStyle(font: big, direction: small, size: big, reserved: 0),
            .setPalette([big, small]), .onePalette(slot: big, value: small),
            .move(x: big, y: big), .text("x"), .textXY(x: small, y: small, string: "y"),
            .textWindow(x0: big, y0: small, x1: big, y1: small, wrap: big, size: small),
            .gotoXY(x: big, y: small), .eraseEOL, .eraseWindow,
            .getImage(x0: small, y0: small, x1: big, y1: big, reserved: 0),
            .putImage(x: big, y: small, mode: big, reserved: 0),
            .copyRegion(x0: small, y0: small, x1: big, y1: big, reserved: 0, destLine: big),
            .copyRegion(x0: 0, y0: 0, x1: big, y1: big, reserved: 0, destLine: big),
            .copyRegion(x0: 0, y0: 0, x1: 7, y1: 7, reserved: 0, destLine: big),
            .fontStyle(font: 0, direction: 1, size: 1, reserved: 0), .text("vertical"),
            .beginText(x0: small, y0: small, x1: big, y1: big, reserved: 0),
            .regionText(justify: 1, string: "a b c"),
            .mouse(num: 0, x0: big, y0: big, x1: small, y1: small, click: 0, clear: 0, reserved: 0, hostCommand: ""),
            .buttonStyle(RIPButtonStyle(width: big, height: big, orientation: small, flags: -1, bevelSize: big,
                                        labelColor: big, dropShadowColor: small, brightColor: big, darkColor: small,
                                        surfaceColor: big, groupNumber: 0, flags2: -1, underlineColor: 0,
                                        cornerColor: big, reserved: 0)),
            .button(x0: big, y0: small, x1: small, y1: big, hotkey: big, flags: big, reserved: 0, text: "<>L"),
        ]
        _ = SwiftRIP.renderResult(RIPScene(commands: commands))
        XCTAssertThrowsError(try RIPWriter.encode(RIPScene(commands: commands)))
    }

    func testLongContinuationChainAndManySegments() throws {
        let chained = "!|T" + String(repeating: "ab\\\r\n", count: 20_000) + "end\r\n"
        let scene = try RIPParser.parse(chained)
        XCTAssertEqual(scene.commands, [.text(String(repeating: "ab", count: 20_000) + "end")])
        let segments = "!|" + String(repeating: "|", count: 50_000) + "c01\r\n"
        XCTAssertEqual(try RIPParser.parse(segments).commands, [.color(1)])
    }
}

/// Regressions for issues found in code review of the rewrite.
final class ReviewRegressionTests: XCTestCase {

    /// Escape pairs in `.unknown` arguments must never be split by a fold.
    func testUnknownArgumentsSurviveFolding() throws {
        let source = "!|z" + String(repeating: "a", count: 71) + "\\|b\r\n"
        let scene = try RIPParser.parse(source)
        XCTAssertEqual(scene.commands, [.unknown(level: "", command: "z", arguments: String(repeating: "a", count: 71) + "\\|b")])
        for width in 8...80 {
            let text = try RIPWriter.encode(scene, lineWidth: width)
            XCTAssertEqual(try RIPParser.parse(text), scene, "width \(width)")
        }
    }

    /// Off-screen geometry still consumes the budget.
    func testOffScreenPieSlicesHitTheBudget() throws {
        let scene = try RIPParser.parse("!|" + Array(repeating: "IZZ4V00A0I7", count: 2000).joined(separator: "|") + "\r\n")
        var options = RIPRenderOptions()
        options.pixelBudget = 20_000_000
        let start = Date()
        let result = SwiftRIP.renderResult(scene, options: options)
        XCTAssertTrue(result.isTruncated)
        XCTAssertTrue(result.framebuffer.indexed.allSatisfy { $0 == 0 })
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testInvisibleLinesHitTheBudget() throws {
        let scene = try RIPParser.parse("!|=04000001|" + Array(repeating: "L0000HR9P", count: 20_000).joined(separator: "|"))
        var options = RIPRenderOptions()
        options.pixelBudget = 1_000_000
        XCTAssertTrue(SwiftRIP.renderResult(scene, options: options).isTruncated)
    }

    func testPublicAPIExtremesDoNotTrap() {
        var options = RIPRenderOptions()
        options.targetSize = CGSize(width: 1e20, height: -1e20)
        options.antiAliasing = false
        XCTAssertEqual(SwiftRIP.render(RIPScene(commands: []), options: options)?.width, 16_384)
        XCTAssertNil(RIPFramebuffer(width: .max, height: 2, indexed: [], palette: []).colorIndex(x: 1, y: 1))
        XCTAssertNil(RIPFramebuffer(width: 1 << 32, height: 1 << 32, indexed: [], palette: []).cgImage())
        XCTAssertThrowsError(try MegaNum.encode(0, width: .max))
        XCTAssertThrowsError(try MegaNum.encode(0, width: 1 << 34))
        XCTAssertEqual(try MegaNum.encode(0, width: MegaNum.maxWidth).count, MegaNum.maxWidth)
    }

    func testWriterRejectsUnrepresentableValues() {
        func encode(_ c: RIPCommand, lineEnding: String = "\r\n") throws -> String {
            try RIPWriter.encode(RIPScene(commands: [c]), lineEnding: lineEnding)
        }
        XCTAssertThrowsError(try encode(.enterBlockMode(mode: 0, transferProtocol: 0, fileType: 0, reserved: 0, filename: "A<>B")))
        XCTAssertThrowsError(try encode(.unknown(level: "", command: "z", arguments: "a|L00000000")))
        XCTAssertThrowsError(try encode(.unknown(level: "", command: "c", arguments: "05")))
        XCTAssertThrowsError(try encode(.unknown(level: "1", command: "M", arguments: "")))
        XCTAssertThrowsError(try encode(.unknown(level: "", command: "e\u{301}", arguments: "")))
        XCTAssertThrowsError(try encode(.unknown(level: "", command: " ", arguments: "")))
        XCTAssertThrowsError(try encode(.color(1), lineEnding: "\n\r"))
        XCTAssertThrowsError(try encode(.color(1), lineEnding: ""))
        XCTAssertEqual(try encode(.unknown(level: "", command: "z", arguments: "a!b\\")), "!|za!b\\\\\r\n")
    }
}
