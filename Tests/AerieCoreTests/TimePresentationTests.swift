import Foundation
import XCTest
@testable import AerieCore

final class TimePresentationTests: XCTestCase {
  private let utc = TimeZone(secondsFromGMT: 0)!
  private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
  func testClockOffsetsCivilDateRelationAndContinuousHands() throws {
    let readings = ClockPresentation.readings(
      [
        WorldClock(name: "West", zone: "Pacific/Honolulu"),
        WorldClock(name: "Quarter offset", zone: "Asia/Kathmandu"),
        WorldClock(name: "East", zone: "Pacific/Kiritimati"),
      ], at: instant("2026-02-01T00:30:15Z"), relativeTo: utc, locale: Locale(identifier: "en_GB"))
    XCTAssertEqual(readings.map(\.day), ["Previous date", "Same date", "Same date"])
    XCTAssertEqual(readings.map(\.offset), ["UTC−10:00", "UTC+05:45", "UTC+14:00"])
    let quarter = try XCTUnwrap(readings.first { $0.name == "Quarter offset" })
    XCTAssertEqual(quarter.hour, 6); XCTAssertEqual(quarter.minute, 15);
    XCTAssertEqual(quarter.second, 15)
    XCTAssertEqual(quarter.minuteAngle, 15.25 / 60 * 2 * .pi, accuracy: 1e-10)
    XCTAssertEqual(quarter.hourAngle, .pi + quarter.minuteAngle / 12, accuracy: 1e-10)
    XCTAssertTrue(quarter.accessibilityLabel.contains("Asia/Kathmandu"))
    let distant = try XCTUnwrap(
      ClockPresentation.readings(
        [WorldClock(name: "West", zone: "Pacific/Pago_Pago")], at: instant("2026-02-01T10:30:00Z"),
        relativeTo: TimeZone(identifier: "Pacific/Kiritimati")!
      ).first)
    XCTAssertEqual(distant.day, "-2 dates apart")
  }
  func testRepeatedDSTHourRetainsDistinctOffsetAndSortingDoesNotAlterManualOrder() throws {
    let clocks = [
      WorldClock(name: "Zulu", zone: "Etc/UTC"),
      WorldClock(name: "Alpha", zone: "America/New_York"),
    ]
    let first = ClockPresentation.readings(
      clocks, at: instant("2026-11-01T05:30:00Z"), relativeTo: utc)
    let second = ClockPresentation.readings(
      clocks, at: instant("2026-11-01T06:30:00Z"), relativeTo: utc)
    XCTAssertEqual(first.map(\.name), ["Zulu", "Alpha"])
    XCTAssertEqual(first[1].hour, 1); XCTAssertEqual(second[1].hour, 1)
    XCTAssertEqual(first[1].offset, "UTC−04:00"); XCTAssertEqual(second[1].offset, "UTC−05:00")
    for order in [WorldClockOrder.name, .localTime] {
      XCTAssertEqual(
        ClockPresentation.readings(clocks, at: instant("2026-11-01T05:30:00Z"), order: order).map(
          \.name), ["Alpha", "Zulu"])
    }
    XCTAssertEqual(clocks[0].name, "Zulu")
  }
  func testInvalidClockInputIsUnavailableAndBounded() {
    let clocks = [WorldClock(name: "Bad", zone: "Unknown/Zone"), WorldClock(name: "", zone: "UTC")]
    XCTAssertTrue(ClockPresentation.readings(clocks, at: Date()).isEmpty)
    let valid = WorldClock(name: "UTC", zone: "UTC")
    for time in [Double.nan, .infinity, 1e100] {
      XCTAssertTrue(
        ClockPresentation.readings([valid], at: Date(timeIntervalSince1970: time)).isEmpty)
    }
    XCTAssertTrue(
      ClockPresentation.readings(Array(repeating: valid, count: 21), at: Date()).isEmpty)
  }
  func testCalendarSystemsAndISOWeeksUseConfiguredZoneAndThursdayForAnyFirstDay() throws {
    var system = Calendar(identifier: .gregorian); system.timeZone = utc;
    system.locale = Locale(identifier: "en_US")
    let selected = instant("2021-01-01T12:00:00Z")
    for kind in CalendarSystem.allCases {
      var options = CalendarOptions(); options.system = kind
      let calendar = options.calendar(systemCalendar: system)
      XCTAssertEqual(calendar.timeZone, utc)
      let model = try XCTUnwrap(
        CalendarMonth.make(
          displayedMonth: selected, selected: selected, now: selected, calendar: calendar,
          showsWeekNumbers: true, weekNumberStyle: .iso8601))
      XCTAssertEqual(model.weeks.flatMap(\.days).filter(\.selected).count, 1)
      XCTAssertTrue((4...6).contains(model.weeks.count))
    }
    for first in 1...7 {
      var options = CalendarOptions(firstWeekday: first); options.system = .gregorian
      let calendar = options.calendar(systemCalendar: system)
      let model = try XCTUnwrap(
        CalendarMonth.make(
          displayedMonth: selected, selected: selected, now: selected, calendar: calendar,
          showsWeekNumbers: true, weekNumberStyle: .iso8601))
      var iso = Calendar(identifier: .iso8601); iso.timeZone = utc
      for week in model.weeks {
        let thursday = try XCTUnwrap(
          week.days.first { calendar.component(.weekday, from: $0.date) == 5 })
        XCTAssertEqual(week.number, iso.component(.weekOfYear, from: thursday.date))
      }
    }
  }
  func testUpcomingRangeUsesCivilDaysAcrossDSTAndRejectsInvalidBounds() throws {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
    var options = CalendarOptions(); options.upcomingDays = 1
    let spring = try XCTUnwrap(
      options.upcomingInterval(from: instant("2026-03-07T17:00:00Z"), calendar: c))
    let autumn = try XCTUnwrap(
      options.upcomingInterval(from: instant("2026-10-31T16:00:00Z"), calendar: c))
    XCTAssertEqual(spring.duration, 23 * 3600); XCTAssertEqual(autumn.duration, 25 * 3600)
    for days in [0, 32] {
      options.upcomingDays = days; XCTAssertFalse(options.valid);
      XCTAssertNil(options.upcomingInterval(from: spring.start, calendar: c))
    }
  }
  func testSettingsBackwardCompatibilityAndOptionValidation() throws {
    var settings = Settings(); settings.weekStartsMonday = false
    XCTAssertEqual(settings.effectiveCalendarOptions.firstWeekday, 1)
    var options = CalendarOptions(firstWeekday: 7); options.system = .hebrew;
    options.upcomingDays = 31
    settings.calendarOptions = options; settings.worldClockStyle = .analog;
    settings.worldClockOrder = .localTime
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).validated(),
      settings)
    options.firstWeekday = 8; settings.calendarOptions = options
    XCTAssertThrowsError(try settings.validated())
    var old =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
    for key in ["calendarOptions", "worldClockStyle", "worldClockOrder"] {
      old.removeValue(forKey: key)
    }
    let decoded = try JSONDecoder().decode(
      Settings.self, from: JSONSerialization.data(withJSONObject: old))
    XCTAssertNil(decoded.calendarOptions); XCTAssertNil(decoded.worldClockStyle);
    XCTAssertNil(decoded.worldClockOrder)
  }
}
