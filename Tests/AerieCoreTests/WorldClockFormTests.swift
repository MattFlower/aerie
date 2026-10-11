import Foundation
import XCTest
@testable import AerieCore

final class WorldClockFormTests: XCTestCase {
  func testEveryValidSpecialNameSurvivesOneLineFormattingAndParsing() throws {
    let names = [
      "Home | office", "Line\nbreak", "CR\r\nline", " tab\tname ", "Quoted \"title\"",
      "\\root\\name", "  padded  ", "Emoji 🦅", "\"Leading quote", "\"", "NEL\u{85}name",
      "Line\u{2028}name",
      "Paragraph\u{2029}name", String(repeating: "|", count: 64), "   ",
    ]
    let clocks = names.map { WorldClock(name: $0, zone: "Etc/UTC") }
    var settings = Settings(); settings.clocks = clocks
    XCTAssertEqual(try settings.validated().clocks, clocks)
    let text = try WorldClockForm.text(clocks)
    XCTAssertEqual(text.split(whereSeparator: \.isNewline).count, clocks.count)
    XCTAssertEqual(try WorldClockForm.parse(text), clocks)
    XCTAssertFalse(text.contains("\u{85}")); XCTAssertFalse(text.contains("\u{2028}"))
    XCTAssertFalse(text.contains("\u{2029}"))
  }
  func testPlainLegacyAndUserEditedNamesRemainSupportedWithTheRightmostSeparator() throws {
    let clocks = try WorldClockForm.parse(
      "UTC | Etc/UTC\r\n\nHome | office | Etc/UTC\nTokyo edited | Asia/Tokyo\n")
    XCTAssertEqual(clocks.map(\.name), ["UTC", "Home | office", "Tokyo edited"])
    XCTAssertEqual(clocks.map(\.zone), ["Etc/UTC", "Etc/UTC", "Asia/Tokyo"])
    XCTAssertEqual(
      try WorldClockForm.parse("\"Line\\nbreak\" | Etc/UTC").first?.name, "Line\nbreak")
    XCTAssertEqual(try WorldClockForm.parse("\"  padded  \" | Etc/UTC").first?.name, "  padded  ")
    XCTAssertTrue(try WorldClockForm.parse(" \n\t ").isEmpty)
  }
  func testMalformedQuotedNamesAndLiteralLineBreaksRejectTheWholeForm() {
    for text in [
      "\"Unclosed | Etc/UTC", "\"Bad\\escape\" | Etc/UTC", "\"Name\" trailing | Etc/UTC",
      "\"Line\nbreak\" | Etc/UTC", "Name without separator", "UTC | Invalid/Zone", " | Etc/UTC",
    ] {
      XCTAssertThrowsError(try WorldClockForm.parse(text), text)
    }
  }
  func testModelAndFormEnforceMatchingNameClockAndInputBounds() {
    let tooLong = WorldClock(name: String(repeating: "a", count: 65), zone: "Etc/UTC")
    XCTAssertFalse(WorldClockForm.valid([tooLong]));
    XCTAssertThrowsError(try WorldClockForm.text([tooLong]))
    XCTAssertThrowsError(try WorldClockForm.parse(tooLong.name + " | Etc/UTC"))
    let tooMany = Array(repeating: WorldClock(name: "UTC", zone: "Etc/UTC"), count: 21)
    XCTAssertFalse(WorldClockForm.valid(tooMany));
    XCTAssertThrowsError(try WorldClockForm.text(tooMany))
    XCTAssertThrowsError(
      try WorldClockForm.parse(Array(repeating: "UTC | Etc/UTC", count: 21).joined(separator: "\n"))
    )
    XCTAssertThrowsError(
      try WorldClockForm.parse(String(repeating: " ", count: WorldClockForm.maximumFormBytes + 1)))
    let pathological = WorldClock(
      name: "a" + String(repeating: "\u{301}", count: 3000), zone: "Etc/UTC")
    XCTAssertEqual(pathological.name.count, 1); XCTAssertFalse(WorldClockForm.valid([pathological]))
    XCTAssertThrowsError(try WorldClockForm.text([pathological]))
    var invalid = Settings(); invalid.clocks = [tooLong]
    XCTAssertThrowsError(try invalid.validated())
  }
  func testMaximumUnicodeNamesAndFullInventoryRoundTripWithinTheDeclaredFormBound() throws {
    let name = "a" + String(repeating: "\u{301}", count: 2047)
    XCTAssertLessThanOrEqual(name.utf8.count, WorldClockForm.maximumNameBytes)
    let clocks = Array(repeating: WorldClock(name: name, zone: "Etc/UTC"), count: 20)
    XCTAssertTrue(WorldClockForm.valid(clocks))
    let text = try WorldClockForm.text(clocks)
    XCTAssertGreaterThan(text.utf8.count, 65_536)
    XCTAssertLessThanOrEqual(text.utf8.count, WorldClockForm.maximumFormBytes)
    XCTAssertEqual(try WorldClockForm.parse(text), clocks)
    for zone in TimeZone.knownTimeZoneIdentifiers {
      XCTAssertLessThanOrEqual(zone.utf8.count, WorldClockForm.maximumZoneBytes)
    }
  }

}
