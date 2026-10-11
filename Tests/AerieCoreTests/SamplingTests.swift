import XCTest
@testable import AerieCore

final class SamplingTests: XCTestCase {
  func testEditingPreservesRuleIdentityAndDisabledStateAndRejectsDuplicates() throws {
    var rule = ThresholdRule(metric: "cpu", threshold: 90); rule.enabled = false
    let edit = RuleEdits.replacing(
      rule, with: ThresholdRule(metric: "memory", threshold: 80, duration: 60))
    XCTAssertEqual(edit.id, rule.id); XCTAssertFalse(edit.enabled)
    XCTAssertEqual(edit.metric, "memory"); XCTAssertEqual(edit.duration, 60)
    var settings = Settings(); settings.rules = [rule, edit]
    XCTAssertThrowsError(try settings.validated())
  }
  private func observation(_ pid: Int, start: UInt64 = 1, parent: Int = 0, cpu: UInt64 = 0)
    -> ProcessObservation
  {
    .init(
      pid: pid, startTime: start, parent: parent, name: "Synthetic", footprint: 1024,
      resident: 2048, cpuNanoseconds: cpu, wakeups: cpu / 1_000_000)
  }
  private func take(
    _ sampler: inout ProcessSampler, _ observations: [ProcessObservation], _ time: Double
  ) -> ProcessSample {
    sampler.sample(
      observations: observations, monotonicTime: time, date: Date(timeIntervalSince1970: time),
      scenario: "synthetic",
      verifiedRecursiveMembers: sampler.trackedIdentities.union(observations.map(\.identity)))
  }
  func testFirstBaselineRatesAreIncompleteAndExplicitlyNull() throws {
    var sampler = ProcessSampler(pids: [10])
    let first = take(&sampler, [observation(10)], 0)
    XCTAssertTrue(first.footprintComplete); XCTAssertFalse(first.cpuComplete);
    XCTAssertFalse(first.wakeupsComplete)
    XCTAssertTrue(first.incomplete); XCTAssertNil(first.totalCPUPercent)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
    XCTAssertTrue(json["totalCPUPercent"] is NSNull)
    let second = take(&sampler, [observation(10, cpu: 20_000_000)], 2)
    XCTAssertFalse(second.incomplete); XCTAssertEqual(second.totalCPUPercent, 1)
  }
  func testSpawnHasIndependentRateBaselineAndRemainsAfterReparentAndExit() {
    var sampler = ProcessSampler(pids: [10])
    _ = take(&sampler, [observation(10)], 0)
    let spawn = take(&sampler, [observation(10), observation(11, parent: 10)], 1)
    XCTAssertEqual(spawn.readings.count, 2); XCTAssertFalse(spawn.cpuComplete)
    let reparent = take(&sampler, [observation(10), observation(11, parent: 1, cpu: 1_000_000)], 2)
    XCTAssertEqual(reparent.readings.count, 2); XCTAssertTrue(reparent.cpuComplete)
    let exit = take(&sampler, [observation(10)], 3)
    XCTAssertEqual(exit.readings.count, 2); XCTAssertNil(exit.totalFootprintBytes)
    XCTAssertEqual(exit.readings.first { $0.pid == 11 }?.status, "exited-or-unavailable")
  }
  func testPIDReuseDoesNotInheritMembershipOrBaseline() {
    var sampler = ProcessSampler(pids: [10])
    _ = take(&sampler, [observation(10)], 0)
    let reused = take(&sampler, [observation(10, start: 99, cpu: 100_000_000)], 1)
    XCTAssertEqual(reused.readings.map(\.startTime), [1]); XCTAssertNil(reused.totalCPUPercent)
    XCTAssertEqual(reused.readings[0].status, "exited-or-unavailable")
  }
  func testUnreadableProcessCannotLowerTotalsOrPretendZero() {
    var sampler = ProcessSampler(pids: [10, 20])
    let blocked = ProcessObservation(pid: 20, startTime: 0, error: 1)
    _ = take(&sampler, [observation(10), blocked], 0)
    let sample = take(&sampler, [observation(10), blocked], 1)
    XCTAssertFalse(sample.footprintComplete); XCTAssertFalse(sample.cpuComplete)
    XCTAssertNil(sample.totalFootprintBytes); XCTAssertNil(sample.totalCPUPercent)
  }
  func testConfirmedExitRetainsIdentityAndFootprintButDoesNotInventTransitionCPU() {
    var sampler = ProcessSampler(pids: [10])
    _ = take(&sampler, [observation(10), observation(11, parent: 10)], 0)
    let identity = ProcessIdentity(pid: 11, startTime: 1)
    let exited = sampler.sample(
      observations: [observation(10)], monotonicTime: 1,
      date: Date(timeIntervalSince1970: 1), scenario: "synthetic", confirmedExits: [identity])
    XCTAssertEqual(exited.readings.count, 2)
    let child = exited.readings.first { $0.pid == 11 }!
    XCTAssertEqual(child.status, "exited-confirmed"); XCTAssertEqual(child.footprintBytes, 0)
    XCTAssertNil(child.cpuPercent); XCTAssertFalse(exited.cpuComplete)
    let settled = take(&sampler, [observation(10)], 2)
    XCTAssertEqual(settled.readings.first { $0.pid == 11 }?.cpuPercent, 0)
    XCTAssertTrue(settled.footprintComplete); XCTAssertTrue(settled.cpuComplete)
    XCTAssertEqual(sampler.trackedIdentities.count, 2)
  }
  func testExitProofCannotZeroLiveOrUnidentifiedProtectedProcess() {
    var sampler = ProcessSampler(pids: [10, 20])
    let protected = ProcessObservation(pid: 20, startTime: 0, error: 1)
    _ = take(&sampler, [observation(10), protected], 0)
    let sample = sampler.sample(
      observations: [observation(10), protected], monotonicTime: 1,
      date: Date(timeIntervalSince1970: 1), scenario: "synthetic",
      confirmedExits: [.init(pid: 10, startTime: 1), .init(pid: 20, startTime: 0)])
    XCTAssertEqual(sample.readings.first { $0.pid == 10 }?.status, "live")
    XCTAssertEqual(sample.readings.first { $0.pid == 20 }?.status, "unreadable")
    XCTAssertFalse(sample.footprintComplete); XCTAssertNil(sample.totalFootprintBytes)
  }
  func testReadableSelectedSubsetCannotClaimWholeCohortCompleteness() throws {
    var sampler = ProcessSampler(pids: [10])
    _ = sampler.sample(
      observations: [observation(10), observation(11, parent: 10)],
      monotonicTime: 0, date: Date(timeIntervalSince1970: 0), scenario: "synthetic")
    let sample = sampler.sample(
      observations: [observation(10), observation(11, parent: 10)],
      monotonicTime: 1, date: Date(timeIntervalSince1970: 1), scenario: "synthetic")
    XCTAssertFalse(sample.cohortComplete); XCTAssertFalse(sample.footprintComplete)
    XCTAssertTrue(sample.incomplete); XCTAssertNil(sample.totalFootprintBytes)
    XCTAssertEqual(sample.observedFootprintBytes, 2048)
    let json =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as! [String: Any]
    XCTAssertTrue(json["totalFootprintBytes"] is NSNull)
    XCTAssertEqual(json["cohortComplete"] as? Bool, false)
  }
  func testMissingNestedOrUnexpectedMemberInvalidatesVerifiedSet() {
    for members: Set<ProcessIdentity> in [
      [.init(pid: 10, startTime: 1)],
      [.init(pid: 10, startTime: 1), .init(pid: 11, startTime: 1), .init(pid: 12, startTime: 1)],
    ] {
      var sampler = ProcessSampler(pids: [10])
      let sample = sampler.sample(
        observations: [observation(10), observation(11, parent: 10)], monotonicTime: 0,
        date: Date(timeIntervalSince1970: 0), scenario: "synthetic",
        verifiedRecursiveMembers: members)
      XCTAssertFalse(sample.cohortComplete); XCTAssertNil(sample.totalFootprintBytes)
      XCTAssertEqual(sample.observedFootprintBytes, 2048)
    }
  }
  func testTerminatedRootAndDuplicateObservationsCannotClaimCompleteTotals() {
    var sampler = ProcessSampler(pids: [10])
    let root = observation(10)
    let duplicate = sampler.sample(
      observations: [root, root], monotonicTime: 0,
      date: Date(timeIntervalSince1970: 0), scenario: "synthetic",
      verifiedRecursiveMembers: [root.identity])
    XCTAssertFalse(duplicate.cohortComplete); XCTAssertNil(duplicate.totalFootprintBytes)
    let exited = sampler.sample(
      observations: [], monotonicTime: 1, date: Date(timeIntervalSince1970: 1),
      scenario: "synthetic", confirmedExits: [root.identity],
      verifiedRecursiveMembers: [root.identity])
    XCTAssertEqual(exited.readings[0].status, "exited-confirmed")
    XCTAssertFalse(exited.cohortComplete); XCTAssertNil(exited.totalFootprintBytes)
  }
  func testBitPreferenceOnlyChangesNetworkRates() {
    XCTAssertEqual(Format.rate(1024, domain: .storage, networkBits: true), "1.0 KiB/s")
    XCTAssertEqual(Format.rate(1024, domain: .storage, networkBits: false), "1.0 KiB/s")
    XCTAssertEqual(Format.rate(1000, domain: .network, networkBits: true), "8.0 Kbit/s")
    XCTAssertEqual(Format.rate(1000, domain: .network, binary: false), "1.0 KB/s")
  }
  func testBoundedSuffixDoesNotMaterializeWholeHistory() {
    var ring = RingBuffer<Int>(capacity: 4)
    for i in 0..<9 { ring.append(i) }
    XCTAssertEqual(ring.suffix(2), [7, 8]); XCTAssertEqual(ring.suffix(100), [5, 6, 7, 8])
    XCTAssertEqual(ring.suffix(0), [])
  }
}
