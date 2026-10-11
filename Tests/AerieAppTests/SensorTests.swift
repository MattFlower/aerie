import AerieCore
import XCTest
@testable import AerieApp

final class SensorTests: XCTestCase {
  private var inventory: [SensorData] {
    [("T001", "°C"), ("T002", "°C"), ("F0Ac", "rpm"), ("P001", "W"), ("V001", "V"), ("I001", "A")]
      .map {
        SensorData(key: $0.0, label: "Synthetic " + $0.0, value: nil, unit: $0.1)
      }
  }
  func testDemandRetainsInventoryAndTemperatureHistoryAndRuleInputsAtEveryTick() {
    var allCalls = 0, demandCalls = 0
    func readings(_ mode: SensorSamplingMode) -> [SensorData] {
      inventory.map { descriptor in
        Collector.sensorReading(descriptor, mode: mode, panelVisible: false) {
          if mode == .all { allCalls += 1 } else { demandCalls += 1 }
          return descriptor.key == "T002" ? 95 : 40
        }
      }
    }
    var all = Snapshot(), demand = Snapshot()
    all.sensors = readings(.all); demand.sensors = readings(.whenNeeded)
    XCTAssertEqual(allCalls, 6); XCTAssertEqual(demandCalls, 2)
    XCTAssertEqual(all.sensors.map(\.key), demand.sensors.map(\.key))
    XCTAssertEqual(all.sensors.map(\.label), demand.sensors.map(\.label))
    XCTAssertEqual(all.metrics["temperature"], 95); XCTAssertEqual(all.metrics, demand.metrics)
    XCTAssertTrue(
      demand.sensors.filter { $0.unit != "°C" }.allSatisfy {
        $0.value == nil && $0.state == .deferred
      })
    var history = HistoryStore(); history.append(.init(date: demand.date, values: demand.metrics))
    XCTAssertEqual(history.recent.values.last?.values["temperature"], 95)
    var engine = RuleEngine()
    let rule = ThresholdRule(metric: "temperature", threshold: 90, duration: 1)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: demand.metrics, time: 0).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: demand.metrics, time: 1).count, 1)
  }
  func testPanelDemandRestoresEveryFamilyAndCloseNeverReusesStaleValues() {
    var calls = 0
    let visible = inventory.map { descriptor in
      Collector.sensorReading(descriptor, mode: .whenNeeded, panelVisible: true) {
        calls += 1; return 42
      }
    }
    XCTAssertEqual(calls, inventory.count);
    XCTAssertTrue(visible.allSatisfy { $0.state == .live && $0.value == 42 })
    for descriptor in visible where descriptor.unit != "°C" {
      let closed = Collector.sensorReading(descriptor, mode: .whenNeeded, panelVisible: false) {
        XCTFail("Hidden non-temperature readings must be explicitly deferred"); return 42
      }
      XCTAssertNil(closed.value); XCTAssertEqual(closed.state, .deferred)
    }
  }
  func testReadFailureAndInvalidTemperatureStayInInventoryWithoutRuleValues() {
    for value: Double? in [nil, .nan, .infinity, 151, -51] {
      let reading = Collector.sensorReading(inventory[0], mode: .all, panelVisible: false) { value }
      XCTAssertEqual(reading.key, inventory[0].key); XCTAssertNil(reading.value)
      XCTAssertEqual(reading.state, .unavailable)
      var snapshot = Snapshot(); snapshot.sensors = [reading]
      XCTAssertNil(snapshot.metrics["temperature"])
    }
  }
  func testFullSamplingRemainsDefaultForNewAndLegacySettings() throws {
    let settings = Settings(); XCTAssertEqual(settings.effectiveSensorSampling, .all)
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: encoded)
    XCTAssertNil(decoded.sensorSampling); XCTAssertEqual(decoded.effectiveSensorSampling, .all)
    var optedIn = decoded; optedIn.sensorSampling = .whenNeeded
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(optedIn))
        .effectiveSensorSampling, .whenNeeded)
  }
}

