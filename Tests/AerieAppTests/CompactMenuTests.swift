import AppKit
import AerieCore
import XCTest
@testable import AerieApp

final class CompactMenuTests: XCTestCase {
  func testUprightLabelGlyphsAndLargerSingleRowValuesFitWhileNetworkFontsStayUnchanged() async {
    await MainActor.run {
      XCTAssertEqual(MenuRenderer.compactPrimaryFont.pointSize, 15)
      XCTAssertEqual(MenuRenderer.compactNetworkFonts.number, 8.5)
      XCTAssertEqual(MenuRenderer.compactNetworkFonts.unit, 8)
      XCTAssertEqual(MenuRenderer.compactNetworkFonts.arrow, 9)
      let primary = MenuRenderer.compactPrimaryFont
      for value in ["0%", "9%", "99%", "100%", "AC", "UPS"] {
        let bounds = (value as NSString).size(withAttributes: [.font: primary])
        XCTAssertLessThanOrEqual(bounds.width, MenuRenderer.compactPercentWidth, value)
        XCTAssertLessThanOrEqual(bounds.height, 19, value)
      }
      for value in ["28.4°", "200.0°", "392.0°", "-58.0°"] {
        XCTAssertLessThanOrEqual(
          (value as NSString).size(withAttributes: [.font: primary]).width,
          MenuRenderer.compactTemperatureWidth, value)
      }
      for label in ["CPU", "GPU", "MEM", "SSD", "NET", "SNS", "BAT", "PWR"] {
        let glyphs = MenuRenderer.uprightLabelGlyphs(label)
        XCTAssertEqual(glyphs.map(\.0).joined(), label)
        XCTAssertEqual(glyphs.count, 3)
        for (index, entry) in glyphs.enumerated() {
          XCTAssertGreaterThanOrEqual(entry.1.x, 0)
          XCTAssertEqual(entry.1.y, -0.5 + CGFloat(index) * 6.5)
          let font = NSFont.systemFont(ofSize: 6.5, weight: .semibold)
          let inkTop = entry.1.y + font.ascender - font.capHeight
          let inkBottom = entry.1.y + font.ascender
          XCTAssertGreaterThanOrEqual(inkTop, 0); XCTAssertLessThanOrEqual(inkBottom, 20)
        }
      }
    }
  }
  func testSelectingMenuPageRefreshesCurrentReadingsAndPowerLabelDistinguishesExternalSupply()
    async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings())
      defer { controller.close() }
      var reads = 0
      controller.onMenuPreview = { _ in
        reads += 1; return []
      }
      let initial = reads
      controller.selectSection(.menus)
      XCTAssertGreaterThan(reads, initial)
      let battery = StatusWidget(
        module: .power, value: MenuValue(full: "BAT 73%"), style: .compact, label: .vertical,
        colorHex: nil)
      let external = StatusWidget(
        module: .power, value: MenuValue(full: "PWR AC", compact: "AC"), style: .compact,
        label: .vertical, colorHex: nil)
      XCTAssertEqual(battery.shortLabel, "BAT"); XCTAssertEqual(external.shortLabel, "PWR")
      XCTAssertEqual(
        MenuRenderer.widget(battery, padding: 1).size,
        MenuRenderer.widget(external, padding: 1).size)
    }
  }
  func testEightEnabledModulesFitAnExplicitLaptopBudgetWithStableValuesAndFullAccessibility()
    async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      let modules: [Module] = [
        .overview, .cpu, .gpu, .memory, .storage, .network, .sensors, .power,
      ]
      let values: [Module: MenuValue] = [
        .overview: MenuValue(full: "Aerie"), .cpu: MenuValue(full: "CPU 42%", compact: "42%"),
        .gpu: MenuValue(full: "GPU 17%", compact: "17%"),
        .memory: MenuValue(full: "MEM 61%", compact: "61%"),
        .storage: MenuValue(full: "SSD 35%", compact: "35%"),
        .power: MenuValue(full: "BAT 73%", compact: "73%"),
        .network: MenuValue.network(download: "12.3 MiB/s", upload: "9.9 KiB/s"),
        .sensors: MenuValue(full: "28.4°C"),
      ]
      let before = modules.map {
        StatusWidget(module: $0, value: values[$0]!, style: .text, label: .automatic, colorHex: nil)
      }
      let after = modules.map {
        StatusWidget(
          module: $0, value: values[$0]!, style: .compact,
          label: $0 == .overview ? .icon : .vertical, colorHex: nil)
      }
      let preview = MenuBarPreview(frame: .zero)
      let beforeWidth = preview.update(before, padding: 4, gap: 6)
      let beforeParts = preview.moduleWidths
      let afterWidth = preview.update(after, padding: 0, gap: 0)
      let afterParts = preview.moduleWidths
      // Synthetic1440pt display: (1440 -200 reserved center)/2 -140 system -120 other =360pt.
      let budget: CGFloat = (1440 - 200) / 2 - 140 - 120
      XCTAssertEqual(after.count, before.count); XCTAssertLessThanOrEqual(afterWidth, budget)
      XCTAssertLessThan(afterWidth, beforeWidth * 0.75)
      for descriptor in after {
        for content in ["0%", "100%", "Unavailable", "—", "999999999999%"] {
          var alternate = descriptor
          alternate = StatusWidget(
            module: descriptor.module,
            value: descriptor.module == .network
              ? MenuValue.network(download: content, upload: content) : MenuValue(full: content),
            style: descriptor.style, label: descriptor.label, colorHex: nil, paused: true)
          XCTAssertEqual(
            MenuRenderer.widget(descriptor, padding: 0).size,
            MenuRenderer.widget(alternate, padding: 0).size)
        }
        XCTAssertTrue(descriptor.accessibility.contains(descriptor.value.full))
      }
      let group = GroupedStatusView(frame: .zero)
      XCTAssertEqual(group.update(after, padding: 0, gap: 0), afterWidth)
      if let directory = ProcessInfo.processInfo.environment["AERIE_COMPACT_FIXTURE_DIRECTORY"] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let rows = zip(beforeParts, afterParts).map {
          ["module": $0.0.rawValue, "beforePoints": $0.1, "afterPoints": $1.1] as [String: Any]
        }
        let report: [String: Any] = [
          "fixture": "synthetic; same eight enabled modules and source values",
          "beforePoints": beforeWidth, "afterPoints": afterWidth, "budgetPoints": budget,
          "modules": rows,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
          .write(to: url.appendingPathComponent("widths.json"))
      }
    }
  }
}
