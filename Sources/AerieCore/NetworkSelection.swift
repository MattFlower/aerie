import Foundation

public struct NetworkSelection: Equatable {
  public var names: [String]?
  public init(names: [String]? = nil) { self.names = names }
  public var valid: Bool {
    guard let names else { return true }
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    return names.count <= 128 && Set(names).count == names.count
      && names.allSatisfy {
        !$0.isEmpty && $0.utf8.count < 32 && $0.unicodeScalars.allSatisfy(allowed.contains)
      }
  }
  public func includes(name: String, active: Bool) -> Bool {
    active && (names?.contains(name) ?? true)
  }
  public var description: String {
    guard let names else { return "All active interfaces" }
    return names.isEmpty
      ? "No interfaces selected" : "Selected active interfaces: " + names.joined(separator: ", ")
  }
}

public struct NetworkCounterRecord {
  public var name: String
  public var received, sent: UInt64
  public var bits: Int
  public init(name: String, received: UInt64, sent: UInt64, bits: Int = 64) {
    self.name = name; self.received = received; self.sent = sent; self.bits = bits
  }
}
public struct NetworkSessionReading {
  public var received, sent: UInt64?
  public var started: Date
  public var rebased: Bool
}
/// Per-interface observed sessions. A missing interface, read failure, reset or source change starts a new baseline.
public struct NetworkSessionTracker {
  private struct Entry { var counter: NetworkCounterRecord; var reading: NetworkSessionReading }
  private var entries: [String: Entry] = [:]
  public init() {}
  public mutating func reset() { entries.removeAll() }
  public mutating func update(_ counters: [NetworkCounterRecord], date: Date) -> [String:
    NetworkSessionReading]
  {
    guard counters.count <= 128, Set(counters.map(\.name)).count == counters.count,
      counters.allSatisfy({ $0.bits == 32 || $0.bits == 64 })
    else { reset(); return [:] }
    let names = Set(counters.map(\.name))
    entries = entries.filter { names.contains($0.key) }
    var result: [String: NetworkSessionReading] = [:]
    for current in counters {
      if var entry = entries[current.name], entry.counter.bits == current.bits,
        current.received >= entry.counter.received, current.sent >= entry.counter.sent
      {
        if let received = entry.reading.received, let sent = entry.reading.sent {
          let incoming = received.addingReportingOverflow(current.received - entry.counter.received)
          let outgoing = sent.addingReportingOverflow(current.sent - entry.counter.sent)
          entry.reading.received = incoming.overflow ? nil : incoming.partialValue
          entry.reading.sent = outgoing.overflow ? nil : outgoing.partialValue
        }
        entry.counter = current; entries[current.name] = entry
      } else {
        let rebased = entries[current.name] != nil
        entries[current.name] = Entry(
          counter: current,
          reading: NetworkSessionReading(received: 0, sent: 0, started: date, rebased: rebased))
      }
      result[current.name] = entries[current.name]?.reading
    }
    return result
  }
}
