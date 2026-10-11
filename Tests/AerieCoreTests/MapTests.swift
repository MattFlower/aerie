import XCTest
@testable import AerieCore

final class MapTests: XCTestCase {
  func testConsentIsIndependentAndOldSettingsKeepMapsOff() throws {
    var configuration = WeatherConfiguration()
    XCTAssertFalse(configuration.mapsValid)
    configuration.name = "Synthetic place"; configuration.latitude = 40;
    configuration.longitude = -100
    configuration.mapsEnabled = true
    XCTAssertTrue(configuration.mapsValid); XCTAssertFalse(configuration.valid)
    configuration.mapsProvider = "unknown"; XCTAssertFalse(configuration.mapsValid)
    let old = Data(
      "{\"enabled\":true,\"name\":\"Synthetic\",\"latitude\":40,\"longitude\":-100}".utf8)
    let decoded = try JSONDecoder().decode(WeatherConfiguration.self, from: old)
    XCTAssertFalse(decoded.mapsEnabled); XCTAssertTrue(decoded.valid)
  }
  func testInheritedCRSAndTimesWithCapabilities() throws {
    let xml = """
      <WMS_Capabilities><Capability><Layer><CRS>EPSG:4326</CRS>
      <Dimension name="time">2026-01-01T00:00:00.000Z,2026-01-01T00:05:00Z</Dimension>
      <Layer><Name>synthetic</Name><Title>Synthetic imagery</Title></Layer></Layer></Capability></WMS_Capabilities>
      """
    let layers = try WMS.parse(Data(xml.utf8))
    XCTAssertEqual(layers.count, 1); XCTAssertEqual(layers[0].name, "synthetic")
    XCTAssertEqual(layers[0].times.count, 2); XCTAssertTrue(layers[0].crs.contains("EPSG:4326"))
  }
  func testWMSAxisOrderAndAdvertisedTime() throws {
    let bounds = MapBounds(west: -120, south: 20, east: -80, north: 50)
    let endpoint = WeatherMapKind.radar.endpoint
    func query(_ layer: WMSLayer) throws -> [String: String] {
      let url = try WMS.image(
        endpoint: endpoint, layer: layer, bounds: bounds, time: Date(timeIntervalSince1970: 0))
      return Dictionary(
        URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map {
          ($0.name, $0.value!)
        }, uniquingKeysWith: { _, last in last })
    }
    XCTAssertEqual(
      try query(.init(name: "test", title: "", crs: ["EPSG:4326"]))["BBOX"],
      "20.0000,-120.0000,50.0000,-80.0000")
    XCTAssertEqual(
      try query(.init(name: "test", title: "", crs: ["CRS:84"]))["BBOX"],
      "-120.0000,20.0000,-80.0000,50.0000")
    XCTAssertEqual(try query(.init(name: "test", title: ""))["TIME"], "1970-01-01T00:00:00Z")
  }
  func testAncientForecastTimesAreNotPresentedAsCurrent() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let layer = WMSLayer(
      name: "snow", title: "", times: [.distantPast, now, now.addingTimeInterval(3600)])
    XCTAssertEqual(layer.visibleTimes(kind: .snow, now: now), [now, now.addingTimeInterval(3600)])
    XCTAssertEqual(layer.visibleTimes(kind: .radar, now: now), [now])
  }
  func testBoundsAndProvidersRejectInvalidRequests() throws {
    XCTAssertTrue(MapBounds.centered(latitude: 85, longitude: 180, span: 16).valid)
    XCTAssertFalse(WMS.allowed(URL(string: "http://mapservices.weather.noaa.gov/")!))
    XCTAssertFalse(WMS.allowed(URL(string: "https://example.com/")!))
    XCTAssertFalse(
      WMS.allowed(URL(string: "https://synthetic:synthetic@mapservices.weather.noaa.gov/")!))
    XCTAssertThrowsError(try WMS.parse(Data("<invalid/>".utf8)))
    XCTAssertThrowsError(
      try WMS.image(
        endpoint: WeatherMapKind.radar.endpoint,
        layer: .init(name: "x", title: "", crs: ["unsupported"]),
        bounds: .centered(latitude: 40, longitude: -100, span: 16), time: nil))
  }
  func testDecodedCostAndCountBoundEvictionAndClearReleaseValues() {
    final class Frame {}
    var cache = CostCache<String, Frame>(maximumCost: 30, maximumCount: 2)
    final class WeakFrame { weak var value: Frame?; init(_ value: Frame?) { self.value = value } }
    var frame: Frame? = Frame(); let retained = WeakFrame(frame)
    XCTAssertTrue(cache.insert(frame!, for: "a", cost: 10)); frame = nil;
    XCTAssertNotNil(retained.value)
    _ = cache.insert(Frame(), for: "b", cost: 10); _ = cache.value(for: "a")
    _ = cache.insert(Frame(), for: "c", cost: 10)
    XCTAssertNil(cache.value(for: "b")); XCTAssertEqual(cache.count, 2)
    XCTAssertFalse(cache.insert(Frame(), for: "too-big", cost: 31)); XCTAssertEqual(cache.cost, 20)
    cache.clear(); XCTAssertNil(retained.value); XCTAssertEqual(cache.cost, 0);
    XCTAssertEqual(cache.count, 0)
  }
}
