import Foundation
import XCTest
@testable import AerieCore

final class CalendarMonthTests: XCTestCase {
  private func calendar(_ zone: String = "UTC", monday: Bool = true) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: zone)!
    value.firstWeekday = monday ? 2 : 1
    value.minimumDaysInFirstWeek = 4
    return value
  }
  private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }
  func testCompleteSixWeekGridSupportsAdjacentDatesAndLocaleWeekOrder() throws {
    let c = calendar(), selected = date(2026, 3, 31, in: c)
    let model = try XCTUnwrap(
      CalendarMonth.make(
        displayedMonth: selected, selected: selected, now: date(2026, 3, 1, in: c), calendar: c,
        showsWeekNumbers: true, locale: Locale(identifier: "en_US")))
    XCTAssertEqual(model.weeks.count, 6)
    let cells = model.weeks.flatMap(\.days)
    XCTAssertEqual(cells.filter(\.inMonth).count, 31)
    XCTAssertEqual(cells.filter(\.selected).map(\.day), [31])
    XCTAssertEqual(cells.filter(\.today).map(\.day), [1])
    XCTAssertEqual(c.component(.weekday, from: cells.first!.date), 2)
    XCTAssertEqual(c.component(.month, from: cells.last!.date), 4)
    XCTAssertEqual(model.weekdaySymbols, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    XCTAssertEqual(Set(cells.map(\.date)).count, 42)
  }
  func testSundayGridAndISOYearBoundaryUseTheConfiguredCalendar() throws {
    let c = calendar(monday: false), selected = date(2027, 1, 1, in: c)
    let model = try XCTUnwrap(
      CalendarMonth.make(
        displayedMonth: selected, selected: selected, now: selected, calendar: c,
        showsWeekNumbers: false, locale: Locale(identifier: "en_US")))
    XCTAssertEqual(model.weekdaySymbols.first, "Sun")
    XCTAssertEqual(c.component(.weekday, from: model.weeks[0].days[0].date), 1)
    XCTAssertEqual(
      model.weeks[0].number, c.component(.weekOfYear, from: model.weeks[0].days[3].date))
    XCTAssertFalse(model.showsWeekNumbers)
  }
  func testSelectedDayIntervalsFollowSpringAndAutumnDSTInsteadOfFixedSeconds() throws {
    let c = calendar("America/New_York")
    for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
      let selected = date(2026, month, day, in: c)
      let model = try XCTUnwrap(
        CalendarMonth.make(
          displayedMonth: selected, selected: selected, now: selected, calendar: c,
          showsWeekNumbers: true))
      XCTAssertEqual(model.dayInterval.duration, Double(hours) * 3600)
      XCTAssertEqual(c.component(.hour, from: model.selection), 0)
    }
  }
  func testNavigationClampsLeapAndShortMonthsAndRejectsUnboundedOffsets() throws {
    let c = calendar()
    let february = try XCTUnwrap(
      CalendarMonth.movedSelection(date(2024, 1, 31, in: c), months: 1, calendar: c))
    XCTAssertEqual(
      c.dateComponents([.year, .month, .day], from: february),
      DateComponents(year: 2024, month: 2, day: 29))
    let april = try XCTUnwrap(
      CalendarMonth.movedSelection(date(2026, 3, 31, in: c), months: 1, calendar: c))
    XCTAssertEqual(
      c.dateComponents([.year, .month, .day], from: april),
      DateComponents(year: 2026, month: 4, day: 30))
    XCTAssertNil(CalendarMonth.movedSelection(april, months: 1201, calendar: c))
  }
}
