@testable import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class WeatherDashboardTests: XCTestCase {
  private let now = ISO8601DateFormatter().date(from: "2024-05-14T14:00:00Z")!
  @MainActor private func fixture(days: Int = 7, nws: Bool = false) -> DashboardController {
    let controller = DashboardController()
    controller.weatherNow = { self.now }
    controller.settings.weather.enabled = true
    controller.settings.weather.name = "Synthetic coast"
    controller.settings.weather.latitude = 10; controller.settings.weather.longitude = 20
    controller.settings.temperature = .fahrenheit; controller.settings.hourlyForecastHours = 168
    controller.weatherStatus = "Updated 2:00pm · refresh 15 min"
    var calendar = Calendar(identifier: .gregorian);
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let midnight = calendar.startOfDay(for: now)
    var report = WeatherReport(
      source: nws ? "NWS" : "Open-Meteo", attributionURL: "https://example.invalid/forecast",
      fetched: now, timeContext: WeatherTimeContext(identifier: "Etc/UTC", offsetSeconds: 0),
      temperature: 24.2, apparent: 23.8, humidity: 53, wind: 14.5, gusts: 20.5, direction: 180,
      pressure: 1011.2, cloud: 20, code: 2,
      hours: [], days: [], alerts: [])
    report.hours = (0..<168).map { index -> WeatherHour in
      let offset = Double(index) * 3600
      let temperature = 24.0 - Double(index % 7)
      let chance = Double(index % 6) * 15
      return WeatherHour(
        date: now.addingTimeInterval(offset), temperature: temperature, precipitation: chance,
        code: index % 6 == 3 ? 61 : 2, isDay: (index + 14) % 24 >= 6 && (index + 14) % 24 < 18,
        apparent: 23.5, wind: 12.5,
        detail: "Synthetic hourly detail.")
    }
    report.isDay = true; report.glyph = .partlyCloudy
    if nws {
      report.periods = (0..<(days * 2)).map {
        let daytime = $0 % 2 == 0
        let start = midnight.addingTimeInterval(Double($0 / 2) * 86400 + (daytime ? 21600 : 64800))
        return WeatherPeriod(
          name: daytime ? "Synthetic day \($0 / 2)" : "Synthetic night \($0 / 2)",
          start: start, end: start.addingTimeInterval(43200), isDay: daytime,
          temperature: daytime ? 24 : 13, precipitation: $0 / 2 == 2 ? 83 : 2,
          condition: $0 / 2 == 2 ? "Rain" : "Partly cloudy",
          detail: "Synthetic issued forecast detail.", wind: "Light winds",
          temperatureStatistic: daytime ? .maximum : .minimum,
          glyph: $0 / 2 == 2 ? .rain : .partlyCloudy)
      }
    } else {
      report.days = (0..<days).map {
        let date = midnight.addingTimeInterval(Double($0) * 86400)
        return WeatherDay(
          date: date, low: 13 - Double($0), high: 24 + Double($0 % 3), code: $0 == 2 ? 61 : 2,
          sunrise: date.addingTimeInterval(21600), sunset: date.addingTimeInterval(64800),
          uv: 2, precipitation: $0 == 2 ? 83 : 2)
      }
    }
    controller.weather = report; controller.show(.weather)
    return controller
  }
  @MainActor private func presentation(_ controller: DashboardController) throws
    -> WeatherDashboardPresentation
  {
    guard case .weather(let value) = controller.canvas.rows.first else {
      throw NSError(domain: "Expected native weather presentation", code: 1)
    }
    return value
  }
  func testSevenHoursAndFiveDaysFitTheExistingViewportWithoutHidingRemainingForecasts() async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = fixture()
      let value = try presentation(controller)
      let viewport = try XCTUnwrap(controller.canvas.enclosingScrollView).contentSize
      XCTAssertEqual(controller.view.bounds.size, NSSize(width: 416, height: 600))
      XCTAssertEqual(viewport.height, 530)
      let weather = try XCTUnwrap(
        controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
      XCTAssertEqual(Int(weather.bounds.width / WeatherDashboardPresentation.hourWidth), 7)
      XCTAssertLessThanOrEqual(
        8 + WeatherDashboardPresentation.currentHeight + WeatherDashboardPresentation.hourlyHeight
          + WeatherDashboardPresentation.dayHeadingHeight + 5
          * WeatherDashboardPresentation.dayHeight, viewport.height)
      XCTAssertEqual(value.hours.count, 168); XCTAssertEqual(value.days.count, 7)
      XCTAssertEqual(value.temperature, "76°"); XCTAssertEqual(value.unit, "°F")
      XCTAssertEqual(value.days[2].chance, "83%"); XCTAssertTrue(value.days[2].wet)
      XCTAssertTrue(value.currentAccessibility.contains("76°F"))
      XCTAssertTrue(value.currentAccessibility.contains("not available"))
      XCTAssertTrue(value.source.contains("CC BY 4.0"))
      XCTAssertEqual(value.hours[7].symbol, "cloud.moon")
      controller.releasePresentation()
      XCTAssertTrue(controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.isEmpty)
      XCTAssertNil(controller.weather)
    }
  }
  func testUnchangedSamplesReuseNativeForecastControlsButAllRelevantChangesRefreshThem()
    async throws
  {
    try await MainActor.run {
      let controller = fixture()
      let first = try presentation(controller)
      let weather = try XCTUnwrap(
        controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
      let hour = try XCTUnwrap(weather.subviews.compactMap { $0 as? NSScrollView }.first)
      hour.contentView.scroll(to: NSPoint(x: 216, y: 0))
      controller.refresh()
      XCTAssertTrue(try presentation(controller) === first)
      XCTAssertEqual(hour.contentView.bounds.minX, 216)
      controller.weather?.humidity = 61; controller.refresh()
      XCTAssertFalse(try presentation(controller) === first)
      XCTAssertTrue(try presentation(controller).currentAccessibility.contains("61.0%"))
      controller.settings.temperature = .celsius; controller.refresh()
      XCTAssertEqual(try presentation(controller).temperature, "24°")
      controller.settings.hourlyForecastHours = 24; controller.refresh()
      XCTAssertEqual(try presentation(controller).hours.count, 24)
      controller.weatherNow = { self.now.addingTimeInterval(7201) }; controller.refresh()
      XCTAssertEqual(try presentation(controller).hours.first?.identifier, "weather-hour:2")
      controller.releasePresentation()
    }
  }
  func testNativeActionsHavePreciseAccessibleDetailsAndPointAlertsRemainProminent() async throws {
    try await MainActor.run {
      let controller = fixture()
      controller.weather?.alertReport = WeatherAlertReport(
        alerts: [
          WeatherAlert(
            event: "Synthetic advisory", headline: "", area: "", sender: "", severity: "Moderate",
            urgency: "", certainty: "", status: "", messageType: "", description: "Synthetic text",
            instructions: "", sent: nil, effective: nil, onset: nil, expires: nil, ends: nil,
            source: nil)
        ],
        fetched: now, updated: nil, moreAvailable: true)
      controller.weatherStatus = "Forecast unavailable · cached forecast"; controller.refresh()
      let value = try presentation(controller)
      XCTAssertTrue(value.statusWarning);
      XCTAssertEqual(value.alerts.first?.identifier, "weather-alert:0")
      XCTAssertTrue(value.currentAccessibility.contains("Additional provider"))
      let weather = try XCTUnwrap(
        controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
      var actions: [String] = []; controller.canvas.onAction = { actions.append($0) }
      let children = try XCTUnwrap(weather.accessibilityChildren())
      for identifier in ["weather-current", "weather-alert:0", value.days[0].identifier] {
        let button = try XCTUnwrap(
          children.compactMap { $0 as? WeatherForecastButton }.first {
            $0.actionIdentifier == identifier
          })
        XCTAssertTrue(button.accessibilityPerformPress())
      }
      XCTAssertEqual(actions, ["weather-current", "weather-alert:0", "weather-day:0"])
      let scroll = try XCTUnwrap(children.compactMap { $0 as? NSScrollView }.first)
      let hours = try XCTUnwrap(scroll.documentView?.accessibilityChildren())
      XCTAssertEqual(hours.count, 168)
      let last = try XCTUnwrap(hours.last as? WeatherForecastButton)
      XCTAssertTrue(last.accessibilityPerformPress());
      XCTAssertEqual(actions.last, "weather-hour:167")
      XCTAssertTrue(last.accessibilityLabel()?.contains("Precipitation / gust timing") == true)
      controller.releasePresentation()
    }
  }
  func testMissingCurrentAndPartialIssuedExtremaRemainQualified() async throws {
    try await MainActor.run {
      let controller = fixture(nws: true)
      controller.weather?.temperature = nil; controller.weather?.pressure = nil
      controller.weather?.hours = []
      controller.weatherNow = { self.now.addingTimeInterval(28800) }; controller.refresh()
      let value = try presentation(controller)
      XCTAssertEqual(value.temperature, "—")
      XCTAssertTrue(value.currentAccessibility.contains("Temperature: Unavailable"))
      XCTAssertTrue(value.fields.contains { $0.0 == "Pressure" && $0.1 == "—" })
      XCTAssertTrue(value.hours.isEmpty)
      XCTAssertTrue(value.days.first?.temperatures.hasPrefix("— / ") == true)
      XCTAssertTrue(
        value.days.first?.accessibility.contains("not midnight-to-midnight daily extrema") == true)
      XCTAssertEqual(value.days.first?.identifier, "weather-outlook:1")
      XCTAssertTrue(value.days.first?.summary.hasPrefix("Partial · ") == true)
      controller.releasePresentation()
    }
  }
  func testHighLowOrderAndPartialDailyAndIssuedForecastsStayInTheSameDenseLayout() async throws {
    try await MainActor.run {
      for nws in [false, true] {
        let controller = fixture(nws: nws)
        let value = try presentation(controller)
        XCTAssertEqual(value.days[0].temperatures, "75° / 55°")
        XCTAssertEqual(value.days[0].basis, nws ? .daytimeAndOvernight : .daily)
        if nws {
          controller.weather?.periods[1].temperatureStatistic = .unknown
        } else {
          controller.weather?.days[0].low = nil
        }
        controller.refresh()
        let updated = try presentation(controller)
        XCTAssertEqual(updated.height, value.height)
        XCTAssertEqual(updated.days[0].temperatures, "75° / —")
        XCTAssertTrue(updated.days[0].summary.hasPrefix("Partial · "))
        controller.releasePresentation()
      }
    }
  }
  func testWeatherModelsAreReleasedOnDisableAndEitherModuleSwitchPath() async throws {
    try await MainActor.run {
      for scenario in 0..<4 {
        let controller = fixture()
        weak var previous: WeatherDashboardPresentation? = try presentation(controller)
        XCTAssertNotNil(previous)
        if scenario == 0 {
          controller.settings.weather.enabled = false; controller.refresh()
        } else if scenario == 1 {
          controller.show(.cpu)
        } else if scenario == 2 {
          controller.modules.selectItem(at: Module.allCases.firstIndex(of: .cpu)!)
          _ = controller.modules.sendAction(
            controller.modules.action, to: controller.modules.target)
        } else {
          controller.releasePresentation()
        }
        XCTAssertNil(previous)
        controller.releasePresentation()
      }
    }
  }
  func testHourlyLabelsAndTemperaturesFitWithOverlayAndAlwaysVisibleScrollbars() async throws {
    try await MainActor.run {
      let controller = fixture()
      let weather = try XCTUnwrap(
        controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
      let strip = try XCTUnwrap(weather.subviews.compactMap { $0 as? NSScrollView }.first)
      for style in [NSScroller.Style.legacy, .overlay] {
        strip.scrollerStyle = style; strip.tile()
        XCTAssertTrue(strip.documentView?.isFlipped == true)
        XCTAssertGreaterThanOrEqual(strip.contentSize.height, 80)
        let first = try XCTUnwrap(
          strip.documentView?.subviews.compactMap { $0 as? WeatherForecastButton }.first {
            $0.actionIdentifier == "weather-hour:0"
          })
        XCTAssertTrue(strip.contentView.bounds.contains(first.frame))
      }
      controller.releasePresentation()
    }
  }
  func testNativeKeyboardFocusScrollsTheLastCachedHourIntoView() async throws {
    try await MainActor.run {
      let controller = fixture()
      let window = NSWindow(
        contentRect: controller.view.bounds, styleMask: [], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = controller
      let weather = try XCTUnwrap(
        controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
      let strip = try XCTUnwrap(weather.subviews.compactMap { $0 as? NSScrollView }.first)
      let last = try XCTUnwrap(
        strip.documentView?.subviews.compactMap { $0 as? WeatherForecastButton }.first {
          $0.actionIdentifier == "weather-hour:167"
        })
      XCTAssertTrue(window.makeFirstResponder(last))
      XCTAssertGreaterThan(strip.contentView.bounds.minX, 0)
      XCTAssertTrue(last.frame.intersects(strip.contentView.bounds))
      MenuPanel.releaseContent(of: window); controller.releasePresentation()
    }
  }
  func testSyntheticNativeWeatherRendersInBothAppearancesAndSparseAlertState() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      for variant in ["daily", "periods", "sparse", "alerts"] {
        let controller = fixture(nws: variant == "periods")
        if variant == "sparse" {
          controller.weather?.temperature = nil; controller.weather?.apparent = nil
          controller.weather?.pressure = nil; controller.weather?.humidity = nil
          controller.weather?.wind = nil; controller.weather?.gusts = nil;
          controller.weather?.cloud = nil
          controller.weather?.glyph = nil; controller.weather?.code = nil;
          controller.weather?.isDay = nil
          controller.weather?.hours = []; controller.weather?.days = []
          controller.weatherStatus = "Forecast unavailable · cached forecast"
        }
        if variant == "alerts" {
          controller.weather?.alertReport = WeatherAlertReport(
            alerts: [
              WeatherAlert(
                event: "Synthetic weather advisory", headline: "", area: "", sender: "",
                severity: "Moderate", urgency: "", certainty: "", status: "", messageType: "",
                description: "Synthetic alert text", instructions: "", sent: nil, effective: nil,
                onset: nil, expires: nil, ends: nil, source: nil)
            ], fetched: now, updated: nil, moreAvailable: false)
        }
        controller.refresh()
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 416, height: 600), styleMask: [],
          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = controller
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
          window.appearance = NSAppearance(named: appearance)
          controller.view.appearance = window.appearance
          controller.view.layoutSubtreeIfNeeded()
          let image = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
          controller.view.cacheDisplay(in: controller.view.bounds, to: image)
          let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
          XCTAssertGreaterThan(png.count, 1000)
          if let directory = ProcessInfo.processInfo.environment["AERIE_WEATHER_FIXTURE_DIRECTORY"]
          {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(
              to: url.appendingPathComponent(
                "weather-\(variant)-\(appearance.rawValue).png"))
            let weather = try XCTUnwrap(
              controller.canvas.subviews.compactMap { $0 as? WeatherDashboardView }.first)
            let visible = NSRect(
              x: 0, y: 0, width: weather.bounds.width, height: min(522, weather.bounds.height))
            let content = try XCTUnwrap(weather.bitmapImageRepForCachingDisplay(in: visible))
            weather.cacheDisplay(in: visible, to: content)
            let visiblePNG = try XCTUnwrap(content.representation(using: .png, properties: [:]))
            try visiblePNG.write(
              to: url.appendingPathComponent(
                "weather-content-\(variant)-\(appearance.rawValue).png"))
          }
        }
        MenuPanel.releaseContent(of: window); controller.releasePresentation()
      }
    }
  }
}
