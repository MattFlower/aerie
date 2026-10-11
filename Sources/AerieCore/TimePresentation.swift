import Foundation

public enum WorldClockStyle: String, Codable, CaseIterable {
  case compact, large, analog
  public var title: String { rawValue.capitalized }
}
public enum WorldClockOrder: String, Codable, CaseIterable {
  case manual, name, localTime
  public var title: String {
    switch self {
    case .manual: return "Manual order"
    case .name: return "Name"
    case .localTime: return "Local time"
    }
  }
}
public enum CalendarSystem: String, Codable, CaseIterable {
  case automatic, gregorian, iso8601, hebrew, islamicCivil, japanese, chinese
  public var title: String {
    switch self {
    case .automatic: return "System calendar"
    case .gregorian: return "Gregorian"
    case .iso8601: return "ISO 8601"
    case .hebrew: return "Hebrew"
    case .islamicCivil: return "Islamic civil"
    case .japanese: return "Japanese"
    case .chinese: return "Chinese"
    }
  }
  public var identifier: Calendar.Identifier? {
    switch self {
    case .automatic: return nil
    case .gregorian: return .gregorian
    case .iso8601: return .iso8601
    case .hebrew: return .hebrew
    case .islamicCivil: return .islamicCivil
    case .japanese: return .japanese
    case .chinese: return .chinese
    }
  }
}
public enum WeekNumberStyle: String, Codable, CaseIterable {
  case iso8601, calendar
  public var title: String { self == .iso8601 ? "ISO 8601 weeks" : "Selected calendar weeks" }
}
public struct CalendarOptions: Codable, Equatable {
  public var system: CalendarSystem = .automatic
  public var firstWeekday = 2
  public var weekNumbers: WeekNumberStyle = .iso8601
  public var upcomingDays = 7
  public init(firstWeekday: Int = 2) { self.firstWeekday = firstWeekday }
  public var valid: Bool { (1...7).contains(firstWeekday) && (1...31).contains(upcomingDays) }
  public func calendar(systemCalendar: Calendar = .current) -> Calendar {
    var value = system.identifier.map { Calendar(identifier: $0) } ?? systemCalendar
    value.locale = systemCalendar.locale; value.timeZone = systemCalendar.timeZone
    value.firstWeekday = firstWeekday
    return value
  }
  public func upcomingInterval(from date: Date, calendar: Calendar) -> DateInterval? {
    guard valid, date.timeIntervalSince1970.isFinite,
      let end = calendar.date(byAdding: .day, value: upcomingDays, to: date), end > date
    else { return nil }
    return DateInterval(start: date, end: end)
  }
}
public struct WorldClockReading: Equatable {
  public let name, zone, time, date, offset, day: String
  public let hour, minute, second: Int
  public var hourAngle: Double { Double(hour % 12) / 12 * 2 * .pi + minuteAngle / 12 }
  public var minuteAngle: Double { (Double(minute) + Double(second) / 60) / 60 * 2 * .pi }
  public var secondAngle: Double { Double(second) / 60 * 2 * .pi }
  public var accessibilityLabel: String {
    "\(name), \(time), \(date), \(offset), \(day), \(zone)"
  }
}
public enum ClockPresentation {
  /// Open-panel formatting only: no per-clock timer or background retained formatter cache.
  public static func readings(
    _ clocks: [WorldClock], at now: Date, relativeTo localZone: TimeZone = .current,
    order: WorldClockOrder = .manual, locale: Locale = .current
  ) -> [WorldClockReading] {
    guard clocks.count <= 20, now.timeIntervalSince1970.isFinite,
      (-62135596800...253402300799).contains(now.timeIntervalSince1970)
    else { return [] }
    let time = DateFormatter(), date = DateFormatter()
    time.locale = locale; date.locale = locale
    time.setLocalizedDateFormatFromTemplate("jmmss")
    date.setLocalizedDateFormatFromTemplate("EEE MMM d")
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = localZone
    let local = calendar.dateComponents([.year, .month, .day], from: now)
    var result: [WorldClockReading] = []
    for clock in clocks {
      guard !clock.name.isEmpty, clock.name.count <= 64,
        let zone = TimeZone(identifier: clock.zone)
      else { continue }
      calendar.timeZone = zone
      let parts = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: now)
      guard let h = parts.hour, let m = parts.minute, let s = parts.second,
        (0...23).contains(h), (0...59).contains(m), (0...60).contains(s)
      else { continue }
      time.timeZone = zone; date.timeZone = zone
      let seconds = zone.secondsFromGMT(for: now), minutes = abs(seconds) / 60
      let offset = String(
        format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
      // Compare civil dates in a neutral calendar, rather than 24-hour elapsed buckets across DST.
      var neutral = Calendar(identifier: .gregorian);
      neutral.timeZone = TimeZone(secondsFromGMT: 0)!
      let dayOffset =
        neutral.date(from: local).flatMap { start in
          neutral.date(from: parts).flatMap { end in
            neutral.dateComponents([.day], from: start, to: neutral.startOfDay(for: end)).day
          }
        } ?? 0
      let day =
        dayOffset == 0
        ? "Same date"
        : dayOffset == 1
          ? "Next date" : dayOffset == -1 ? "Previous date" : "\(dayOffset) dates apart"
      result.append(
        WorldClockReading(
          name: clock.name, zone: zone.identifier, time: time.string(from: now),
          date: date.string(from: now), offset: offset, day: day, hour: h, minute: m, second: s))
    }
    if order == .manual { return result }
    return result.sorted {
      if order == .localTime {
        let l = $0.hour * 3600 + $0.minute * 60 + $0.second
        let r = $1.hour * 3600 + $1.minute * 60 + $1.second
        if l != r { return l < r }
      }
      if $0.name != $1.name {
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      return $0.zone < $1.zone
    }
  }
}
