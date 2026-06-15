import XCTest
@testable import SwiftRIP

/// Per-command parse-only smoke matrix.
///
/// Goal: every Level 0 / Level 1 / Level 9 dispatch path in `RIPParser` is
/// exercised by at least one assertion that the minimal well-formed encoding
/// of that command decodes without throwing and yields the correct
/// `RIPCommand` case. This is intentionally redundant with `ParserTests` —
/// it provides a single-glance coverage table so future refactors of the
/// parser dispatch surface a missing case immediately.
///
/// Width discipline matches `RIPParser`: x/y are 3-wide, palette slot is
/// 1-wide, palette value is 2-wide, etc. Helper `MN` encodes integers to
/// base-36 at the requested width.
private func MN(_ value: Int, _ width: Int) -> String {
    MegaNum.encode(value, width: width)
}

/// Wrap a command body in the canonical `!|<body>\n` RIP frame and decode it,
/// asserting that exactly one command is returned and that it matches the
/// expected case.
private func smoke(_ body: String, expect: RIPCommand,
                   file: StaticString = #file, line: UInt = #line) {
    do {
        let cmds = try RIPParser.parse("!|\(body)\n").commands
        XCTAssertEqual(cmds.count, 1, "expected single command for body=\(body)", file: file, line: line)
        XCTAssertEqual(cmds.first, expect, file: file, line: line)
    } catch {
        XCTFail("decode threw for body=\(body): \(error)", file: file, line: line)
    }
}

final class CommandCoverageTests: XCTestCase {

    // MARK: - Level 0: windows + cursor + clear

    func test_w_textWindow()    { smoke("w" + MN(1,2)+MN(1,2)+MN(10,2)+MN(5,2)+MN(0,1)+MN(1,1),
                                        expect: .textWindow(x0: 1, y0: 1, x1: 10, y1: 5, wrap: 0, size: 1)) }
    func test_v_viewport()      { smoke("v" + MN(0,3)+MN(0,3)+MN(639,3)+MN(349,3),
                                        expect: .viewport(x0: 0, y0: 0, x1: 639, y1: 349)) }
    func test_star_resetWindows() { smoke("*", expect: .resetWindows) }
    func test_e_eraseWindow()   { smoke("e", expect: .eraseWindow) }
    func test_E_eraseView()     { smoke("E", expect: .eraseView) }
    func test_g_gotoXY()        { smoke("g" + MN(10,3)+MN(20,3),
                                        expect: .gotoXY(x: 10, y: 20)) }
    func test_H_home()          { smoke("H", expect: .home) }
    func test_gt_eraseEOL()     { smoke(">", expect: .eraseEOL) }

    // MARK: - Level 0: color + palette + write mode

    func test_c_color()         { smoke("c" + MN(15,2), expect: .color(15)) }
    func test_Q_setPalette() {
        let body = "Q" + (0..<16).map { MN($0, 2) }.joined()
        smoke(body, expect: .setPalette(Array(0..<16)))
    }
    func test_a_onePalette()    { smoke("a" + MN(5,1)+MN(31,2),
                                        expect: .onePalette(slot: 5, value: 31)) }
    func test_W_writeMode()     { smoke("W" + MN(1,1), expect: .writeMode(1)) }
    func test_m_move()          { smoke("m" + MN(7,3)+MN(8,3),
                                        expect: .move(x: 7, y: 8)) }

    // MARK: - Level 0: text

    func test_T_text()          { smoke("THello", expect: .text("Hello")) }
    func test_at_textXY()       { smoke("@" + MN(1,3)+MN(2,3) + "Hi",
                                        expect: .textXY(x: 1, y: 2, string: "Hi")) }
    func test_Y_fontStyle()     { smoke("Y" + MN(1,2)+MN(0,2)+MN(2,2)+MN(0,2),
                                        expect: .fontStyle(font: 1, direction: 0, size: 2, reserved: 0)) }

    // MARK: - Level 0: primitives

