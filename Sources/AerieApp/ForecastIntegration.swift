import AerieCore
import Foundation

enum ForecastIntegration {
  /// Public documentation example rounded to the same precision as manual settings.
  static func run() async -> Int32 {
    var configuration = WeatherConfiguration()
    configuration.enabled = true; configuration.provider = "nws"
    configuration.name = "Public development fixture"; configuration.latitude = 39.75;
    configuration.longitude = -97.09
    do {
      let report = try await NWSProvider().fetch(configuration: configuration)
      let output: [String: Any] = [
        "scenario": "fixed public development point; no user defaults/location/UI",
        "source": report.source, "hours": report.hours.count, "periods": report.periods.count,
        "observationAvailable": report.observationTime != nil,
        "temperatureAvailable": report.temperature != nil,
        "timezoneAvailable": report.timeContext.identifier != nil,
        "alertCollectionAvailable": report.alertReport != nil,
        "alerts": report.alertReport?.alerts.count ?? 0, "notes": report.notes,
      ]
      let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
      print(String(decoding: data, as: UTF8.self))
      return report.hours.isEmpty && report.periods.isEmpty ? 1 : 0
    } catch { print("NWS fixed development fixture unavailable: \(error)"); return 1 }
  }
}
