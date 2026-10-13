import Foundation

/// Compact outlooks retain the distinction between daily extrema and issued day/night periods.
public struct WeatherOutlook {
  public let date: Date
  public let title: String
  public let summary: String
  public let low, high, day, night, precipitation: Double?
  public let code: Int?
  public let glyph: WeatherGlyph?
  public let isDay: Bool?
  public let dayIndex: Int?
  public let periodIndices: [Int]
  public var identifier: String {
    dayIndex.map { "weather-day:\($0)" } ?? "weather-outlook:\(periodIndices.first ?? -1)"
  }
  public var isDaily: Bool { dayIndex != nil }
}

public enum WeatherOutlookPresentation {
  public static func outlooks(_ report: WeatherReport, at now: Date) -> [WeatherOutlook] {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE"
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone =
      report.days.isEmpty ? report.timeContext.instantZone : report.timeContext.dailyZone
    formatter.timeZone = calendar.timeZone
    let today = calendar.startOfDay(for: now)
    func title(_ date: Date) -> String {
      calendar.isDate(date, inSameDayAs: now) ? "Today" : formatter.string(from: date)
    }
    if !report.days.isEmpty {
      return report.days.indices.filter { report.days[$0].date >= today }.sorted {
        report.days[$0].date < report.days[$1].date
      }.map { index in
        let value = report.days[index]
        return WeatherOutlook(
          date: value.date, title: title(value.date),
          summary: WeatherCondition.describe(value.code),
          low: finite(value.low), high: finite(value.high), day: nil, night: nil,
          precipitation: probability(value.precipitation), code: value.code, glyph: nil, isDay: nil,
          dayIndex: index, periodIndices: [])
      }
    }
    let groups = Dictionary(
      grouping: report.periods.indices.filter {
        report.periods[$0].end > now
      }
    ) { calendar.startOfDay(for: report.periods[$0].start) }
    return groups.keys.sorted().map { date in
      let indices = groups[date]!.sorted { report.periods[$0].start < report.periods[$1].start }
      let day = indices.first { report.periods[$0].isDay }
      let night = indices.first { !report.periods[$0].isDay }
      let primary = report.periods[day ?? night ?? indices[0]]
      var conditions: [String] = []
      for index in indices {
        let value = report.periods[index].condition
        if !value.isEmpty && !conditions.contains(value) { conditions.append(value) }
      }
      return WeatherOutlook(
        date: date, title: title(date),
        summary: conditions.isEmpty
          ? "Conditions unavailable" : conditions.joined(separator: " · "),
        low: nil, high: nil,
        day: day.flatMap { finite(report.periods[$0].temperature) },
        night: night.flatMap { finite(report.periods[$0].temperature) },
        precipitation: indices.compactMap { probability(report.periods[$0].precipitation) }.max(),
        code: nil, glyph: primary.glyph, isDay: primary.isDay, dayIndex: nil, periodIndices: indices
      )
    }
  }
  public static func daylight(_ hour: WeatherHour, report: WeatherReport) -> Bool? {
    if let isDay = hour.isDay { return isDay }
    // Only infer daylight when this forecast day's actual sunrise and sunset were supplied.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = report.timeContext.dailyZone
    guard let day = report.days.first(where: { calendar.isDate($0.date, inSameDayAs: hour.date) }),
      let rise = day.sunrise, let set = day.sunset, rise < set
    else { return nil }
    return hour.date >= rise && hour.date < set
  }
  public static func message(
    _ outlook: WeatherOutlook, report: WeatherReport, temperature: TemperatureUnit
  ) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = report.timeContext.instantZone
    formatter.dateStyle = .medium; formatter.timeStyle = .short
    func degrees(_ value: Double?) -> String {
      finite(value).map { Format.temperature($0, unit: temperature) } ?? "Unavailable"
    }
    var text: [String] = []
    if let index = outlook.dayIndex, report.days.indices.contains(index) {
      let day = report.days[index]
      text = [
        "Daily minimum: " + degrees(day.low), "Daily maximum: " + degrees(day.high),
        "Conditions: " + WeatherCondition.describe(day.code),
        "Maximum precipitation probability: "
          + (probability(day.precipitation).map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        "Maximum UV index: " + (finite(day.uv).map { String(format: "%.1f", $0) } ?? "Unavailable"),
        "Sunrise: " + (day.sunrise.map(formatter.string(from:)) ?? "Unavailable"),
        "Sunset: " + (day.sunset.map(formatter.string(from:)) ?? "Unavailable"),
      ]
    } else {
      for index in outlook.periodIndices where report.periods.indices.contains(index) {
        let period = report.periods[index]
        text += [
          period.name + (period.isDay ? " · day period" : " · night period"),
          "Valid: \(formatter.string(from: period.start)) – \(formatter.string(from: period.end))",
          "Forecast-period temperature: " + degrees(period.temperature),
          "Precipitation probability: "
            + (probability(period.precipitation).map { String(format: "%.0f%%", $0) }
              ?? "Unavailable"),
          "Wind: " + (period.wind.isEmpty ? "Unavailable" : period.wind),
          period.condition, period.detail, "",
        ]
      }
      text.append(
        "Day and night values are issued period temperatures, not calculated daily extrema. The compact rain chance is the maximum probability among these periods."
      )
    }
    return text.joined(separator: "\n")
      + "\n\nSource: \(report.source) · fetched \(report.fetched.formatted())\n\(report.timeContext.description)\nUnavailable fields were not supplied or are invalid. This view uses cached forecasts; opening it makes no new requests."
  }
  private static func finite(_ value: Double?) -> Double? {
    value.flatMap { $0.isFinite ? $0 : nil }
  }
  private static func probability(_ value: Double?) -> Double? {
    finite(value).flatMap { (0...100).contains($0) ? $0 : nil }
  }
}
