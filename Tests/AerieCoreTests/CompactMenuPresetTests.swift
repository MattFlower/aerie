import Foundation
import XCTest
@testable import AerieCore

final class CompactMenuPresetTests: XCTestCase {
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
