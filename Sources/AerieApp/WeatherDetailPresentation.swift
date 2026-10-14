import AerieCore
import AppKit

/// Cached weather is arranged as explicit observations/forecast windows, never inferred facts.
enum WeatherDetailPresentation {
  static func source(_ report: WeatherReport) -> String {
    (report.source == "NWS" ? "NWS · Public-domain data" : "Open-Meteo · CC BY 4.0") + "\n"
      + report.attributionURL
  }
  static func number(_ value: Double?, suffix: String, range: ClosedRange<Double> = 0...1e12)
    -> String
  {
    guard let value, value.isFinite, range.contains(value) else { return "Unavailable" }
    return String(format: suffix == "%" || suffix == "°" ? "%.0f" : "%.1f", value) + suffix
  }
  static func date(_ date: Date?, zone: TimeZone) -> String {
    guard let date else { return "Unavailable" }
    let formatter = DateFormatter(); formatter.timeZone = zone
    formatter.dateStyle = .medium; formatter.timeStyle = .short
    return formatter.string(from: date) + " " + (zone.abbreviation(for: date) ?? zone.identifier)
  }
  static func current(_ report: WeatherReport, name: String, status: String, unit: TemperatureUnit)
    -> DetailPresentation
  {
    let condition = report.condition ?? WeatherCondition.describe(report.code)
    var value = DetailPresentation(
      title: "Current conditions",
      subtitle: name + " · " + condition + "\n" + report.source + " · cached forecast/observation",
      symbol: MenuRenderer.weatherSymbol(
        code: report.code, daylight: report.isDay, glyph: report.glyph), accent: .systemBlue,
      hero: DetailFact("Temperature", Format.weatherTemperature(report.temperature, unit: unit)),
      highlights: [
        DetailFact("Feels like", Format.weatherTemperature(report.apparent, unit: unit)),
        DetailFact("Humidity", number(report.humidity, suffix: "%", range: 0...100)),
      ],
      sections: [
        DetailSection(
          title: "Wind & air",
          facts: [
            DetailFact("Wind", number(report.wind, suffix: " km/h")),
            DetailFact("Gusts", number(report.gusts, suffix: " km/h")),
            DetailFact("Direction", number(report.direction, suffix: "°", range: 0...360)),
            DetailFact(
              "Surface pressure",
              number(report.pressure, suffix: " hPa", range: Double.leastNonzeroMagnitude...1e12)),
            DetailFact("Cloud cover", number(report.cloud, suffix: "%", range: 0...100)),
          ]),
        DetailSection(
          title: "Observation & forecast",
          facts: [
            DetailFact(
              "Observed", date(report.observationTime, zone: report.timeContext.instantZone)),
            DetailFact(
              "Forecast updated", date(report.forecastUpdated, zone: report.timeContext.instantZone)
            ),
          ],
          paragraphs: [
            status,
            "Current dew point, UV and visibility are not supplied by this observation source. Forecast values are available in hourly details.",
          ]),
      ], source: source(report))
    if let station = report.observationStation {
      value.sections[value.sections.count - 1].facts.insert(DetailFact("Station", station), at: 0)
    }
    if !status.hasPrefix("Updated ") { value.notices.append(status) }
    value.notices += report.alerts
    if let alerts = report.alertReport, !alerts.alerts.isEmpty {
      value.notices += alerts.alerts.map {
        $0.event + " · " + $0.severity + ". Open the alert in Weather for official instructions."
      }
    }
    value.diagnostics =
      WeatherDashboardPresentation.currentMessage(report, status: status, unit: unit)
      + "\nStored temperature (°C): \(report.temperature.map(String.init(describing:)) ?? "Unavailable")"
    return value
  }
  static func hour(_ hour: WeatherHour, report: WeatherReport, unit: TemperatureUnit)
    -> DetailPresentation
  {
    let fields = HourlyForecastPresentation.fields(
      hour, zone: report.timeContext.instantZone, temperature: unit)
    func field(_ label: String) -> DetailFact {
      let value = fields.first { $0.0 == label }?.1 ?? "Unavailable"
      if value.hasSuffix("%"), let number = Double(value.dropLast()), number.isFinite {
        return DetailFact(label, String(format: "%.0f%%", number))
      }
      return DetailFact(label, value)
    }
    let condition = hour.condition ?? WeatherCondition.describe(hour.code)
    let window =
      date(hour.date, zone: report.timeContext.instantZone)
      + (hour.end.map { " – " + date($0, zone: report.timeContext.instantZone) }
        ?? " · forecast instant")
    var value = DetailPresentation(
      title: "Hourly forecast", subtitle: window + "\n" + condition,
      symbol: MenuRenderer.weatherSymbol(
        code: hour.code, daylight: WeatherOutlookPresentation.daylight(hour, report: report),
        glyph: hour.glyph), accent: .systemBlue,
      hero: field("Temperature"),
      highlights: [field("Feels like"), field("Precipitation probability")],
      sections: [
        DetailSection(
          title: "Wind & air",
          facts: [
            field("Wind"), field("Gusts"), field("Humidity"), field("Dew point"),
            field("Wind direction"), field("Surface pressure"), field("Cloud cover"),
            field("Visibility"),
          ]),
        DetailSection(
          title: "Precipitation & sunlight",
          facts: [field("Precipitation amount"), field("UV index")],
          paragraphs: [
            hour.precedingHourAggregates
              ? "Precipitation and maximum gust cover the preceding hour; temperature describes the forecast instant."
              : "Readings apply to the provider’s stated forecast window."
          ]),
        DetailSection(
          title: "Forecast", paragraphs: [hour.detail ?? "No additional narrative supplied."]),
      ], source: source(report))
    let indices = HourlyForecastPresentation.indices(report.hours, at: hour.date, limit: 24)
    if indices.count > 1 {
      value.chart = DetailForecastChart(
        title: "Cached hourly temperature · forecast hours",
        dates: indices.map { report.hours[$0].date },
        values: indices.map { report.hours[$0].temperature }, unit: unit,
        zone: report.timeContext.instantZone)
    }
    value.diagnostics =
      HourlyForecastPresentation.message(hour, report: report, temperature: unit)
      + "\nStored temperature (°C): \(hour.temperature.map(String.init(describing:)) ?? "Unavailable")"
    return value
  }
  static func outlook(_ outlook: WeatherOutlook, report: WeatherReport, unit: TemperatureUnit)
    -> DetailPresentation
  {
    let basis: String
    switch outlook.basis {
    case .daily: basis = "Provider forecast-day high and low"
    case .daytimeAndOvernight:
      basis = "Daytime high / following overnight low · not midnight-to-midnight extrema"
    case .unclassifiedPeriods:
      basis = "Daily extrema unavailable · period statistic or timezone is unverified"
    }
    var value = DetailPresentation(
      title: outlook.title + " outlook", subtitle: outlook.summary,
      symbol: MenuRenderer.weatherSymbol(
        code: outlook.code, daylight: outlook.isDay, glyph: outlook.glyph), accent: .systemBlue,
      highlights: [
        DetailFact("High", Format.weatherTemperature(outlook.high, unit: unit)),
        DetailFact("Low", Format.weatherTemperature(outlook.low, unit: unit)),
      ], notices: [basis], source: source(report))
    if let qualification = outlook.qualification {
      value.notices.append(qualification + " forecast · missing values are not inferred")
    }
    if let index = outlook.dayIndex, report.days.indices.contains(index) {
      let day = report.days[index]
      value.sections = [
        DetailSection(
          title: "Rain & daylight",
          facts: [
            DetailFact(
              "Maximum rain chance", number(day.precipitation, suffix: "%", range: 0...100)),
            DetailFact("Maximum UV index", number(day.uv, suffix: "")),
            DetailFact("Sunrise", date(day.sunrise, zone: report.timeContext.instantZone)),
            DetailFact("Sunset", date(day.sunset, zone: report.timeContext.instantZone)),
          ])
      ]
    } else {
      for index in outlook.periodIndices where report.periods.indices.contains(index) {
        let period = report.periods[index]
        value.sections.append(
          DetailSection(
            title: period.name,
            facts: [
              DetailFact(
                period.temperatureStatistic.rawValue,
                Format.weatherTemperature(period.temperature, unit: unit)),
              DetailFact("Rain chance", number(period.precipitation, suffix: "%", range: 0...100)),
              DetailFact("Wind", period.wind.isEmpty ? "Unavailable" : period.wind),
              DetailFact("Trend", period.temperatureTrend ?? "Not supplied"),
            ],
            paragraphs: [
              date(period.start, zone: report.timeContext.instantZone) + " – "
                + date(period.end, zone: report.timeContext.instantZone), period.condition,
              period.detail,
            ]))
      }
    }
    value.diagnostics = WeatherOutlookPresentation.message(
      outlook, report: report, temperature: unit)
    return value
  }
  static func period(_ period: WeatherPeriod, report: WeatherReport, unit: TemperatureUnit)
    -> DetailPresentation
  {
    DetailPresentation(
      title: period.name, subtitle: period.condition,
      symbol: MenuRenderer.weatherSymbol(code: nil, daylight: period.isDay, glyph: period.glyph),
      hero: DetailFact(
        period.temperatureStatistic.rawValue,
        Format.weatherTemperature(period.temperature, unit: unit)),
      highlights: [
        DetailFact("Rain chance", number(period.precipitation, suffix: "%", range: 0...100)),
        DetailFact("Wind", period.wind.isEmpty ? "Unavailable" : period.wind),
      ],
      sections: [
        DetailSection(
          title: "Valid window",
          facts: [
            DetailFact("Starts", date(period.start, zone: report.timeContext.instantZone)),
            DetailFact("Ends", date(period.end, zone: report.timeContext.instantZone)),
          ], paragraphs: [period.detail])
      ], source: source(report),
      diagnostics:
        "\(period.name)\n\(period.detail)\nTemperature statistic: \(period.temperatureStatistic.rawValue)\nStored temperature (°C): \(period.temperature.map(String.init(describing:)) ?? "Unavailable")\nTemperature trend: \(period.temperatureTrend ?? "Not supplied")\nSource: \(source(report))\nFetched: \(report.fetched.formatted())\n\(report.timeContext.description)"
    )
  }
  static func alert(_ alert: WeatherAlert, fetched: Date) -> DetailPresentation {
    let zone = TimeZone(secondsFromGMT: 0)!
    return DetailPresentation(
      title: alert.event, subtitle: alert.headline, symbol: "exclamationmark.triangle",
      accent: alert.severity == "Extreme" || alert.severity == "Severe"
        ? .systemRed : .systemOrange,
      highlights: [DetailFact("Severity", alert.severity), DetailFact("Urgency", alert.urgency)],
      notices: ["Official alert · " + alert.status + " · " + alert.messageType],
      sections: [
        DetailSection(
          title: "Instructions",
          paragraphs: [
            alert.instructions.isEmpty
              ? "No instructions supplied. Read the official message below." : alert.instructions
          ]),
        DetailSection(title: "Official message", paragraphs: [alert.description]),
        DetailSection(
          title: "Area & authority",
          facts: [
            DetailFact("Area", alert.area), DetailFact("Issuing office", alert.sender),
            DetailFact("Certainty", alert.certainty),
          ]),
        DetailSection(
          title: "Alert timing · UTC",
          facts: [
            DetailFact("Sent", date(alert.sent, zone: zone)),
            DetailFact("Effective", date(alert.effective, zone: zone)),
            DetailFact("Onset", date(alert.onset, zone: zone)),
            DetailFact("Message expires", date(alert.expires, zone: zone)),
            DetailFact("Event ends", date(alert.ends, zone: zone)),
            DetailFact("Fetched", date(fetched, zone: zone)),
          ]),
      ],
      source: "NWS · Public-domain data\n"
        + (alert.source?.absoluteString ?? "https://www.weather.gov/alerts"),
      diagnostics: "Fetched: \(fetched.formatted())\n" + AlertPresentation.message(alert))
  }
  static func alerts(_ report: WeatherAlertReport) -> DetailPresentation {
    var value = DetailPresentation(
      title: "Current alerts at map center",
      subtitle: "\(report.alerts.count) official messages · fetched "
        + date(report.fetched, zone: TimeZone(secondsFromGMT: 0)!),
      symbol: "exclamationmark.triangle", accent: .systemOrange,
      notices: [
        "These messages apply to the queried point, not the entire map. Alert validity is independent of the selected radar or forecast frame."
      ], source: "NWS · Public-domain data", diagnostics: AlertPresentation.text(report))
    if report.moreAvailable {
      value.notices.append("Additional results exist · showing at most 100 messages")
    }
    if report.alerts.isEmpty {
      value.sections = [
        DetailSection(
          title: "No active point messages returned",
          paragraphs: [
            "This does not establish the absence of hazards elsewhere in the map extent."
          ])
      ]
    }
    for alert in report.alerts {
      value.sections.append(
        DetailSection(
          title: alert.event + " · " + alert.severity,
          facts: [
            DetailFact("Urgency", alert.urgency), DetailFact("Area", alert.area),
            DetailFact("Sent", date(alert.sent, zone: TimeZone(secondsFromGMT: 0)!)),
            DetailFact("Effective", date(alert.effective, zone: TimeZone(secondsFromGMT: 0)!)),
            DetailFact("Onset", date(alert.onset, zone: TimeZone(secondsFromGMT: 0)!)),
            DetailFact("Message expires", date(alert.expires, zone: TimeZone(secondsFromGMT: 0)!)),
            DetailFact("Event ends", date(alert.ends, zone: TimeZone(secondsFromGMT: 0)!)),
          ],
          paragraphs: [alert.headline, alert.instructions, alert.description]))
    }
    return value
  }
}
