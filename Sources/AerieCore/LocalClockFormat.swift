import Foundation

/// One formatting policy shared by the local clock, Settings example and detail menu.
public enum LocalClockFormat {
  public static func configure(
    _ formatter: DateFormatter, pattern: String,
    locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent,
    zone: TimeZone = .autoupdatingCurrent
  ) {
    formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = zone
    if pattern.isEmpty {
      formatter.setLocalizedDateFormatFromTemplate("EEE MMMd jmm")
    } else {
      formatter.dateFormat = String(pattern.prefix(80))
    }
  }
}