    func test_X_pixel()         { smoke("X" + MN(10,3)+MN(11,3),
                                        expect: .pixel(x: 10, y: 11)) }
    func test_L_line()          { smoke("L" + MN(0,3)+MN(10,3)+MN(36,3)+MN(40,3),
                                        expect: .line(x0: 0, y0: 10, x1: 36, y1: 40)) }
    func test_R_rectangle()     { smoke("R" + MN(0,3)+MN(0,3)+MN(36,3)+MN(36,3),
                                        expect: .rectangle(x0: 0, y0: 0, x1: 36, y1: 36)) }
    func test_B_bar()           { smoke("B" + MN(0,3)+MN(0,3)+MN(36,3)+MN(36,3),
                                        expect: .bar(x0: 0, y0: 0, x1: 36, y1: 36)) }
    func test_C_circle()        { smoke("C" + MN(180,3)+MN(180,3)+MN(36,3),
                                        expect: .circle(x: 180, y: 180, radius: 36)) }
    func test_O_oval()          { smoke("O" + MN(180,3)+MN(180,3)+MN(0,3)+MN(360,3)+MN(72,3)+MN(36,3),
                                        expect: .oval(x: 180, y: 180, startAngle: 0, endAngle: 360, xrad: 72, yrad: 36)) }
    func test_o_filledOval()    { smoke("o" + MN(180,3)+MN(180,3)+MN(72,3)+MN(36,3),
                                        expect: .filledOval(x: 180, y: 180, xrad: 72, yrad: 36)) }
    func test_A_arc()           { smoke("A" + MN(180,3)+MN(180,3)+MN(0,3)+MN(360,3)+MN(36,3),
                                        expect: .arc(x: 180, y: 180, startAngle: 0, endAngle: 360, radius: 36)) }
    func test_V_ovalArc()       { smoke("V" + MN(180,3)+MN(180,3)+MN(0,3)+MN(360,3)+MN(72,3)+MN(36,3),
                                        expect: .ovalArc(x: 180, y: 180, startAngle: 0, endAngle: 360, xrad: 72, yrad: 36)) }
    func test_I_pieSlice()      { smoke("I" + MN(180,3)+MN(180,3)+MN(0,3)+MN(360,3)+MN(36,3),
                                        expect: .pieSlice(x: 180, y: 180, startAngle: 0, endAngle: 360, radius: 36)) }
    func test_i_ovalPieSlice()  { smoke("i" + MN(180,3)+MN(180,3)+MN(0,3)+MN(360,3)+MN(72,3)+MN(36,3),
                                        expect: .ovalPieSlice(x: 180, y: 180, startAngle: 0, endAngle: 360, xrad: 72, yrad: 36)) }
    func test_Z_bezier()        { smoke("Z" + MN(0,3)+MN(10,3)+MN(36,3)+MN(36,3)+MN(180,3)+MN(180,3)+MN(36,3)+MN(36,3)+MN(10,2),
                                        expect: .bezier(x0: 0, y0: 10, x1: 36, y1: 36, x2: 180, y2: 180, x3: 36, y3: 36, count: 10)) }

    // MARK: - Level 0: polygons + fill + styles

