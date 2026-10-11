import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class CalendarViewTests: XCTestCase {
  func testNativeControlsSelectDatesAndNavigateWithoutRebuildingOnEachSample() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
      let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!
      let model = try XCTUnwrap(
        CalendarMonth.make(
          displayedMonth: date, selected: date, now: date, calendar: calendar,
          showsWeekNumbers: true))
      let view = CalendarMonthView(
        frame: NSRect(x: 0, y: 0, width: 388, height: CalendarMonthView.height(model)))
      var selected: Date?, moves: [Int] = [], today = false
      view.onSelect = { selected = $0 }; view.onMove = { moves.append($0) };
      view.onToday = { today = true }
      view.update(model)
      let buttons = view.subviews.compactMap { $0 as? NSButton }
      XCTAssertEqual(buttons.count, 45)
      let selectedButton = try XCTUnwrap(buttons.first { $0.title == "31" && $0.state == .on })
      selectedButton.performClick(nil)
      XCTAssertEqual(selectedButton.state, .on)
      let first = try XCTUnwrap(buttons.first { $0.title == "23" && $0.tag == 28 })
      first.performClick(nil)
      XCTAssertEqual(selected, model.weeks[4].days[0].date)
      buttons.first { $0.title == "‹" }?.performClick(nil)
      buttons.first { $0.title == "›" }?.performClick(nil)
      buttons.first { $0.title == "Today" }?.performClick(nil)
      XCTAssertEqual(moves, [-1, 1]); XCTAssertTrue(today)
      view.update(model)
      XCTAssertTrue(view.subviews.contains { $0 === first })
      XCTAssertTrue(buttons.allSatisfy { $0.accessibilityLabel()?.isEmpty == false })
    }
  }
  func testInteractiveRowsReleaseCalendarAndEventControlsAfterClosing() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let date = Date(timeIntervalSince1970: 1_700_000_000)
      let model = try XCTUnwrap(
        CalendarMonth.make(
          displayedMonth: date, selected: date, now: date,
          calendar: Calendar(identifier: .gregorian), showsWeekNumbers: false))
      let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
      var action: String?
      view.onAction = { action = $0 }
      view.update(
        rows: [.calendar(model), .action("Synthetic appointment", "12:00", "synthetic-id")],
        points: [])
      let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
      button.performClick(nil); XCTAssertEqual(action, "synthetic-id")
      XCTAssertNotNil(view.subviews.first { $0 is CalendarMonthView })
      view.releaseInteractiveRows()
      XCTAssertTrue(view.subviews.isEmpty); XCTAssertTrue(view.rows.isEmpty)
      button.performClick(nil); XCTAssertEqual(action, "synthetic-id")
      XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
    }
  }
}
