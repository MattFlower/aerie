import AerieCore
import Foundation

protocol SamplingTimer: AnyObject { func cancel() }
final class DispatchSamplingTimer: SamplingTimer {
  private let timer: DispatchSourceTimer
  init(queue: DispatchQueue, interval: Double, tick: @escaping () -> Void) {
    timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
    timer.setEventHandler(handler: tick); timer.resume()
  }
  func cancel() { timer.cancel() }
  deinit { timer.cancel() }
}
/// Owned and called on the collector queue. Pausing removes the timer itself.
final class SamplingSchedule {
  typealias Factory = (Double, @escaping () -> Void) -> SamplingTimer
  private let factory: Factory
  private var timer: SamplingTimer?
  private var tick: () -> Void = {}
  private(set) var paused = false
  private(set) var interval = 1.0
  var isScheduled: Bool { timer != nil }
  init(factory: @escaping Factory) { self.factory = factory }
  func configure(interval: Double, tick: @escaping () -> Void) {
    timer?.cancel(); timer = nil
    self.interval = interval; self.tick = tick
    if !paused { timer = factory(interval, tick) }
  }
  func setPaused(_ value: Bool) {
    guard value != paused else { return }
    paused = value; timer?.cancel(); timer = nil
    if !paused { timer = factory(interval, tick) }
  }
  deinit { timer?.cancel() }
}
enum ProcessDemand {
  static func required(module: Module, visible: Bool) -> Bool {
    visible && [.cpu, .memory, .storage, .power].contains(module)
  }
}
