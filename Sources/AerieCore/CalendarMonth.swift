import Foundation

public struct CalendarCell: Equatable {
  public let date: Date
  public let day: Int
  public let inMonth, selected, today: Bool
}
public struct CalendarWeek: Equatable {
  public let days: [CalendarCell]
  public let number: Int
}
public struct CalendarMonth: Equatable {
  public let start: Date
  public let selection: Date
  public let weeks: [CalendarWeek]
  public let weekdaySymbols: [String]
  public let showsWeekNumbers: Bool
  public let title: String
  public let selectedDayTitle: String
  public let dayInterval: DateInterval
  public let calendar: Calendar

  /// Calendar arithmetic preserves the user's calendar, time zone, and DST day lengths.
  public static func make(
    displayedMonth: Date, selected: Date, now: Date, calendar: Calendar,
    showsWeekNumbers: Bool, locale: Locale = .current
  ) -> CalendarMonth? {
    guard (1...7).contains(calendar.firstWeekday),
      let month = calendar.dateInterval(of: .month, for: displayedMonth),
      let day = calendar.dateInterval(of: .day, for: selected),
      let count = calendar.range(of: .day, in: .month, for: month.start),
      (1...40).contains(count.count)
    else { return nil }
    let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
    guard let first = calendar.date(byAdding: .day, value: -offset, to: month.start) else {
      return nil
    }
    let rowCount = (offset + count.count + 6) / 7
    var weeks: [CalendarWeek] = []
    for row in 0..<rowCount {
      var cells: [CalendarCell] = []
      for column in 0..<7 {
        guard let date = calendar.date(byAdding: .day, value: row * 7 + column, to: first) else {
          return nil
        }
        cells.append(
          CalendarCell(
            date: date, day: calendar.component(.day, from: date),
            inMonth: date >= month.start && date < month.end,
            selected: calendar.isDate(date, inSameDayAs: selected),
            today: calendar.isDate(date, inSameDayAs: now)))
      }
      // A week number belongs to the calendar's complete week, including adjacent-month days.
      weeks.append(
        CalendarWeek(days: cells, number: calendar.component(.weekOfYear, from: cells[0].date)))
    }
    let formatter = DateFormatter()
    formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMMM y")
    let title = formatter.string(from: month.start)
    formatter.dateStyle = .full
    let selectedTitle = formatter.string(from: day.start)
    let symbols = formatter.shortWeekdaySymbols ?? []
    guard symbols.count == 7 else { return nil }
    let ordered = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    return CalendarMonth(
      start: month.start, selection: day.start, weeks: weeks, weekdaySymbols: ordered,
      showsWeekNumbers: showsWeekNumbers, title: title, selectedDayTitle: selectedTitle,
      dayInterval: day, calendar: calendar)
  }

  /// Clamp the selected day in a shorter destination month instead of overflowing into another month.
  public static func movedSelection(_ selected: Date, months: Int, calendar: Calendar) -> Date? {
    guard (-1200...1200).contains(months),
      let start = calendar.dateInterval(of: .month, for: selected)?.start,
      let destination = calendar.date(byAdding: .month, value: months, to: start),
      let days = calendar.range(of: .day, in: .month, for: destination)
    else { return nil }
    let day = min(calendar.component(.day, from: selected), days.count)
    return calendar.date(byAdding: .day, value: day - 1, to: destination)
  }
}
