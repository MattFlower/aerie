import Foundation

/// One clock per line, with the rightmost pipe separating the zone. Quoted names are JSON strings.
public enum WorldClockForm {
  public static let maximumNameBytes = 4096
  public static let maximumZoneBytes = 128
  public static let maximumFormBytes = 524_288
  public static func valid(_ clocks: [WorldClock]) -> Bool {
    clocks.count <= 20
      && clocks.allSatisfy {
        !$0.name.isEmpty && $0.name.count <= 64 && $0.name.utf8.count <= maximumNameBytes
          && $0.zone.utf8.count <= maximumZoneBytes && TimeZone(identifier: $0.zone) != nil
      }
  }
  public static func text(_ clocks: [WorldClock]) throws -> String {
    guard valid(clocks) else { throw SettingsError.invalid }
    let encoder = JSONEncoder()
    return try clocks.map { clock in
      let encoded = try encoder.encode(clock.name)
      var name = String(decoding: encoded, as: UTF8.self)
      // These legal JSON characters are also native-editor line separators.
      for (character, escape) in [
        ("\u{85}", "\\u0085"), ("\u{2028}", "\\u2028"), ("\u{2029}", "\\u2029"),
      ] {
        name = name.replacingOccurrences(of: character, with: escape)
      }
      return name + " | " + clock.zone
    }.joined(separator: "\n")
  }
  public static func parse(_ text: String) throws -> [WorldClock] {
    guard text.utf8.count <= maximumFormBytes else { throw SettingsError.invalid }
    var lines: [Substring] = []
    func append(_ line: Substring) throws {
      guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
      guard lines.count < 20 else { throw SettingsError.invalid }
      lines.append(line)
    }
    var start = text.startIndex
    for index in text.indices where text[index].isNewline {
      try append(text[start..<index]); start = text.index(after: index)
    }
    try append(text[start...])
    let clocks = try lines.map { line -> WorldClock in
      guard let separator = line.lastIndex(of: "|") else { throw SettingsError.invalid }
      let encoded = line[..<separator].trimmingCharacters(in: .whitespaces)
      let zone = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      let name: String
      if encoded.hasPrefix("\"") {
        guard let decoded = try? JSONDecoder().decode(String.self, from: Data(encoded.utf8)) else {
          throw SettingsError.invalid
        }
        name = decoded
      } else {
        name = encoded
      }
      return WorldClock(name: name, zone: zone)
    }
    guard valid(clocks) else { throw SettingsError.invalid }
    return clocks
  }
}
