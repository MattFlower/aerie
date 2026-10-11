import XCTest
@testable import AerieCore

final class ChangeRuleTests: XCTestCase {
  func testInitialBaselineMissingRecoveryAndSleepDoNotFire() {
    let rule = ChangeRule(kind: .connectivity, cooldown: 10)
    var engine = ChangeRuleEngine()
    XCTAssertTrue(
      engine.evaluate(rules: [rule], values: [.connectivity: "Connected"], time: 0).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: [:], time: 1).isEmpty)
    XCTAssertTrue(
      engine.evaluate(rules: [rule], values: [.connectivity: "Offline"], time: 2).isEmpty)
    XCTAssertTrue(
      engine.evaluate(rules: [rule], values: [.connectivity: "Connected"], time: 40).isEmpty)
    engine.reset()
    XCTAssertTrue(
      engine.evaluate(rules: [rule], values: [.connectivity: "Offline"], time: 41).isEmpty)
  }
  func testCooldownConsumesTransitionsAndRulesAreIndependent() {
    let connection = ChangeRule(kind: .connectivity, cooldown: 10)
    let power = ChangeRule(kind: .powerSource, cooldown: 10)
    var engine = ChangeRuleEngine()
    _ = engine.evaluate(
      rules: [connection, power],
      values: [.connectivity: "Connected", .powerSource: "AC"], time: 0)
    let events = engine.evaluate(
      rules: [connection, power],
      values: [.connectivity: "Offline", .powerSource: "Battery"], time: 1)
    XCTAssertEqual(events.map(\.rule.kind), [.connectivity, .powerSource])
    XCTAssertEqual(events[0].previous, "Connected"); XCTAssertEqual(events[0].current, "Offline")
    XCTAssertTrue(
      engine.evaluate(rules: [connection], values: [.connectivity: "Connected"], time: 2).isEmpty)
    XCTAssertTrue(
      engine.evaluate(rules: [connection], values: [.connectivity: "Connected"], time: 12).isEmpty)
    XCTAssertEqual(
      engine.evaluate(rules: [connection], values: [.connectivity: "Offline"], time: 13).count, 1)
  }
  func testDisabledEditedAndNonMonotonicRulesRequireNewBaseline() {
    var rule = ChangeRule(kind: .lowPower, cooldown: 10)
    var engine = ChangeRuleEngine()
    _ = engine.evaluate(rules: [rule], values: [.lowPower: "Disabled"], time: 0)
    rule.enabled = false
    XCTAssertTrue(engine.evaluate(rules: [rule], values: [.lowPower: "Enabled"], time: 1).isEmpty)
    rule.enabled = true
    XCTAssertTrue(engine.evaluate(rules: [rule], values: [.lowPower: "Enabled"], time: 2).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: [.lowPower: "Disabled"], time: 1).isEmpty)
    rule.kind = .thermal
    XCTAssertTrue(engine.evaluate(rules: [rule], values: [.thermal: "Fair"], time: 3).isEmpty)
    XCTAssertTrue(
      engine.evaluate(rules: [rule], values: [.thermal: "Critical"], time: .nan).isEmpty)
  }
  func testOldSettingsDecodeAndDuplicateKindsAreRejected() throws {
    var settings = Settings()
    let encoded = try JSONEncoder().encode(settings)
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object.removeValue(forKey: "changeRules")
    let old = try JSONSerialization.data(withJSONObject: object)
    XCTAssertNil(try JSONDecoder().decode(Settings.self, from: old).validated().changeRules)
    settings.changeRules = [ChangeRule(kind: .thermal), ChangeRule(kind: .thermal)]
    XCTAssertThrowsError(try settings.validated())
    settings.changeRules = [ChangeRule(kind: .thermal, cooldown: .infinity)]
    XCTAssertThrowsError(try settings.validated())
  }
  func testThresholdEditCannotCreditPreviousSustainTime() {
    var rule = ThresholdRule(metric: "cpu", threshold: 50, duration: 10)
    var engine = RuleEngine()
    _ = engine.evaluate(rules: [rule], values: ["cpu": 90], time: 0)
    rule.threshold = 80
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 90], time: 10).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 90], time: 20).count, 1)
  }
}
