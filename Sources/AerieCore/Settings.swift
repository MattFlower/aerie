import Foundation

public enum Module: String, CaseIterable, Codable {
  case overview, cpu, gpu, memory, storage, network, sensors, power, time, weather
  public var title: String {
    switch self {
    case .overview: return "Overview"
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    case .memory: return "Memory"
    case .storage: return "Storage"
    case .network: return "Network"
    case .sensors: return "Sensors"
    case .power: return "Power"
    case .time: return "Time"
    case .weather: return "Weather"
    }
  }
}
public enum DisplayStyle: String, CaseIterable, Codable { case text, graph, compact }
public enum Theme: String, CaseIterable, Codable { case system, light, dark }
public enum TemperatureUnit: String, Codable { case celsius, fahrenheit }
public struct MenuConfiguration: Codable, Equatable {
  public var module: Module
  public var visible: Bool
  public var style: DisplayStyle
  public init(module: Module, visible: Bool = true, style: DisplayStyle = .text) {
    self.module = module
    self.visible = visible
    self.style = style
  }
}
public struct WorldClock: Codable, Equatable {
  public var name: String
  public var zone: String
  public init(name: String, zone: String) {
    self.name = name
    self.zone = zone
  }
}
public struct WeatherConfiguration: Codable, Equatable {
  public var enabled = false
  public var provider = "openMeteo"
  public var name = ""
  public var latitude = 0.0
  public var longitude = 0.0
  public var mapsEnabled = false
  public var mapsProvider = "noaa"
  public init() {}
  enum CodingKeys: String, CodingKey {
    case enabled, provider, name, latitude, longitude, mapsEnabled, mapsProvider
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "openMeteo"
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
    longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
    mapsEnabled = try c.decodeIfPresent(Bool.self, forKey: .mapsEnabled) ?? false
    mapsProvider = try c.decodeIfPresent(String.self, forKey: .mapsProvider) ?? "noaa"
  }
  public var mapsValid: Bool { hasLocation && mapsEnabled && mapsProvider == "noaa" }
  public var valid: Bool {
    enabled && hasLocation && ["openMeteo", "nws"].contains(provider)
  }
  public var hasLocation: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty && latitude.isFinite
      && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }
}
public struct Settings: Codable, Equatable {
  public var schema = 1
  public var interval = 1.0
  public var processCount = 5
  public var normalizedProcessCPU = true
  public var menus = [
    MenuConfiguration(module: .overview), MenuConfiguration(module: .cpu),
    MenuConfiguration(module: .memory), MenuConfiguration(module: .storage),
    MenuConfiguration(module: .network), MenuConfiguration(module: .sensors),
    MenuConfiguration(module: .power), MenuConfiguration(module: .weather),
    MenuConfiguration(module: .time, visible: false),
    MenuConfiguration(module: .gpu, visible: false),
  ]
  public var combined = false
  public var theme = Theme.system
  public var temperature = TemperatureUnit.celsius
  public var binaryBytes = true
  public var networkBits = false
  public var networkInterfaces: [String]?
  public var networkSelection: NetworkSelection { NetworkSelection(names: networkInterfaces) }
  public var compactSpacing = false
  // Optional for old configurations. Full sampling remains the default until explicitly changed.
  public var sensorSampling: SensorSamplingMode?
  public var effectiveSensorSampling: SensorSamplingMode { sensorSampling ?? .all }
  public var clockFormat = "EEE d MMM HH:mm"
  public var weekStartsMonday = true
  public var showWeekNumbers = true
  public var clocks = [WorldClock(name: "UTC", zone: "Etc/UTC")]
  public var weather = WeatherConfiguration()
  public var rules: [ThresholdRule] = []
  // Optional for decoding configurations saved before change rules existed.
  public var changeRules: [ChangeRule]?
  public init() {}
  public func validated() throws -> Settings {
    guard schema == 1, [0.5, 1, 2, 3, 5].contains(interval), (1...20).contains(processCount),
      networkSelection.valid,
      menus.count <= Module.allCases.count,
      Set(menus.map(\.module)).count == menus.count,
      menus.contains(where: \.visible), clockFormat.count <= 80,
      clocks.count <= 20, clocks.allSatisfy({ TimeZone(identifier: $0.zone) != nil }),
      rules.count <= 50, rules.allSatisfy(\.valid), Set(rules.map(\.id)).count == rules.count,
      (changeRules ?? []).count <= ChangeKind.allCases.count,
      (changeRules ?? []).allSatisfy(\.valid),
      Set((changeRules ?? []).map(\.id)).count == (changeRules ?? []).count,
      Set((changeRules ?? []).map(\.kind)).count == (changeRules ?? []).count,
      !weather.enabled || weather.valid, !weather.mapsEnabled || weather.mapsValid,
      ["openMeteo", "nws"].contains(weather.provider), weather.mapsProvider == "noaa"
    else { throw SettingsError.invalid }
    return self
  }
}
public enum SettingsError: Error { case invalid }

public enum Format {
  public static func bytes(_ value: Double, binary: Bool = true) -> String {
    guard value.isFinite, value >= 0 else { return "Unavailable" }
    let units = binary ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["B", "KB", "MB", "GB", "TB"]
    var n = value
    var i = 0
    while n >= (binary ? 1024 : 1000), i < 4 {
      n /= binary ? 1024 : 1000
      i += 1
    }
    return String(format: n >= 100 || i == 0 ? "%.0f %@" : "%.1f %@", n, units[i])
  }
  public static func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "Unavailable" }
    return String(format: "%.0f%%", value * 100)
  }
  public static func temperature(_ value: Double, unit: TemperatureUnit) -> String {
    String(
      format: "%.1f°%@", unit == .celsius ? value : value * 1.8 + 32,
      unit == .celsius ? "C" : "F")
  }
  public static func duration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "Unavailable" }
    let n = Int(seconds)
    return n >= 86400 ? "\(n / 86400)d \(n % 86400 / 3600)h" : "\(n / 3600)h \(n % 3600 / 60)m"
  }
}
