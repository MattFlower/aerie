import AerieNative
import Darwin
import Foundation

struct StorageProcessResources: Encodable {
  let pid: Int32
  let birth, resourceIdentity: UInt64
  let footprint, resident, cpuNanoseconds, interruptWakeups: UInt64?
  let lifetimePeakFootprint: UInt64?
  let error: Int?
  init(pid: Int32, expectedBirth: UInt64 = 0, reaped: Bool = false) {
    self.pid = pid
    if reaped {
      birth = 0; resourceIdentity = 0; footprint = 0; resident = 0
      cpuNanoseconds = nil; interruptWakeups = nil; error = nil
      lifetimePeakFootprint = nil
    } else {
      let before = aerie_process_birth(pid)
      let value = aerie_process(pid)
      birth = aerie_process_birth(pid); resourceIdentity = value.start_time
      let matching = expectedBirth == 0 || (before == expectedBirth && birth == expectedBirth)
      let valid = value.valid != 0 && matching
      footprint = valid ? value.footprint : nil
      resident = valid ? value.resident : nil
      cpuNanoseconds = valid ? value.cpu_ns : nil
      interruptWakeups = valid ? value.wakeups : nil
      lifetimePeakFootprint =
        valid && value.lifetime_peak_footprint > 0 ? value.lifetime_peak_footprint : nil
      error = valid ? nil : matching ? Int(value.error) : Int(ESRCH)
    }
  }
}
struct StorageCommandMeasurement: Encodable {
  let kind = "storageCommandLifecycle"
  let command: UUID
  let date: Date
  let monotonicTime: Double
  let phase: String
  let registeredPID: Int32
  let registeredBirth: UInt64
  let app, helper: StorageProcessResources
  let exitStatus: Int32?
  let confirmedExit: Bool
  let nominalIntervalSeconds = 0.025
}
/// Explicit development instrumentation, never enabled in ordinary monitoring or CI.
/// Launch/confirmed-reap registration cannot miss a short helper; resource polling still can.
final class StorageCommandProbe {
  private let queue = DispatchQueue(label: "app.aerie.storage-measurement", qos: .utility)
  private let timer: DispatchSourceTimer
  private let pid: Int32
  private let birth: UInt64
  private let command = UUID()
  private let output: (StorageCommandMeasurement) -> Void
  private var ended = false
  private static let outputLock = NSLock()
  static var cliOutput: ((StorageCommandMeasurement) -> Void)? {
    guard CommandLine.arguments.contains("--storage-command-measurements") else { return nil }
    return { record in
      let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
        outputLock.lock(); print(line); fflush(stdout); outputLock.unlock()
      }
    }
  }
  init(pid: Int32, birth: UInt64, output: @escaping (StorageCommandMeasurement) -> Void) {
    self.pid = pid; self.birth = birth; self.output = output
    timer = DispatchSource.makeTimerSource(queue: queue)
    queue.sync { capture(phase: "started", status: nil) }
    timer.schedule(deadline: .now() + 0.025, repeating: 0.025, leeway: .milliseconds(1))
    timer.setEventHandler { [weak self] in
      guard let self, !self.ended else { return }; self.capture(phase: "running", status: nil)
    }
    timer.resume()
  }
  private func capture(phase: String, status: Int32?) {
    output(
      StorageCommandMeasurement(
        command: command, date: Date(),
        monotonicTime: ProcessInfo.processInfo.systemUptime, phase: phase,
        registeredPID: pid, registeredBirth: birth, app: StorageProcessResources(pid: getpid()),
        helper: StorageProcessResources(pid: pid, expectedBirth: birth, reaped: status != nil),
        exitStatus: status,
        confirmedExit: status != nil))
  }
  func finish(status: Int32) {
    timer.cancel()
    queue.sync {
      ended = true; capture(phase: "reaped", status: status)
    }
  }
  deinit { timer.cancel() }
}
