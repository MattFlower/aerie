import Foundation
import XCTest
@testable import AerieCore

final class EventCalendarSelectionTests: XCTestCase {
  func testAllNoneAndExplicitSelectionRemainDistinctThroughSavedSettings() throws {
    for identifiers in [nil, [], ["fixture-primary", "fixture-secondary"]] as [[String]?] {
      var settings = Settings(); settings.eventCalendars = identifiers
      let data = try JSONEncoder().encode(settings.validated())
      XCTAssertEqual(
        try JSONDecoder().decode(Settings.self, from: data).eventCalendars, identifiers)
    }
    var object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
    object.removeValue(forKey: "eventCalendars")
    let legacy = try JSONDecoder().decode(
      Settings.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.eventCalendars)
  }
  func testInvalidDuplicateUnboundedOrControlIdentifiersAreRejected() {
    for identifiers in [
      [""], [" fixture"], ["fixture\nvalue"], ["fixture", "fixture"],
      [String(repeating: "x", count: 513)], (0..<129).map { "fixture-\($0)" },
    ] {
      XCTAssertFalse(EventCalendarSelection.valid(identifiers))
      var settings = Settings(); settings.eventCalendars = identifiers
      XCTAssertThrowsError(try settings.validated())
    }
    XCTAssertTrue(EventCalendarSelection.valid((0..<128).map { "fixture-\($0)" }))
  }
}
