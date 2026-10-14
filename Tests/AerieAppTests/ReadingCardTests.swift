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
  @MainActor private func render(_ model: DetailPresentation, name: String) throws {
    let controller = DetailWindowController(presentation: model)
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      controller.window?.appearance = NSAppearance(named: appearance)
      let view = controller.detailDocument; view.appearance = controller.window?.appearance
      let visible = NSRect(
        x: 0, y: 0, width: view.bounds.width, height: min(572, view.bounds.height))
      let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: visible));
      view.cacheDisplay(in: visible, to: image)
      let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
      if let directory = ProcessInfo.processInfo.environment["AERIE_DETAIL_FIXTURE_DIRECTORY"] {
        let url = URL(fileURLWithPath: directory);
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try png.write(
          to: url.appendingPathComponent(
            "detail-content-edge-" + name + "-" + appearance.rawValue + ".png"))
      }
    }
    controller.window?.setContentSize(NSSize(width: 500, height: 400))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(controller.detailDocument.bounds.width, 500)
    XCTAssertTrue(controller.detailDocument.accessibilityChildren()?.isEmpty == false)
    if name == "long-graphics" {
      for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        controller.detailDocument.appearance = NSAppearance(named: appearance)
        let view = controller.detailDocument
        let visible = NSRect(
          x: 0, y: 0, width: view.bounds.width, height: min(352, view.bounds.height))
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: visible))
        view.cacheDisplay(in: visible, to: image)
        if let directory = ProcessInfo.processInfo.environment["AERIE_DETAIL_FIXTURE_DIRECTORY"] {
          try XCTUnwrap(image.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
              "detail-content-edge-narrow-graphics-" + appearance.rawValue + ".png"))
        }
      }
    }
    let content = try XCTUnwrap(controller.window?.contentView)
    let buttons = content.subviews.compactMap { $0 as? NSButton }
    XCTAssertEqual(buttons.count, 2)
    XCTAssertTrue(buttons.allSatisfy { content.bounds.contains($0.frame) })
    XCTAssertFalse(buttons[0].frame.intersects(buttons[1].frame))
    for diagnostics in [false, true] {
      if diagnostics { controller.toggleDiagnostics() }
      XCTAssertEqual(controller.diagnosticsVisible, diagnostics)
      for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        controller.window?.appearance = NSAppearance(named: appearance)
        content.appearance = controller.window?.appearance
        content.layoutSubtreeIfNeeded()
      }
    }
    controller.toggleDiagnostics(); XCTAssertFalse(controller.diagnosticsVisible)
    controller.close(); XCTAssertNil(controller.detailDocument.presentation)
  }
  func testLongNamesMissingFieldsAndUnclassifiedSourcesHaveNativeLightDarkLayouts() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var long = fixture();
      long.gpu[0].name = String(
        repeating: "Synthetic graphics adapter with a long label ", count: 5)
      long.volumes[0].name = String(repeating: "Synthetic archive volume ", count: 7)
      long.interfaces[0].name = "synthetic-interface-with-an-unusually-long-name-for-testing"
      let longTargets: [(String, ReadingTarget)] = [
        ("long-graphics", .graphics(0)), ("long-volume", .volume(0)),
        ("long-interface", .interface(long.interfaces[0].name)),
        (
          "long-process",
          .process(
            ProcessData(
              pid: 42, name: String(repeating: "Synthetic application name ", count: 9), cpu: nil,
              memory: 0, read: nil, write: nil, wakeups: nil))
        ),
      ]
      for (name, target) in longTargets {
        try render(
          try XCTUnwrap(ReadingDetails.make(target, snapshot: long, settings: .init())), name: name)
      }
      var empty = Snapshot(); empty.date = fixture().date
      let emptyProcessor = try XCTUnwrap(
        ReadingDetails.make(.processor, snapshot: empty, settings: .init()))
      XCTAssertEqual(emptyProcessor.highlights[1].value, "Unavailable")
      XCTAssertTrue(emptyProcessor.fullText.contains("Uptime: Unavailable"))
      XCTAssertEqual(
        emptyProcessor.sections[1].facts.map(\.value), Array(repeating: "Unavailable", count: 3))
      try render(emptyProcessor, name: "missing-processor")
      var unsupported = fixture(); unsupported.memory.validity = .unavailable
      unsupported.gpu = [GPUData(name: "Synthetic unsupported driver")]
      unsupported.volumes[0].total = 0; unsupported.volumes[0].important = nil
      unsupported.interfaces[0].download = nil; unsupported.interfaces[0].upload = nil;
      unsupported.interfaces[0].counterBits = 32
      unsupported.power = PowerData(source: "AC Power", present: false)
      let source = PowerSourceReading(
        name: "Synthetic unclassified source", kind: .unknown, transport: nil, present: nil,
        input: .unknown, charging: nil, current: nil, maximum: nil, minutes: nil, voltage: nil,
        amperage: nil, temperature: nil)
      unsupported.power.inventory = PowerSourceInventory(
        sources: [source], available: true, reportedCount: 2, unreadableCount: 1)
      for (name, target) in [
        ("missing-memory", ReadingTarget.memory), ("unsupported-graphics", .graphics(0)),
        ("zero-volume", .volume(0)), ("limited-interface", .interface("en9")),
        ("incomplete-power", .power), ("unclassified-power", .powerSource(0)),
      ] {
        try render(
          try XCTUnwrap(ReadingDetails.make(target, snapshot: unsupported, settings: .init())),
          name: name)
      }
      XCTAssertTrue(
        try XCTUnwrap(ReadingDetails.make(.power, snapshot: unsupported, settings: .init()))
          .notices.contains { $0.contains("incomplete or ambiguous") })
      unsupported.power.inventory = PowerSourceInventory(available: true)
      let absent = try XCTUnwrap(
        ReadingDetails.make(.power, snapshot: unsupported, settings: .init()))
      XCTAssertTrue(absent.notices.contains { $0.contains("No present internal battery") })
      try render(absent, name: "no-battery")
      unsupported.power.inventory = PowerSourceInventory()
      let unavailable = try XCTUnwrap(
        ReadingDetails.make(.power, snapshot: unsupported, settings: .init()))
      XCTAssertTrue(unavailable.notices.contains { $0.contains("absence cannot be determined") })
      try render(unavailable, name: "unavailable-power")
    }
  }
  func testEmptyPrimaryPanelsAndKeyboardControlEdgesPreserveConfigurationAndRouting() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = DashboardController(); var settings = Settings(); settings.interval = 3
      settings.temperature = .fahrenheit; settings.networkBits = true; settings.processCount = 7
      controller.settings = settings; controller.snapshot.date = fixture().date
      for module in [Module.cpu, .gpu, .memory, .storage, .network, .power] {
        controller.show(module)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
          controller.view.appearance = NSAppearance(named: appearance);
          controller.canvas.appearance = controller.view.appearance
          let visible = NSRect(
            x: 0, y: 0, width: controller.canvas.bounds.width,
            height: min(530, controller.canvas.bounds.height))
          let image = try XCTUnwrap(controller.canvas.bitmapImageRepForCachingDisplay(in: visible));
          controller.canvas.cacheDisplay(in: visible, to: image)
          if let directory = ProcessInfo.processInfo.environment["AERIE_DETAIL_FIXTURE_DIRECTORY"] {
            let url = URL(fileURLWithPath: directory);
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(
              to: url.appendingPathComponent(
                "panel-content-empty-" + module.rawValue + "-" + appearance.rawValue + ".png"))
          }
        }
        XCTAssertEqual(controller.settings.interval, 3);
        XCTAssertEqual(controller.settings.temperature, .fahrenheit)
        XCTAssertTrue(controller.settings.networkBits);
        XCTAssertEqual(controller.settings.processCount, 7)
      }
      let canvas = controller.canvas
      let note = String(repeating: "Synthetic accounting explanation. ", count: 5)
      canvas.update(
        rows: [
          .note(note),
          .reading(
            ReadingCard(
              title: "Synthetic resource", subtitle: "Details", symbol: "app", facts: [],
              target: .memory, compact: true)),
        ], points: [])
      let wideNext = canvas.rowRect(1).minY
      canvas.setFrameSize(NSSize(width: 280, height: canvas.frame.height))
      XCTAssertGreaterThan(canvas.rowRect(1).minY, wideNext)
      XCTAssertEqual(canvas.rowRect(0).height, DashboardRow.note(note).height(for: 280))
      canvas.setFrameSize(NSSize(width: 416, height: canvas.frame.height))
      canvas.update(
        rows: (0..<3).map {
          .reading(
            ReadingCard(
              title: "Synthetic resource \($0)", subtitle: "Details", symbol: "app", facts: [],
              target: .memory, compact: true))
        }, points: [])
      var actions: [String] = []; canvas.onAction = { actions.append($0) }
      _ = canvas.becomeFirstResponder()
      let down = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
          context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
          keyCode: 125))
      let enter = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
          context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
          keyCode: 36))
      canvas.keyDown(with: down); canvas.keyDown(with: enter)
      XCTAssertEqual(actions, ["reading:1"])
      controller.show(.cpu); controller.setHistoryExpanded(true);
      controller.zoomPicker.selectItem(at: 2); controller.historyPosition.doubleValue = 0.3
      controller.refresh(); XCTAssertEqual(controller.zoomPicker.indexOfSelectedItem, 2);
      XCTAssertEqual(controller.historyPosition.doubleValue, 0.3)
      controller.releasePresentation()
    }
  }

}