extension SensorTests {
  func testIndividualRulesReadOnlyRequiredKeysAndNeverGrowHistorySeries() {
    let fan = ThresholdRule(metric: "sensor:F0Ac", threshold: 35, duration: 0, sensorUnit: "rpm")
    var off = ThresholdRule(metric: "sensor:P001", threshold: 35, duration: 0, sensorUnit: "W");
    off.enabled = false
    let required = SensorIdentity.requiredKeys(rules: [fan, off])
    var called: [String] = []
    var snapshot = Snapshot()
    snapshot.sensors = inventory.map { descriptor in
      Collector.sensorReading(
        descriptor, mode: .whenNeeded, panelVisible: false,
        ruleRequired: required.contains(descriptor.key)
      ) {
        called.append(descriptor.key); return 40
      }
    }
    XCTAssertEqual(called, ["T001", "T002", "F0Ac"])
    XCTAssertTrue(snapshot.metrics.keys.allSatisfy { !$0.hasPrefix("sensor:") })
    let values = snapshot.ruleMetrics(rules: [fan, off], base: snapshot.metrics)
    XCTAssertEqual(values[fan.valueKey], 40); XCTAssertNil(values[off.valueKey])
    XCTAssertTrue(
      snapshot.ruleMetrics(rules: [fan], base: snapshot.metrics, suspended: true).isEmpty)
    var engine = RuleEngine()
    XCTAssertEqual(engine.evaluate(rules: [fan, off], values: values, time: 0), [fan])
    var history = HistoryStore();
    history.append(.init(date: snapshot.date, values: snapshot.metrics))
    XCTAssertEqual(history.recent.values.last?.values, snapshot.metrics)
    XCTAssertEqual(snapshot.ruleMetrics(rules: [], base: snapshot.metrics), snapshot.metrics)
  }
  func testMissingDeferredWrongUnitAndNonfiniteSensorValuesCannotFire() {
    let rpm = ThresholdRule(metric: "sensor:F0Ac", threshold: 35, duration: 0, sensorUnit: "rpm")
    let watts = ThresholdRule(metric: "sensor:F0Ac", threshold: 35, duration: 0, sensorUnit: "W")
    var snapshot = Snapshot()
    snapshot.sensors = [SensorData(key: "F0Ac", label: "Fan", value: 40, unit: "rpm")]
    var engine = RuleEngine()
    XCTAssertEqual(
      engine.evaluate(
        rules: [rpm, watts], values: snapshot.ruleMetrics(rules: [rpm, watts], base: [:]), time: 0),
      [rpm])
    for state in [SensorReadState.unavailable, .deferred] {
      snapshot.sensors[0].state = state
      XCTAssertTrue(snapshot.ruleMetrics(rules: [rpm], base: [:]).isEmpty)
    }
    snapshot.sensors[0].state = .live; snapshot.sensors[0].value = .nan
    XCTAssertTrue(snapshot.ruleMetrics(rules: [rpm], base: [:]).isEmpty)
    snapshot.sensors.removeAll();
    XCTAssertTrue(snapshot.ruleMetrics(rules: [rpm], base: [:]).isEmpty)
  }
  func testMissingSensorResetsSustainAndAliasNeverChangesRuleIdentity() {
    let rule = ThresholdRule(metric: "sensor:F0Ac", threshold: 35, duration: 2, sensorUnit: "rpm")
    var snapshot = Snapshot();
    snapshot.sensors = [SensorData(key: "F0Ac", label: "Fan", value: 40, unit: "rpm")]
    XCTAssertEqual(snapshot.sensors[0].title(names: ["F0Ac": "Exhaust"]), "Exhaust [F0Ac]")
    XCTAssertEqual(snapshot.sensors[0].title(names: nil), "Fan [F0Ac]")
    var engine = RuleEngine()
    XCTAssertTrue(
      engine.evaluate(
        rules: [rule], values: snapshot.ruleMetrics(rules: [rule], base: [:]), time: 0
      ).isEmpty)
    snapshot.sensors[0].value = nil
    XCTAssertTrue(
      engine.evaluate(
        rules: [rule], values: snapshot.ruleMetrics(rules: [rule], base: [:]), time: 1
      ).isEmpty)
    snapshot.sensors[0].value = 40
    XCTAssertTrue(
      engine.evaluate(
        rules: [rule], values: snapshot.ruleMetrics(rules: [rule], base: [:]), time: 2
      ).isEmpty)
    XCTAssertEqual(
      engine.evaluate(
        rules: [rule], values: snapshot.ruleMetrics(rules: [rule], base: [:]), time: 4), [rule])
  }
}
