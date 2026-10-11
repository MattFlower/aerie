import Foundation
import XCTest
@testable import AerieCore
final class KeyboardShortcutTests: XCTestCase {
  func testNamedShortcutsAreExplicitNormalizedUniqueAndPortable() throws {
    let parsed = try KeyboardShortcut.parse(
      " CPU | command+option+c\nSettings | Control+Shift+Space")
    XCTAssertEqual(parsed[0].module, .cpu); XCTAssertEqual(parsed[0].key, "C")
    XCTAssertEqual(parsed[0].combination, "Command+Option+C")
    XCTAssertNil(parsed[1].module); XCTAssertEqual(parsed[1].combination, "Control+Shift+Space")
    XCTAssertEqual(try KeyboardShortcut.parse(""), [])
    for input in [
      "CPU | C", "CPU | Shift+C", "CPU | Command+Command+C", "CPU | Command+unknown",
      "Unknown | Command+C", "CPU | Command+C\nMemory | Command+C",
      "CPU | Command+C\nCPU | Control+C", "CPU | Command+C+", "CPU | Command+F21",
    ] { XCTAssertThrowsError(try KeyboardShortcut.parse(input)) }
    var settings = Settings(); XCTAssertTrue((settings.shortcuts ?? []).isEmpty)
    settings.shortcuts = parsed; XCTAssertEqual(try settings.validated(), settings)
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)), settings)
  }
}
