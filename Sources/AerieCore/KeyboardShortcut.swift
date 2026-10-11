import Foundation

public struct KeyboardShortcut: Codable, Equatable, Hashable {
  /// nil targets Settings; modules retain their own named menu behavior.
  public var module: Module?
  public var key: String
  public var command, control, option, shift: Bool
  public init(
    module: Module?, key: String, command: Bool = true, control: Bool = false, option: Bool = false,
    shift: Bool = false
  ) {
    self.module = module; self.key = key.uppercased(); self.command = command
    self.control = control; self.option = option; self.shift = shift
  }
  public var targetTitle: String { module?.title ?? "Settings" }
  public var combination: String {
    ([
      command ? "Command" : nil, control ? "Control" : nil, option ? "Option" : nil,
      shift ? "Shift" : nil,
    ].compactMap { $0 } + [key == "SPACE" ? "Space" : key]).joined(separator: "+")
  }
  public var valid: Bool {
    guard command || control else { return false }
    if key == "SPACE" { return true }
    if key.utf8.count == 1, let value = key.utf8.first {
      return (65...90).contains(value) || (48...57).contains(value)
    }
    return (1...20).contains(where: { key == "F\($0)" })
  }
  public static func valid(_ values: [KeyboardShortcut]) -> Bool {
    values.count <= Module.allCases.count + 1 && values.allSatisfy(\.valid)
      && Set(values.map(\.targetTitle)).count == values.count
      && Set(values.map(\.combination)).count == values.count
  }
  public static func parse(_ text: String) throws -> [KeyboardShortcut] {
    guard text.utf8.count <= 4096 else { throw SettingsError.invalid }
    let lines = text.split(separator: "\n").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    let values = try lines.map { line -> KeyboardShortcut in
      let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard parts.count == 2 else { throw SettingsError.invalid }
      let module = Module.allCases.first {
        $0.title.caseInsensitiveCompare(parts[0]) == .orderedSame
      }
      guard module != nil || parts[0].caseInsensitiveCompare("Settings") == .orderedSame else {
        throw SettingsError.invalid
      }
      let tokens = parts[1].uppercased().split(separator: "+", omittingEmptySubsequences: false).map
      { $0.trimmingCharacters(in: .whitespaces) }
      guard tokens.count >= 2, let key = tokens.last,
        Set(tokens.dropLast()).count == tokens.count - 1,
        tokens.dropLast().allSatisfy({ ["COMMAND", "CONTROL", "OPTION", "SHIFT"].contains($0) })
      else { throw SettingsError.invalid }
      let shortcut = KeyboardShortcut(
        module: module, key: key, command: tokens.contains("COMMAND"),
        control: tokens.contains("CONTROL"), option: tokens.contains("OPTION"),
        shift: tokens.contains("SHIFT"))
      guard shortcut.valid else { throw SettingsError.invalid }; return shortcut
    }
    guard valid(values) else { throw SettingsError.invalid }; return values
  }
}
