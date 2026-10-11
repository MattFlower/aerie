import Foundation

public enum SettingsProfileError: Error, Equatable {
  case invalid, unsupportedVersion(Int)
}

/// A validated, local configuration draft. Creating or reviewing one performs no side effects.
public struct SettingsProfile {
  public enum Kind: Equatable { case imported, defaults }
  public static let maximumBytes = 1_000_000
  public let kind: Kind
  public let settings: Settings

  private init(kind: Kind, settings: Settings) {
    self.kind = kind; self.settings = settings
  }

  public static func imported(_ data: Data, preservingHistory: Bool) throws -> SettingsProfile {
    guard !data.isEmpty, data.count <= maximumBytes else { throw SettingsProfileError.invalid }
    struct Header: Decodable { let schema: Int }
    let decoder = JSONDecoder()
    let version: Int
    do { version = try decoder.decode(Header.self, from: data).schema } catch {
      throw SettingsProfileError.invalid
    }
    guard version == 1 else { throw SettingsProfileError.unsupportedVersion(version) }
    do {
      var value = try decoder.decode(Settings.self, from: data)
      // A file cannot opt into external sources, local event selection, or archival retention.
      value.weather = WeatherConfiguration(); value.publicAddress = nil
      value.daylight = nil; value.eventCalendars = []
      value.persistentHistory = preservingHistory
      return SettingsProfile(kind: .imported, settings: try value.validated())
    } catch { throw SettingsProfileError.invalid }
  }

  public static func defaults(preservingHistory: Bool) -> SettingsProfile {
    var value = Settings()
    value.eventCalendars = []; value.persistentHistory = preservingHistory
    return SettingsProfile(kind: .defaults, settings: value)
  }

  public static func exported(_ settings: Settings) throws -> Data {
    var value = try settings.validated()
    value.weather = WeatherConfiguration(); value.eventCalendars = nil
    value.daylight = nil; value.publicAddress = nil; value.persistentHistory = nil
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard data.count <= maximumBytes else { throw SettingsProfileError.invalid }
    return data
  }

  public var title: String {
    kind == .defaults ? "Review default settings" : "Review imported settings"
  }
  public var summary: String {
    "Aerie profile format 1\nSystem interval: \(settings.interval) seconds\nVisible menu items: \(settings.menus.filter(\.visible).count)\nWorld clocks: \(settings.clocks.count)\nThreshold rules: \(settings.rules.count)\nChange rules: \((settings.changeRules ?? []).count)\n\nForecasts, maps, public-IP lookup and offline daylight are off. Event calendars are unselected. Numeric history remains \(settings.effectivePersistentHistory ? "enabled" : "off"); the current archive preference is preserved.\n\nStage these changes to inspect and edit every option. They take effect only when you click Apply. Changing the network selection clears its traffic history. OS permissions and launch-at-login registration require their own controls."
  }
}
