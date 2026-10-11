import Foundation
import XCTest
@testable import AerieCore
final class HistoryWindowTests: XCTestCase {
  func testZoomAndPanUseElapsedTimeAndKeepMissingGapSemantics() {
    let points = [0.0, 1, 2, 80, 90, 100].map {
      HistoryPoint(date: Date(timeIntervalSince1970: $0), values: $0 == 90 ? [:] : ["cpu": $0])
    }
    XCTAssertEqual(HistoryWindow.visible(points, zoom: 1, position: 0).count, 6)
    let oldest = HistoryWindow.visible(points, zoom: 2, position: 0)
    XCTAssertEqual(oldest.map { $0.date.timeIntervalSince1970 }, [0, 1, 2])
    let latest = HistoryWindow.visible(points, zoom: 2, position: 1)
    XCTAssertEqual(latest.map { $0.date.timeIntervalSince1970 }, [80, 90, 100])
    XCTAssertNil(latest[1].values["cpu"])
    XCTAssertEqual(
      HistoryPlot.samples(latest, metric: "cpu", expectedInterval: 1).map(\.startsSegment),
      [true, true, true])
    XCTAssertTrue(HistoryWindow.visible(points, zoom: 4, position: 0.5).isEmpty)
    for (zoom, position) in [(0.0, 1.0), (2, .nan), (65, 1), (1, -1)] {
      XCTAssertTrue(HistoryWindow.visible(points, zoom: zoom, position: position).isEmpty)
    }
    XCTAssertTrue(HistoryWindow.visible([], zoom: 1, position: 1).isEmpty)
  }
  func testTodayFollowsRolloverLongClosedIntervalsAndTimeZonesUnlessUserPinsDate() {
    var calendar = Calendar(identifier: .gregorian);
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))!
    let after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 1))!
    var selection = CalendarSelection()
    XCTAssertEqual(selection.date(now: before), before);
    XCTAssertEqual(selection.date(now: after), after)
    selection.select(before); XCTAssertEqual(selection.date(now: after), before)
    selection.today(); XCTAssertEqual(selection.date(now: after), after)
    selection.move(months: 1, now: after, calendar: calendar)
    XCTAssertEqual(calendar.component(.month, from: selection.date(now: after)), 4)
    selection.today();
    XCTAssertEqual(
      selection.date(now: after.addingTimeInterval(604800)), after.addingTimeInterval(604800))
  }
}
