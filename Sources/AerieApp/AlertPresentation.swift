import AerieCore
import Foundation

enum AlertPresentation {
  static func text(_ report: WeatherAlertReport) -> String {
    let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE d MMM yyyy HH:mm 'UTC'"
    func date(_ value: Date?) -> String { value.map(formatter.string) ?? "Unavailable" }
    var sections = [
      "CURRENT NWS ALERTS AT THE MAP CENTER\nFetched: \(date(report.fetched))\nProvider collection updated: \(date(report.updated))\nThese messages apply to the queried point, not the entire map extent. They describe current alerts independently of any historical radar or future forecast frame."
    ]
    if report.moreAvailable {
      sections.append(
        "More results are available from the provider. This view shows at most 100 messages and does not claim complete results."
      )
    }
    if report.alerts.isEmpty {
      sections.append(
        "NWS returned no active messages for this point at the fetch time. This does not establish the absence of hazards elsewhere in the map extent."
      )
    }
    for alert in report.alerts { sections.append(message(alert, formatter: formatter)) }
    return sections.joined(separator: "\n\n────────────────────────\n\n")
  }
  static func message(_ alert: WeatherAlert) -> String {
    let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE d MMM yyyy HH:mm 'UTC'"
    return message(alert, formatter: formatter)
  }
  private static func message(_ alert: WeatherAlert, formatter: DateFormatter) -> String {
    func date(_ value: Date?) -> String { value.map(formatter.string) ?? "Unavailable" }
    return """
      \(alert.event)
      \(alert.headline)
      Area: \(alert.area)
      Issuing office: \(alert.sender)
      Status: \(alert.status) · Message: \(alert.messageType)
      Severity: \(alert.severity) · Urgency: \(alert.urgency) · Certainty: \(alert.certainty)
      Message sent: \(date(alert.sent))
      Effective: \(date(alert.effective))
      Onset: \(date(alert.onset))
      Message expires: \(date(alert.expires))
      Event ends: \(date(alert.ends))

      \(alert.description)

      Instructions:
      \(alert.instructions)

      Source: \(alert.source?.absoluteString ?? "https://www.weather.gov/alerts")
      """
  }

}
