import Foundation

/// Sensor identities remain firmware keys; a local alias never changes their meaning.
public enum SensorIdentity {
  public static let units = ["°C", "rpm", "W", "V", "A"]
  public static func validKey(_ key: String) -> Bool {
    let bytes = Array(key.utf8)
    return bytes.count == 4 && bytes.allSatisfy { (32...126).contains($0) }
      && bytes.contains { $0 != 32 }
  }
  public static func key(metric: String) -> String? {
    guard metric.hasPrefix("sensor:") else { return nil }
    let key = String(metric.dropFirst(7))
    return validKey(key) ? key : nil
  }
  public static func valid(names: [String: String]?) -> Bool {
    guard let names else { return true }
    return names.count <= 1024
      && names.allSatisfy { key, value in
        validKey(key) && !value.isEmpty && value.utf8.count <= 64
          && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
          && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
      }
  }
  public static func requiredKeys(rules: [ThresholdRule]) -> Set<String> {
    Set(rules.filter { $0.enabled && $0.valid }.compactMap { key(metric: $0.metric) })
  }
  /// Four literal key characters precede a separator, preserving keys containing spaces.
  public static func parseNames(_ text: String) throws -> [String: String]? {
    guard text.utf8.count <= 131_072 else { throw SettingsError.invalid }
    var names: [String: String] = [:]
    for line in text.components(separatedBy: .newlines) {
      if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
      let key = String(line.prefix(4))
      let remainder = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
      guard validKey(key), remainder.hasPrefix("|"), names[key] == nil else {
        throw SettingsError.invalid
      }
      names[key] = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
      guard names.count <= 1024 else { throw SettingsError.invalid }
    }
    guard valid(names: names) else { throw SettingsError.invalid }
    return names.isEmpty ? nil : names
  }
}
