import AerieCore
import AerieNative
import Darwin
import Foundation

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
var sampler = ProcessSampler(pids: selected.map(Int.init))
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
let start = ProcessInfo.processInfo.systemUptime
repeat {
  let now = ProcessInfo.processInfo.systemUptime
  var all = [AerieProcess](repeating: AerieProcess(), count: 8192)
  let count = Int(aerie_processes(&all, 8192))
  all = Array(all.prefix(count))
  for pid in selected where !all.contains(where: { $0.pid == pid }) {
    all.append(aerie_process(pid))
  }
  let observations = all.map { p in
    ProcessObservation(
      pid: Int(p.pid), startTime: p.start_time, parent: Int(p.ppid), name: name(p.name),
      footprint: p.valid != 0 ? p.footprint : nil, resident: p.valid != 0 ? p.resident : nil,
      cpuNanoseconds: p.valid != 0 ? p.cpu_ns : nil, wakeups: p.valid != 0 ? p.wakeups : nil,
      error: p.valid != 0 ? nil : Int(p.error))
  }
  let record = sampler.sample(
    observations: observations, monotonicTime: now, date: Date(), scenario: scenario)
  if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
    print(line)
  }
  if now - start >= duration { break }
  Thread.sleep(forTimeInterval: min(interval, max(0, duration - (now - start))))
} while true
