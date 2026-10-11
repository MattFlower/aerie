import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class DashboardAccessibilityTests: XCTestCase {
  func testFullInventoryRemainsAccessibleAndCloseReleasesItsDocumentExtent() throws {
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
    let rows = (0..<600).map { DashboardRow.metric("Synthetic sensor \($0)", "42 °C") }
    view.update(rows: rows, points: [])
    let elements = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertEqual(elements.count, 600)
    XCTAssertEqual(elements.first?.accessibilityLabel(), "Synthetic sensor 0: 42 °C")
    XCTAssertEqual(elements.last?.accessibilityLabel(), "Synthetic sensor 599: 42 °C")
    XCTAssertGreaterThan(view.frame.height, 10_000)
    view.releaseInteractiveRows()
    XCTAssertLessThan(view.frame.height, 100)
    XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
    XCTAssertTrue(elements.allSatisfy { $0.accessibilityParent() == nil })
    view.update(rows: [.metric("CPU", "10%")], points: [])
    XCTAssertEqual(view.accessibilityChildren()?.count, 1)
    XCTAssertLessThan(view.frame.height, 100)
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
