import Foundation
#if canImport(FoundationXML)
  import FoundationXML
#endif

public enum MapError: Error {
  case consentRequired, invalidMetadata, unavailableLayer, oversized, invalidResponse
}
public enum WeatherMapKind: String, CaseIterable {
  case radar, satellite, stormTracks, temperature, wind, windSpeed, rain, snow, alerts
  public var title: String {
    switch self {
    case .radar: return "Observed radar"
    case .satellite: return "Satellite"
    case .stormTracks: return "Tropical storm tracks"
    case .temperature: return "Forecast temperature"
    case .wind: return "Forecast wind barbs"
    case .windSpeed: return "Forecast wind speed"
    case .rain: return "Forecast precipitation"
    case .snow: return "Forecast snow"
    case .alerts: return "Current watches, warnings & advisories"
    }
  }
  public var forecast: Bool { [.temperature, .wind, .windSpeed, .rain, .snow].contains(self) }
  public var coverage: String {
    switch self {
    case .satellite: return "GOES regional and global mosaics; coverage depends on selected band"
    case .stormTracks:
      return "NHC tropical-cyclone past and forecast tracks; no convective-cell tracks"
    case .alerts:
      return "Current US NWS watches, warnings and advisories; no historical or forecast alerts"
    default: return "US coverage; provider data may be absent outside its supported region"
    }
  }
  public var endpoint: URL {
    let address: String
    switch self {
    case .radar: address = "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows"
    case .satellite: address = "https://nowcoast.noaa.gov/geoserver/observations/satellite/ows"
    case .stormTracks:
      address =
        "https://mapservices.weather.noaa.gov/tropical/services/tropical/NHC_tropical_weather/MapServer/WMSServer"
    case .alerts:
      address =
        "https://mapservices.weather.noaa.gov/eventdriven/services/WWA/watch_warn_adv/MapServer/WMSServer"
    default:
      let key = [
        .temperature: "temp", .wind: "wind", .windSpeed: "wspd", .rain: "qpf", .snow: "snow",
      ][self]!
      address = "https://mapservices.weather.noaa.gov/geoserver/ndfd/\(key)/ows"
    }
    return URL(string: address)!
  }
  public func preferred(_ layers: [WMSLayer]) throws -> WMSLayer {
    let key: String
    switch self {
    case .radar: key = "conus_bref_qcd"
    case .satellite: key = "goes_longwave_imagery"
    case .temperature: key = "temp"
    case .wind: key = "wind"
    case .windSpeed: key = "wspd"
    case .rain: key = "qpf"
    case .snow: key = "snow"
    case .alerts:
      // ArcGIS REST IDs and WMS layer names need not agree. Resolve the advertised product.
      guard
        let layer = layers.first(where: {
          let title = $0.title.lowercased();
          return title.contains("watch") && title.contains("warning")
        })
      else { throw MapError.unavailableLayer }
      return layer
    case .stormTracks:
      let tracks = layers.filter {
        $0.title.contains("Forecast Track") || $0.title.contains("Past Track")
      }
      guard !tracks.isEmpty, tracks.count <= 64 else { throw MapError.unavailableLayer }
      let commonCRS = tracks.dropFirst().reduce(tracks[0].crs) { $0.intersection($1.crs) }
      guard commonCRS.contains("CRS:84") || commonCRS.contains("EPSG:4326") else {
        throw MapError.unavailableLayer
      }
      return WMSLayer(
        name: tracks.map(\.name).joined(separator: ","), title: "NHC past/forecast tracks",
        crs: commonCRS)
    }
    guard let layer = layers.first(where: { $0.name == key || $0.name.hasSuffix(":" + key) }) else {
      throw MapError.unavailableLayer
    }
    return layer
  }
}

