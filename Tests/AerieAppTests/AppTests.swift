import AerieCore
import AerieNative
import XCTest
@testable import AerieApp

final class AppTests: XCTestCase {
  func testFailedMemoryReadCannotPublishPreviousMemoryOrTriggerRule() {
    let date = Date(timeIntervalSince1970: 100)
    var previous = MemoryData()
    previous.validity = .fresh; previous.sampledAt = date; previous.usedFraction = 0.95
    var failed = AerieMemory(); failed.valid = 0
    let reading = Collector.memoryReading(
      failed, previous: previous, date: date.addingTimeInterval(10)
    ) { _, _ in
      XCTFail("A failed read must not update counter baselines"); return 0
    }
    XCTAssertEqual(reading.validity, .stale(lastSuccess: date))
    XCTAssertNil(reading.usedFraction); XCTAssertNil(reading.pageIn)
    var snapshot = Snapshot(); snapshot.memory = reading
    XCTAssertNil(snapshot.metrics["memory"])
    var history = HistoryStore();
    history.append(.init(date: snapshot.date, values: snapshot.metrics))
    XCTAssertNil(history.recent.values.last?.values["memory"])
    var engine = RuleEngine()
    let rule = ThresholdRule(metric: "memory", threshold: 90, duration: 5)
    _ = engine.evaluate(rules: [rule], values: ["memory": 95], time: 0)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: snapshot.metrics, time: 10).isEmpty)
  }
  func testFirstFailedMemoryReadIsUnavailableAndSuccessfulRecoveryIsFresh() {
    let missing = Collector.memoryReading(AerieMemory(), previous: MemoryData(), date: .distantPast)
    { _, _ in nil }
    XCTAssertEqual(missing.validity, .unavailable)
    var native = AerieMemory(); native.valid = 1; native.total = 1000; native.internal = 500
    native.wired = 100; native.compressed = 100
    let recovered = Collector.memoryReading(native, previous: missing, date: .distantFuture) {
      _, _ in nil
    }
    XCTAssertEqual(recovered.validity, .fresh); XCTAssertEqual(recovered.usedFraction, 0.7)
  }
  func testProcessDemandFollowsVisibleModule() {
    for module in Module.allCases {
      XCTAssertFalse(ProcessDemand.required(module: module, visible: false))
      XCTAssertEqual(
        ProcessDemand.required(module: module, visible: true),
        [.cpu, .memory, .storage, .power].contains(module))
    }
  }
  func testPauseResumeAndReconfigureOwnExactlyOneTimer() {
    final class Timer: SamplingTimer {
      var cancelled = false
      let tick: () -> Void
      init(_ tick: @escaping () -> Void) { self.tick = tick }
      func cancel() { cancelled = true }
      func fire() { if !cancelled { tick() } }
    }
    var timers: [Timer] = []; var intervals: [Double] = []; var ticks = 0
    let schedule = SamplingSchedule { interval, tick in
      let timer = Timer(tick); timers.append(timer); intervals.append(interval); return timer
    }
    schedule.configure(interval: 1) { ticks += 1 }; timers[0].fire()
    schedule.setPaused(true); XCTAssertTrue(timers[0].cancelled);
    XCTAssertFalse(schedule.isScheduled)
    schedule.configure(interval: 2) { ticks += 1 }; XCTAssertEqual(timers.count, 1)
    timers[0].fire(); XCTAssertEqual(ticks, 1)
    schedule.setPaused(false); XCTAssertEqual(intervals, [1, 2]); timers[1].fire()
    schedule.setPaused(false); XCTAssertEqual(timers.count, 2)
    schedule.configure(interval: 0.5) { ticks += 1 }; XCTAssertTrue(timers[1].cancelled)
    schedule.setPaused(true); schedule.setPaused(true); XCTAssertTrue(timers[2].cancelled)
    schedule.setPaused(false); XCTAssertEqual(intervals, [1, 2, 0.5, 0.5])
    XCTAssertEqual(timers.filter { !$0.cancelled }.count, 1); XCTAssertEqual(ticks, 2)
  }
}
