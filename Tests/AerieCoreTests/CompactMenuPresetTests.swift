import Foundation
import XCTest
@testable import AerieCore

final class CompactMenuPresetTests: XCTestCase {
  func testSavedCompactPresentationSurvivesRepeatedDecodeValidateAndEncode() throws {
    var expected = Settings(); expected.menus.reverse()
    expected.menus[0].visible = true; expected.processCount = 7
    expected = try expected.validated()
    var data = try JSONEncoder().encode(expected)
    for _ in 0..<3 {
      let restored = try JSONDecoder().decode(Settings.self, from: data).validated()
      XCTAssertEqual(restored, expected)
      XCTAssertTrue(restored.effectiveGroupedMenus)
      XCTAssertEqual(restored.effectiveMenuPadding, 0)
      XCTAssertEqual(restored.effectiveMenuGap, 2)
      XCTAssertEqual(restored.menus.map(\.labelPlacement), expected.menus.map(\.labelPlacement))
      data = try JSONEncoder().encode(restored)
    }
  }
  func testLegacyMissingPresentationFieldsPreserveSavedStylesWithoutApplyingFreshPreset() throws {
    var saved = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as? [String: Any])
    for key in ["groupedMenus", "menuPadding", "menuGap"] { saved.removeValue(forKey: key) }
    var menus = try XCTUnwrap(saved["menus"] as? [[String: Any]])
    for index in menus.indices {
      menus[index].removeValue(forKey: "labelPlacement")
      menus[index]["style"] = menus[index]["module"] as? String == "network" ? "stacked" : "text"
    }
    saved["menus"] = menus
    let restored = try JSONDecoder().decode(
      Settings.self, from: JSONSerialization.data(withJSONObject: saved)
    ).validated()
    XCTAssertFalse(restored.effectiveGroupedMenus)
    XCTAssertEqual(restored.effectiveMenuPadding, 1)
    XCTAssertEqual(restored.menus.first { $0.module == .network }?.style, .stacked)
    XCTAssertTrue(restored.menus.allSatisfy { $0.labelPlacement == nil })
    let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(restored))
      .validated()
    XCTAssertEqual(again, restored)
  }
  func testPresetPreservesEveryModuleSourceRuleUnitAndCollectorChoice() throws {
    var original = Settings(); original.interval = 0.5; original.processCount = 12
    original.sensorSampling = .all; original.networkInterfaces = ["en7"]
    original.weather.name = "Synthetic point"; original.weather.latitude = 10;
    original.weather.longitude = 20
    original.weather.enabled = true; original.temperature = .fahrenheit
    original.persistentHistory = true;
    original.rules = [ThresholdRule(metric: "cpu", threshold: 50)]
    original.menuPadding = 8; original.menuGap = 6; original.groupedMenus = false
    var compact = original; compact.applyCompactMenuPreset()
    var restored = compact
    restored.menus = original.menus; restored.groupedMenus = original.groupedMenus
    restored.combined = original.combined; restored.compactSpacing = original.compactSpacing
    restored.menuPadding = original.menuPadding; restored.menuGap = original.menuGap
    XCTAssertEqual(restored, original)
    XCTAssertEqual(compact.menus.map(\.module), original.menus.map(\.module))
    XCTAssertEqual(compact.menus.map(\.visible), original.menus.map(\.visible))
    XCTAssertEqual(try compact.validated(), compact)
  }
  func testNetworkShortUnitsKeepBitsDistinctAndOverflowAndUnknownHonest() {
    XCTAssertEqual(CompactNetworkColumn("↓9.9 MiB/s").unit, "MiB/s")
    XCTAssertEqual(CompactNetworkColumn("↑9.9 Mbit/s").unit, "Mb/s")
    XCTAssertEqual(CompactNetworkColumn("999.9 GiB/s").number, "999.9")
    XCTAssertEqual(CompactNetworkColumn("1000 GiB/s").number, ">999")
    XCTAssertEqual(CompactNetworkColumn("—").number, "—")
    for invalid in ["nan B/s", "-1 B/s", "1 unknown", "1 2 3", String(repeating: "9", count: 256)] {
      XCTAssertEqual(CompactNetworkColumn(invalid).number, "…")
    }
  }
}