public struct MapBounds: Equatable {
  public var west: Double, south: Double, east: Double, north: Double
  public init(west: Double, south: Double, east: Double, north: Double) {
    self.west = west; self.south = south; self.east = east; self.north = north
  }
  public static func centered(latitude: Double, longitude: Double, span: Double) -> MapBounds {
    let width = min(160, max(1, span))
    let x = min(180 - width / 2, max(-180 + width / 2, longitude))
    let y = min(85 - width / 2, max(-85 + width / 2, latitude))
    return .init(
      west: x - width / 2, south: y - width / 2, east: x + width / 2, north: y + width / 2)
  }
  public var valid: Bool {
    [west, south, east, north].allSatisfy(\.isFinite) && west >= -180 && east <= 180
      && south >= -90 && north <= 90 && west < east && south < north
  }
}
public struct WMSLayer: Equatable {
  public var name: String
  public var title: String
  public var crs: Set<String>
  public var times: [Date]
  public var timeEnabled: Bool
  public var abstract = ""
  public var styles: [String]
  public init(
    name: String, title: String, crs: Set<String> = ["EPSG:4326"], times: [Date] = [],
    styles: [String] = [], timeEnabled: Bool? = nil
  ) {
    self.name = name; self.title = title; self.crs = crs; self.times = times; self.styles = styles
    self.timeEnabled = timeEnabled ?? !times.isEmpty
  }
  public func visibleTimes(kind: WeatherMapKind, now: Date) -> [Date] {
    let relevant = times.filter {
      kind.forecast
        ? $0 >= now.addingTimeInterval(-7200)
        : $0 <= now.addingTimeInterval(300) && $0 >= now.addingTimeInterval(-43200)
    }
    return Array((kind.forecast ? relevant.prefix(256) : relevant.suffix(256)))
  }
  public func timeline(kind: WeatherMapKind, now: Date) -> MapTimeline {
    guard timeEnabled else { return .timeless }
    let frames = visibleTimes(kind: kind, now: now)
    return frames.isEmpty ? .unavailable(latestAdvertised: times.max()) : .frames(frames)
  }
}

public enum WMS {
  public static let baseEndpoint = URL(
    string:
      "https://mapservices.weather.noaa.gov/static/services/nws_reference_maps/nws_reference_map/MapServer/WMSServer"
  )!
  public static let allowedHosts: Set<String> = [
    "opengeo.ncep.noaa.gov", "nowcoast.noaa.gov", "mapservices.weather.noaa.gov", "api.weather.gov",
  ]
  public static func allowed(_ url: URL) -> Bool {
    url.scheme == "https" && allowedHosts.contains(url.host?.lowercased() ?? "") && url.user == nil
      && url.password == nil
  }
  private static func request(_ endpoint: URL, _ values: [(String, String)]) throws -> URL {
    guard allowed(endpoint), var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
    else { throw MapError.invalidResponse }
    c.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
    guard let url = c.url else { throw MapError.invalidResponse }; return url
  }
  public static func capabilities(_ endpoint: URL) throws -> URL {
    try request(
      endpoint, [("SERVICE", "WMS"), ("VERSION", "1.3.0"), ("REQUEST", "GetCapabilities")])
  }
  public static func image(
    endpoint: URL, layer: WMSLayer, bounds: MapBounds, time: Date?, size: Int = 512
  ) throws -> URL {
    guard bounds.valid, (64...1024).contains(size), !layer.name.isEmpty, layer.name.count < 4096
    else { throw MapError.invalidResponse }
    // A time-enabled product must never silently request an undated service default.
    guard !layer.timeEnabled || (time != nil && layer.times.contains(time!)) else {
      throw MapError.unavailableLayer
    }
    let crs = layer.crs.contains("CRS:84") ? "CRS:84" : "EPSG:4326"
    guard layer.crs.contains(crs) else { throw MapError.unavailableLayer }
    // WMS 1.3 EPSG:4326 uses latitude/longitude order; CRS:84 uses longitude/latitude.
    let coordinates =
      crs == "CRS:84"
      ? [bounds.west, bounds.south, bounds.east, bounds.north]
      : [bounds.south, bounds.west, bounds.north, bounds.east]
    let bbox = coordinates.map {
      String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0)
    }.joined(separator: ",")
    var values = [
      ("SERVICE", "WMS"), ("VERSION", "1.3.0"), ("REQUEST", "GetMap"), ("LAYERS", layer.name),
      ("STYLES", ""), ("CRS", crs), ("BBOX", bbox), ("WIDTH", String(size)),
      ("HEIGHT", String(size)), ("FORMAT", "image/png"), ("TRANSPARENT", "TRUE"),
    ]
    if let time { values.append(("TIME", ISO8601DateFormatter().string(from: time))) }
    return try request(endpoint, values)
  }
  public static func legend(endpoint: URL, layer: WMSLayer) throws -> URL {
    try request(
      endpoint,
      [
        ("SERVICE", "WMS"), ("VERSION", "1.3.0"), ("REQUEST", "GetLegendGraphic"),
        ("LAYER", layer.name.split(separator: ",").first.map(String.init) ?? layer.name),
        ("FORMAT", "image/png"), ("WIDTH", "20"), ("HEIGHT", "20"),
      ])
  }
  public static func parse(_ data: Data) throws -> [WMSLayer] {
    guard data.count <= 2_000_000 else { throw MapError.oversized }
    let delegate = CapabilitiesParser(); let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    guard parser.parse(), !delegate.layers.isEmpty else { throw MapError.invalidMetadata }
    return delegate.layers
  }
}

