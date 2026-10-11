import AerieCore
import AerieNative
import Foundation

struct ClockStateReading {
  var subscriptions: Int? = nil
  var rows: [ClockResidency] = []
  var status = "Clock-state telemetry has no baseline"
}
struct ClockSourceReading {
  var subscriptions: Int? = nil
  var counters: [ClockCounter] = []
  var statuses: [Int32] = [1, 1, 1]
}
protocol ClockStateSource: AnyObject {
  func read() -> ClockSourceReading
  func close()
}
private final class NativeClockStateSource: ClockStateSource {
  private var reader: OpaquePointer?
  private let profiler: SamplingProfiler?
  init?(profiler: SamplingProfiler? = nil) {
    self.profiler = profiler
    guard let value = aerie_performance_create() else { return nil }; reader = value
  }
  func read() -> ClockSourceReading {
    profiler?.mark(.clockPrepare)
    var channels = [AerieClockChannel](repeating: AerieClockChannel(), count: 128)
    var statuses = [Int32](repeating: 1, count: 3)
    profiler?.mark(.clockNative)
    let count = Int(aerie_performance_read(reader, &channels, 128, &statuses))
    profiler?.mark(.clockDecode)
    let counters: [ClockCounter] = channels.prefix(max(0, min(128, count))).compactMap { channel in
      guard let kind = ClockChannelKind(rawValue: Int(channel.kind)),
        (1...64).contains(channel.state_count)
      else { return nil }
      let states = withUnsafeBytes(of: channel.states) { bytes in
        bytes.bindMemory(to: AerieClockState.self).prefix(Int(channel.state_count)).map {
          (name: Self.text($0.name), ticks: $0.ticks)
        }
      }
      return ClockCounter(
        kind: kind,
        identity: "\(channel.kind):\(channel.driver_id):\(channel.channel_id)",
        name: Self.text(channel.name), unit: Self.text(channel.unit), states: states)
    }
    return ClockSourceReading(
      subscriptions: Int(aerie_performance_subscription_count(reader)),
      counters: counters, statuses: statuses)
  }
  private static func text<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) {
      String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
    }
  }
  func close() { aerie_performance_close(reader); reader = nil }
  deinit { close() }
}
/// Serial collector ownership, with no additional sampling timer or child process.
final class ClockStateReader {
  private let profiler: SamplingProfiler?
  private let factory: () -> ClockStateSource?
  private var source: ClockStateSource?
  private var tracker = ClockResidencyTracker()
  private var attempted = -Double.infinity
  private var retryNeeded = true
  init(profiler: SamplingProfiler? = nil, factory: (() -> ClockStateSource?)? = nil) {
    self.profiler = profiler
    self.factory = factory ?? { NativeClockStateSource(profiler: profiler) }
  }
  func sample(time: Double) -> ClockStateReading {
    if retryNeeded && time - attempted >= 60 {
      close(); attempted = time; source = factory()
    }
    var reading = source?.read() ?? ClockSourceReading()
    if reading.statuses.count != 3 { reading = ClockSourceReading() }
    let statuses = reading.statuses
    retryNeeded = statuses.contains { $0 != 0 && $0 != 5 }
    let names = ["CPU complexes", "CPU cores", "GPU"]
    let messages = statuses.enumerated().compactMap { index, status -> String? in
      let message: String
      switch status {
      case 0: return nil
      case 1: message = "system interface unavailable"
      case 2: message = "channel unavailable"
      case 3: message = "subscription unavailable to this process"
      case 4: message = "sample unavailable"
      case 5: message = "128-channel or 64-state bound reached; partial inventory"
      default: message = "unavailable"
      }
      return names[index] + ": " + message
    }
    profiler?.mark(.clockDerive)
    let rows = tracker.update(reading.counters, time: time)
    return ClockStateReading(
      subscriptions: reading.subscriptions.flatMap { (1...3).contains($0) ? $0 : nil },
      rows: rows,
      status: messages.isEmpty
        ? "Read-only clock-state residency; interval baseline required. GHz needs explicit frequency labels."
        : messages.joined(separator: " · "))
  }
  func close() {
    source?.close(); source = nil; tracker.reset(); retryNeeded = true
    attempted = -Double.infinity
  }
  deinit { close() }
}
