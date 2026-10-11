import Foundation
import XCTest
@testable import AerieCore

final class SolarDayTests: XCTestCase {
  private func point(latitude: Double = 0, longitude: Double = 0, zone: String = "Etc/UTC")
    -> DaylightConfiguration
  {
    var value = DaylightConfiguration(); value.enabled = true; value.name = "Synthetic point"
    value.latitude = latitude; value.longitude = longitude; value.zone = zone; return value
  }
  private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
  func testPublishedMathematicalReferenceAgreesWithinOneMinute() throws {
    // Computed reference, not observations or a user location. NOAA's published day worksheet:
    // https://gml.noaa.gov/grad/solcalc/NOAA_Solar_Calculations_day.ods
    let day = try XCTUnwrap(
      SolarDay.make(
        date: date("2010-06-21T12:00:00Z"),
        configuration: point(latitude: 40, longitude: -105, zone: "Etc/GMT+7")))
    XCTAssertEqual(
      day.boundaries[0].rises[0].timeIntervalSince(day.interval.start), 16276.4236, accuracy: 60)
    XCTAssertEqual(
      day.boundaries[0].sets[0].timeIntervalSince(day.interval.start), 70329.4205, accuracy: 60)
    XCTAssertEqual(day.transits[0].timeIntervalSince(day.interval.start), 43302.9221, accuracy: 60)
    XCTAssertEqual(day.boundaries[0].secondsAbove, 54052.9968, accuracy: 60)
  }
  func testSyntheticEquatorEquinoxGeometryAndTwilightOrdering() throws {
    let day = try XCTUnwrap(
      SolarDay.make(date: date("2026-03-20T12:00:00Z"), configuration: point()))
    let daylight = day.boundaries[0]
    XCTAssertEqual(daylight.rises.count, 1); XCTAssertEqual(daylight.sets.count, 1)
    XCTAssertEqual(
      daylight.rises[0].timeIntervalSince(day.interval.start), 6 * 3600, accuracy: 1800)
    XCTAssertEqual(
      daylight.sets[0].timeIntervalSince(day.interval.start), 18 * 3600, accuracy: 1800)
    XCTAssertEqual(daylight.secondsAbove, 12 * 3600, accuracy: 1200)
    XCTAssertEqual(day.transits.count, 1)
    for (inner, outer) in zip(day.boundaries, day.boundaries.dropFirst()) {
      XCTAssertLessThan(outer.rises[0], inner.rises[0]);
      XCTAssertGreaterThan(outer.sets[0], inner.sets[0])
      XCTAssertGreaterThan(outer.secondsAbove, inner.secondsAbove)
    }
  }
  func testSeasonalHemispheresAndTruePolarDayNightAreDistinctFromMissingData() throws {
    let summer = date("2026-06-21T12:00:00Z"), winter = date("2026-12-21T12:00:00Z")
    let northSummer = try XCTUnwrap(SolarDay.make(date: summer, configuration: point(latitude: 45)))
    let northWinter = try XCTUnwrap(SolarDay.make(date: winter, configuration: point(latitude: 45)))
    XCTAssertGreaterThan(northSummer.boundaries[0].secondsAbove, 15 * 3600)
    XCTAssertLessThan(northWinter.boundaries[0].secondsAbove, 9 * 3600)
    let southSummer = try XCTUnwrap(
      SolarDay.make(date: summer, configuration: point(latitude: -45)))
    XCTAssertLessThan(southSummer.boundaries[0].secondsAbove, 9 * 3600)
    let light = try XCTUnwrap(SolarDay.make(date: summer, configuration: point(latitude: 90)))
    let dark = try XCTUnwrap(SolarDay.make(date: winter, configuration: point(latitude: 90)))
    XCTAssertEqual(light.boundaries[0].state, .continuousAbove)
    XCTAssertEqual(light.boundaries[0].secondsAbove, light.interval.duration, accuracy: 0.01)
    XCTAssertTrue(light.boundaries[0].rises.isEmpty);
    XCTAssertTrue(light.boundaries[0].sets.isEmpty)
    XCTAssertEqual(dark.boundaries[0].state, .continuousBelow);
    XCTAssertEqual(dark.boundaries[0].secondsAbove, 0)
  }
  func testLocalDaysFollowDSTAndCrossingDatesStayWithinTheirOwnDay() throws {
    for (instant, duration) in [
      ("2026-03-08T12:00:00Z", 82800.0), ("2026-11-01T12:00:00Z", 90000.0),
    ] {
      let day = try XCTUnwrap(
        SolarDay.make(date: date(instant), configuration: point(zone: "America/New_York")))
      XCTAssertEqual(day.interval.duration, duration)
      for boundary in day.boundaries {
        XCTAssertGreaterThanOrEqual(boundary.secondsAbove, 0);
        XCTAssertLessThanOrEqual(boundary.secondsAbove, duration)
        for event in boundary.rises + boundary.sets {
          XCTAssertGreaterThanOrEqual(event, day.interval.start);
          XCTAssertLessThan(event, day.interval.end)
        }
      }
    }
  }
  func testAntimeridianLeapDayAndNonHourTimezoneRemainAbsoluteInstants() throws {
    for (longitude, zone) in [
      (179.99, "Pacific/Kiritimati"), (-179.99, "Etc/GMT+12"), (86.25, "Asia/Kathmandu"),
    ] {
      let day = try XCTUnwrap(
        SolarDay.make(
          date: date("2024-02-29T12:00:00Z"), configuration: point(longitude: longitude, zone: zone)
        ))
      XCTAssertEqual(day.boundaries[0].rises.count, 1);
      XCTAssertEqual(day.boundaries[0].sets.count, 1)
      XCTAssertEqual(day.transits.count, 1)
      for event in day.boundaries.flatMap({ $0.rises + $0.sets }) + day.transits {
        XCTAssertGreaterThanOrEqual(event, day.interval.start);
        XCTAssertLessThan(event, day.interval.end)
      }
    }
  }
  func testRefinedExtremaCatchBriefCrossingsBetweenGridPointsIncludingDayEdges() {
    for center in [10.0, 150.0, 43210.0, 86390.0] {
      let samples = SolarCurve.samples(duration: 86400) { time in
        0.0001 - pow((time - center) / 1000, 2)
      }
      XCTAssertLessThan(samples.count, 400)
      XCTAssertTrue(samples.contains { $0.value > 0 })
      XCTAssertTrue(zip(samples, samples.dropFirst()).contains { ($0.value < 0) != ($1.value < 0) })
    }
    var calls = 0
    let flat = SolarCurve.samples(duration: 86400) { _ in
      calls += 1; return 1
    }
    XCTAssertLessThan(flat.count, 400); XCTAssertLessThan(calls, 1000)
  }
  func testDisabledMalformedAndUnsupportedDatesNeverProduceEstimatedEvents() throws {
    var disabled = point(); disabled.enabled = false
    XCTAssertNil(SolarDay.make(date: date("2026-03-20T12:00:00Z"), configuration: disabled))
    for configuration in [
      point(latitude: 91), point(longitude: .nan), point(zone: "Invalid/Fixture"),
    ] {
      XCTAssertNil(SolarDay.make(date: date("2026-03-20T12:00:00Z"), configuration: configuration))
      var settings = Settings(); settings.daylight = configuration;
      XCTAssertThrowsError(try settings.validated())
    }
    XCTAssertNil(SolarDay.make(date: Date(timeIntervalSince1970: .nan), configuration: point()))
    XCTAssertNil(SolarDay.make(date: date("2100-03-20T12:00:00Z"), configuration: point()))
    var settings = Settings(); settings.daylight = disabled
    XCTAssertNil(try settings.validated().daylight)
    XCTAssertNil(Settings().daylight)
    settings.daylight = point()
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings.validated()))
        .daylight, point())
  }
}
