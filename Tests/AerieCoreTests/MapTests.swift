import XCTest
@testable import AerieCore

final class MapTests: XCTestCase {
  func testStateBoundariesResolveAdvertisedIdentityAndRejectUnrelatedOrTimedLayers() throws {
    let layers: [WMSLayer] = [
      .init(name: "old", title: "NWS County Borders"),
      .init(name: "future", title: "NWS States Borders", times: [Date(timeIntervalSince1970: 0)]),
      .init(name: "unsupported", title: "NWS States Borders", crs: ["unknown"]),
      .init(name: "synthetic-new-id", title: "NWS States Borders", crs: ["CRS:84"]),
    ]
    XCTAssertEqual(try WMS.stateBoundaries(layers).name, "synthetic-new-id")
    XCTAssertThrowsError(try WMS.stateBoundaries(Array(layers.prefix(3))))
  }
  func testLegendRequestsUseAdvertisedStyleAndExplicitLabels() throws {
    let xml = """
      <WMS_Capabilities><Capability><Layer><CRS>EPSG:4326</CRS>
      <Layer><Name>synthetic</Name><Title>Synthetic imagery</Title>
      <Style><Name>synthetic-reflectivity</Name><LegendURL width="500" height="30">
      <OnlineResource href="https://example.invalid/legend?width=500&amp;height=30"/>
      </LegendURL></Style>
      </Layer></Layer></Capability></WMS_Capabilities>
      """
    let layer = try XCTUnwrap(WMS.parse(Data(xml.utf8)).first)
    let url = try WMS.legend(endpoint: WeatherMapKind.radar.endpoint, layer: layer)
    let query = Dictionary(
      uniqueKeysWithValues:
        try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map {
          ($0.name, $0.value ?? "")
        })
    XCTAssertEqual(query["STYLE"], "synthetic-reflectivity")
    XCTAssertEqual(query["LEGEND_OPTIONS"], "forceLabels:on")
    XCTAssertEqual(query["WIDTH"], "500"); XCTAssertEqual(query["HEIGHT"], "30")
    let image = try WMS.image(
      endpoint: WeatherMapKind.radar.endpoint, layer: layer,
      bounds: .centered(latitude: 40, longitude: -100, span: 16), time: nil)
    let imageQuery = Dictionary(
      uniqueKeysWithValues:
        try XCTUnwrap(URLComponents(url: image, resolvingAgainstBaseURL: false)?.queryItems).map {
          ($0.name, $0.value ?? "")
        })
    XCTAssertEqual(imageQuery["STYLES"], query["STYLE"])
    var invalid = layer; invalid.legendRequestWidth = 1025
    XCTAssertThrowsError(try WMS.legend(endpoint: WeatherMapKind.radar.endpoint, layer: invalid))
  }
  func testLegendRequestSymbolDimensionsAreIndependentOfFinalImageSize() throws {
    let xml = """
      <WMS_Capabilities><Capability><Layer><CRS>EPSG:4326</CRS>
      <Layer><Name>synthetic</Name><Title>Synthetic forecast</Title>
      <Style><Name>synthetic-primary</Name><LegendURL width="46" height="1142">
      <OnlineResource href="http://example.invalid/legend?WIDTH=20&amp;height=20&amp;style=untrusted"/>
      </LegendURL></Style>
      <Style><Name>synthetic-secondary</Name><LegendURL width="99" height="99">
      <OnlineResource href="https://example.invalid/legend?width=99&amp;height=99"/>
      </LegendURL></Style></Layer></Layer></Capability></WMS_Capabilities>
      """
    let layer = try XCTUnwrap(WMS.parse(Data(xml.utf8)).first)
    let url = try WMS.legend(endpoint: WeatherMapKind.temperature.endpoint, layer: layer)
    XCTAssertEqual(url.host, WeatherMapKind.temperature.endpoint.host)
    XCTAssertEqual(url.scheme, "https")
    let query = Dictionary(
      uniqueKeysWithValues:
        try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map {
          ($0.name, $0.value ?? "")
        })
    XCTAssertEqual(query["WIDTH"], "20"); XCTAssertEqual(query["HEIGHT"], "20")
    XCTAssertEqual(query["STYLE"], "synthetic-primary")
    for invalid in ["width=20&amp;WIDTH=99", "width=not-a-number"] {
      XCTAssertThrowsError(
        try WMS.parse(Data(xml.replacingOccurrences(of: "WIDTH=20", with: invalid).utf8)))
    }
  }
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
