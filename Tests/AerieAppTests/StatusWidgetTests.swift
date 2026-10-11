import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class StatusWidgetTests: XCTestCase {
  func testNetworkGeometryIsFixedAcrossDigitsUnitsMissingPauseStylesAndLabels() async throws {
    await MainActor.run {
      for style in DisplayStyle.allCases {
        for label in MenuLabelPlacement.allCases {
          var expected: NSSize?
          for value in [
            "0 B/s", "9.9 KiB/s", "99.9 MiB/s", "999.9 Gbit/s", "—",
            String(repeating: "9", count: 256) + " TiB/s",
          ] {
            for paused in [false, true] {
              let descriptor = StatusWidget(
                module: .network,
                value: MenuValue(
                  full: "Download " + value,
                  secondary: "↑" + value, stackedPrimary: "↓" + value), style: style, label: label,
                colorHex: nil, paused: paused)
              let image = MenuRenderer.widget(descriptor, padding: 2)
              if let expected {
                XCTAssertEqual(image.size, expected)
              } else {
                expected = image.size
              }
              XCTAssertEqual(image.size.height, 20); XCTAssertTrue(image.isTemplate)
            }
          }
        }
      }
    }
  }
  func testGroupPreservesIndividualHitRegionsAccessibilityAndReleasesCapturedOwner() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var group: GroupedStatusView? = GroupedStatusView(frame: .zero)
      weak var weakGroup = group
      let descriptors = [Module.cpu, .memory, .network].map {
        StatusWidget(
          module: $0,
          value: MenuValue(
            full: $0.title + " 20%", compact: "20%", secondary: "↑1 KiB/s",
            stackedPrimary: "↓2 KiB/s"), style: .stacked, label: .vertical, colorHex: nil)
      }
      var pressed: [Module] = []; group?.onSelect = { pressed.append($0) }
      let width = try XCTUnwrap(group?.update(descriptors, padding: 1, gap: 2))
      XCTAssertLessThan(width, 400)
      let elements = try XCTUnwrap(
        group?.accessibilityChildren()?.compactMap { $0 as? NSAccessibilityElement })
      XCTAssertEqual(elements.count, 3)
      for (index, element) in elements.enumerated() {
        XCTAssertTrue(element.accessibilityPerformPress())
        let rect = try XCTUnwrap(group?.segments[index])
        XCTAssertEqual(
          group?.module(at: NSPoint(x: rect.midX, y: rect.midY)), descriptors[index].module)
        XCTAssertTrue(
          element.accessibilityLabel()?.contains(descriptors[index].module.title) ?? false)
      }
      XCTAssertEqual(pressed, [.cpu, .memory, .network])
      group?.releaseContent(); group = nil
      XCTAssertNil(weakGroup)
      XCTAssertFalse(elements[0].accessibilityPerformPress())
    }
  }
  func testWeatherSymbolFallbackAndRasterUsesBoundedNativeImages() async throws {
    try await MainActor.run {
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: nil), "questionmark.circle")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: 123456), "questionmark.circle")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: 0, daylight: false), "moon.stars")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: 0, daylight: true), "sun.max")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: 0), "sparkles")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: 2), "cloud")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: 61), "cloud.rain")
      XCTAssertEqual(
        MenuRenderer.weatherSymbol(code: nil, daylight: false, glyph: .clear), "moon.stars")
      XCTAssertEqual(MenuRenderer.weatherSymbol(code: nil, glyph: .thunder), "cloud.bolt.rain")
      for module in Module.allCases {
        let widget = StatusWidget(
          module: module, value: MenuValue(full: "Synthetic"), style: .text, label: .icon,
          colorHex: nil)
        XCTAssertNotNil(
          NSImage(systemSymbolName: widget.defaultSymbol, accessibilityDescription: nil))
      }
      for glyph in [
        WeatherGlyph.clear, .partlyCloudy, .cloudy, .fog, .rain, .snow, .sleet, .mixed, .thunder,
        .wind, .tornado, .hurricane, .tropicalStorm, .dust, .smoke, .haze, .hot, .cold, .blizzard,
      ] {
        XCTAssertNotNil(
          NSImage(
            systemSymbolName: MenuRenderer.weatherSymbol(code: nil, glyph: glyph),
            accessibilityDescription: nil))
      }
      let descriptor = StatusWidget(
        module: .weather, value: MenuValue(full: "12°C", secondary: "Rain"), style: .text,
        label: .icon, colorHex: nil, symbol: "cloud.rain")
      let image = MenuRenderer.widget(descriptor, padding: 1)
      XCTAssertLessThan(image.size.width, 160)
      let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: 20,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap);
      image.draw(in: NSRect(origin: .zero, size: image.size))
      XCTAssertTrue(
        (0..<bitmap.pixelsWide).contains { x in
          (0..<20).contains { bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0 > 0 }
        })
    }
  }
  func testNativeGaugesKeepUnavailableDistinctFromZeroAndReleaseTheirAccessibility() async throws {
    try await MainActor.run {
      let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 320))
      view.update(
        rows: [
          .gauge("GPU utilization", "Unavailable", nil, .systemBlue),
          .gauge("CPU utilization", "0%", 0, .systemBlue),
        ], points: [])
      let labels = view.accessibilityChildren()?.compactMap {
        ($0 as? NSAccessibilityElement)?.accessibilityLabel()
      }
      XCTAssertEqual(labels, ["GPU utilization: Unavailable", "CPU utilization: 0%"])
      let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: 416, pixelsHigh: 320, bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0))
      NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap); view.draw(view.bounds)
      XCTAssertNil(view.window); view.releaseInteractiveRows()
      XCTAssertTrue(view.rows.isEmpty); XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
    }
  }

}
