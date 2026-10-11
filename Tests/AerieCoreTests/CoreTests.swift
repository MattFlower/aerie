import XCTest

@testable import AerieCore

final class CoreTests: XCTestCase {
  func testRingIsChronologicalAfterWrapping() {
    var ring = RingBuffer<Int>(capacity: 3)
    for i in 0..<10 { ring.append(i) }
    XCTAssertEqual(ring.values, [7, 8, 9])
    XCTAssertEqual(ring.count, 3)
  }
  func testRingEmptyAndMinimumCapacity() {
    var ring = RingBuffer<Int>(capacity: 0)
    XCTAssertEqual(ring.values, [])
    ring.append(1)
    ring.append(2)
    XCTAssertEqual(ring.values, [2])
    XCTAssertEqual(ring.capacity, 1)
  }
  func testCounterRateUsesElapsedTime() {
    XCTAssertEqual(
      CounterRate.rate(previous: .init(time: 1, value: 100), current: .init(time: 3, value: 300)),
      100)
  }
  func testCountersDistinguishZeroFromMissing() {
    XCTAssertNil(CounterRate.rate(previous: nil, current: .init(time: 1, value: 10)))
    XCTAssertEqual(
      CounterRate.rate(previous: .init(time: 1, value: 10), current: .init(time: 2, value: 10)), 0)
  }
  func testCounterResetAndSleepDiscardRate() {
    XCTAssertNil(
      CounterRate.rate(previous: .init(time: 1, value: 100), current: .init(time: 2, value: 1)))
    XCTAssertNil(
      CounterRate.rate(previous: .init(time: 1, value: 100), current: .init(time: 100, value: 200)))
    XCTAssertNil(
      CounterRate.rate(previous: .init(time: 1, value: 100), current: .init(time: 1, value: 200)))
  }
  func testHistoryAggregatesAndStaysBounded() {
    var store = HistoryStore()
    for i in 0..<5000 {
      store.append(
        .init(date: Date(timeIntervalSince1970: Double(i)), values: ["cpu": Double(i % 2)]))
    }
    XCTAssertEqual(store.recent.count, 600)
    XCTAssertEqual(store.minutes.count, 83)
    XCTAssertEqual(store.hours.count, 1)
    XCTAssertEqual(store.minutes.values[0].values["cpu"], 0.5)
  }
  func testHistoryDoesNotInventMissingMetrics() {
    var store = HistoryStore()
    store.append(.init(date: Date(timeIntervalSince1970: 0), values: ["cpu": 80]))
    store.append(.init(date: Date(timeIntervalSince1970: 30), values: [:]))
    store.append(.init(date: Date(timeIntervalSince1970: 61), values: [:]))
    XCTAssertEqual(store.minutes.values[0].values["cpu"], 80)
    XCTAssertNil(store.recent.values[1].values["cpu"])
  }
  func testHistoryCapacityMatchesDisclosedInterval() {
    var store = HistoryStore(interval: 0.5)
    XCTAssertEqual(store.recent.capacity, 1200)
    store.configure(interval: 2)
    XCTAssertEqual(store.recent.capacity, 300)
  }
  func testSustainedRuleAndCooldown() {
    var engine = RuleEngine()
    let rule = ThresholdRule(metric: "cpu", threshold: 90, duration: 10, cooldown: 30)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 0).isEmpty)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 9).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 10), [rule])
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 11).isEmpty)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 40), [rule])
  }
  func testMissingValueResetsSustain() {
    var engine = RuleEngine()
    let rule = ThresholdRule(metric: "cpu", threshold: 90, duration: 10)
    _ = engine.evaluate(rules: [rule], values: ["cpu": 95], time: 0)
    _ = engine.evaluate(rules: [rule], values: [:], time: 9)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 10).isEmpty)
  }
  func testSleepResetsSustain() {
    var engine = RuleEngine()
    let rule = ThresholdRule(metric: "cpu", threshold: 90, duration: 10)
    _ = engine.evaluate(rules: [rule], values: ["cpu": 95], time: 0)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["cpu": 95], time: 100).isEmpty)
  }
  func testBelowRuleAndDisabledRule() {
    var engine = RuleEngine()
    var rule = ThresholdRule(metric: "battery", threshold: 20, comparison: .below, duration: 0)
    XCTAssertEqual(engine.evaluate(rules: [rule], values: ["battery": 10], time: 1), [rule])
    rule.enabled = false
    XCTAssertTrue(engine.evaluate(rules: [rule], values: ["battery": 10], time: 1000).isEmpty)
  }
  func testSettingsRoundTrip() throws {
    let original = Settings()
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(original))
    XCTAssertEqual(try decoded.validated(), original)
    XCTAssertFalse(decoded.weather.enabled)
  }
  func testInvalidSettingsRejected() {
    var s = Settings()
    s.interval = 60
    XCTAssertThrowsError(try s.validated())
    s = Settings()
    s.menus = []
    XCTAssertThrowsError(try s.validated())
    s = Settings()
    s.menus.append(s.menus[0])
    XCTAssertThrowsError(try s.validated())
    s = Settings()
    s.clocks = [.init(name: "Invalid", zone: "Invalid/Zone")]
    XCTAssertThrowsError(try s.validated())
  }
  func testWeatherMustBeExplicitlyEnabled() {
    var c = WeatherConfiguration()
    c.name = "Synthetic city"
    c.latitude = 10
    c.longitude = 20
    XCTAssertThrowsError(try OpenMeteoProvider.requestURL(c))
    c.enabled = true
    XCTAssertNoThrow(try OpenMeteoProvider.requestURL(c))
  }
  func testWeatherCoordinateRoundingAndValidation() throws {
    var c = WeatherConfiguration()
    c.name = "Synthetic city"
    c.enabled = true
    c.latitude = 10.12345
    c.longitude = 20.98765
    let components = URLComponents(
      url: try OpenMeteoProvider.requestURL(c), resolvingAgainstBaseURL: false)
    let values = Dictionary(
      uniqueKeysWithValues: components!.queryItems!.map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(values["latitude"], "10.12")
    XCTAssertEqual(values["longitude"], "20.99")
    c.latitude = 100
    XCTAssertThrowsError(try OpenMeteoProvider.requestURL(c))
  }
  func testUnimplementedProviderNeverSilentlyUsesAnotherEndpoint() {
    var configuration = WeatherConfiguration()
    configuration.enabled = true; configuration.name = "Synthetic city"
    configuration.latitude = 10; configuration.longitude = 20
    for provider in ["nws", "unknown"] {
      configuration.provider = provider
      XCTAssertFalse(configuration.valid)
      XCTAssertThrowsError(try OpenMeteoProvider.requestURL(configuration))
      var settings = Settings(); settings.weather = configuration
      XCTAssertThrowsError(try settings.validated())
    }
  }
  func testSyntheticForecastDecode() throws {
    let data = Data(
      """
      {"current":{"temperature_2m":12,"weather_code":3,"relative_humidity_2m":80},
       "hourly":{"time":[100,200],"temperature_2m":[12,null],"weather_code":[3,1],"precipitation_probability":[50,0]},
       "daily":{"time":[100],"temperature_2m_min":[5],"temperature_2m_max":[14],"weather_code":[3],"sunrise":[50],"sunset":[150]}}
      """.utf8)
    let report = try OpenMeteoProvider.decode(data, fetched: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(report.temperature, 12)
    XCTAssertEqual(report.hours.count, 1)
    XCTAssertEqual(report.hours[0].precipitation, 50)
    XCTAssertEqual(report.days[0].low, 5)
  }
  func testMalformedForecastArraysRejected() {
    let data = Data(
      """
      {"current":{"temperature_2m":12},"hourly":{"time":[100],"temperature_2m":[],"weather_code":[3]}}
      """.utf8)
    XCTAssertThrowsError(try OpenMeteoProvider.decode(data))
  }
  func testForecastMissingTemperatureRejected() {
    XCTAssertThrowsError(try OpenMeteoProvider.decode(Data("{\"current\":{}}".utf8)))
  }
  func testUnknownConditionsRemainUnavailable() {
    XCTAssertEqual(WeatherCondition.describe(nil), "Conditions unavailable")
    XCTAssertEqual(WeatherCondition.describe(61), "Rain")
  }
  func testLunarAgeAlwaysInRange() {
    for day in stride(from: -100000, through: 100000, by: 100) {
      let age = Astronomy.moonAge(at: Date(timeIntervalSince1970: Double(day) * 86400))
      XCTAssertGreaterThanOrEqual(age, 0)
      XCTAssertLessThan(age, 29.530589)
    }
  }
  func testUnitsAndUnavailableValues() {
    XCTAssertEqual(Format.bytes(1024), "1.0 KiB")
    XCTAssertEqual(Format.bytes(1000, binary: false), "1.0 KB")
    XCTAssertEqual(Format.temperature(0, unit: .fahrenheit), "32.0°F")
    XCTAssertEqual(Format.percent(nil), "Unavailable")
  }
}
