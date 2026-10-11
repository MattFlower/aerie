import Foundation
import XCTest
@testable import AerieCore

final class MenuPresentationTests: XCTestCase {
  func testLegacyDefaultsRoundTripAndExplicitCombinedConfiguration() throws {
    var settings = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(Settings()))
    XCTAssertEqual(settings.effectiveCombinedModules, [.cpu, .memory])
    XCTAssertNil(settings.combinedColorHex); XCTAssertFalse(settings.effectivePersistentHistory)
    settings.combined = true; settings.menus = [];
    settings.combinedModules = [.network, .cpu, .memory]
    settings.combinedStyle = .stacked; settings.combinedColorHex = "#123ABC"
    XCTAssertEqual(try settings.validated(), settings)
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)), settings)
    settings.combinedStyle = .graph; XCTAssertThrowsError(try settings.validated())
    settings.combinedStyle = .text; settings.combinedModules = [.cpu, .cpu]
    XCTAssertThrowsError(try settings.validated())
    settings.combinedModules = [.overview]; XCTAssertThrowsError(try settings.validated())
    settings.combinedModules = []; XCTAssertThrowsError(try settings.validated())
    settings.combinedModules = [.cpu]; settings.combinedColorHex = "red"
    XCTAssertThrowsError(try settings.validated())
  }
  func testColorsAreOptionalExactHexRGBAndMenuTextIsBounded() throws {
    XCTAssertTrue(MenuColor.valid(nil)); XCTAssertEqual(MenuColor.rgb("#ff0044"), 0xff0044)
    for color in ["", "123456", "#123", "#12345678", "#GG0000", "#-10000"] {
      XCTAssertFalse(MenuColor.valid(color))
    }
    var settings = Settings(); settings.menus[0].colorHex = "#00FF44"
    XCTAssertNoThrow(try settings.validated()); settings.menus[0].colorHex = "#GG0000"
    XCTAssertThrowsError(try settings.validated())
    let value = MenuValue(full: String(repeating: "x", count: 10_000))
    XCTAssertEqual(value.full.count, 256); XCTAssertEqual(value.stackedPrimary.count, 256)
  }
  func testCombinedNamesAcceptCaseAndOrderWithoutExposingInternalIdentifiers() throws {
    XCTAssertEqual(
      try MenuPresentation.modules(fromTitles: " Network, cpu, Memory "), [.network, .cpu, .memory])
    for text in ["", "CPU,", "CPU,CPU", "Overview", "unknown", String(repeating: "x", count: 1025)]
    { XCTAssertThrowsError(try MenuPresentation.modules(fromTitles: text)) }
  }
  func testCombinedOrderAndTwoLineNetworkPreserveEveryChosenValue() {
    let cpu = MenuValue(full: "CPU 20%", compact: "20%", secondary: "U 10% S 10%")
    let memory = MenuValue(full: "MEM 40%", compact: "40%")
    let network = MenuValue(full: "↓10K ↑2K", secondary: "↑2K", stackedPrimary: "↓10K")
    XCTAssertEqual(MenuPresentation.combined([memory, cpu], compact: false), "MEM 40% · CPU 20%")
    XCTAssertEqual(MenuPresentation.combined([cpu, memory], compact: true), "20% · 40%")
    let single = MenuPresentation.stacked([network]); XCTAssertEqual(single.0, "↓10K");
    XCTAssertEqual(single.1, "↑2K")
    let pair = MenuPresentation.stacked([cpu, memory]); XCTAssertEqual(pair.0, "CPU 20%");
    XCTAssertEqual(pair.1, "MEM 40%")
    let triple = MenuPresentation.stacked([cpu, memory, network]);
    XCTAssertEqual(triple.0, "CPU 20% · MEM 40%"); XCTAssertEqual(triple.1, "↓10K ↑2K")
  }
  func testNetworkBriefAndAccessibleValuesStayDistinctForLegacyCombinedConsumers() {
    let value = MenuValue.network(download: "12 KiB/s", upload: "34 MiB/s")
    XCTAssertEqual(value.full, "Download 12 KiB/s, upload 34 MiB/s")
    XCTAssertEqual(value.compact, "↓12 KiB/s ↑34 MiB/s")
    XCTAssertEqual(MenuPresentation.combined([value], compact: true), "↓12 KiB/s ↑34 MiB/s")
    XCTAssertEqual(MenuPresentation.stacked([value]).0, "↓12 KiB/s")
    XCTAssertEqual(MenuPresentation.stacked([value]).1, "↑34 MiB/s")
    XCTAssertEqual(MenuValue.network(download: "—", upload: "—").compact, "↓— ↑—")
  }

}
