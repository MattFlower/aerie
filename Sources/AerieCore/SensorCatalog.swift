import Foundation

/// Hardware scopes describe native SoC metadata, independently of process architecture.
public enum SensorPlatform: String, CaseIterable {
  case unknown, intel, a18Pro
  case m1, m1Pro, m1Max, m1Ultra, m2, m2Pro, m2Max, m2Ultra, m3, m3Pro, m3Max, m3Ultra, m4, m4Pro,
    m4Max, m5, m5Pro, m5Max, m5Ultra, m6, m6Pro, m6Max
  public static var known: [SensorPlatform] { allCases.filter { $0 != .unknown } }
  public static var apple: [SensorPlatform] { known.filter { $0 != .intel } }
  public static func generation(_ number: Int) -> [SensorPlatform] {
    apple.filter { $0.rawValue.hasPrefix("m" + String(number)) }
  }
  public static func detect(
    cpuBrand: String, nativeGPUModels: [String] = [], nativeARM: Bool? = nil
  ) -> SensorPlatform {
    // Prefer native registry SoC names to an emulated/translated process's CPU description.
    for text in nativeGPUModels + [cpuBrand] {
      let words = text.split(separator: " ").map(String.init)
      guard words.first == "Apple", words.count >= 2 else { continue }
      let family = words[1].lowercased()
      let suffix =
        words.dropFirst(2).first.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        ?? ""
      if let platform = SensorPlatform(rawValue: family + suffix), platform != .unknown {
        return platform
      }
      if let platform = SensorPlatform(rawValue: family), words.count == 2 { return platform }
    }
    return nativeARM != true && cpuBrand.contains("Intel") ? .intel : .unknown
  }
}

