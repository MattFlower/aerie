import Foundation

public struct WeatherHour: Equatable {
  public var date: Date
  public var temperature: Double?
  public var precipitation: Double?
  public var code: Int
  public var condition: String?
  public var end: Date?
  public var precedingHourAggregates: Bool
  public var apparent, humidity, dewpoint, wind, gusts, direction, pressure, cloud, amount, uv,
    visibility: Double?
  public var windDescription, gustDescription, detail: String?
  public init(
    date: Date, temperature: Double?, precipitation: Double?, code: Int, condition: String? = nil,
    end: Date? = nil, precedingHourAggregates: Bool = false, apparent: Double? = nil,
    humidity: Double? = nil, dewpoint: Double? = nil,
    wind: Double? = nil, gusts: Double? = nil, direction: Double? = nil, pressure: Double? = nil,
    cloud: Double? = nil, amount: Double? = nil, uv: Double? = nil, visibility: Double? = nil,
    windDescription: String? = nil, gustDescription: String? = nil, detail: String? = nil
  ) {
    self.date = date
    self.temperature = temperature
    self.precipitation = precipitation
    self.code = code
    self.condition = condition; self.end = end;
    self.precedingHourAggregates = precedingHourAggregates; self.apparent = apparent;
    self.humidity = humidity
    self.dewpoint = dewpoint; self.wind = wind; self.gusts = gusts; self.direction = direction
    self.pressure = pressure; self.cloud = cloud; self.amount = amount; self.uv = uv;
    self.visibility = visibility
    self.windDescription = windDescription; self.gustDescription = gustDescription;
    self.detail = detail
  }
}
public struct WeatherDay: Equatable {
  public var date: Date
  public var low: Double
  public var high: Double
  public var code: Int
  public var sunrise: Date?
  public var sunset: Date?
  public var uv: Double?
  public var precipitation: Double?
}
/// Unix timestamps are instants; daily boundaries retain the provider's response offset.
public struct WeatherTimeContext: Equatable {
  public let identifier: String?
  public let offsetSeconds: Int?
  public init(identifier: String?, offsetSeconds: Int?) {
    self.identifier = identifier.flatMap {
      $0.utf8.count <= 128 && TimeZone(identifier: $0) != nil ? $0 : nil
    }
    self.offsetSeconds = offsetSeconds.flatMap { (-64800...64800).contains($0) ? $0 : nil }
  }
  public var instantZone: TimeZone {
    identifier.flatMap(TimeZone.init(identifier:))
      ?? offsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? TimeZone(secondsFromGMT: 0)!
  }
  public var dailyZone: TimeZone {
    offsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? instantZone
  }
  public var description: String {
    if let identifier {
      return "Forecast times in \(identifier). Daily dates follow the provider's forecast days."
    }
    if let offsetSeconds {
      let minutes = abs(offsetSeconds) / 60
      let offset = String(
        format: "UTC%@%02d:%02d", offsetSeconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
      return "Forecast times use \(offset). Daylight saving adjustments unavailable."
    }
    return "Forecast timezone unavailable; times shown in UTC."
  }
}
public struct WeatherReport {
  public var source: String
  public var attributionURL: String
  public var fetched: Date
  public var timeContext: WeatherTimeContext
  public var temperature: Double?
  public var apparent: Double?
  public var humidity: Double?
  public var wind: Double?
  public var gusts: Double?
  public var direction: Double?
  public var pressure: Double?
  public var cloud: Double?
  public var code: Int?
  public var hours: [WeatherHour]
  public var days: [WeatherDay]
  public var alerts: [String]
  public var condition: String? = nil
  public var observationTime: Date? = nil
  public var observationStation: String? = nil
  public var forecastUpdated: Date? = nil
  public var periods: [WeatherPeriod] = []
  public var alertReport: WeatherAlertReport? = nil
  public var notes: [String] = []
}
public enum WeatherError: Error {
  case invalidConfiguration, invalidResponse
  case http(Int)
  case payloadTooLarge
}
public protocol WeatherProvider {
  func fetch(configuration: WeatherConfiguration) async throws -> WeatherReport
}
public enum WeatherCondition {
  public static func describe(_ code: Int?) -> String {
    switch code {
    case 0: return "Clear"
    case 1: return "Mostly clear"
    case 2: return "Partly cloudy"
    case 3: return "Overcast"
    case 45, 48: return "Fog"
    case 51, 53, 55, 56, 57: return "Drizzle"
    case 61, 63, 65, 66, 67: return "Rain"
    case 71, 73, 75, 77: return "Snow"
    case 80, 81, 82: return "Rain showers"
    case 85, 86: return "Snow showers"
    case 95, 96, 99: return "Thunderstorms"
    default: return "Conditions unavailable"
    }
  }
}

public struct OpenMeteoProvider: WeatherProvider {
  public init() {}
  public static func requestURL(_ configuration: WeatherConfiguration) throws -> URL {
    guard configuration.valid, configuration.provider == "openMeteo" else {
      throw WeatherError.invalidConfiguration
    }
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
      URLQueryItem(
        name: "latitude",
        value: String(
          format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), configuration.latitude)),
      URLQueryItem(
        name: "longitude",
        value: String(
          format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), configuration.longitude)),
      URLQueryItem(
        name: "current",
        value:
          "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,cloud_cover,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
      ),
      URLQueryItem(
        name: "hourly",
        value:
          "temperature_2m,precipitation_probability,weather_code,apparent_temperature,relative_humidity_2m,dew_point_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,surface_pressure,cloud_cover,precipitation,uv_index,visibility"
      ),
      URLQueryItem(
        name: "daily",
        value:
          "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max"
      ),
      URLQueryItem(name: "temperature_unit", value: "celsius"),
      URLQueryItem(name: "wind_speed_unit", value: "kmh"),
      URLQueryItem(name: "precipitation_unit", value: "mm"),
      URLQueryItem(name: "forecast_days", value: "7"),
      URLQueryItem(name: "timeformat", value: "unixtime"),
      URLQueryItem(name: "timezone", value: "auto"),
    ]
    return components.url!
  }
  public func fetch(configuration: WeatherConfiguration) async throws -> WeatherReport {
    let url = try Self.requestURL(configuration)
    let client = ForecastHTTPClient(service: .openMeteo)
    defer { client.close() }
    return try Self.decode(await client.data(url))
  }
  public static func decode(_ data: Data, fetched: Date = Date()) throws -> WeatherReport {
    guard data.count <= ForecastHTTPClient.maximumBytes else { throw WeatherError.payloadTooLarge }
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    let c = payload.current
    guard let temperature = c.temperature_2m, temperature.isFinite else {
      throw WeatherError.invalidResponse
    }
    var hours: [WeatherHour] = []
    if let h = payload.hourly {
      guard h.time.count <= 384, h.time.count == h.temperature_2m.count,
        h.time.count == h.weather_code.count
      else {
        throw WeatherError.invalidResponse
      }
      for i in h.time.indices {
        guard h.time[i].isFinite, (-62135596800...253402300799).contains(h.time[i]) else {
          throw WeatherError.invalidResponse
        }
        func value(_ array: [Double?]?, range: ClosedRange<Double>? = nil) -> Double? {
          guard let array, i < array.count, let n = array[i], n.isFinite, range?.contains(n) ?? true
          else { return nil }
          return n
        }
        hours.append(
          WeatherHour(
            date: Date(timeIntervalSince1970: h.time[i]), temperature: value(h.temperature_2m),
            precipitation: value(h.precipitation_probability, range: 0...100),
            code: h.weather_code[i] ?? -1,
            precedingHourAggregates: true, apparent: value(h.apparent_temperature),
            humidity: value(h.relative_humidity_2m, range: 0...100),
            dewpoint: value(h.dew_point_2m), wind: value(h.wind_speed_10m, range: 0...1e12),
            gusts: value(h.wind_gusts_10m, range: 0...1e12),
            direction: value(h.wind_direction_10m, range: 0...360),
            pressure: value(h.surface_pressure, range: Double.leastNonzeroMagnitude...1e12),
            cloud: value(h.cloud_cover, range: 0...100),
            amount: value(h.precipitation, range: 0...1e12),
            uv: value(h.uv_index, range: 0...1e12), visibility: value(h.visibility, range: 0...1e12)
          ))
      }
    }
    var days: [WeatherDay] = []
    if let d = payload.daily {
      guard d.time.count == d.temperature_2m_min.count, d.time.count == d.temperature_2m_max.count,
        d.time.count == d.weather_code.count
      else { throw WeatherError.invalidResponse }
      for i in d.time.indices {
        guard let low = d.temperature_2m_min[i], let high = d.temperature_2m_max[i] else {
          continue
        }
        func value(_ array: [Double?]?) -> Double? { array.flatMap { i < $0.count ? $0[i] : nil } }
        days.append(
          WeatherDay(
            date: Date(timeIntervalSince1970: d.time[i]), low: low, high: high,
            code: d.weather_code[i] ?? -1,
            sunrise: value(d.sunrise).map(Date.init(timeIntervalSince1970:)),
            sunset: value(d.sunset).map(Date.init(timeIntervalSince1970:)),
            uv: value(d.uv_index_max),
            precipitation: value(d.precipitation_probability_max)))
      }
    }
    return WeatherReport(
      source: "Open-Meteo", attributionURL: "https://open-meteo.com/", fetched: fetched,
      timeContext: WeatherTimeContext(
        identifier: payload.timezone, offsetSeconds: payload.utc_offset_seconds),
      temperature: temperature, apparent: c.apparent_temperature, humidity: c.relative_humidity_2m,
      wind: c.wind_speed_10m, gusts: c.wind_gusts_10m, direction: c.wind_direction_10m,
      pressure: c.surface_pressure, cloud: c.cloud_cover, code: c.weather_code,
      hours: hours, days: days, alerts: [])
  }
  private struct Payload: Decodable {
    var timezone: String?
    var utc_offset_seconds: Int?
    var current: Current
    var hourly: Hourly?
    var daily: Daily?
  }
  private struct Current: Decodable {
    var temperature_2m: Double?
    var apparent_temperature: Double?
    var relative_humidity_2m: Double?
    var wind_speed_10m: Double?
    var wind_gusts_10m: Double?
    var wind_direction_10m: Double?
    var surface_pressure: Double?
    var cloud_cover: Double?
    var weather_code: Int?
  }
  private struct Hourly: Decodable {
    var time: [Double]
    var temperature_2m: [Double?]
    var precipitation_probability: [Double?]?
    var weather_code: [Int?]
    var apparent_temperature, relative_humidity_2m, dew_point_2m, wind_speed_10m, wind_gusts_10m,
      wind_direction_10m, surface_pressure, cloud_cover, precipitation, uv_index,
      visibility: [Double?]?
  }
  private struct Daily: Decodable {
    var time: [Double]
    var temperature_2m_min: [Double?]
    var temperature_2m_max: [Double?]
    var weather_code: [Int?]
    var sunrise: [Double?]?
    var sunset: [Double?]?
    var uv_index_max: [Double?]?
    var precipitation_probability_max: [Double?]?
  }
}

public enum Astronomy {
  /// Approximate synodic lunar age; informational, not an astronomical ephemeris.
  public static func moonAge(at date: Date) -> Double {
    let days = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451550.1
    return (days.truncatingRemainder(dividingBy: 29.530588853) + 29.530588853).truncatingRemainder(
      dividingBy: 29.530588853)
  }
  public static func moonName(at date: Date) -> String {
    let phase = moonAge(at: date) / 29.530588853
    let names = [
      "New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon",
      "Waning gibbous", "Last quarter", "Waning crescent",
    ]
    return names[Int((phase * 8).rounded()) % 8]
  }
}
