import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class SettingsLayoutTests: XCTestCase {
  func testNativeFormsFitMinimumAndDefaultSizesAcrossAppearancesWithoutShowingWindows() async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(
        settings: Settings(),
        interfaces: [
          InterfaceData(name: "en0", active: true, addresses: "", received: 0, sent: 0, errors: 0)
        ],
        sensors: [SensorData(key: "Tp09", label: "CPU efficiency sensor 1", value: 35, unit: "°C")],
        interfaceDescriptions: ["en0": InterfaceDescription(name: "Synthetic Wi-Fi", kind: "Wi-Fi")]
      )
      defer { controller.close() }
      let window = try XCTUnwrap(controller.window), root = try XCTUnwrap(window.contentView)
      let appearances: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua]
      let output = ProcessInfo.processInfo.environment["AERIE_SETTINGS_FIXTURE_DIRECTORY"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
      }
      if let output {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      }
      for size in [NSSize(width: 840, height: 560), NSSize(width: 880, height: 680)] {
        window.setContentSize(size)
        for appearance in appearances {
          window.appearance = NSAppearance(named: appearance)
          for section in SettingsSection.allCases {
            controller.selectSection(section); root.layoutSubtreeIfNeeded()
            let tabs = try preferenceTabs(controller)
            let scroll = try XCTUnwrap(tabs.selectedTabViewItem?.view as? NSScrollView)
            let form = try XCTUnwrap(scroll.documentView as? SettingsForm)
            form.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(scroll.contentView.bounds.width, 400, section.rawValue)
            XCTAssertGreaterThan(form.frame.height, 100, section.rawValue)
            for row in form.stack.arrangedSubviews where !row.isHidden {
              XCTAssertGreaterThan(row.frame.width, 0, section.rawValue)
              XCTAssertLessThanOrEqual(row.frame.maxX, form.bounds.width + 1, section.rawValue)
            }
            if let output {
              let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
              root.cacheDisplay(in: root.bounds, to: bitmap)
              let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
              let filename =
                section.rawValue.replacingOccurrences(of: " ", with: "-") + "-"
                + appearance.rawValue + "-" + String(Int(size.width)) + ".png"
              try png.write(to: output.appendingPathComponent(filename))
            }
          }
        }
      }
      XCTAssertFalse(window.isVisible)
    }
  }
}
