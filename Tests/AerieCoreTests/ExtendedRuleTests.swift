import Foundation
import XCTest
@testable import AerieCore

final class ExtendedRuleTests: XCTestCase {
  func testInclusiveScalarAndRangeBoundariesAreExplicit() {
    for (comparison, equal) in [
      (RuleComparison.above, false), (.below, false), (.atLeast, true), (.atMost, true),
    ] {
      let rule = ThresholdRule(metric: "cpu", threshold: 50, comparison: comparison)
      XCTAssertTrue(rule.valid); XCTAssertEqual(rule.matches(50), equal)
      XCTAssertFalse(rule.matches(.nan)); XCTAssertFalse(rule.matches(.infinity))
    }
    let inside = ThresholdRule(
      metric: "cpu", threshold: 40, comparison: .inside, upperThreshold: 60)
    let outside = ThresholdRule(
      metric: "cpu", threshold: 40, comparison: .outside, upperThreshold: 60)
    for value in [40.0, 50, 60] {
      XCTAssertTrue(inside.matches(value)); XCTAssertFalse(outside.matches(value))
    }
    for value in [39.0, 61] {
      XCTAssertFalse(inside.matches(value)); XCTAssertTrue(outside.matches(value))
    }
  }
  func testRecoveryBandNeverArmsAndOncePerEpisodeWaitsForRecovery() {
    let rule = ThresholdRule(
      metric: "cpu", threshold: 90, duration: 2, cooldown: 10, hysteresis: 5, repeatWhileMet: false)
    var engine = RuleEngine()
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 89], time: 0).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 91], time: 1).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 87], time: 2).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 87], time: 3), [rule])
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 13).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 85], time: 14).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 89], time: 15).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 91], time: 16).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 91], time: 18), [rule])
  }
  func testRangeRecoveryUsesBothBoundsAndDoesNotCollapseOutsideGap() {
    let inside = ThresholdRule(
      metric: "cpu", threshold: 40, comparison: .inside, upperThreshold: 60, hysteresis: 5)
    XCTAssertFalse(inside.matches(35)); XCTAssertTrue(inside.matches(35, active: true))
    XCTAssertTrue(inside.matches(65, active: true));
    XCTAssertFalse(inside.matches(66, active: true))
    let outside = ThresholdRule(
      metric: "cpu", threshold: 40, comparison: .outside, upperThreshold: 60, hysteresis: 5)
    XCTAssertFalse(outside.matches(42)); XCTAssertTrue(outside.matches(42, active: true))
    XCTAssertFalse(outside.matches(45, active: true));
    XCTAssertFalse(outside.matches(55, active: true))
    XCTAssertTrue(outside.matches(58, active: true))
    var invalid = outside; invalid.hysteresis = 11
    XCTAssertFalse(invalid.valid); XCTAssertFalse(invalid.matches(0, active: true))
  }
  func testMissingPauseAndClockGapResetEpisodeButKeepCooldown() {
    let rule = ThresholdRule(
      metric: "cpu", threshold: 90, duration: 0, cooldown: 10, hysteresis: 5, repeatWhileMet: false)
    var engine = RuleEngine()
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 0), [rule])
    _ = engine.evaluate(rules: [rule], values: [:], time: 1)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 9).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 10), [rule])
    engine.reset()
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 89], time: 11).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 19).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 20), [rule])
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 89], time: 100).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 101), [rule])
  }
  func testEditsRearmAndDeletionReleasesEpisodeAndCooldownState() {
    var rule = ThresholdRule(
      metric: "cpu", threshold: 50, duration: 0, cooldown: 30, repeatWhileMet: false)
    var engine = RuleEngine()
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 0), [rule])
    rule.threshold = 80
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 1), [rule])
    XCTAssertTrue(engine.evaluate(rules: [], values: ["cpu": 99], time: 2).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 3), [rule])
  }
  func testLegacyRepeatDefaultsAndExtendedSettingsRoundTrip() throws {
    let old = Data(
      #"{"id":"00000000-0000-0000-0000-000000000001","metric":"cpu","threshold":90,"comparison":"above","duration":0,"cooldown":10,"enabled":true}"#
        .utf8)
    let rule = try JSONDecoder().decode(ThresholdRule.self, from: old)
    XCTAssertTrue(rule.valid); XCTAssertTrue(rule.repeats); XCTAssertEqual(rule.recoveryBand, 0)
    var engine = RuleEngine()
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 0), [rule])
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 99], time: 10), [rule])
    var settings = Settings();
    settings.rules = [
      ThresholdRule(
        metric: "sensor:I0AA", threshold: -2, comparison: .inside, sensorUnit: "A",
        upperThreshold: 2, hysteresis: 0.25, repeatWhileMet: false)
    ]
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).validated(),
      settings)
    XCTAssertTrue(settings.rules[0].conditionDescription.contains("A"))
  }
  func testInvalidRangeBandAndStorageMetricsCannotFabricateRates() {
    for rule in [
      ThresholdRule(metric: "cpu", threshold: 50, comparison: .inside),
      ThresholdRule(metric: "cpu", threshold: 50, comparison: .outside, upperThreshold: 40),
      ThresholdRule(metric: "cpu", threshold: 50, upperThreshold: 60),
      ThresholdRule(metric: "cpu", threshold: 50, hysteresis: -1),
      ThresholdRule(metric: "cpu", threshold: 50, hysteresis: .nan),
    ] { XCTAssertFalse(rule.valid) }
    let read = ThresholdRule(metric: "diskRead", threshold: 0, comparison: .atMost, duration: 0)
    let write = ThresholdRule(metric: "diskWrite", threshold: 1, duration: 0)
    XCTAssertTrue(read.valid); XCTAssertTrue(write.valid)
    var engine = RuleEngine()
    XCTAssertTrue(engine.evaluate(rules: [read, write], values: [:], time: 0).isEmpty)
    XCTAssertEqual(
      engine.evaluate(rules: [read, write], values: ["diskRead": 0, "diskWrite": 2], time: 1),
      [read, write])
  }
}
