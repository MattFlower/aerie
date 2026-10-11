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
        var legendError: String?
        do {
          let legendURL = try WMS.legend(endpoint: kind.endpoint, layer: layer)
          let legend = try await client.data(legendURL)
          _ = try MapRaster.decode(legend, requireVisibleContent: true)
          legendValid = true
        } catch {
          legendError = String(describing: error)
        }
        if !legendValid { passed = false }
        var result: [String: Any] = [
          "layer": kind.rawValue, "validRaster": true, "legendValid": legendValid,
          "advertisedTimes": times.count, "decodedCost": raster.cost, "serviceLayer": layer.name,
          "serviceTitle": layer.title,
          "timeEnabled": layer.timeEnabled,
        ]
        if let legendError { result["legendError"] = legendError }
        results.append(result)
      } catch {
        passed = false
        results.append([
          "layer": kind.rawValue, "validRaster": false, "error": String(describing: error),
        ])
      }
    }
    do {
      let metadata = try await client.data(WMS.capabilities(WMS.baseEndpoint))
      let layer = try WMS.stateBoundaries(WMS.parse(metadata))
      let url = try WMS.image(
        endpoint: WMS.baseEndpoint, layer: layer,
        bounds: bounds, time: nil)
      let raster = try MapRaster.decode(await client.data(url), requireVisibleContent: true)
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
