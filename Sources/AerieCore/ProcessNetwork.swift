import Foundation

public struct ProcessNetworkCounter: Equatable {
  public let pid: Int32
  public let name: String
  public let received, sent: UInt64
}
public struct ProcessNetworkFrame {
  public let time: Double
  public let counters: [ProcessNetworkCounter]
}
public enum ProcessNetworkError: Error { case malformed, oversized }
/// A bounded, incremental decoder for the OS logger's per-process-only CSV stream.
public struct ProcessNetworkCSV {
  private var buffer = Data()
  private var rows: [ProcessNetworkCounter] = []
  private var pids: Set<Int32> = []
  private var frameTime: Double?
  private var receivedColumn = 1, sentColumn = 2
  public init() {}
  public mutating func consume(_ data: Data, time: Double) throws -> [ProcessNetworkFrame] {
    guard time.isFinite, data.count <= 65536, buffer.count + data.count <= 131072 else {
      throw ProcessNetworkError.oversized
    }
    buffer.append(data)
    var consumed = 0
    var frames: [ProcessNetworkFrame] = []
    while let end = buffer[consumed...].firstIndex(of: 10) {
      let line = buffer[consumed..<end]; consumed = end + 1
      guard line.count <= 2048, let string = String(data: line, encoding: .utf8) else {
        throw ProcessNetworkError.malformed
      }
      let fields = try Self.fields(string.trimmingCharacters(in: .newlines))
      guard !fields.isEmpty else { continue }
      if fields[0].isEmpty {
        guard fields.count == 4, fields.last == "", Set(fields[1...2]) == ["bytes_in", "bytes_out"]
        else {
          throw ProcessNetworkError.malformed
        }
        if let frameTime { frames.append(.init(time: frameTime, counters: rows)) }
        rows.removeAll(keepingCapacity: true); pids.removeAll(keepingCapacity: true)
        frameTime = time
        receivedColumn = fields.firstIndex(of: "bytes_in")!;
        sentColumn = fields.firstIndex(of: "bytes_out")!
      } else {
        guard frameTime != nil, fields.count == 4, fields.last == "",
          let split = fields[0].lastIndex(of: "."),
          let pid = Int32(fields[0][fields[0].index(after: split)...]), pid >= 0,
          let received = UInt64(fields[receivedColumn]), let sent = UInt64(fields[sentColumn]),
          rows.count < 4096, pids.insert(pid).inserted
        else { throw ProcessNetworkError.malformed }
        let name = String(fields[0][..<split])
        guard !name.isEmpty, name.utf8.count <= 128 else { throw ProcessNetworkError.malformed }
        rows.append(.init(pid: pid, name: name, received: received, sent: sent))
      }
    }
    if consumed > 0 { buffer.removeSubrange(0..<consumed) }
    guard buffer.count <= 2048 else { throw ProcessNetworkError.oversized }
    return frames
  }
  private static func fields(_ line: String) throws -> [String] {
    if line.isEmpty { return [] }
    let characters = Array(line); var fields: [String] = [], value = ""
    var quoted = false, endedQuote = false, index = 0
    while index < characters.count {
      let c = characters[index]
      if quoted {
        if c == "\"" {
          if index + 1 < characters.count, characters[index + 1] == "\"" {
            value.append(c); index += 1
          } else {
            quoted = false; endedQuote = true
          }
        } else {
          value.append(c)
        }
      } else if c == "," {
        fields.append(value); value = ""; endedQuote = false
      } else if c == "\"", value.isEmpty, !endedQuote {
        quoted = true
      } else {
        guard !endedQuote, c != "\"", !c.isNewline else { throw ProcessNetworkError.malformed }
        value.append(c)
      }
      index += 1
    }
    guard !quoted else { throw ProcessNetworkError.malformed }
    fields.append(value); return fields
  }
}
public struct ProcessNetworkReading {
  public let pid: Int32
  public let name: String
  public let received, sent: UInt64
  public let download, upload: Double?
}
public struct ProcessNetworkRates {
  private struct Baseline { let identity: UInt64; let time: Double; let received, sent: UInt64 }
  private var previous: [Int32: Baseline] = [:]
  public init() {}
  public mutating func update(_ frame: ProcessNetworkFrame, identity: (Int32) -> UInt64?) -> (
    rows: [ProcessNetworkReading], denied: Int
  ) {
    var next: [Int32: Baseline] = [:], rows: [ProcessNetworkReading] = []
    var denied = 0
    for counter in frame.counters {
      guard counter.pid > 0, let start = identity(counter.pid), start > 0 else {
        denied += 1; continue
      }
      let old = previous[counter.pid].flatMap {
        $0.identity == start && counter.received >= $0.received && counter.sent >= $0.sent
          ? $0 : nil
      }
      func rate(_ value: UInt64, _ oldValue: UInt64?) -> Double? {
        CounterRate.rate(
          previous: old.flatMap { baseline in oldValue.map { .init(time: baseline.time, value: $0) }
          },
          current: .init(time: frame.time, value: value))
      }
      rows.append(
        .init(
          pid: counter.pid, name: counter.name, received: counter.received, sent: counter.sent,
          download: rate(counter.received, old?.received), upload: rate(counter.sent, old?.sent)))
      next[counter.pid] = .init(
        identity: start, time: frame.time, received: counter.received, sent: counter.sent)
    }
    previous = next; return (rows, denied)
  }
}
