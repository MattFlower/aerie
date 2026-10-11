import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class DaylightDashboardTests: XCTestCase {
  func testOfflineDaylightWorksWithWeatherOffAndReleasesItsResultOnCloseDisableOrModuleChange()
    async
  {
    await MainActor.run {
      _ = NSApplication.shared
      let dashboard = DashboardController(); _ = dashboard.view
      var point = DaylightConfiguration(); point.enabled = true; point.name = "Synthetic point"
      dashboard.settings.daylight = point
      XCTAssertFalse(dashboard.settings.weather.enabled)
      dashboard.show(.time)
      XCTAssertEqual(dashboard.daylightReading?.boundaries.count, 4)
      let instant = dashboard.daylightReading?.interval.start
      dashboard.refresh(); XCTAssertEqual(dashboard.daylightReading?.interval.start, instant)
      dashboard.releaseDaylight(); XCTAssertNil(dashboard.daylightReading)
      dashboard.refresh(); XCTAssertNotNil(dashboard.daylightReading)
      dashboard.suspended = true; dashboard.refresh(); XCTAssertNil(dashboard.daylightReading)
      dashboard.suspended = false; dashboard.refresh(); XCTAssertNotNil(dashboard.daylightReading)
      dashboard.show(.cpu); XCTAssertNil(dashboard.daylightReading)
      dashboard.show(.time); XCTAssertNotNil(dashboard.daylightReading)
      dashboard.settings.daylight = nil; dashboard.refresh();
      XCTAssertNil(dashboard.daylightReading)
    }
  }
}