private final class CapabilitiesParser: NSObject, XMLParserDelegate {
  var layers: [WMSLayer] = []
  private var stack: [WMSLayer] = []
  private var elements: [String] = []
  private var texts: [String] = []
  private var dimension: String?
  private var nodes = 0
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes: [String: String]
  ) {
    let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
    nodes += 1; if nodes > 50000 || elements.count > 64 { parser.abortParsing(); return }
    elements.append(name); texts.append("")
    if name == "Layer" {
      let parent = stack.last
      stack.append(
        WMSLayer(
          name: "", title: "", crs: parent?.crs ?? [], times: parent?.times ?? [],
          styles: parent?.styles ?? [], timeEnabled: parent?.timeEnabled ?? false))
    }
    if name == "Dimension" || name == "Extent" { dimension = attributes["name"] }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard !texts.isEmpty else { return }
    if texts[texts.count - 1].count + string.count > 256000 { parser.abortParsing(); return }
    texts[texts.count - 1].append(string)
  }
  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    guard let name = elements.popLast(), let text = texts.popLast() else { return }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stack.isEmpty else { return }
    let index = stack.count - 1
    if name == "Name", elements.last == "Layer" { stack[index].name = value }
    if name == "Title", elements.last == "Layer" { stack[index].title = value }
    if name == "Abstract", elements.last == "Layer" { stack[index].abstract = value }
    if name == "Name", elements.last == "Style" { stack[index].styles.append(value) }
    if name == "CRS" || name == "SRS" {
      stack[index].crs.formUnion(value.split(whereSeparator: \.isWhitespace).map(String.init))
    }
    if (name == "Dimension" || name == "Extent"), dimension == "time" {
      stack[index].timeEnabled = true
      guard let times = WMSTimeDimension.parse(value) else { parser.abortParsing(); return }
      stack[index].times = times
      dimension = nil
    }
    if name == "Layer", let layer = stack.popLast(), !layer.name.isEmpty { layers.append(layer) }
  }
}

/// Cache cost is decoded pixels, not compressed network bytes.
public struct CostCache<Key: Hashable, Value> {
  private var entries: [Key: (Value, Int)] = [:]
  private var order: [Key] = []
  public private(set) var cost = 0
  public let maximumCost: Int
  public let maximumCount: Int
  public var count: Int { entries.count }
  public init(maximumCost: Int, maximumCount: Int) {
    self.maximumCost = max(0, maximumCost); self.maximumCount = max(0, maximumCount)
  }
  public mutating func value(for key: Key) -> Value? {
    guard let entry = entries[key] else { return nil }
    order.removeAll { $0 == key }; order.append(key); return entry.0
  }
  @discardableResult public mutating func insert(_ value: Value, for key: Key, cost itemCost: Int)
    -> Bool
  {
    guard itemCost >= 0, itemCost <= maximumCost, maximumCount > 0 else { return false }
    if let old = entries.removeValue(forKey: key) { cost -= old.1; order.removeAll { $0 == key } }
    while !order.isEmpty && (entries.count >= maximumCount || cost + itemCost > maximumCost) {
      let victim = order.removeFirst();
      if let old = entries.removeValue(forKey: victim) { cost -= old.1 }
    }
    entries[key] = (value, itemCost); order.append(key); cost += itemCost; return true
  }
  public mutating func clear() { entries.removeAll(); order.removeAll(); cost = 0 }
}
