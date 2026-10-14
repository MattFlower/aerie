@testable import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class DetailViewTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1715695200)
  private func report() -> WeatherReport {
    var report = WeatherReport(
      source: "Open-Meteo", attributionURL: "https://example.invalid/forecast", fetched: now,
      timeContext: WeatherTimeContext(identifier: "Etc/UTC", offsetSeconds: 0),
      temperature: 24.2, apparent: 23.8, humidity: 53, wind: 14.5, gusts: 20.5, direction: 180,
      pressure: 1011.2, cloud: 20, code: 2, hours: [], days: [], alerts: [])
    report.hours = (0..<24).map {
      WeatherHour(
        date: now.addingTimeInterval(Double($0) * 3600), temperature: 24.2 - Double($0 % 6),
        precipitation: Double($0 % 5) * 12, code: 2, apparent: 23.8, humidity: 53, dewpoint: 16.3,
        wind: 14.5, gusts: 20.5, direction: 180, pressure: 1011.2, cloud: 20, amount: 0.2, uv: 3,
        visibility: 10000, detail: "Synthetic forecast narrative. Light winds ease overnight.")
    }
    report.days = [
      WeatherDay(
        date: now.addingTimeInterval(-14 * 3600), low: 13.1, high: 24.2, code: 2,
        sunrise: now.addingTimeInterval(-8 * 3600), sunset: now.addingTimeInterval(4 * 3600), uv: 3,
        precipitation: 20)
    ]
    return report
  }
  private func alert() -> WeatherAlert {
    WeatherAlert(
      event: "Synthetic weather advisory", headline: "Strong winds may affect exposed roads.",
      area: "Synthetic coast", sender: "Synthetic forecast office", severity: "Moderate",
      urgency: "Expected", certainty: "Likely", status: "Actual", messageType: "Alert",
      description:
        "Synthetic official description. Winds increase this evening, then ease overnight.",
      instructions: "Secure loose outdoor objects and use care on exposed roads.", sent: now,
      effective: now.addingTimeInterval(3600), onset: now.addingTimeInterval(7200),
      expires: now.addingTimeInterval(10800), ends: now.addingTimeInterval(14400),
      source: URL(string: "https://example.invalid/alert"))
  }
  func testWeatherUsesWholeDegreesAndRetainsOriginalPrecisionAndTiming() {
    let report = report(), hour = report.hours[0]
    let current = WeatherDetailPresentation.current(
      report, name: "Synthetic coast", status: "Updated 2:00pm · refresh 15 min", unit: .fahrenheit)
    XCTAssertEqual(current.hero?.value, "76°F")
    XCTAssertEqual(current.highlights[0].value, "75°F")
    XCTAssertEqual(report.temperature, 24.2)
    let detail = WeatherDetailPresentation.hour(hour, report: report, unit: .fahrenheit)
    XCTAssertEqual(detail.hero?.value, "76°F")
    XCTAssertTrue(detail.diagnostics.contains("24.2"))
    XCTAssertTrue(detail.diagnostics.contains("Valid until: Unavailable"))
    XCTAssertTrue(detail.diagnostics.contains("Forecast instant:"))
    XCTAssertEqual(detail.chart?.values.first!, 24.2)
    XCTAssertEqual(Format.weatherTemperature(-0.1, unit: .celsius), "0°C")
    XCTAssertEqual(Format.weatherTemperature(nil, unit: .fahrenheit), "Unavailable")
    XCTAssertEqual(Format.weatherTemperature(.infinity, unit: .fahrenheit), "Unavailable")
    XCTAssertEqual(Format.temperature(42.35, unit: .celsius), "42.4°C")
  }
  func testMissingValuesAndAllFiveAlertTimesRemainDistinctAndAvailable() {
    var sparse = report(); sparse.temperature = nil; sparse.apparent = nil; sparse.humidity = nil
    let current = WeatherDetailPresentation.current(
      sparse, name: "Synthetic coast", status: "Forecast unavailable · cached forecast",
      unit: .fahrenheit)
    XCTAssertEqual(current.hero?.value, "Unavailable"); XCTAssertFalse(current.notices.isEmpty)
    let message = WeatherDetailPresentation.alert(alert(), fetched: now)
    let times = message.sections.flatMap(\.facts)
    for label in ["Sent", "Effective", "Onset", "Message expires", "Event ends", "Fetched"] {
      XCTAssertNotNil(times.first { $0.label == label })
    }
    XCTAssertTrue(message.sections.first?.paragraphs.first?.contains("Secure") == true)
    XCTAssertTrue(message.fullText.contains("Synthetic forecast office"))
  }
  func testSensorMenuAndDetailSelectSameFirstLiveFiniteSourceInsteadOfHottest() async {
    await MainActor.run {
      let sensors = [
        SensorData(key: "BAD", label: "CPU package", value: .nan, unit: "°C"),
        SensorData(key: "TCPU", label: "CPU package", value: 42.35, unit: "°C"),
        SensorData(key: "TGPU", label: "GPU board", value: 86.8, unit: "°C"),
      ]
      XCTAssertEqual(SensorMenuPresentation.selected(sensors)?.key, "TCPU")
      XCTAssertEqual(SensorMenuPresentation.shortLabel(sensors[1]), "CPU")
      XCTAssertEqual(
        SensorMenuPresentation.shortLabel(
          SensorData(key: "TC01", label: "TC01", value: 42, unit: "°C")), "TMP")
      XCTAssertEqual(
        SensorMenuPresentation.shortLabel(
          SensorData(key: "CPU0", label: "CPU0", value: 42, unit: "°C")), "TMP")
      let controller = DashboardController(); controller.snapshot.sensors = sensors;
      controller.show(.sensors)
      let rows = controller.canvas.rows.compactMap {
        if case .sensor(let sensor) = $0 { return sensor }; return nil
      }
      XCTAssertEqual(rows.filter(\.selected).map(\.key), ["TCPU"])
      XCTAssertTrue(
        SensorMenuPresentation.description(
          sensors, names: ["TCPU": "Processor package"], unit: .celsius
        ).contains("Processor package"))
      let unknown = SensorMenuPresentation.detail(
        SensorData(key: "TC01", label: "TC01", value: 42.35, unit: "°C"), names: nil,
        unit: .celsius, selected: true)
      XCTAssertEqual(unknown.title, "Unknown sensor");
      XCTAssertTrue(unknown.diagnostics.contains("TC01"))
      controller.releasePresentation()
    }
  }
  func testDiagnosticsAreExplicitAndClosingReleasesPresentation() async {
    await MainActor.run {
      _ = NSApplication.shared
      let controller = DetailWindowController(
        presentation: WeatherDetailPresentation.hour(
          report().hours[0], report: report(), unit: .fahrenheit))
      XCTAssertFalse(controller.diagnosticsVisible)
      controller.toggleDiagnostics(); XCTAssertTrue(controller.diagnosticsVisible)
      controller.toggleDiagnostics(); XCTAssertFalse(controller.diagnosticsVisible)
      controller.window?.close()
      XCTAssertNil(controller.detailDocument.presentation)
      XCTAssertEqual(controller.detailDocument.frame.height, 16)
    }
  }
  func testDetailAccessibilityFramesFollowTheScrolledDocumentAndForecastZone() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var report = report();
      report.timeContext = WeatherTimeContext(identifier: "Asia/Tokyo", offsetSeconds: 32400)
      let controller = DetailWindowController(
        presentation: WeatherDetailPresentation.hour(
          report.hours[0], report: report, unit: .fahrenheit))
      let element = try XCTUnwrap(
        controller.detailDocument.accessibilityChildren()?.first as? NSAccessibilityElement)
      let initial = element.accessibilityFrame()
      let scroll = try XCTUnwrap(controller.detailDocument.enclosingScrollView)
      scroll.contentView.scroll(to: NSPoint(x: 0, y: 200));
      scroll.reflectScrolledClipView(scroll.contentView)
      XCTAssertNotEqual(element.accessibilityFrame().origin.y, initial.origin.y)
      let chart = try XCTUnwrap(
        controller.detailDocument.accessibilityChildren()?.last as? NSAccessibilityElement)
      XCTAssertTrue(
        chart.accessibilityLabel()?.contains(
          WeatherDetailPresentation.date(now, zone: report.timeContext.instantZone)) == true)
      XCTAssertFalse(
        chart.accessibilityLabel()?.contains(
          WeatherDetailPresentation.date(now, zone: TimeZone(secondsFromGMT: 0)!)) == true)
      controller.close()
    }
  }
  func testSyntheticDrilldownsRenderWithNativeResizingAndBothScrollbarStyles() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let report = report()
      let outlook = try XCTUnwrap(WeatherOutlookPresentation.outlooks(report, at: now).first)
      let models: [(String, DetailPresentation)] = [
        (
          "weather-current",
          WeatherDetailPresentation.current(
            report, name: "Synthetic coast", status: "Updated 2:00pm · refresh 15 min",
            unit: .fahrenheit)
        ),
        (
          "weather-hour",
          WeatherDetailPresentation.hour(report.hours[0], report: report, unit: .fahrenheit)
        ),
        (
          "weather-day",
          WeatherDetailPresentation.outlook(outlook, report: report, unit: .fahrenheit)
        ),
        ("weather-alert", WeatherDetailPresentation.alert(alert(), fetched: now)),
        (
          "map-alerts",
          WeatherDetailPresentation.alerts(
            WeatherAlertReport(alerts: [alert()], fetched: now, updated: nil, moreAvailable: false))
        ),
        (
          "clock-states",
          DetailPresentation(
            title: "Synthetic CPU", subtitle: "Hardware clock-state distribution · 3s interval",
            symbol: "waveform.path",
            highlights: [
              DetailFact("Active-labelled residency", "24%"),
              DetailFact("Active interval average", "2.410 GHz"),
            ],
            sections: [
              DetailSection(
                title: "Reported states",
                bars: [("Idle", 0.76), ("2400 MHz", 0.20), ("2500 MHz", 0.04)])
            ], source: "On this Mac · hardware residency counters",
            diagnostics: "Synthetic source details.")
        ),
        (
          "sensor-reading",
          SensorMenuPresentation.detail(
            SensorData(key: "TCPU", label: "CPU package", value: 42.35, unit: "°C"), names: nil,
            unit: .fahrenheit, selected: true)
        ),
        (
          "calendar-event",
          DetailPresentation(
            title: "Synthetic planning session", subtitle: "Calendar event", symbol: "calendar",
            sections: [
              DetailSection(
                title: "When & where",
                facts: [
                  DetailFact("Starts", "May 14, 2024 at 2:00 PM UTC"),
                  DetailFact("Ends", "May 14, 2024 at 3:00 PM UTC"),
                  DetailFact("Calendar", "Synthetic calendar"),
                  DetailFact("Location", "Conference room"),
                ]),
              DetailSection(
                title: "Notes",
                paragraphs: ["Review the upcoming milestone and assign follow-up tasks."]),
            ], source: "On this Mac · selected event calendar",
            diagnostics: "Synthetic event details.")
        ),
      ]
      for (name, model) in models {
        let controller = DetailWindowController(presentation: model)
        let content = try XCTUnwrap(controller.window?.contentView)
        let scroll = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
        for style in [NSScroller.Style.legacy, .overlay] {
          scroll.scrollerStyle = style; scroll.tile()
          controller.detailDocument.setFrameSize(
            NSSize(width: scroll.contentSize.width, height: controller.detailDocument.frame.height))
          XCTAssertLessThanOrEqual(controller.detailDocument.frame.width, scroll.contentSize.width)
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
          controller.window?.appearance = NSAppearance(named: appearance);
          content.appearance = controller.window?.appearance
          content.layoutSubtreeIfNeeded()
          let image = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
          content.cacheDisplay(in: content.bounds, to: image)
          let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
          XCTAssertGreaterThan(png.count, 1000)
          if let directory = ProcessInfo.processInfo.environment["AERIE_DETAIL_FIXTURE_DIRECTORY"] {
            let url = URL(fileURLWithPath: directory);
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent(name + "-" + appearance.rawValue + ".png"))
            let visible = NSRect(
              x: 0, y: 0, width: controller.detailDocument.bounds.width,
              height: min(572, controller.detailDocument.bounds.height))
            let detailImage = try XCTUnwrap(
              controller.detailDocument.bitmapImageRepForCachingDisplay(in: visible))
            controller.detailDocument.cacheDisplay(in: visible, to: detailImage)
            let detailPNG = try XCTUnwrap(detailImage.representation(using: .png, properties: [:]))
            try detailPNG.write(
              to: url.appendingPathComponent(
                "detail-content-" + name + "-" + appearance.rawValue + ".png"))
          }
        }
        controller.window?.setContentSize(NSSize(width: 500, height: 400));
        content.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(controller.detailDocument.frame.width, 500)
        XCTAssertGreaterThan(controller.detailDocument.measuredHeight, 100)
        XCTAssertTrue(controller.detailDocument.accessibilityChildren()?.isEmpty == false)
        controller.close(); XCTAssertNil(controller.detailDocument.presentation)
      }
    }
  }
}
