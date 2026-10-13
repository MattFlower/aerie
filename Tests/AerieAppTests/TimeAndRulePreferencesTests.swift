@testable import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class TimeAndRulePreferencesTests: XCTestCase {
  func testNewTimeAndRuleControlsApplyOffWindowWithoutRequestingAccess() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      let content = try XCTUnwrap(controller.window?.contentView)
      let tabs = try XCTUnwrap(try preferenceTabs(controller))
      @MainActor func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
      }
      let controls = tabs.tabViewItems.compactMap(\.view).flatMap { descendants($0) }
      @MainActor func popup(_ title: String) throws -> NSPopUpButton {
        try XCTUnwrap(
          controls.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == title })
      }
      @MainActor func field(_ title: String) throws -> NSTextField {
        try XCTUnwrap(
          controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == title })
      }
      try popup("World clock style").selectItem(withTitle: "Analog")
      try popup("World clock ordering").selectItem(withTitle: "Name")
      try popup("Calendar system").selectItem(withTitle: "Hebrew")
      try popup("First weekday").selectItem(withTitle: "Wednesday")
      try popup("Week number convention").selectItem(withTitle: "Selected calendar weeks")
      try field("Upcoming event days (1–31)").stringValue = "14"
      try popup("Hourly forecast rows").selectItem(withTitle: "168")
      let comparison = try popup("Condition"), upper = try field("Upper bound (ranges only)")
      XCTAssertFalse(upper.isEnabled)
      comparison.selectItem(withTitle: "Inside range (inclusive)");
      _ = comparison.sendAction(comparison.action, to: comparison.target)
      XCTAssertTrue(upper.isEnabled); upper.stringValue = "200"
      try field("Limit").stringValue = "100"
      try field("Recovery margin").stringValue = "5"
      try popup("Notify me when").selectItem(withTitle: "Storage read speed")
      let repeats = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first {
          $0.title == "Repeat while active after each cooldown"
        })
      repeats.state = .off
      try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "Add to Draft" })
        .performClick(nil)
      var applied: Settings?
      controller.onApply = { applied = $0 }
      let apply = try XCTUnwrap(
        try preferenceControls(controller).compactMap { $0 as? NSButton }.first {
          $0.title == "Apply"
        })
      apply.performClick(nil)
      let settings = try XCTUnwrap(applied), rule = try XCTUnwrap(settings.rules.first)
      XCTAssertEqual(settings.worldClockStyle, .analog);
      XCTAssertEqual(settings.worldClockOrder, .name)
      XCTAssertEqual(settings.calendarOptions?.system, .hebrew);
      XCTAssertEqual(settings.calendarOptions?.firstWeekday, 4)
      XCTAssertEqual(settings.calendarOptions?.weekNumbers, .calendar);
      XCTAssertEqual(settings.calendarOptions?.upcomingDays, 14)
      XCTAssertEqual(settings.effectiveHourlyForecastHours, 168)
      XCTAssertEqual(rule.metric, "diskRead"); XCTAssertEqual(rule.comparison, .inside);
      XCTAssertEqual(rule.upperThreshold, 200_000_000)
      XCTAssertEqual(rule.recoveryBand, 5_000_000); XCTAssertFalse(rule.repeats)
      XCTAssertFalse(settings.weather.enabled); XCTAssertFalse(settings.weather.mapsEnabled)
      XCTAssertNil(settings.eventCalendars); XCTAssertFalse(controller.window?.isVisible ?? true)
      applied = nil; try field("Upcoming event days (1–31)").stringValue = "32";
      apply.performClick(nil)
      XCTAssertNil(applied)
    }
  }
  func testAllClockStylesDrawAndRemainAccessibleWithoutSubwindowsOrTimers() async throws {
    try await MainActor.run {
      let reading = try XCTUnwrap(
        ClockPresentation.readings(
          [
            WorldClock(
              name: "Synthetic clock " + String(repeating: "Long ", count: 9),
              zone: "Asia/Kathmandu")
          ],
          at: Date(timeIntervalSince1970: 1_700_000_000)
        ).first)
      let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 320))
      let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: 416, pixelsHigh: 320, bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0))
      NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
      for style in WorldClockStyle.allCases {
        view.update(rows: [.clock(reading, style)], points: [])
        view.draw(view.bounds)
        let element = try XCTUnwrap(view.accessibilityChildren()?.first as? NSAccessibilityElement)
        XCTAssertEqual(element.accessibilityLabel(), reading.accessibilityLabel)
        XCTAssertTrue(view.subviews.isEmpty)
      }
      view.releaseInteractiveRows()
      XCTAssertTrue(view.rows.isEmpty); XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
      XCTAssertNil(view.window)
    }
  }
  func testWeatherRowsExposeCachedHourActionsAndRetainUnavailableTemperature() async throws {
    try await MainActor.run {
      let dashboard = DashboardController(); _ = dashboard.view
      var settings = Settings(); settings.weather.enabled = true; settings.weather.provider = "nws"
      settings.weather.name = "Synthetic fixture"; settings.weather.latitude = 10;
      settings.weather.longitude = 20
      dashboard.settings = settings
      let now = Date()
      dashboard.weather = WeatherReport(
        source: "NWS", attributionURL: "https://www.weather.gov/", fetched: now,
        timeContext: WeatherTimeContext(identifier: "UTC", offsetSeconds: nil),
        hours: [
          WeatherHour(
            date: now.addingTimeInterval(3600), temperature: nil, precipitation: 0, code: 71)
        ], days: [], alerts: [])
      dashboard.show(.weather)
      let weather = try XCTUnwrap(
        dashboard.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
      let value = try XCTUnwrap(weather.presentation)
      XCTAssertEqual(value.hours.first?.temperature, "—")
      XCTAssertEqual(value.hours.first?.chance, "0%")
      XCTAssertTrue(value.hours.first?.accessibility.contains("Temperature: Unavailable") == true)
      var selected: String?
      dashboard.canvas.onAction = { selected = $0 }
      let strip = try XCTUnwrap(weather.subviews.compactMap { $0 as? NSScrollView }.first)
      let hour = try XCTUnwrap(
        strip.documentView?.subviews.compactMap { $0 as? WeatherForecastButton }.first)
      XCTAssertTrue(hour.accessibilityPerformPress())
      XCTAssertEqual(selected, "weather-hour:0")
      dashboard.canvas.releaseInteractiveRows(); XCTAssertTrue(dashboard.canvas.subviews.isEmpty)
    }
  }
}
