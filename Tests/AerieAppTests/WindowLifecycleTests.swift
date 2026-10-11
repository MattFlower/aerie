import AppKit
import XCTest
@testable import AerieApp

final class WindowLifecycleTests: XCTestCase {
  func testStableOpaqueIdentityRolesAndClosingAttachmentAreRecordedWithoutTitles() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var reports: [WindowLifecycle.Report] = []
      let diagnostics = WindowLifecycle(emit: { reports.append($0) })
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false; window.title = "Private synthetic content"
      diagnostics.start(); diagnostics.register(window, role: .dashboard)
      let id = try XCTUnwrap(reports.last?.eventWindow)
      let count = reports.count
      diagnostics.register(window, role: .dashboard)
      XCTAssertEqual(reports.count, count)
      NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
      MenuPanel.releaseContent(of: window); diagnostics.capture(.tick)
      let state = try XCTUnwrap(reports.last?.windows.first { $0.id == id })
      XCTAssertEqual(state.role, .dashboard); XCTAssertTrue(state.closing)
      XCTAssertFalse(state.visible); XCTAssertFalse(state.contentAttached)
      let data = try JSONEncoder().encode(reports.last!)
      XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(window.title))
      XCTAssertGreaterThan(reports.last?.app.birth ?? 0, 0)
      XCTAssertGreaterThan(reports.last?.app.resourceIdentity ?? 0, 0)
    }
  }
  func testEventBurstIsBoundedAndDroppedCountIsExplicitOnNextExistingTick() async {
    await MainActor.run {
      _ = NSApplication.shared
      var now = 10.0
      var reports: [WindowLifecycle.Report] = []
      let diagnostics = WindowLifecycle(
        clock: { now }, resources: { StorageProcessResources(pid: 0, reaped: true) },
        emit: { reports.append($0) })
      for _ in 0..<200 { diagnostics.capture(.occlusion) }
      XCTAssertEqual(reports.count, WindowLifecycle.maximumEventsPerSecond)
      now = 11; diagnostics.capture(.tick)
      XCTAssertEqual(reports.last?.droppedEvents, 72)
      now = 12; diagnostics.capture(.tick)
      XCTAssertEqual(reports.last?.droppedEvents, 0)
      XCTAssertEqual(reports.last?.monotonicTime, 12)
    }
  }
}
