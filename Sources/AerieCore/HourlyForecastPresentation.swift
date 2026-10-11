import Foundation

public enum HourlyForecastPresentation {
  public static func indices(_ hours: [WeatherHour], at now: Date, limit: Int) -> [Int] {
    guard hours.count <= 384, [24, 48, 72, 168].contains(limit), now.timeIntervalSince1970.isFinite
    else { return [] }
    return hours.indices.filter {
      let h = hours[$0]
      guard h.date.timeIntervalSince1970.isFinite,
        (-62135596800...253402300799).contains(h.date.timeIntervalSince1970)
      else { return false }
      if let end = h.end {
        return end.timeIntervalSince1970.isFinite
          && (-62135596800...253402300799).contains(end.timeIntervalSince1970) && end > h.date
          && end > now
      }
      return h.date >= now.addingTimeInterval(-3600)
    }.sorted { hours[$0].date == hours[$1].date ? $0 < $1 : hours[$0].date < hours[$1].date }
      .prefix(limit).map { $0 }
  }
  public static func fields(_ hour: WeatherHour, zone: TimeZone, temperature: TemperatureUnit) -> [(
    String, String
  )] {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone; formatter.dateFormat = "EEE d MMM yyyy HH:mm:ss z (XXXXX)"
    func date(_ date: Date?) -> String {
      guard let date, date.timeIntervalSince1970.isFinite,
        (-62135596800...253402300799).contains(date.timeIntervalSince1970)
      else { return "Unavailable" }
      return formatter.string(from: date)
    }
    func number(_ value: Double?, suffix: String, range: ClosedRange<Double>? = nil) -> String {
      guard let value, value.isFinite, range?.contains(value) ?? true else { return "Unavailable" }
      return String(format: "%.1f", value) + suffix
    }
    func degrees(_ value: Double?) -> String {
      value.flatMap { $0.isFinite ? Format.temperature($0, unit: temperature) : nil }
        ?? "Unavailable"
    }
    func text(_ value: String?) -> String? {
      value.flatMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String($0.prefix(4096))
      }
    }
    let end = hour.end.flatMap { $0 > hour.date ? $0 : nil }
    let window: String
    if hour.precedingHourAggregates {
      window =
        date(hour.date.addingTimeInterval(-3600)) + " – " + date(hour.date)
        + " (preceding hour; precipitation sum/probability and maximum gust)"
    } else if let end {
      window = date(hour.date) + " – " + date(end) + " (provider forecast period)"
    } else {
      window = "Unavailable"
    }
    return [
      (hour.end == nil ? "Forecast instant" : "Valid from", date(hour.date)),
      ("Valid until", date(end)),
      ("Conditions", text(hour.condition) ?? WeatherCondition.describe(hour.code)),
      ("Temperature", degrees(hour.temperature)), ("Feels like", degrees(hour.apparent)),
      ("Humidity", number(hour.humidity, suffix: "%", range: 0...100)),
      ("Dew point", degrees(hour.dewpoint)),
      ("Wind", text(hour.windDescription) ?? number(hour.wind, suffix: " km/h", range: 0...1e12)),
      ("Gusts", text(hour.gustDescription) ?? number(hour.gusts, suffix: " km/h", range: 0...1e12)),
      ("Wind direction", number(hour.direction, suffix: "°", range: 0...360)),
      (
        "Surface pressure",
        number(hour.pressure, suffix: " hPa", range: Double.leastNonzeroMagnitude...1e12)
      ),
      ("Cloud cover", number(hour.cloud, suffix: "%", range: 0...100)),
      ("Precipitation probability", number(hour.precipitation, suffix: "%", range: 0...100)),
      ("Precipitation amount", number(hour.amount, suffix: " mm", range: 0...1e12)),
      ("Precipitation / gust timing", window),
      ("UV index", number(hour.uv, suffix: "", range: 0...1e12)),
      ("Visibility", number(hour.visibility, suffix: " m", range: 0...1e12)),
      ("Provider detail", text(hour.detail) ?? "Unavailable"),
    ]
  }
  public static func message(
    _ hour: WeatherHour, report: WeatherReport, temperature: TemperatureUnit
  ) -> String {
    fields(hour, zone: report.timeContext.instantZone, temperature: temperature).map {
      $0.0 + ": " + $0.1
    }.joined(separator: "\n")
      + "\n\nSource: \(report.source) · fetched \(report.fetched.formatted())\n\(report.timeContext.description)\nUnavailable fields were not supplied or are invalid. This view uses cached forecasts; opening it makes no new requests."
  }
}
