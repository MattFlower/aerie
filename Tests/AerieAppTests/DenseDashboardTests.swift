import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class DenseDashboardTests: XCTestCase {
  func testPickerSelectionUpdatesWindowDescriptionAlongWithTheVisibleModule() async {
    await MainActor.run {
      _ = NSApplication.shared
      let controller = DashboardController()
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 416, height: 600),
        styleMask: [], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = controller
      for module in [Module.cpu, .gpu, .memory, .overview] {
        controller.modules.selectItem(at: Module.allCases.firstIndex(of: module)!)
        _ = controller.modules.sendAction(controller.modules.action, to: controller.modules.target)
        XCTAssertEqual(controller.module, module)
        XCTAssertEqual(window.accessibilityLabel(), "Aerie \(module.title) detail")
      }
      MenuPanel.releaseContent(of: window); controller.releasePresentation()
    }
  }
  func testRelativeAxesRetainSecondsAndNotesGrowToPreserveTheirFullText() {
    XCTAssertEqual(relativeHistorySpan(19), "19s")
    XCTAssertEqual(relativeHistorySpan(599), "9m 59s")
    XCTAssertEqual(relativeHistorySpan(3600), "1h 0m")
    XCTAssertEqual(relativeHistorySpan(604800), "7d 0h")
    XCTAssertEqual(relativeHistorySpan(.nan), "Unavailable")
    let short = DashboardRow.note("Short source note")
    let long = DashboardRow.note(
      String(repeating: "A complete accounting description with readable words. ", count: 20))
    XCTAssertGreaterThan(long.height, short.height * 4)
  }
  @MainActor private func fixture() -> DashboardController {
    let controller = DashboardController(); _ = controller.view
    controller.snapshot.cpu = CPUData(
      user: 0.11, system: 0.06,
      cores: (0..<18).map { Double($0) / 30 }, groups: [("Group A", 6), ("Group B", 12)],
      load: [1.1, 1.2, 1.3], uptime: 86400, frequency: 2.4)
    controller.snapshot.gpu = [
      GPUData(
        name: "Synthetic GPU", utilization: 0.25,
        renderer: 0.2, tiler: 0.1, memory: 512 * 1024 * 1024)
    ]
    controller.snapshot.processes = (0..<7).map { index in
      ProcessData(
        pid: index + 1, name: "Synthetic process \(index + 1)", cpu: Double(7 - index) / 100,
        memory: Double(index + 1) * 1024 * 1024, read: 1024, write: 2048, wakeups: 1)
    }
    controller.snapshot.memory = MemoryData(
      validity: .fresh, total: 16 * 1073741824, app: 6 * 1073741824,
      wired: 2 * 1073741824, compressed: 1073741824, free: 3 * 1073741824,
      cached: 4 * 1073741824, pressure: "Normal", usedFraction: 0.61)
    controller.snapshot.volumes = [
      VolumeData(
        name: "Synthetic storage", path: "/Synthetic", total: 512 * 1073741824,
        free: 256 * 1073741824, removable: false, local: true, readOnly: false)
    ]
    controller.snapshot.diskRead = 12 * 1048576; controller.snapshot.diskWrite = 4 * 1048576
    controller.snapshot.networkAvailable = true; controller.snapshot.connectivity = "Connected"
    controller.snapshot.interfaces = [
      InterfaceData(
        name: "en9", active: true, addresses: "203.0.113.7",
        received: 1000, sent: 2000, download: 5 * 1048576, upload: 2 * 1048576, errors: 0)
    ]
    controller.snapshot.sensors = [
      SensorData(key: "TEST", label: "Synthetic temperature", value: 42, unit: "°C")
    ]
    controller.snapshot.power = PowerData(
      source: "Battery Power", present: true, percent: 0.8,
      charging: false, external: false, minutes: 120, health: 0.95, cycles: 100, watts: 12,
      voltage: 12, amperage: 1)
    controller.settings.processCount = 7
    for index in 0..<20 {
      controller.history.append(
        .init(
          date: Date(timeIntervalSince1970: 1700000000 + Double(index)),
          values: ["cpu": Double(index), "gpu": Double(index * 2), "memory": 61]))
    }
    return controller
  }
  func testCPUUsefulContentFitsBeforeAdvancedTelemetryAndPreservesAdditionalProcesses() async throws
  {
    try await MainActor.run {
      let controller = fixture(); controller.show(.cpu)
      let rows = controller.canvas.rows
      let viewport = try XCTUnwrap(controller.canvas.enclosingScrollView).contentSize.height
      var y: CGFloat = 8; var processCount = 0; var gpuBeforeFooter = false; var foundFooter = false
      for row in rows {
        if case .metric(let key, _) = row, key.hasPrefix("Synthetic process") { processCount += 1 }
        if case .heading(let title) = row, title == "GPU · Synthetic GPU" {
          XCTAssertEqual(processCount, 5); gpuBeforeFooter = true
        }
        y += row.height
        if case .facts(let items) = row, items.contains(where: { $0.0 == "Uptime" }) {
          XCTAssertTrue(gpuBeforeFooter); XCTAssertLessThanOrEqual(y, viewport); foundFooter = true
        }
      }
      XCTAssertTrue(foundFooter); XCTAssertEqual(processCount, 7)
      guard case .trend(let title, let detail, _) = rows.first else {
        return XCTFail("CPU trend first")
      }
      XCTAssertEqual(title, "CPU 17%"); XCTAssertTrue(detail.contains("User 11%"))
      XCTAssertTrue(detail.contains("System 6%"))
      XCTAssertFalse(
        rows.contains {
          if case .gauge("Total", _, _, _) = $0 { return true }; return false
        })
      controller.releasePresentation()
    }
  }
  func testGPUIsDistinctKeepsSupportedFieldsAndHidesUnknownOptionalReadings() async {
    await MainActor.run {
      let controller = fixture(); controller.show(.gpu)
      guard case .trend(let title, _, let series) = controller.canvas.rows.first else {
        return XCTFail("GPU utilization first")
      }
      XCTAssertEqual(title, "GPU 25%"); XCTAssertEqual(series.map(\.key), ["gpu"])
      @MainActor func facts() -> [(String, String)] {
        controller.canvas.rows.flatMap {
          if case .facts(let items) = $0 { return items }; return []
        }
      }
      XCTAssertFalse(
        facts().contains { ["Temperature", "Frequency", "Frame rate"].contains($0.0) })
      XCTAssertTrue(facts().contains { $0.0 == "CPU total" && $0.1 == "17%" })
      controller.snapshot.gpu[0].temperature = 45; controller.snapshot.gpu[0].frequency = 0.8
      controller.snapshot.gpu[0].fps = 60; controller.refresh()
      XCTAssertTrue(facts().contains { $0.0 == "Temperature" && $0.1.contains("45") })
      XCTAssertTrue(facts().contains { $0.0 == "Frequency" && $0.1.contains("0.80 GHz") })
      XCTAssertTrue(facts().contains { $0.0 == "Frame rate" && $0.1 == "60 FPS" })
      controller.releasePresentation()
    }
  }
  func testSecondaryToolsDoNotResetSelectionAcrossSamplesAndChartRemainsAccessible() async throws {
    try await MainActor.run {
      let controller = fixture(); controller.show(.cpu)
      let collapsed = try XCTUnwrap(controller.canvas.enclosingScrollView).contentSize.height
      XCTAssertTrue(controller.zoomPicker.isHidden)
      controller.setHistoryExpanded(true)
      XCTAssertFalse(controller.zoomPicker.isHidden)
      XCTAssertLessThan(
        try XCTUnwrap(controller.canvas.enclosingScrollView).contentSize.height, collapsed)
      controller.windowPicker.selectItem(at: 0); controller.zoomPicker.selectItem(at: 2)
      controller.historyPosition.doubleValue = 0.3; controller.refresh()
      let old = controller.displayedHistory
      controller.snapshot.cpu.user = 0.2; controller.refresh()
      XCTAssertEqual(controller.displayedHistory.map(\.date), old.map(\.date))
      XCTAssertEqual(controller.displayedHistory.map(\.values), old.map(\.values))
      XCTAssertEqual(controller.zoomPicker.indexOfSelectedItem, 2)
      XCTAssertEqual(controller.historyPosition.doubleValue, 0.3)
      let chart = try XCTUnwrap(
        controller.canvas.accessibilityChildren()?.first as? NSAccessibilityElement)
      XCTAssertTrue(chart.accessibilityPerformPress())
      XCTAssertTrue(chart.accessibilityLabel()?.contains("Selected") == true)
      controller.setHistoryExpanded(false)
      XCTAssertEqual(
        try XCTUnwrap(controller.canvas.enclosingScrollView).contentSize.height, collapsed)
      controller.releasePresentation()
    }
  }
  func testSyntheticNativePanelsRenderAtLaptopSizeInBothAppearances() async throws {
    try await MainActor.run {
      let controller = fixture()
      for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        for module in [Module.cpu, .gpu, .memory, .storage, .network, .power, .time, .sensors] {
          controller.show(module); controller.view.appearance = NSAppearance(named: appearance)
          let image = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
          controller.view.cacheDisplay(in: controller.view.bounds, to: image)
          let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
          XCTAssertGreaterThan(png.count, 1000)
          if let directory = ProcessInfo.processInfo.environment["AERIE_DETAIL_FIXTURE_DIRECTORY"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(
              to: url.appendingPathComponent(module.rawValue + "-" + appearance.rawValue + ".png"))
          }
        }
      }
      controller.releasePresentation()
    }
  }
}
