import AerieNative
import Darwin
import Foundation

// A small external sampler. Only caller-selected PIDs and their descendants are included.
struct Reading: Codable {
  var timestamp: Date
  var pid: Int
  var parent: Int
  var name: String
  var footprintBytes: UInt64?
  var residentBytes: UInt64?
  var cpuPercent: Double?
  var interruptWakeupsPerSecond: Double?
  var error: Int?
}
struct Sample: Codable {
  var scenario: String
  var timestamp: Date
  var readings: [Reading]
  var totalFootprintBytes: UInt64
  var totalCPUPercent: Double
  var totalWakeupsPerSecond: Double
  var incomplete: Bool
}
let arguments = CommandLine.arguments
func option(_ key: String, default fallback: String) -> String {
  guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return fallback }
  return arguments[i + 1]
}
let selected = option("--pids", default: "").split(separator: ",").compactMap { Int32($0) }
let duration = Double(option("--duration", default: "60")) ?? 60
let interval = Double(option("--interval", default: "2")) ?? 2
let scenario = option("--scenario", default: "idle")
guard !selected.isEmpty, duration > 0, duration <= 3600, interval >= 0.5, interval <= 60 else {
  fputs("Usage: AerieMeasure --pids 123,456 --scenario idle --duration 60 --interval 2\n", stderr)
  exit(2)
}
func name<T>(_ tuple: T) -> String {
  withUnsafeBytes(of: tuple) {
    String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
  }
}
var previous: [Int32: AerieProcess] = [:]
var previousTime: Double?
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
let start = ProcessInfo.processInfo.systemUptime
repeat {
  let now = ProcessInfo.processInfo.systemUptime
  var all = [AerieProcess](repeating: AerieProcess(), count: 8192)
  let count = Int(aerie_processes(&all, 8192))
  all = Array(all.prefix(count))
  var ids = Set(selected)
  var changed = true
  while changed {
    changed = false
    for p in all where ids.contains(p.ppid) && !ids.contains(p.pid) {
      ids.insert(p.pid)
      changed = true
    }
  }
  var samples: [Reading] = []
  for pid in ids.sorted() {
    let p = all.first { $0.pid == pid } ?? aerie_process(pid)
    let old = previous[pid]
    let dt = previousTime.map { now - $0 } ?? 0
    func rate(_ value: UInt64, _ prior: UInt64?) -> Double? {
      guard p.valid != 0, old?.valid != 0, old?.start_time == p.start_time,
        let prior, value >= prior, dt > 0
      else { return nil }
      return Double(value - prior) / dt
    }
    samples.append(
      Reading(
        timestamp: Date(), pid: Int(pid), parent: Int(p.ppid), name: name(p.name),
        footprintBytes: p.valid != 0 ? p.footprint : nil,
        residentBytes: p.valid != 0 ? p.resident : nil,
        cpuPercent: rate(p.cpu_ns, old?.cpu_ns).map { $0 / 1e7 },
        interruptWakeupsPerSecond: rate(p.wakeups, old?.wakeups),
        error: p.valid != 0 ? nil : Int(p.error)))
    previous[pid] = p
  }
  let record = Sample(
    scenario: scenario, timestamp: Date(), readings: samples,
    totalFootprintBytes: samples.compactMap(\.footprintBytes).reduce(0, +),
    totalCPUPercent: samples.compactMap(\.cpuPercent).reduce(0, +),
    totalWakeupsPerSecond: samples.compactMap(\.interruptWakeupsPerSecond).reduce(0, +),
    incomplete: samples.contains { $0.footprintBytes == nil })
  if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
    print(line)
  }
  previousTime = now
  if now - start >= duration { break }
  Thread.sleep(forTimeInterval: min(interval, max(0, duration - (now - start))))
} while true
