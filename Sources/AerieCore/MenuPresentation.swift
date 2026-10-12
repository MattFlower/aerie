import Foundation

/// Bounded columns keep units and explicit overflow honest while geometry stays fixed.
public struct CompactNetworkColumn: Equatable {
  public let number: String, unit: String
  public init(_ line: String) {
    let source = line.hasPrefix("↓") || line.hasPrefix("↑") ? String(line.dropFirst()) : line
    let parts = source.split(whereSeparator: \.isWhitespace).map(String.init)
    guard parts.count == 2, let value = Double(parts[0]), value.isFinite, value >= 0 else {
      number =
        ["—", "Unavailable", "Paused", ""].contains(source.trimmingCharacters(in: .whitespaces))
        ? "—" : "…"
      unit = ""; return
    }
    let allowed = [
      "B/s", "KB/s", "MB/s", "GB/s", "TB/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s", "bit/s", "Kbit/s",
      "Mbit/s", "Gbit/s", "Tbit/s",
    ]
    guard allowed.contains(parts[1]) else { number = "…"; unit = ""; return }
    unit = parts[1].replacingOccurrences(of: "bit", with: "b")
    number =
      value >= 1000
      ? ">999"
      : parts[0].count <= 5 ? parts[0] : String(format: value >= 100 ? "%.0f" : "%.1f", value)
  }
}

public enum MenuColor {
  public static func rgb(_ value: String?) -> UInt32? {
    guard let value, value.utf8.count == 7, value.first == "#",
      value.dropFirst().utf8.allSatisfy({
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      })
    else { return nil }
    return UInt32(value.dropFirst(), radix: 16)
  }
  public static func valid(_ value: String?) -> Bool { value == nil || rgb(value) != nil }
}
public struct MenuValue: Equatable {
  public let full, compact, secondary, stackedPrimary: String
  public static func network(download: String, upload: String) -> MenuValue {
    MenuValue(
      full: "Download " + download + ", upload " + upload,
      compact: "↓" + download + " ↑" + upload,
      secondary: "↑" + upload, stackedPrimary: "↓" + download)
  }
  public init(
    full: String, compact: String? = nil, secondary: String = "", stackedPrimary: String? = nil
  ) {
    self.full = String(full.prefix(256)); self.compact = String((compact ?? full).prefix(256))
    self.secondary = String(secondary.prefix(256))
    self.stackedPrimary = String((stackedPrimary ?? full).prefix(256))
  }
}
public enum MenuPresentation {
  public static func modules(fromTitles text: String) throws -> [Module] {
    guard text.utf8.count <= 1024 else { throw SettingsError.invalid }
    let result = try text.split(separator: ",", omittingEmptySubsequences: false).map { title in
      let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        let module = Module.allCases.first(where: {
          $0.title.caseInsensitiveCompare(name) == .orderedSame
        }), module != .overview
      else { throw SettingsError.invalid }; return module
    }
    guard (1...6).contains(result.count), Set(result).count == result.count else {
      throw SettingsError.invalid
    }
    return result
  }

  public static func combined(_ values: [MenuValue], compact: Bool) -> String {
    values.prefix(6).map { compact ? $0.compact : $0.full }.joined(separator: " · ")
  }
  public static func stacked(_ values: [MenuValue]) -> (String, String) {
    guard !values.isEmpty else { return ("Aerie", "Unavailable") }
    if values.count == 1 { return (values[0].stackedPrimary, values[0].secondary) }
    let split = (min(values.count, 6) + 1) / 2
    return (
      combined(Array(values.prefix(split)), compact: false),
      combined(Array(values.prefix(6).dropFirst(split)), compact: false)
    )
  }
}
