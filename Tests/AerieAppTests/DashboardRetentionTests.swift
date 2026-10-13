@testable import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class DashboardRetentionTests: XCTestCase {
  @MainActor private func forecast() -> WeatherReport {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    return WeatherReport(
      source: "Synthetic forecast", attributionURL: "https://example.invalid/forecast",
      fetched: date, timeContext: WeatherTimeContext(identifier: nil, offsetSeconds: 0),
      temperature: 20, apparent: nil, humidity: nil, wind: nil, gusts: nil, direction: nil,
      pressure: nil, cloud: nil, code: 0,
      hours: (0..<168).map {
        WeatherHour(
          date: date.addingTimeInterval(Double($0) * 3600), temperature: 20,
          precipitation: nil, code: 0,
          detail: String(repeating: "Synthetic forecast detail. ", count: 16))
      }, days: [], alerts: [])
  }
  func testDismissalDropsCopiedModelsWhileLiveSourcesAndSelectionsSurvive() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var live = Snapshot()
      live.cpu.cores = Array(repeating: 0.2, count: 8)
      live.sensors = (0..<512).map {
        SensorData(key: "T\($0)", label: "Synthetic sensor \($0)", value: 35, unit: "°C")
      }
      live.interfaces = (0..<16).map {
        InterfaceData(
          name: "synthetic\($0)", active: true, addresses: "", received: 0, sent: 0, errors: 0)
      }
      let liveWeather = forecast()
      var liveHistory = HistoryStore(interval: 1)
      for index in 0..<24 {
        liveHistory.append(
          HistoryPoint(
            date: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
            values: ["cpu": 20]))
      }
      let controller = DashboardController()
      var daylight = DaylightConfiguration(); daylight.enabled = true;
      daylight.name = "Synthetic point"
      controller.settings.daylight = daylight; controller.settings.theme = .dark
      controller.snapshot = live; controller.weather = liveWeather; controller.history = liveHistory
      controller.calendarRows = [.note("Synthetic calendar detail")]
      controller.shortcutStatus = "Synthetic shortcut status"
      controller.show(.time)
      XCTAssertNotNil(controller.daylightReading)
      let address = try PublicAddressReading.parse(
        Data("{\"ip\":\"203.0.113.7\"}".utf8), date: liveWeather.fetched)
      controller.updatePublicAddress(address, status: "Synthetic address")
      controller.windowPicker.selectItem(at: 2); controller.zoomPicker.selectItem(at: 2)
      controller.historyPosition.doubleValue = 0.3
      controller.releasePresentation()
      XCTAssertFalse(controller.isPresentationLoaded)
      XCTAssertTrue(controller.snapshot.sensors.isEmpty)
      XCTAssertTrue(controller.snapshot.interfaces.isEmpty)
      XCTAssertTrue(controller.snapshot.cpu.cores.isEmpty)
      XCTAssertTrue(controller.weather == nil); XCTAssertNil(controller.publicAddress)
      XCTAssertTrue(controller.daylightReading == nil);
      XCTAssertTrue(controller.calendarRows.isEmpty)
      XCTAssertNil(controller.shortcutStatus); XCTAssertEqual(controller.history.recent.count, 0)
      XCTAssertTrue(controller.canvas.rows.isEmpty); XCTAssertTrue(controller.canvas.points.isEmpty)
      XCTAssertEqual(live.sensors.count, 512); XCTAssertEqual(live.interfaces.count, 16)
      XCTAssertEqual(liveWeather.hours.count, 168); XCTAssertEqual(liveHistory.recent.count, 24)
      XCTAssertEqual(controller.settings.theme, .dark)
      XCTAssertEqual(controller.settings.daylight, daylight)
      XCTAssertEqual(controller.module, .time)
      XCTAssertEqual(controller.windowPicker.indexOfSelectedItem, 2)
      XCTAssertEqual(controller.zoomPicker.indexOfSelectedItem, 2)
      XCTAssertEqual(controller.historyPosition.doubleValue, 0.3)
      // Opening hydrates from current source models; dismissing never erases source history.
      live.sensors[0].value = 42
      controller.snapshot = live; controller.weather = liveWeather; controller.history = liveHistory
      controller.show(.sensors)
      XCTAssertEqual(controller.snapshot.sensors.first?.value, 42)
      XCTAssertEqual(controller.weather?.hours.count, 168)
      XCTAssertEqual(controller.history.recent.count, 24)
      XCTAssertFalse(controller.canvas.rows.isEmpty)
      controller.releasePresentation()
    }
  }
  func testLateAddressDeliveryDoesNotRepopulateDismissedPresentation() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = DashboardController(); controller.show(.network)
      let reading = try PublicAddressReading.parse(
        Data("{\"ip\":\"203.0.113.7\"}".utf8), date: Date(timeIntervalSince1970: 1_700_000_000))
      controller.updatePublicAddress(reading, status: "Synthetic address")
      controller.releasePresentation()
      controller.updatePublicAddress(reading, status: "Synthetic late address")
      XCTAssertNil(controller.publicAddress); XCTAssertFalse(controller.isPresentationLoaded)
      XCTAssertTrue(controller.canvas.rows.isEmpty)
      // Explicit opening preparation supplies the current reading before the first paint.
      controller.updatePublicAddress(
        reading, status: "Synthetic current address", preparingPresentation: true)
      controller.settings.publicAddress = true; controller.show(.network)
      XCTAssertEqual(controller.publicAddress?.address, reading.address)
      XCTAssertTrue(
        controller.canvas.rows.contains { row in
          if case .metric(_, let value) = row { return value == reading.address }
          return false
        })
      controller.releasePresentation()
    }
  }
  func testRepeatedTeardownAlsoClearsCopiesBeforeAnyHierarchyWasLoaded() async {
    await MainActor.run {
      _ = NSApplication.shared
      let controller = DashboardController()
      XCTAssertFalse(controller.isViewLoaded)
      controller.weather = forecast()
      controller.snapshot.cpu.cores = [0.5]
      controller.calendarRows = [.note("Synthetic calendar detail")]
      controller.releasePresentation(); controller.releasePresentation()
      XCTAssertTrue(controller.weather == nil); XCTAssertTrue(controller.snapshot.cpu.cores.isEmpty)
      XCTAssertTrue(controller.calendarRows.isEmpty); XCTAssertFalse(controller.isViewLoaded)
    }
  }
}
