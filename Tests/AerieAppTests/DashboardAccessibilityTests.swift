import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class DashboardAccessibilityTests: XCTestCase {
  func testFullInventoryRemainsAccessibleAndCloseReleasesItsDocumentExtent() throws {
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
    let rows = (0..<600).map { DashboardRow.metric("Synthetic sensor \($0)", "42 °C") }
    view.update(rows: rows, points: [])
    let groups = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertEqual(groups.count, 10)
    XCTAssertTrue(groups.allSatisfy { ($0.accessibilityChildren()?.count ?? 0) <= 64 })
    let elements = try XCTUnwrap(
      groups.flatMap { $0.accessibilityChildren() ?? [] } as? [NSAccessibilityElement])
    XCTAssertEqual(elements.count, 600)
    XCTAssertEqual(elements.first?.accessibilityLabel(), "Synthetic sensor 0: 42 °C")
    XCTAssertEqual(elements.last?.accessibilityLabel(), "Synthetic sensor 599: 42 °C")
    XCTAssertGreaterThan(view.frame.height, 10_000)
    view.releaseInteractiveRows()
    XCTAssertLessThan(view.frame.height, 100)
    XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
    XCTAssertTrue(elements.allSatisfy { $0.accessibilityParent() == nil })
    XCTAssertTrue(
      groups.allSatisfy {
        $0.accessibilityParent() == nil && $0.accessibilityChildren()?.isEmpty == true
      })
    view.update(rows: [.metric("CPU", "10%")], points: [])
    XCTAssertEqual(view.accessibilityChildren()?.count, 1)
    XCTAssertLessThan(view.frame.height, 100)
  }
  func testLongHierarchyReusesGroupsAndRowsAndShrinksWithoutRetainingRemovedParents() throws {
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
    view.update(rows: (0..<200).map { .metric("Sensor \($0)", "10") }, points: [])
    let groups = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
    let first = try XCTUnwrap(groups[0].accessibilityChildren()?.first as? NSAccessibilityElement)
    let last = try XCTUnwrap(groups.last?.accessibilityChildren()?.last as? NSAccessibilityElement)
    view.update(rows: (0..<200).map { .metric("Sensor \($0)", "20") }, points: [])
    let next = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertTrue(groups[0] === next[0])
    XCTAssertTrue(first === next[0].accessibilityChildren()?.first as? NSAccessibilityElement)
    XCTAssertEqual(first.accessibilityLabel(), "Sensor 0: 20")
    view.update(rows: [.metric("Sensor 0", "30")], points: [])
    XCTAssertTrue(first.accessibilityParent() as? DashboardView === view)
    XCTAssertNil(last.accessibilityParent())
    XCTAssertTrue(
      groups.allSatisfy {
        $0.accessibilityParent() == nil && $0.accessibilityChildren()?.isEmpty == true
      })
  }
  func testLongDocumentRootReportsViewportAndVisibleGroupsAfterScroll() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 416, height: 490), styleMask: [], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 416, height: 490))
      let view = DashboardView(frame: scroll.bounds)
      window.contentView = scroll; scroll.documentView = view
      let rows = (0..<600).map { DashboardRow.metric("Sensor \($0)", "42 °C") }
      view.update(rows: rows, points: [])
      XCTAssertEqual(view.accessibilityFrame().height, view.visibleRect.height)
      XCTAssertLessThan(view.accessibilityFrame().height, 500)
      XCTAssertTrue(view.isAccessibilityElement())
      let first = try XCTUnwrap(
        view.accessibilityVisibleChildren()?.first as? NSAccessibilityElement)
      XCTAssertEqual(first.accessibilityLabel(), "Statistics rows 1–64")
      scroll.contentView.scroll(to: NSPoint(x: 0, y: 8000))
      scroll.reflectScrolledClipView(scroll.contentView); view.update(rows: rows, points: [])
      let later = try XCTUnwrap(
        view.accessibilityVisibleChildren()?.first as? NSAccessibilityElement)
      XCTAssertNotEqual(first.accessibilityLabel(), later.accessibilityLabel())
      XCTAssertEqual(view.accessibilityChildren()?.count, 10)
      view.releaseInteractiveRows(); MenuPanel.releaseContent(of: window)
    }
  }
  func testLiveMetricAndChartElementsKeepIdentityAndUpdateTheirValues() throws {
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
    let points = [
      HistoryPoint(date: Date(timeIntervalSince1970: 100), values: ["cpu": 10]),
      HistoryPoint(date: Date(timeIntervalSince1970: 101), values: ["cpu": 20]),
      HistoryPoint(date: Date(timeIntervalSince1970: 102), values: ["cpu": 30]),
    ]
    let rows: [DashboardRow] = [.metric("CPU", "10%"), .chart("cpu", "CPU %", .blue, 100)]
    view.update(rows: rows, points: points)
    let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertEqual(children.count, 2)
    view.update(rows: [.metric("CPU", "20%"), rows[1]], points: points)
    let next = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertTrue(children[0] === next[0]); XCTAssertTrue(children[1] === next[1])
    XCTAssertEqual(next[0].accessibilityLabel(), "CPU: 20%")
    XCTAssertTrue(next[1].accessibilityPerformPress())
    XCTAssertEqual(view.selectedPoint?.date, points[1].date)
    XCTAssertTrue(next[1].accessibilityLabel()?.contains("20.00") == true)
    XCTAssertEqual(next[1].accessibilityRole(), .button)
    XCTAssertTrue(next[1].isAccessibilityEnabled())
    view.releaseInteractiveRows()
    XCTAssertTrue(view.points.isEmpty); XCTAssertNil(view.selectedPoint)
    XCTAssertNil(next[1].accessibilityParent())
    XCTAssertFalse(next[1].accessibilityPerformPress())
  }
  func testChangingRowKindsReplacesOnlyThatElementAndReleasesOldParent() throws {
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
    view.update(rows: [.chart("cpu", "CPU %", .blue, 100)], points: [])
    let chart = try XCTUnwrap(view.accessibilityChildren()?.first as? NSAccessibilityElement)
    view.update(rows: [.metric("Charge", "80%")], points: [])
    let metric = try XCTUnwrap(view.accessibilityChildren()?.first as? NSAccessibilityElement)
    XCTAssertFalse(chart === metric); XCTAssertNil(chart.accessibilityParent())
    XCTAssertEqual(metric.accessibilityRole(), .staticText)
    view.update(rows: [], points: [])
    XCTAssertNil(metric.accessibilityParent());
    XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
    XCTAssertFalse(view.selectHistory(fraction: .nan))
  }
}
