import Foundation

public enum WeatherOutlookBasis {
  case daily, daytimeAndOvernight, unclassifiedPeriods
}

/// Provider extrema retain their actual daily or issued-period windows.
public struct WeatherOutlook {
  public let date: Date
  public let title: String
  public let summary: String
  public let low, high, precipitation: Double?
  public let code: Int?
  public let glyph: WeatherGlyph?
  public let isDay: Bool?
  public let dayIndex: Int?
  public let periodIndices: [Int]
  public let basis: WeatherOutlookBasis
  public var identifier: String {
    dayIndex.map { "weather-day:\($0)" } ?? "weather-outlook:\(periodIndices.first ?? -1)"
  }
  public var isDaily: Bool { dayIndex != nil }
  public var qualification: String? {
    if basis == .unclassifiedPeriods { return "Period details" }
    if high == nil || low == nil { return "Partial" }
    return nil
  }
}

public enum WeatherOutlookPresentation {
  public static func outlooks(_ report: WeatherReport, at now: Date) -> [WeatherOutlook] {
    let formatter = DateFormatter(); formatter.dateFormat = "EEE"
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone =
      report.days.isEmpty ? report.timeContext.instantZone : report.timeContext.dailyZone
    formatter.timeZone = calendar.timeZone
    let today = calendar.startOfDay(for: now)
    let hasZone = report.timeContext.identifier != nil || report.timeContext.offsetSeconds != nil
    func title(_ date: Date) -> String {
      if !hasZone { return formatter.string(from: date) + " UTC" }
      return calendar.isDate(date, inSameDayAs: now) ? "Today" : formatter.string(from: date)
    }
    if !report.days.isEmpty {
      return report.days.indices.filter { report.days[$0].date >= today }.sorted {
        report.days[$0].date < report.days[$1].date
      }.map { index in
        let value = report.days[index]
        return WeatherOutlook(
          date: value.date, title: title(value.date),
          summary: WeatherCondition.describe(value.code),
          low: finite(value.low), high: finite(value.high),
          precipitation: probability(value.precipitation), code: value.code, glyph: nil, isDay: nil,
          dayIndex: index, periodIndices: [], basis: .daily)
      }
    }
    let active = report.periods.indices.filter { report.periods[$0].end > now }
    func forecastDate(_ index: Int) -> Date {
      let period = report.periods[index]
      let start = calendar.startOfDay(for: period.start)
      // A pre-dawn minimum belongs to the overnight window that began on the prior local day.
      // Calendar arithmetic preserves civil dates across DST; no fixed 86400-second subtraction.
      if hasZone, period.temperatureStatistic == .minimum,
        calendar.component(.hour, from: period.start) < 12
      {
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
      }
      return start
    }
    var groups = Dictionary(grouping: active, by: forecastDate)
    let earlierOvernight = active.filter { forecastDate($0) < today }
    // Keep an active earlier overnight forecast inspectable, without assigning its minimum
    // to today's daytime/following-night pair.
    if !earlierOvernight.isEmpty && groups[today] == nil { groups[today] = [] }
    return groups.keys.filter { $0 >= today }.sorted().map { date in
      let paired = groups[date]!.sorted { report.periods[$0].start < report.periods[$1].start }
      let extra = date == today ? earlierOvernight : []
      let indices = (paired + extra).sorted { report.periods[$0].start < report.periods[$1].start }
      let maxima = paired.filter { report.periods[$0].temperatureStatistic == .maximum }
      let minima = paired.filter { report.periods[$0].temperatureStatistic == .minimum }
      let classified = hasZone && (!maxima.isEmpty || !minima.isEmpty)
      let high = hasZone ? maxima.compactMap { finite(report.periods[$0].temperature) }.max() : nil
      let low = hasZone ? minima.compactMap { finite(report.periods[$0].temperature) }.min() : nil
      let primary = report.periods[maxima.first ?? paired.first ?? indices[0]]
      var conditions: [String] = []
      for index in paired.isEmpty ? extra : paired {
        let value = report.periods[index].condition
        if !value.isEmpty && !conditions.contains(value) { conditions.append(value) }
      }
      return WeatherOutlook(
        date: date, title: title(date),
        summary: conditions.isEmpty
          ? "Conditions unavailable" : conditions.joined(separator: " · "),
        low: low, high: high,
        precipitation: (paired.isEmpty ? extra : paired).compactMap {
          probability(report.periods[$0].precipitation)
        }.max(),
        code: nil, glyph: primary.glyph, isDay: primary.isDay, dayIndex: nil,
        periodIndices: indices,
        basis: classified ? .daytimeAndOvernight : .unclassifiedPeriods)
    }
  }
  public static func daylight(_ hour: WeatherHour, report: WeatherReport) -> Bool? {
    if let isDay = hour.isDay { return isDay }
    var calendar = Calendar(identifier: .gregorian);
    calendar.timeZone = report.timeContext.dailyZone
    guard let day = report.days.first(where: { calendar.isDate($0.date, inSameDayAs: hour.date) }),
      let rise = day.sunrise, let set = day.sunset, rise < set
    else { return nil }
    return hour.date >= rise && hour.date < set
  }
  public static func message(
    _ outlook: WeatherOutlook, report: WeatherReport, temperature: TemperatureUnit
  ) -> String {
    let formatter = DateFormatter(); formatter.timeZone = report.timeContext.instantZone
    formatter.dateStyle = .medium; formatter.timeStyle = .short
    func degrees(_ value: Double?) -> String {
      finite(value).map { Format.weatherTemperature($0, unit: temperature) } ?? "Unavailable"
    }
    var text = ["High: " + degrees(outlook.high), "Low: " + degrees(outlook.low)]
    if let index = outlook.dayIndex, report.days.indices.contains(index) {
      let day = report.days[index]
      text += [
        "Basis: provider daily maximum / minimum for its forecast-day boundary.",
        "Conditions: " + WeatherCondition.describe(day.code),
        "Maximum precipitation probability: "
          + (probability(day.precipitation).map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        "Maximum UV index: " + (finite(day.uv).map { String(format: "%.1f", $0) } ?? "Unavailable"),
        "Sunrise: " + (day.sunrise.map(formatter.string(from:)) ?? "Unavailable"),
        "Sunset: " + (day.sunset.map(formatter.string(from:)) ?? "Unavailable"),
      ]
    } else {
      text.append(
        outlook.basis == .daytimeAndOvernight
          ? "Basis: provider maximum for the issued daytime period and minimum for its following overnight period. These are not midnight-to-midnight daily extrema; partial/current periods retain their published valid windows."
          : "Daily high/low unavailable: period statistic or forecast timezone is unverified. Original period temperatures remain below; hourly samples are never promoted to daily extrema."
      )
      if outlook.qualification != nil {
        text.append("Partial or unclassified forecast; absent high/low values are not inferred.")
      }
      for index in outlook.periodIndices where report.periods.indices.contains(index) {
        let period = report.periods[index]
        text += [
          "", period.name,
          "Valid: \(formatter.string(from: period.start)) – \(formatter.string(from: period.end))",
          "Temperature statistic: " + period.temperatureStatistic.rawValue,
          "Forecast-period temperature: " + degrees(period.temperature),
          "Temperature trend: " + (period.temperatureTrend ?? "Not supplied"),
          "Precipitation probability: "
            + (probability(period.precipitation).map { String(format: "%.0f%%", $0) }
              ?? "Unavailable"),
          "Wind: " + (period.wind.isEmpty ? "Unavailable" : period.wind),
          period.condition, period.detail,
        ]
      }
      text.append(
        "An active earlier pre-dawn period can appear in details but is not paired with today's following-night low. The compact rain chance is the maximum probability among the paired periods."
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
