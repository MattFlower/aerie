import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class ModuleActivationTests: XCTestCase {
  func testPointerFallbackUsesDrawnSegmentsAndGapsAfterReorderAndHide() async throws {
    try await MainActor.run {
      let group = GroupedStatusView(frame: .zero)
      let descriptors = [Module.network, .gpu, .overview, .cpu].map {
        StatusWidget(
          module: $0, value: MenuValue(full: "42%"), style: .compact,
          label: .vertical, colorHex: nil)
      }
      _ = group.update(descriptors, padding: 0, gap: 2)
      var requests: [Module] = []; group.onSelect = { requests.append($0) }
      for (index, rect) in group.segments.enumerated() {
        XCTAssertTrue(group.activate(at: NSPoint(x: rect.midX, y: rect.midY)))
        XCTAssertEqual(requests.last, descriptors[index].module)
        if index < group.segments.count - 1 {
          let gap = NSPoint(x: rect.maxX + 1, y: rect.midY)
          XCTAssertNil(group.module(at: gap)); XCTAssertFalse(group.activate(at: gap))
        }
      }
      XCTAssertEqual(requests, [.network, .gpu, .overview, .cpu])
      _ = group.update(
        Array(descriptors.reversed().filter { $0.module != .overview }), padding: 0, gap: 2)
      XCTAssertEqual(group.widgets.map(\.module), [.cpu, .gpu, .network])
      XCTAssertTrue(group.activate(at: NSPoint(x: group.segments[1].midX, y: 12)))
      XCTAssertEqual(requests.last, .gpu)
      XCTAssertTrue(group.activate(at: nil)); XCTAssertEqual(requests.last, .gpu)
      group.releaseContent()
    }
  }
  func testFocusedKeyboardAndAccessibleSegmentActivationNeverDefaultsToOverview() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let group = GroupedStatusView(frame: .zero)
      _ = group.update(
        [Module.overview, .cpu, .gpu].map {
          StatusWidget(
            module: $0, value: MenuValue(full: "42%"), style: .compact,
            label: .vertical, colorHex: nil)
        }, padding: 0, gap: 2)
      var requests: [Module] = []; group.onSelect = { requests.append($0) }
      let right = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: "",
          charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
      group.keyDown(with: right); group.keyDown(with: right)
      XCTAssertTrue(group.activate(from: nil)); XCTAssertEqual(requests.last, .gpu)
      let children = try XCTUnwrap(group.accessibilityChildren() as? [NSAccessibilityElement])
      XCTAssertTrue(children[1].accessibilityPerformPress()); XCTAssertEqual(requests.last, .cpu)
      XCTAssertTrue(group.activate(from: right)); XCTAssertEqual(requests.last, .cpu)
      group.releaseContent()
    }
  }
  func testMatchingModuleTogglesWhileAnotherModuleSwitchesForEveryConfiguration() {
    for requested in Module.allCases {
      XCTAssertEqual(ModuleActivation.resolve(requested: requested, shown: nil), .show(requested))
      for shown in Module.allCases {
        XCTAssertEqual(
          ModuleActivation.resolve(requested: requested, shown: shown),
          requested == shown ? .close : .show(requested))
      }
    }
  }
}