/// Community catalog data adapted under MIT; see THIRD_PARTY_NOTICES.md.
/// Exact-case SMC keys, kind and platform must agree; no component prefix guesses.
public enum SensorCatalog {
  public static let sourceRevision = "0c0e551e199938a92af963c25a15a3ca1aef7764"
  private struct Entry {
    let key, name, unit: String
    let platforms: [SensorPlatform]
  }
  public static func name(
    key: String, unit: String, platform: SensorPlatform, namespace: String = "smc"
  ) -> String? {
    guard namespace == "smc", platform != .unknown, SensorIdentity.validKey(key) else { return nil }
    let exact = entries.filter {
      $0.key == key && $0.unit == unit && $0.platforms.contains(platform)
    }
    if !exact.isEmpty { return resolve(exact) }
    // Only catalog-declared decimal wildcard slots are eligible, with the key's own suffix.
    let candidates = entries.filter { entry in
      guard entry.unit == unit, entry.platforms.contains(platform),
        let position = entry.key.firstIndex(of: "%")
      else { return false }
      let offset = entry.key.distance(from: entry.key.startIndex, to: position)
      let bytes = Array(key.utf8); guard (48...57).contains(bytes[offset]) else { return false }
      return entry.key.replacingOccurrences(of: "%", with: String(UnicodeScalar(bytes[offset])))
        == key
    }
    guard let name = resolve(candidates), let entry = candidates.first,
      let position = entry.key.firstIndex(of: "%")
    else { return nil }
    let offset = entry.key.distance(from: entry.key.startIndex, to: position)
    return name.replacingOccurrences(of: "%", with: String(UnicodeScalar(Array(key.utf8)[offset])))
  }
  private static func resolve(_ candidates: [Entry]) -> String? {
    guard let count = candidates.map({ $0.platforms.count }).min() else { return nil }
    let names = Set(candidates.filter { $0.platforms.count == count }.map(\.name))
    return names.count == 1 ? names.first : nil
  }
  public static func fallback(key: String, unit: String) -> String {
    let kind =
      ["°C": "Temperature", "rpm": "Fan speed", "W": "Power", "V": "Voltage", "A": "Current"][unit]
      ?? "Hardware"
    return kind + " sensor"
  }
  private static let entries: [Entry] = [
    Entry(key: "TA%P", name: "Ambient %", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "Th%H", name: "Heatpipe %", unit: "°C", platforms: [.intel]),
    Entry(key: "TZ%C", name: "Thermal zone %", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TC0D", name: "CPU diode", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TC0E", name: "CPU diode virtual", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TC0F", name: "CPU diode filtered", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TC0H", name: "CPU heatsink", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TC0P", name: "CPU proximity", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TCAD", name: "CPU package", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TCAC", name: "CPU A core die", unit: "°C", platforms: [.intel]),
    Entry(key: "TCBC", name: "CPU B core die", unit: "°C", platforms: [.intel]),
    Entry(key: "TCAH", name: "CPU A heatsink", unit: "°C", platforms: [.intel]),
    Entry(key: "TCBH", name: "CPU B heatsink", unit: "°C", platforms: [.intel]),
    Entry(key: "TC%c", name: "CPU sensor %", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TC%C", name: "CPU sensor %", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TCGC", name: "GPU Intel Graphics", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TG0D", name: "GPU diode", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TGDD", name: "GPU AMD Radeon", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TG0H", name: "GPU heatsink", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TG0P", name: "GPU proximity", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "Tm0P", name: "Mainboard", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "Tp0P", name: "Powerboard", unit: "°C", platforms: [.intel]),
    Entry(key: "TB1T", name: "Battery", unit: "°C", platforms: [.intel]),
    Entry(key: "TW0P", name: "Airport", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TL0P", name: "Display", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TI%P", name: "Thunderbolt %", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TH%A", name: "Disk % (A)", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TH%B", name: "Disk % (B)", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TH%C", name: "Disk % (C)", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TTLD", name: "Thunderbolt left", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TTRD", name: "Thunderbolt right", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TN0D", name: "Northbridge diode", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TN0H", name: "Northbridge heatsink", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TN0P", name: "Northbridge proximity", unit: "°C", platforms: SensorPlatform.known),
    Entry(key: "TMA1", name: "Memory riser A slot 1", unit: "°C", platforms: [.intel]),
    Entry(key: "TMA2", name: "Memory riser A slot 2", unit: "°C", platforms: [.intel]),
    Entry(key: "TMA3", name: "Memory riser A slot 3", unit: "°C", platforms: [.intel]),
    Entry(key: "TMA4", name: "Memory riser A slot 4", unit: "°C", platforms: [.intel]),
    Entry(key: "TMB1", name: "Memory riser B slot 1", unit: "°C", platforms: [.intel]),
    Entry(key: "TMB2", name: "Memory riser B slot 2", unit: "°C", platforms: [.intel]),
    Entry(key: "TMB3", name: "Memory riser B slot 3", unit: "°C", platforms: [.intel]),
    Entry(key: "TMB4", name: "Memory riser B slot 4", unit: "°C", platforms: [.intel]),
    Entry(
      key: "Tp09", name: "CPU efficiency sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0T", name: "CPU efficiency sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp01", name: "CPU performance sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp05", name: "CPU performance sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0D", name: "CPU performance sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0H", name: "CPU performance sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0L", name: "CPU performance sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0P", name: "CPU performance sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0X", name: "CPU performance sensor 7", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp0b", name: "CPU performance sensor 8", unit: "°C",
      platforms: SensorPlatform.generation(1)),
    Entry(key: "Tg05", name: "GPU sensor 1", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tg0D", name: "GPU sensor 2", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tg0L", name: "GPU sensor 3", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tg0T", name: "GPU sensor 4", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tm02", name: "Memory 1", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tm06", name: "Memory 2", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tm08", name: "Memory 3", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(key: "Tm09", name: "Memory 4", unit: "°C", platforms: SensorPlatform.generation(1)),
    Entry(
      key: "Tp1h", name: "CPU efficiency sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp1t", name: "CPU efficiency sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp1p", name: "CPU efficiency sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp1l", name: "CPU efficiency sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp01", name: "CPU performance sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp05", name: "CPU performance sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp09", name: "CPU performance sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp0D", name: "CPU performance sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp0X", name: "CPU performance sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp0b", name: "CPU performance sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp0f", name: "CPU performance sensor 7", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Tp0j", name: "CPU performance sensor 8", unit: "°C",
      platforms: SensorPlatform.generation(2)),
    Entry(key: "Tg0f", name: "GPU sensor 1", unit: "°C", platforms: SensorPlatform.generation(2)),
    Entry(key: "Tg0j", name: "GPU sensor 2", unit: "°C", platforms: SensorPlatform.generation(2)),
    Entry(
      key: "Te05", name: "CPU efficiency sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Te0L", name: "CPU efficiency sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Te0P", name: "CPU efficiency sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Te0S", name: "CPU efficiency sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf04", name: "CPU performance sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf09", name: "CPU performance sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf0A", name: "CPU performance sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf0B", name: "CPU performance sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf0D", name: "CPU performance sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf0E", name: "CPU performance sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf44", name: "CPU performance sensor 7", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf49", name: "CPU performance sensor 8", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf4A", name: "CPU performance sensor 9", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf4B", name: "CPU performance sensor 10", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf4D", name: "CPU performance sensor 11", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Tf4E", name: "CPU performance sensor 12", unit: "°C",
      platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf14", name: "GPU sensor 1", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf18", name: "GPU sensor 2", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf19", name: "GPU sensor 3", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf1A", name: "GPU sensor 4", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf24", name: "GPU sensor 5", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf28", name: "GPU sensor 6", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf29", name: "GPU sensor 7", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(key: "Tf2A", name: "GPU sensor 8", unit: "°C", platforms: SensorPlatform.generation(3)),
    Entry(
      key: "Te05", name: "CPU efficiency sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Te0S", name: "CPU efficiency sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Te09", name: "CPU efficiency sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Te0H", name: "CPU efficiency sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp01", name: "CPU performance sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp05", name: "CPU performance sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp09", name: "CPU performance sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp0D", name: "CPU performance sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp0V", name: "CPU performance sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp0Y", name: "CPU performance sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp0b", name: "CPU performance sensor 7", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp0e", name: "CPU performance sensor 8", unit: "°C",
      platforms: SensorPlatform.generation(4)),
    Entry(key: "Tg0G", name: "GPU sensor 1", unit: "°C", platforms: [.m4]),
    Entry(key: "Tg0H", name: "GPU sensor 2", unit: "°C", platforms: [.m4]),
    Entry(key: "Tg1U", name: "GPU sensor 1", unit: "°C", platforms: [.m4Pro, .m4Max]),
    Entry(key: "Tg1k", name: "GPU sensor 2", unit: "°C", platforms: [.m4Pro, .m4Max]),
    Entry(key: "Tg0K", name: "GPU sensor 3", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(key: "Tg0L", name: "GPU sensor 4", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(key: "Tg0d", name: "GPU sensor 5", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(key: "Tg0e", name: "GPU sensor 6", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(key: "Tg0j", name: "GPU sensor 7", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(key: "Tg0k", name: "GPU sensor 8", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tm0p", name: "Memory Proximity 1", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tm1p", name: "Memory Proximity 2", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tm2p", name: "Memory Proximity 3", unit: "°C", platforms: SensorPlatform.generation(4)),
    Entry(
      key: "Tp00", name: "CPU super sensor 1", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp04", name: "CPU super sensor 2", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp08", name: "CPU super sensor 3", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0C", name: "CPU super sensor 4", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0G", name: "CPU super sensor 5", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0K", name: "CPU super sensor 6", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0O", name: "CPU performance sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0R", name: "CPU performance sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0U", name: "CPU performance sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0X", name: "CPU performance sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0a", name: "CPU performance sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0d", name: "CPU performance sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0g", name: "CPU performance sensor 7", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0j", name: "CPU performance sensor 8", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0m", name: "CPU performance sensor 9", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0p", name: "CPU performance sensor 10", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0u", name: "CPU performance sensor 11", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0y", name: "CPU performance sensor 12", unit: "°C",
      platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg0U", name: "GPU sensor 1", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg0X", name: "GPU sensor 2", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg0d", name: "GPU sensor 3", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg0g", name: "GPU sensor 4", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg0j", name: "GPU sensor 5", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg1Y", name: "GPU sensor 6", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg1c", name: "GPU sensor 7", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(key: "Tg1g", name: "GPU sensor 8", unit: "°C", platforms: SensorPlatform.generation(5)),
    Entry(
      key: "Tp0j", name: "CPU super sensor 1", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0g", name: "CPU super sensor 2", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp09", name: "CPU super sensor 3", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp07", name: "CPU super sensor 4", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0m", name: "CPU performance sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0L", name: "CPU performance sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0I", name: "CPU performance sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0d", name: "CPU performance sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0E", name: "CPU performance sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0G", name: "CPU performance sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp0b", name: "CPU performance sensor 7", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Tp05", name: "CPU performance sensor 8", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Te07", name: "CPU efficiency sensor 1", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Te08", name: "CPU efficiency sensor 2", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Te09", name: "CPU efficiency sensor 3", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Te0c", name: "CPU efficiency sensor 4", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Te0h", name: "CPU efficiency sensor 5", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(
      key: "Te0i", name: "CPU efficiency sensor 6", unit: "°C",
      platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg1e", name: "GPU sensor 1", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg0d", name: "GPU sensor 2", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg0c", name: "GPU sensor 3", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg0b", name: "GPU sensor 4", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg1c", name: "GPU sensor 5", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg1d", name: "GPU sensor 6", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg07", name: "GPU sensor 7", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg1f", name: "GPU sensor 8", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg09", name: "GPU sensor 9", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg0a", name: "GPU sensor 10", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg1g", name: "GPU sensor 11", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Tg1h", name: "GPU sensor 12", unit: "°C", platforms: SensorPlatform.generation(6)),
    Entry(key: "Te05", name: "CPU efficiency sensor 1", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Te0S", name: "CPU efficiency sensor 2", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Tp05", name: "CPU performance sensor 1", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Tp0D", name: "CPU performance sensor 2", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Tg05", name: "GPU sensor 1", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Tg0D", name: "GPU sensor 2", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Tg0L", name: "GPU sensor 3", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "Tg0e", name: "GPU sensor 4", unit: "°C", platforms: [.a18Pro]),
    Entry(key: "TaLP", name: "Airflow left", unit: "°C", platforms: SensorPlatform.apple),
    Entry(key: "TaRF", name: "Airflow right", unit: "°C", platforms: SensorPlatform.apple),
    Entry(key: "TH0x", name: "NAND", unit: "°C", platforms: SensorPlatform.apple),
    Entry(key: "TB1T", name: "Battery 1", unit: "°C", platforms: SensorPlatform.apple),
    Entry(key: "TB2T", name: "Battery 2", unit: "°C", platforms: SensorPlatform.apple),
    Entry(key: "TW0P", name: "Airport", unit: "°C", platforms: SensorPlatform.apple),
    Entry(key: "VCAC", name: "CPU IA", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VCSC", name: "CPU System Agent", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VC%C", name: "CPU sensor %", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VCTC", name: "GPU Intel Graphics", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VG0C", name: "GPU", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VM0R", name: "Memory", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "Vb0R", name: "CMOS", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VD0R", name: "DC In", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VP0R", name: "12V rail", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "Vp0C", name: "12V vcc", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VV2S", name: "3V", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VR3R", name: "3.3V", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VV1S", name: "5V", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VV9S", name: "12V", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "VeES", name: "PCI 12V", unit: "V", platforms: SensorPlatform.known),
    Entry(key: "IC0R", name: "CPU High side", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "IG0R", name: "GPU High side", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "ID0R", name: "DC In", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "IBAC", name: "Battery", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "IDBR", name: "Brightness", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "IU1R", name: "Thunderbolt Left", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "IU2R", name: "Thunderbolt Right", unit: "A", platforms: SensorPlatform.known),
    Entry(key: "PC0C", name: "CPU sensor", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCAB", name: "CPU A core power (PCAB)", unit: "W", platforms: [.intel]),
    Entry(key: "PCAC", name: "CPU A core power (PCAC)", unit: "W", platforms: [.intel]),
    Entry(key: "PCBB", name: "CPU B core power (PCBB)", unit: "W", platforms: [.intel]),
    Entry(key: "PCBC", name: "CPU B core power (PCBC)", unit: "W", platforms: [.intel]),
    Entry(key: "PCAM", name: "CPU sensor (IMON)", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCPC", name: "CPU Package", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCTR", name: "CPU Total", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCPT", name: "CPU Package total", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCPR", name: "CPU Package total (SMC)", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PC0R", name: "CPU Computing high side", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PC0G", name: "CPU GFX", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCEC", name: "CPU VccEDRAM", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCPG", name: "GPU Intel Graphics", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PG0C", name: "GPU", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PG0R", name: "GPU sensor 1", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PG1R", name: "GPU sensor 2", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCGC", name: "Intel GPU", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PCGM", name: "Intel GPU (IMON)", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PC3C", name: "RAM", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PPBR", name: "Battery", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PDTR", name: "DC In", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PMTR", name: "Memory Total", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PSTR", name: "System Total", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PN0C", name: "Northbridge", unit: "W", platforms: [.intel]),
    Entry(key: "PU1R", name: "Thunderbolt Left", unit: "W", platforms: SensorPlatform.known),
    Entry(key: "PU2R", name: "Thunderbolt Right", unit: "W", platforms: SensorPlatform.known),
    Entry(
      key: "PDBR", name: "Power Delivery Brightness", unit: "W",
      platforms: SensorPlatform.generation(1) + SensorPlatform.generation(4)),
    Entry(
      key: "PBwo", name: "Display Backlight", unit: "W",
      platforms: SensorPlatform.generation(5) + [.a18Pro]),
  ]
}
