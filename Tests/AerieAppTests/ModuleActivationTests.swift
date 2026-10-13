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
  func testTrackedStatusActionUsesPointerForMissingAndNonMouseCurrentEvents() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: -700, y: 300, width: 300, height: 24), styleMask: [],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let group = GroupedStatusView(frame: .zero)
      window.contentView?.addSubview(group)
      _ = group.update(
        [Module.overview, .cpu, .gpu, .network].map {
          StatusWidget(
            module: $0, value: MenuValue(full: "42%"), style: .compact,
            label: .vertical, colorHex: nil)
        }, padding: 0, gap: 6)
      var requests: [Module] = []; group.onSelect = { requests.append($0) }
      XCTAssertTrue(group.press(index: 3))
      XCTAssertTrue(group.acceptsFirstMouse(for: nil))
      let rect = group.segments[2]
      let pointer = window.convertPoint(
        toScreen: group.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil))
      let unrelated = try XCTUnwrap(
        NSEvent.otherEvent(
          with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 1,
          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0))
      XCTAssertTrue(group.activate(from: unrelated, pointerInScreen: pointer))
      XCTAssertEqual(requests.last, .gpu)
      XCTAssertTrue(group.press(index: 0))
      XCTAssertTrue(group.activate(from: nil, pointerInScreen: pointer))
      XCTAssertEqual(requests.last, .gpu)
      let staleKey = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2,
          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
          isARepeat: false, keyCode: 36))
      XCTAssertTrue(group.press(index: 3))
      XCTAssertTrue(group.activate(from: staleKey, pointerInScreen: pointer))
      XCTAssertEqual(requests.last, .gpu)
      let unrelatedWindow = NSWindow(
        contentRect: NSRect(x: 1200, y: 800, width: 40, height: 40), styleMask: [],
        backing: .buffered, defer: false)
      unrelatedWindow.isReleasedWhenClosed = false
      let staleMouse = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 3,
          windowNumber: unrelatedWindow.windowNumber, context: nil, eventNumber: 1,
          clickCount: 1, pressure: 0))
      XCTAssertTrue(group.activate(from: staleMouse, pointerInScreen: pointer))
      XCTAssertEqual(requests.last, .gpu)
      let gap = group.segments[1].maxX + 3
      let gapPointer = window.convertPoint(
        toScreen: group.convert(NSPoint(x: gap, y: 12), to: nil))
      let count = requests.count
      XCTAssertFalse(group.activate(from: unrelated, pointerInScreen: gapPointer))
      XCTAssertEqual(requests.count, count)
      group.releaseContent(); window.contentView = nil
    }
  }
  func testNativeButtonTargetsRetainDestinationsAcrossForwardedSendersAndSettingsTransitions()
    async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      let dashboard = DashboardController()
      var shown: Module?
      var requests: [Module] = []
      let modules: [Module] = [.network, .cpu, .gpu, .memory, .overview]
      let targets = modules.map { module in
        StatusItemTarget(module: module) { selected, _ in
          requests.append(selected)
          switch ModuleActivation.resolve(requested: selected, shown: shown) {
          case .close: shown = nil; dashboard.releasePresentation()
          case .show(let selected):
            dashboard.show(selected); shown = selected
          }
        }
      }
      let buttons = modules.map { _ in NSButton(frame: .zero) }
      for (target, button) in zip(targets, buttons) { target.attach(to: button) }
      for index in buttons.indices {
        buttons[index].performClick(nil)
        XCTAssertEqual(shown, modules[index]); XCTAssertEqual(dashboard.module, modules[index])
        XCTAssertEqual(dashboard.modules.titleOfSelectedItem, modules[index].title)
      }
      buttons[4].performClick(nil)
      XCTAssertNil(shown); XCTAssertFalse(dashboard.isPresentationLoaded)
      // Opening Settings closes/releases the detail hierarchy; the next toolbar action must
      // rebuild it for its own module, even after Network was previously selected.
      buttons[0].performClick(nil); XCTAssertEqual(shown, .network)
      shown = nil; dashboard.releasePresentation()
      buttons[1].performClick(nil)
      XCTAssertEqual(shown, .cpu); XCTAssertEqual(dashboard.modules.titleOfSelectedItem, "CPU")
      let forwarded = NSButton(frame: .zero)
      targets[2].attach(to: forwarded); forwarded.performClick(nil)
      XCTAssertEqual(shown, .gpu); XCTAssertEqual(requests.last, .gpu)
      forwarded.performClick(nil); XCTAssertNil(shown)
      dashboard.releasePresentation()
    }
  }
  func testGroupedMouseEventsAndTrackedActionsShareOpenSwitchCloseAndSettingsLifecycle()
    async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: -800, y: 400, width: 400, height: 24), styleMask: [],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let group = GroupedStatusView(frame: .zero)
      window.contentView?.addSubview(group)
      let modules: [Module] = [.network, .cpu, .gpu, .memory, .overview]
      _ = group.update(
        modules.map {
          StatusWidget(
            module: $0, value: MenuValue(full: "42%"), style: .compact,
            label: .vertical, colorHex: nil)
        }, padding: 0, gap: 6)
      let dashboard = DashboardController(); var shown: Module?
      group.onSelect = { selected in
        switch ModuleActivation.resolve(requested: selected, shown: shown) {
        case .close: shown = nil; dashboard.releasePresentation()
        case .show(let selected): dashboard.show(selected); shown = selected
        }
      }
      @MainActor func click(_ index: Int) throws {
        let rect = group.segments[index]
        let point = group.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let event = try XCTUnwrap(
          NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: Double(index + 1), windowNumber: window.windowNumber, context: nil,
            eventNumber: index + 1, clickCount: 1, pressure: 0))
        let screenPoint = window.convertPoint(toScreen: point)
        group.pointerLocation = { screenPoint }
        group.mouseUp(with: event)
      }
      try click(0); XCTAssertEqual(shown, .network)
      try click(1); XCTAssertEqual(shown, .cpu)
      try click(2); XCTAssertEqual(shown, .gpu)
      XCTAssertEqual(dashboard.modules.titleOfSelectedItem, "GPU")
      try click(2); XCTAssertNil(shown)
      try click(0); XCTAssertEqual(shown, .network)
      // The Settings transition releases the page; a tracked action without a mouse current
      // event must ignore the retained Network focus and rebuild the clicked Memory page.
      shown = nil; dashboard.releasePresentation()
      let rect = group.segments[3]
      let pointer = window.convertPoint(
        toScreen: group.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil))
      XCTAssertTrue(group.activate(from: nil, pointerInScreen: pointer))
      XCTAssertEqual(shown, .memory)
      XCTAssertEqual(dashboard.modules.titleOfSelectedItem, "Memory")
      XCTAssertTrue(group.activate(from: nil, pointerInScreen: pointer)); XCTAssertNil(shown)
      dashboard.releasePresentation(); group.releaseContent(); window.contentView = nil
    }
  }
  func testChildMouseUpIgnoresForeignWindowCoordinatesAfterSettings() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: -800, y: 400, width: 400, height: 24), styleMask: [],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let group = GroupedStatusView(frame: .zero); window.contentView?.addSubview(group)
      _ = group.update(
        [Module.overview, .cpu, .gpu, .network].map {
          StatusWidget(
            module: $0, value: MenuValue(full: "42%"), style: .compact,
            label: .vertical, colorHex: nil)
        }, padding: 0, gap: 6)
      var requests: [Module] = []; group.onSelect = { requests.append($0) }
      XCTAssertTrue(group.press(index: 3))
      let rect = group.segments[2]
      let pointer = window.convertPoint(
        toScreen: group.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil))
      group.pointerLocation = { pointer }
      let foreign = NSWindow(
        contentRect: NSRect(x: 1000, y: 700, width: 50, height: 50), styleMask: [],
        backing: .buffered, defer: false)
      foreign.isReleasedWhenClosed = false
      let up = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 1,
          windowNumber: foreign.windowNumber, context: nil, eventNumber: 1,
          clickCount: 1, pressure: 0))
      group.mouseUp(with: up)
      XCTAssertEqual(requests.last, .gpu)
      let gapPointer = window.convertPoint(
        toScreen: group.convert(NSPoint(x: group.segments[1].maxX + 3, y: 12), to: nil))
      group.pointerLocation = { gapPointer }; let count = requests.count
      group.mouseUp(with: up); XCTAssertEqual(requests.count, count)
      group.releaseContent(); window.contentView = nil
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
