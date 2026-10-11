import Foundation

/// Semantic weather categories; native views choose their own original rendering.
public enum WeatherGlyph: String {
  case clear, partlyCloudy, cloudy, fog, rain, snow, sleet, mixed, thunder, wind, tornado,
    hurricane, tropicalStorm, dust, smoke, haze, hot, cold, blizzard
}
public struct WeatherIconMetadata: Equatable {
  public let glyph: WeatherGlyph
  public let isDay: Bool
  /// Reads a recognized NWS icon identifier; never downloads or embeds an icon asset.
  public static func nws(_ source: String?) -> WeatherIconMetadata? {
    guard let source, source.utf8.count <= 1024, let url = URLComponents(string: source),
      url.scheme == "https", url.host == "api.weather.gov", url.user == nil, url.password == nil,
      url.port == nil, url.fragment == nil
    else { return nil }
    let parts = url.path.split(separator: "/").map(String.init)
    guard (4...5).contains(parts.count), parts[0] == "icons", parts[1] == "land",
      ["day", "night"].contains(parts[2])
    else { return nil }
    let codes = parts.dropFirst(3).map {
      $0.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
    }
    let catalog: [String: WeatherGlyph] = [
      "skc": .clear, "few": .partlyCloudy, "sct": .partlyCloudy, "bkn": .cloudy, "ovc": .cloudy,
      "wind_skc": .wind, "wind_few": .wind, "wind_sct": .wind, "wind_bkn": .wind, "wind_ovc": .wind,
      "snow": .snow, "rain_snow": .mixed, "rain_sleet": .mixed, "snow_sleet": .mixed,
      "fzra": .sleet, "rain_fzra": .mixed, "snow_fzra": .mixed, "sleet": .sleet,
      "rain": .rain, "rain_showers": .rain, "rain_showers_hi": .rain,
      "tsra": .thunder, "tsra_sct": .thunder, "tsra_hi": .thunder,
      "tornado": .tornado, "hurricane": .hurricane, "tropical_storm": .tropicalStorm,
      "dust": .dust, "smoke": .smoke, "haze": .haze, "hot": .hot, "cold": .cold,
      "blizzard": .blizzard, "fog": .fog,
    ]
    let glyphs = codes.compactMap { catalog[$0] }
    guard glyphs.count == codes.count, Set(glyphs).count == 1, let glyph = glyphs.first else {
      return nil
    }
    return WeatherIconMetadata(glyph: glyph, isDay: parts[2] == "day")
  }
}
