import Foundation
import XCTest
@testable import AerieCore

final class SensorIdentityTests: XCTestCase {
  func testKeysAliasesPreserveIdentityAndBoundCopiedNames() throws {
    for key in ["T001", "F0Ac", " A  ", "A|01"] { XCTAssertTrue(SensorIdentity.validKey(key)) }
    for key in ["", "    ", "TOOLONG", "Té01", "T\t01"] {
      XCTAssertFalse(SensorIdentity.validKey(key))
    }
    let names = try SensorIdentity.parseNames("T001 | Enclosure probe\n A   | Spare\n\n")
    XCTAssertEqual(names, ["T001": "Enclosure probe", " A  ": "Spare"])
    XCTAssertNil(try SensorIdentity.parseNames(" \n"))
    for text in [
      "T001 | One\nT001 | Two", "BAD|Name", "T001 |",
      "T001 | " + String(repeating: "a", count: 65), "T001 | Bad\u{01}name",
      String(repeating: "a", count: 131073),
    ] {
      XCTAssertThrowsError(try SensorIdentity.parseNames(text), text)
    }
    let many = Dictionary(
      uniqueKeysWithValues: (0...1024).map { (String(format: "%04X", $0), "Name") })
    XCTAssertFalse(SensorIdentity.valid(names: many))
  }
  func testSensorRulesRequireNativeUnitAndAllowSignedThresholds() {
    let signed = ThresholdRule(metric: "sensor:T001", threshold: -5, duration: 0, sensorUnit: "°C")
    XCTAssertTrue(signed.valid); XCTAssertEqual(signed.valueKey, "sensor:T001:°C")
    XCTAssertFalse(ThresholdRule(metric: "sensor:T001", threshold: 5).valid)
    XCTAssertFalse(ThresholdRule(metric: "sensor:BAD", threshold: 5, sensorUnit: "°C").valid)
    XCTAssertFalse(ThresholdRule(metric: "sensor:T001", threshold: 5, sensorUnit: "°F").valid)
    XCTAssertFalse(ThresholdRule(metric: "sensor:F001", threshold: -1, sensorUnit: "rpm").valid)
    XCTAssertFalse(ThresholdRule(metric: "sensor:I001", threshold: .nan, sensorUnit: "A").valid)
    XCTAssertFalse(ThresholdRule(metric: "cpu", threshold: 5, sensorUnit: "°C").valid)
    XCTAssertFalse(ThresholdRule(metric: "cpu", threshold: -1).valid)
    var engine = RuleEngine()
    XCTAssertTrue(engine.evaluate(rules: [signed], values: ["sensor:T001": -4], time: 0).isEmpty)
    XCTAssertEqual(
      engine.evaluate(rules: [signed], values: [signed.valueKey: -4], time: 1), [signed])
  }
  func testLegacySettingsAndRulesRoundTripAliasesAndRejectInvalidImports() throws {
    var settings = Settings()
    XCTAssertNil(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).sensorNames)
    settings.sensorNames = ["F0Ac": "Exhaust fan"]
    settings.rules = [ThresholdRule(metric: "sensor:F0Ac", threshold: 2000, sensorUnit: "rpm")]
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(try decoded.validated(), settings)
    settings.sensorNames = ["T001": "Bad\nname"]
    XCTAssertThrowsError(try settings.validated())
    settings.sensorNames = nil; settings.rules[0].sensorUnit = "°F"
    XCTAssertThrowsError(try settings.validated())
    let legacy = Data(
      "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"metric\":\"cpu\",\"threshold\":90,\"comparison\":\"above\",\"duration\":30,\"cooldown\":300,\"enabled\":true}"
        .utf8)
    XCTAssertTrue(try JSONDecoder().decode(ThresholdRule.self, from: legacy).valid)
  }
  func testOnlyValidEnabledRulesDemandSpecificKeysAndNoSamplingChangeByAlias() {
    let fan = ThresholdRule(metric: "sensor:F0Ac", threshold: 2000, sensorUnit: "rpm")
    var disabled = ThresholdRule(metric: "sensor:P001", threshold: 5, sensorUnit: "W");
    disabled.enabled = false
    let invalid = ThresholdRule(metric: "sensor:I001", threshold: 5)
    XCTAssertEqual(
      SensorIdentity.requiredKeys(rules: [
        fan, disabled, invalid, ThresholdRule(metric: "cpu", threshold: 50),
      ]), ["F0Ac"])
    XCTAssertTrue(
      SensorDemand.required(unit: "rpm", mode: .whenNeeded, panelVisible: false, ruleRequired: true)
    )
    XCTAssertFalse(SensorDemand.required(unit: "W", mode: .whenNeeded, panelVisible: false))
  }
}