    func test_P_polygon() {
        let pts: [RIPPoint] = [.init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 10)]
        smoke("P" + MN(pts.count, 2) + pts.map { MN($0.x,3)+MN($0.y,3) }.joined(),
              expect: .polygon(points: pts))
    }
    func test_p_fillPolygon() {
        let pts: [RIPPoint] = [.init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 10)]
        smoke("p" + MN(pts.count, 2) + pts.map { MN($0.x,3)+MN($0.y,3) }.joined(),
              expect: .fillPolygon(points: pts))
    }
    func test_l_polyline() {
        let pts: [RIPPoint] = [.init(x: 0, y: 0), .init(x: 10, y: 10)]
        smoke("l" + MN(pts.count, 2) + pts.map { MN($0.x,3)+MN($0.y,3) }.joined(),
              expect: .polyline(points: pts))
    }
    func test_F_fill()          { smoke("F" + MN(180,3)+MN(180,3)+MN(7,1),
                                        expect: .fill(x: 180, y: 180, border: 7)) }
    func test_eq_lineStyle()    { smoke("=" + MN(0,2)+MN(0,4)+MN(1,2),
                                        expect: .lineStyle(style: 0, userPattern: 0, thickness: 1)) }
    func test_S_fillStyle()     { smoke("S" + MN(0,2)+MN(7,2),
                                        expect: .fillStyle(pattern: 0, color: 7)) }
    func test_f_fillPattern() {
        let bytes: [UInt8] = [0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00]
        smoke("f" + bytes.map { MN(Int($0), 2) }.joined() + MN(7, 2),
              expect: .fillPattern(bytes: bytes, color: 7))
    }

    // MARK: - Level 1: text region + image + icon

    func test_1T_beginText()    { smoke("1T" + MN(0,3)+MN(0,3)+MN(216,3)+MN(216,3)+MN(0,2),
                                        expect: .beginText(x0: 0, y0: 0, x1: 216, y1: 216, reserved: 0)) }
    func test_1t_regionText()   { smoke("1t" + MN(2,2) + "Hi",
                                        expect: .regionText(flags: 2, string: "Hi")) }
    func test_1E_endText()      { smoke("1E", expect: .endText) }
    func test_1G_getImage()     { smoke("1G" + MN(0,3)+MN(0,3)+MN(216,3)+MN(216,3)+MN(0,2),
                                        expect: .getImage(x0: 0, y0: 0, x1: 216, y1: 216, reserved: 0)) }
    func test_1P_putImage()     { smoke("1P" + MN(0,3)+MN(216,3)+MN(1,1)+MN(0,2),
                                        expect: .putImage(x: 0, y: 216, mode: 1, reserved: 0)) }
    func test_1W_writeIcon()    { smoke("1WLOGO.ICN",
                                        expect: .writeIcon(filename: "LOGO.ICN")) }
    func test_1I_loadIcon()     { smoke("1I" + MN(0,3)+MN(216,3)+MN(0,1)+MN(1,1)+MN(0,2) + "LOGO.ICN",
                                        expect: .loadIcon(x: 0, y: 216, mode: 0, clipboard: 1, reserved: 0, filename: "LOGO.ICN")) }

    // MARK: - Level 1: buttons + mouse + define/query

    func test_1B_buttonStyle()  {
        let body = "1B" + MN(216,3)+MN(72,3)+MN(0,2)+MN(1,4)+MN(1,2)+MN(0,2)+MN(0,2)+MN(15,2)+MN(8,2)+MN(7,2)+MN(7,2)+MN(7,2)+MN(7,2)+MN(0,2)+MN(0,2) + "label"
        smoke(body, expect: .buttonStyle(width: 216, height: 72, orientation: 0, flags: 1, bevelSize: 1, dfore: 0, dback: 0, bright: 15, dark: 8, surface: 7, gborder: 7, gcorner: 7, uline: 7, corner: 0, reserved: 0, label: "label"))
    }
    func test_1U_button()       { smoke("1U" + MN(0,3)+MN(0,3)+MN(216,3)+MN(216,3)+MN(0x41,2)+MN(0,3) + "Login",
                                        expect: .button(x0: 0, y0: 0, x1: 216, y1: 216, hotkey: 0x41, flags: 0, label: "Login")) }
    func test_1M_mouse()        { smoke("1M" + MN(1,2)+MN(0,3)+MN(0,3)+MN(216,3)+MN(216,3)+MN(1,1)+MN(1,1) + "Hello|GO MAIN",
                                        expect: .mouse(num: 1, x0: 0, y0: 0, x1: 216, y1: 216, click: 1, clear: 1, text: "Hello", hostCommand: "GO MAIN")) }
    func test_1K_killMouseFields() { smoke("1K", expect: .killMouseFields) }
    func test_1D_define()       { smoke("1D" + MN(36,3)+MN(0,2) + "MyMacro",
                                        expect: .define(id: 36, flags: 0, string: "MyMacro")) }
    func test_1q_query()        { smoke("1?" + MN(0,2) + "GET STATUS",
                                        expect: .query(flags: 0, string: "GET STATUS")) }
    func test_1C_copyRegion()   { smoke("1C" + MN(0,3)+MN(0,3)+MN(216,3)+MN(216,3)+MN(1,1)+MN(36,3)+MN(72,3),
                                        expect: .copyRegion(x0: 0, y0: 0, x1: 216, y1: 216, destPage: 1, destX: 36, destY: 72)) }
    func test_1R_readScene()    { smoke("1RNEXT.RIP",
                                        expect: .readScene(filename: "NEXT.RIP")) }
    func test_1F_fileQuery()    { smoke("1FREADER.TXT|" + MN(0,2),
                                        expect: .fileQuery(filename: "READER.TXT", reserved: 0)) }

    // MARK: - Level 9: block mode

    func test_9lt_enterBlockMode() { smoke("9<" + MN(1,1)+MN(2,2)+MN(0,4) + "FILE.ICN",
                                           expect: .enterBlockMode(mode: 1, fileType: 2, reserved: 0, filename: "FILE.ICN")) }
    func test_9N_noMore()       { smoke("9NoMore", expect: .noMore) }
}
