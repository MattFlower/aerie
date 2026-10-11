import XCTest
@testable import AerieCore

final class MapStateTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  func testRefreshPreservesVariantValidFrameAndPlaybackAcrossMetadataChanges() throws {
    let times = [-600.0, -300, 0].map { now.addingTimeInterval($0) }
    let chosen = WMSLayer(name: "band-2", title: "Synthetic band", times: times)
    var selection = MapSelection(); selection.select(kind: .satellite);
    selection.select(layer: chosen)
    try selection.reconcile(layers: [chosen], now: now)
    selection.select(frame: 1); selection.playing = true
    let changed = WMSLayer(
      name: "band-2", title: "Renamed band", times: times + [now.addingTimeInterval(60)])
    try selection.reconcile(layers: [changed], now: now.addingTimeInterval(30))
    XCTAssertEqual(selection.layer?.title, "Renamed band"); XCTAssertEqual(selection.time, times[1])
    XCTAssertTrue(selection.playing)
  }
  func testDisappearingVariantFallsBackAndExpiredFrameSelectsCurrentEligibleFrame() throws {
    var selection = MapSelection()
    selection.select(
      layer: WMSLayer(name: "removed", title: "", times: [now.addingTimeInterval(-50000)]))
    let current = WMSLayer(
      name: "conus_bref_qcd", title: "Radar", times: [now.addingTimeInterval(-60), now])
    try selection.reconcile(layers: [current], now: now)
    XCTAssertEqual(selection.layer?.name, current.name); XCTAssertEqual(selection.time, now)
    selection.playing = true
    let only = WMSLayer(name: current.name, title: "Radar", times: [now.addingTimeInterval(60)])
    try selection.reconcile(layers: [only], now: now)
    XCTAssertEqual(selection.time, now.addingTimeInterval(60)); XCTAssertFalse(selection.playing)
  }
  func testExpiredOnlyTimeEnabledLayerCannotRequestUndatedDefault() throws {
    let expired = WMSLayer(name: "old", title: "", times: [now.addingTimeInterval(-50000)])
    XCTAssertEqual(
      expired.timeline(kind: .radar, now: now), .unavailable(latestAdvertised: expired.times[0]))
    XCTAssertThrowsError(
      try WMS.image(
        endpoint: WeatherMapKind.radar.endpoint, layer: expired,
        bounds: .centered(latitude: 40, longitude: -100, span: 16), time: nil))
    let empty = WMSLayer(name: "empty", title: "", timeEnabled: true)
    XCTAssertEqual(empty.timeline(kind: .radar, now: now), .unavailable(latestAdvertised: nil))
  }
  func testTimelessProductsAndValidFutureForecastsRemainUsable() throws {
    let timeless = WMSLayer(name: "1", title: "Current alerts")
    XCTAssertEqual(timeless.timeline(kind: .alerts, now: now), .timeless)
    let future = WMSLayer(name: "temp", title: "", times: [now.addingTimeInterval(3600)])
    XCTAssertEqual(future.timeline(kind: .temperature, now: now), .frames(future.times))
    XCTAssertFalse(future.timeline(kind: .radar, now: now).available)
    let url = try WMS.image(
      endpoint: WeatherMapKind.alerts.endpoint, layer: timeless,
      bounds: .centered(latitude: 40, longitude: -100, span: 16), time: nil)
    XCTAssertFalse(
      URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.contains {
        $0.name == "TIME"
      })
  }
  func testOverlappingVisibilitySleepAndCloseEventsOnlyResumeWhenAllPermitIt() {
    var activity = MapActivity()
    XCTAssertEqual(activity.reconcile(), .unchanged)
    activity.windowVisible = true; XCTAssertEqual(activity.reconcile(), .resume)
    XCTAssertEqual(activity.reconcile(), .unchanged)
    activity.miniaturized = true; XCTAssertEqual(activity.reconcile(), .suspend)
    activity.sleeping = true; activity.miniaturized = false
    XCTAssertEqual(activity.reconcile(), .unchanged)
    activity.applicationHidden = true; activity.sleeping = false
    XCTAssertEqual(activity.reconcile(), .unchanged)
    activity.applicationHidden = false; XCTAssertEqual(activity.reconcile(), .resume)
    activity.windowVisible = false; XCTAssertEqual(activity.reconcile(), .suspend)
    activity.windowVisible = true; XCTAssertEqual(activity.reconcile(), .resume)
    activity.closed = true; XCTAssertEqual(activity.reconcile(), .suspend)
    activity.sleeping = false; activity.applicationHidden = false
    XCTAssertEqual(activity.reconcile(), .unchanged); XCTAssertFalse(activity.active)
  }
  func testTimeExtentExpansionWhitespaceDeduplicationAndHostileBounds() throws {
    let values = try XCTUnwrap(
      WMSTimeDimension.parse(
        "2026-01-01T00:00:00Z/2026-01-01T01:00:00Z/PT15M, 2026-01-01T00:30:00.000Z"))
    XCTAssertEqual(values.count, 5);
    XCTAssertEqual(values.last!.timeIntervalSince(values.first!), 3600)
    for invalid in [
      "2026-01-01T00:00:00Z/2026-01-02T00:00:00Z/PT0S",
      "2026-01-02T00:00:00Z/2026-01-01T00:00:00Z/PT1H",
      "2026-01-01T00:00:00Z/2026-01-02T00:00:00Z/PT0.001S", "invalid",
    ] {
      XCTAssertNil(WMSTimeDimension.parse(invalid))
    }
    let xml =
      "<WMS_Capabilities><Layer><CRS>EPSG:4326</CRS><Dimension name=\"time\">2026-01-01T00:00:00Z/2026-01-01T01:00:00Z/PT15M</Dimension><Layer><Name>test</Name></Layer></Layer></WMS_Capabilities>"
    let layer = try XCTUnwrap(WMS.parse(Data(xml.utf8)).first)
    XCTAssertTrue(layer.timeEnabled); XCTAssertEqual(layer.times, values)
  }
  func testAlertPreferenceIncludesWatchesAndAdvisoriesAndRejectsMissingLayer() throws {
    let layers = [
      WMSLayer(name: "0", title: "CurrentWarnings"), WMSLayer(name: "1", title: "WatchesWarnings"),
    ]
    XCTAssertEqual(try WeatherMapKind.alerts.preferred(layers).name, "1")
    XCTAssertThrowsError(try WeatherMapKind.alerts.preferred([layers[0]]))
    let reversed = [
      WMSLayer(name: "0", title: "WatchesWarnings"), WMSLayer(name: "1", title: "CurrentWarnings"),
    ]
    XCTAssertEqual(try WeatherMapKind.alerts.preferred(reversed).name, "0")
  }
  func testAggregatedTrackLayersRequireCommonSupportedProjection() {
    let layers = [
      WMSLayer(name: "a", title: "Forecast Track", crs: ["CRS:84"]),
      WMSLayer(name: "b", title: "Past Track", crs: ["EPSG:4326"]),
    ]
    XCTAssertThrowsError(try WeatherMapKind.stormTracks.preferred(layers))
  }
}
