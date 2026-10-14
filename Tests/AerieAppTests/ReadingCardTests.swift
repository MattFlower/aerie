@testable import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class ReadingCardTests: XCTestCase {
  private func fixture() -> Snapshot {
    var s = Snapshot(); s.date = Date(timeIntervalSince1970: 1715695200)
    s.cpu = CPUData(
      user: 0.1, system: 0.07, cores: [0, 0.2, 0.5], groups: [("Synthetic group", 3)],
      load: [1, 2, 3], uptime: 86400, frequency: 2.4)
    s.gpu = [
      GPUData(name: "Synthetic GPU", utilization: 0.25, renderer: 0.2, tiler: 0.1, memory: 1048576)
    ]
    s.memory = MemoryData(
      validity: .fresh, total: 16 * 1073741824, app: 6 * 1073741824, wired: 2 * 1073741824,
      compressed: 1073741824, free: 3 * 1073741824, cached: 4 * 1073741824, purgeable: 1073741824,
      swap: 1048576, swapTotal: 1073741824, pressure: "Normal", usedFraction: 0.61, pageIn: 1024,
      pageOut: 2048, swapIn: 4096, swapOut: 8192)
    s.volumes = [
      VolumeData(
        name: "Synthetic storage", path: "/Synthetic", total: 512 * 1073741824,
        free: 256 * 1073741824, important: 300 * 1073741824, removable: false, local: true,
        readOnly: true)
    ]
    s.interfaces = [
      InterfaceData(
        name: "en9", active: true, addresses: "203.0.113.7", received: 1000000, sent: 2000000,
        download: 1048576, upload: nil, errors: 0)
    ]
    s.wifi = WiFiReading(
      interface: "en9", powered: true, mode: .station, signal: -60, noise: -90, rate: 150,
      channel: 10, ssid: "Synthetic-private-identity", bssid: "02:00:00:00:00:01", country: "US",
      authorization: .authorized, fetched: s.date)
    let battery = PowerSourceReading(
      name: "Synthetic battery", kind: .internalBattery, transport: "Internal", present: true,
      input: .battery, charging: false, current: 80, maximum: 100, minutes: 120, voltage: 12,
      amperage: -1, temperature: 30)
    s.power = PowerData(
      inventory: PowerSourceInventory(sources: [battery], available: true, reportedCount: 1),
      source: "Battery Power", present: true, percent: 0.8, charging: false, external: false,
      minutes: 120, health: 0.95, cycles: 100, watts: 12, voltage: 12, amperage: -1,
      peripherals: [("Synthetic peripheral", 0.6)])
    return s
  }
  func testMemoryDetailsPreserveAllValuesWithoutTreatingCategoriesAsAnExhaustivePartition() throws {
    let s = fixture();
    let model = try XCTUnwrap(ReadingDetails.make(.memory, snapshot: s, settings: .init()))
    let fields = model.sections.flatMap(\.facts)
    for key in [
      "App", "Wired", "Compressed", "File cache", "Physical", "Free", "Purgeable",
      "Swap used / total", "Page in", "Page out", "Swap in", "Swap out",
    ] { XCTAssertNotNil(fields.first { $0.label == key }) }
    XCTAssertTrue(model.fullText.contains("not a partition"));
    XCTAssertTrue(model.fullText.contains("Used-memory percentage is not memory-pressure"))
    XCTAssertEqual(model.sections.first?.bars.first?.1, 6.0 / 16.0)
  }
  func testInterfaceVolumeAndPowerDetailsKeepMissingScopeAndRawCountersHonest() throws {
    let s = fixture()
    let interface = try XCTUnwrap(
      ReadingDetails.make(.interface("en9"), snapshot: s, settings: .init()))
    XCTAssertEqual(interface.highlights[1].value, "Unavailable")
    XCTAssertTrue(interface.fullText.contains("Received raw bytes: 1000000"))
    XCTAssertTrue(interface.fullText.contains("203.0.113.7"))
    let volume = try XCTUnwrap(ReadingDetails.make(.volume(0), snapshot: s, settings: .init()))
    XCTAssertTrue(volume.fullText.contains("300 GiB"));
    XCTAssertTrue(volume.fullText.contains("Read only"));
    XCTAssertTrue(volume.diagnostics.contains("/Synthetic"))
    let source = try XCTUnwrap(ReadingDetails.make(.powerSource(0), snapshot: s, settings: .init()))
    XCTAssertTrue(source.fullText.contains("Internal battery"));
    XCTAssertTrue(source.fullText.contains("30.0°C"))
    XCTAssertNil(ReadingDetails.make(.volume(10), snapshot: s, settings: .init()))
  }
  func testCapturedWiFiRadioRetainsNoIdentityAndProcessDoesNotLookupReusedPID() throws {
    var s = fixture()
    let radio = try XCTUnwrap(ReadingDetails.make(.wifi, snapshot: s, settings: .init()))
    XCTAssertFalse(radio.fullText.contains("Synthetic-private-identity"));
    XCTAssertFalse(radio.fullText.contains("02:00:00:00:00:01"))
    let original = ProcessData(
      pid: 42, name: "Original captured process", cpu: 0.2, memory: 1048576, read: nil, write: 1024,
      wakeups: 1)
    s.processes = [ProcessData(pid: 42, name: "Reused PID process", cpu: 0.9, memory: 4096)]
    let process = try XCTUnwrap(
      ReadingDetails.make(.process(original), snapshot: s, settings: .init()))
    XCTAssertEqual(process.title, "Original captured process");
    XCTAssertFalse(process.fullText.contains("Reused PID process"))
  }
  func testVirtualCardsPressScrollAndReleaseWithoutAddingPerRowViews() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let canvas = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 530))
      let rows: [DashboardRow] = (0..<1024).map {
        .reading(
          ReadingCard(
            title: "Synthetic volume \($0)", subtitle: "Volume details", symbol: "internaldrive",
            facts: [("Capacity", "1 GiB")], target: .volume($0)))
      }
      canvas.update(rows: rows, points: [])
      XCTAssertTrue(canvas.subviews.isEmpty)
      var selected: String?; canvas.onAction = { selected = $0 }
      XCTAssertTrue(canvas.activateReading(1000)); XCTAssertEqual(selected, "reading:1000")
      XCTAssertGreaterThan(canvas.rowRect(1000).minY, canvas.rowRect(1).minY)
      canvas.releaseInteractiveRows(); XCTAssertEqual(canvas.rowRect(1000), .zero);
      XCTAssertTrue(canvas.rows.isEmpty)
    }
  }
  func testAllCapturedResourceSurfacesRenderWithReadableMissingStates() async throws {
    try await MainActor.run {
      _ = NSApplication.shared; let s = fixture()
      let process = ProcessData(
        pid: 42, name: "Synthetic process", cpu: 0.2, memory: 1048576, read: 1024, write: nil,
        wakeups: 1)
      let targets: [(String, ReadingTarget)] = [
        ("processor", .processor), ("graphics", .graphics(0)), ("memory", .memory),
        ("volume", .volume(0)), ("interface", .interface("en9")), ("battery", .power),
        ("power-source", .powerSource(0)), ("peripheral", .peripheral(0)), ("wifi-radio", .wifi),
        ("process", .process(process)),
        (
          "process-network",
          .networkProcess(
            ProcessPresentation.NetworkRow(
              pid: 42, name: "Synthetic process", download: 1024, upload: nil))
        ),
      ]
      for (name, target) in targets {
        let model = try XCTUnwrap(ReadingDetails.make(target, snapshot: s, settings: .init()))
        let controller = DetailWindowController(presentation: model)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
          controller.window?.appearance = NSAppearance(named: appearance)
          let view = controller.detailDocument; view.appearance = controller.window?.appearance
          let visible = NSRect(
            x: 0, y: 0, width: view.bounds.width, height: min(572, view.bounds.height))
          let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: visible));
          view.cacheDisplay(in: visible, to: image)
          let png = try XCTUnwrap(image.representation(using: .png, properties: [:]));
          XCTAssertGreaterThan(png.count, 1000)
          if let directory = ProcessInfo.processInfo.environment["AERIE_DETAIL_FIXTURE_DIRECTORY"] {
            let url = URL(fileURLWithPath: directory);
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(
              to: url.appendingPathComponent(
                "detail-content-resource-" + name + "-" + appearance.rawValue + ".png"))
          }
        }
        controller.close(); XCTAssertNil(controller.detailDocument.presentation)
      }
    }
  }
}
