import AerieCore
import AppKit

/// An explicit developer command using a fixed public CONUS extent, never saved user settings.
enum MapIntegration {
  @MainActor static func run() async -> Int32 {
    let client = MapHTTPClient(); defer { client.close() }
    let bounds = MapBounds(west: -125, south: 24, east: -66, north: 50)
    var results: [[String: Any]] = []
    var passed = true
    for kind in WeatherMapKind.allCases {
      do {
        let data = try await client.data(WMS.capabilities(kind.endpoint))
        let layers = try WMS.parse(data); let layer = try kind.preferred(layers)
        let timeline = layer.timeline(kind: kind, now: Date())
        guard timeline.available else { throw MapError.unavailableLayer }
        let times = timeline.times
        let time = kind.forecast ? times.first : times.last
        let url = try WMS.image(endpoint: kind.endpoint, layer: layer, bounds: bounds, time: time)
        let raster = try MapRaster.decode(await client.data(url))
        var legendValid = false
        do {
          let legendURL = try WMS.legend(endpoint: kind.endpoint, layer: layer)
          if let legend = try? await client.data(legendURL) {
            legendValid = (try? MapRaster.decode(legend)) != nil
          }
        }
        if !legendValid { passed = false }
        results.append([
          "layer": kind.rawValue, "validRaster": true, "legendValid": legendValid,
          "advertisedTimes": times.count, "decodedCost": raster.cost, "serviceLayer": layer.name,
          "serviceTitle": layer.title,
          "timeEnabled": layer.timeEnabled,
        ])
      } catch {
        passed = false
        results.append([
          "layer": kind.rawValue, "validRaster": false, "error": String(describing: error),
        ])
      }
    }
    do {
      let url = try WMS.image(
        endpoint: WMS.baseEndpoint, layer: WMSLayer(name: "3", title: "NWS boundaries"),
        bounds: bounds, time: nil)
      let raster = try MapRaster.decode(await client.data(url))
      results.append(["layer": "boundaries", "validRaster": true, "decodedCost": raster.cost])
    } catch { passed = false; results.append(["layer": "boundaries", "validRaster": false]) }
    do {
      let data = try await client.data(WeatherAlerts.request(latitude: 40, longitude: -100))
      let report = try WeatherAlerts.parse(data, fetched: Date())
      results.append([
        "layer": "pointAlertDetails", "validMetadata": true, "messageCount": report.alerts.count,
        "moreAvailable": report.moreAvailable,
      ])
    } catch {
      passed = false;
      results.append([
        "layer": "pointAlertDetails", "validMetadata": false,
        "error": String(describing: error),
      ])
    }
    let output: [String: Any] = [
      "fixture": "fixed public CONUS extent", "usedUserSettings": false, "results": results,
      "passed": passed,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      print(text)
    }
    return passed ? 0 : 1
  }
}
