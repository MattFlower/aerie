import Darwin
import Foundation

/// Explicit diagnostic mode only. One owner/thread; no values, names, identifiers or extra timer.
final class SamplingProfiler {
  enum Phase: String, CaseIterable {
    case demand, inventory, cpu, clockPrepare, clockNative, clockDecode, clockDerive
    case memory, network, storage, gpu, sensors, power, other, processes, delivery
    case appReceive, appHistory, appRules, appMenu, appVisible, appWeather
  }
  struct Stamp { let wall: UInt64; let cpu: UInt64? }
  struct Total: Encodable {
    var calls = 0, cpuSamples = 0, invalidWallSamples = 0
    var observedWallNanoseconds: UInt64 = 0, observedCPUNanoseconds: UInt64 = 0
  }
  struct Report: Encodable {
    let kind = "samplingPhases"
    let schema = 1
    let scope: String
    let ticks: Int
    let phases: [String: Total]
  }
  private let clock: () -> Stamp
  private let emit: (Report) -> Void
  private let scope: String
  private let window: Int
  private var current: (Phase, Stamp)?
  private var totals: [String: Total] = [:]
  private var ticks = 0
  init(
    scope: String, window: Int = 60,
    clock: @escaping () -> Stamp = { SamplingProfiler.nativeStamp() },
    emit: @escaping (Report) -> Void = { report in
      let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
      if let data = try? encoder.encode(report), let line = String(data: data, encoding: .utf8) {
        print(line); fflush(stdout)
      }
    }
  ) {
    precondition((1...3600).contains(window))
    self.scope = scope; self.window = window; self.clock = clock; self.emit = emit
  }
  private static func nativeStamp() -> Stamp {
    var time = timespec()
    let cpu: UInt64?
    if clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0, time.tv_sec >= 0,
      time.tv_nsec >= 0, time.tv_nsec < 1_000_000_000
    {
      let seconds = UInt64(time.tv_sec).multipliedReportingOverflow(by: 1_000_000_000)
      let total = seconds.partialValue.addingReportingOverflow(UInt64(time.tv_nsec))
      cpu = seconds.overflow || total.overflow ? nil : total.partialValue
    } else {
      cpu = nil
    }
    return Stamp(wall: DispatchTime.now().uptimeNanoseconds, cpu: cpu)
  }
  func begin(_ phase: Phase) { precondition(current == nil); current = (phase, clock()) }
  private func record(until end: Stamp) {
    guard let (phase, start) = current else { return }
    var value = totals[phase.rawValue, default: Total()]; value.calls += 1
    if end.wall >= start.wall {
      let total = value.observedWallNanoseconds.addingReportingOverflow(end.wall - start.wall)
      if !total.overflow {
        value.observedWallNanoseconds = total.partialValue
      } else {
        value.invalidWallSamples += 1
      }
    } else {
      value.invalidWallSamples += 1
    }
    if let first = start.cpu, let last = end.cpu, last >= first {
      let total = value.observedCPUNanoseconds.addingReportingOverflow(last - first)
      if !total.overflow {
        value.observedCPUNanoseconds = total.partialValue; value.cpuSamples += 1
      }
    }
    totals[phase.rawValue] = value
  }
  func mark(_ phase: Phase) {
    guard current != nil else { return }
    let stamp = clock(); record(until: stamp); current = (phase, stamp)
  }
  func finish() {
    guard current != nil else { return }
    record(until: clock()); current = nil; ticks += 1
    if ticks >= window {
      let report = Report(scope: scope, ticks: ticks, phases: totals)
      totals.removeAll(keepingCapacity: true); ticks = 0; emit(report)
    }
  }
}
