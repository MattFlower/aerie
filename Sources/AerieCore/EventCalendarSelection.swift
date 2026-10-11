import Foundation

/// nil includes all event calendars; an empty selection deliberately includes none.
public enum EventCalendarSelection {
  public static func valid(_ identifiers: [String]?) -> Bool {
    guard let identifiers else { return true }
    return identifiers.count <= 128 && Set(identifiers).count == identifiers.count
      && identifiers.allSatisfy {
        !$0.isEmpty && $0.utf8.count <= 512
          && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
          && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
      }
  }
}
