import AerieCore
import AerieNative
import AppKit
import XCTest
@testable import AerieApp

final class ProcessGroupingAppTests: XCTestCase {
  private let path = "/Applications/Synthetic.app/Contents/MacOS/Main"
  private func row(_ pid: Int, cpu: Double?, memory: Double, group: ProcessGroupIdentity? = nil)
    -> ProcessData
  {
    ProcessData(
      pid: pid, name: "Process", cpu: cpu, memory: memory, read: 0, write: 10, wakeups: 0,
      group: group)
  }
  func testCombiningUsesIdentityPreservesMissingRatesAndNeverMergesUnknownNames() throws {
    let group = try XCTUnwrap(ProcessGroupIdentity(executablePath: path))
    var members = [
      row(1, cpu: 0.2, memory: 100, group: group), row(2, cpu: 0.3, memory: 200, group: group),
    ]
    let unknown = [row(3, cpu: 0, memory: 50), row(4, cpu: 0, memory: 50)]
    let combined = ProcessPresentation.combine(members + unknown, enabled: true)
    XCTAssertEqual(combined.count, 3)
    let app = try XCTUnwrap(combined.first { $0.members == 2 })
    XCTAssertEqual(app.cpu ?? -1, 0.5, accuracy: 1e-12); XCTAssertEqual(app.memory, 300)
    XCTAssertEqual(app.name, "Synthetic · 2 processes"); XCTAssertEqual(app.read, 0)
    XCTAssertEqual(app.write, 20); XCTAssertEqual(app.wakeups, 0)
    XCTAssertEqual(
      ProcessPresentation.combine(members + unknown, enabled: false).map(\.pid), [1, 2, 3, 4])
    members[1].cpu = nil; members[1].write = nil
    let partial = try XCTUnwrap(ProcessPresentation.combine(members, enabled: true).first)
    XCTAssertNil(partial.cpu); XCTAssertNil(partial.write); XCTAssertEqual(partial.read, 0)
    for bad in [Double.nan, .infinity, -1] {
      XCTAssertNil(ProcessPresentation.completeSum([1, bad]))
    }
    XCTAssertNil(
      ProcessPresentation.completeSum([.greatestFiniteMagnitude, .greatestFiniteMagnitude]))
  }
  func testReaderIsLazyBoundedAndDoesNotReusePathsAfterIdentityChangeOrMissingRead() throws {
    let old = ProcessIdentity(pid: 1, startTime: 100), new = ProcessIdentity(pid: 1, startTime: 200)
    var calls: [ProcessIdentity] = [], available = true
    let reader = ProcessGroupReader { identity in
      calls.append(identity); return available && identity == new ? self.path : nil
    }
    XCTAssertTrue(reader.read([new], enabled: false, visible: true).isEmpty)
    XCTAssertTrue(reader.read([new], enabled: true, visible: false).isEmpty)
    XCTAssertTrue(
      reader.read(Array(repeating: new, count: 8193), enabled: true, visible: true).isEmpty)
    XCTAssertTrue(calls.isEmpty)
    let identities = [old, new, new, ProcessIdentity(pid: 2, startTime: 0)]
    let groups = reader.read(identities, enabled: true, visible: true)
    XCTAssertNil(groups[old]); XCTAssertEqual(groups[new]?.name, "Synthetic");
    XCTAssertEqual(calls.count, 2)
    available = false; XCTAssertTrue(reader.read([new], enabled: true, visible: true).isEmpty)
    var bytes = [CChar](repeating: 0, count: 4096)
    XCTAssertEqual(aerie_process_path(0, 100, &bytes, 4096), 0)
    XCTAssertEqual(aerie_process_path(1, 0, &bytes, 4096), 0)
    XCTAssertEqual(aerie_process_path(1, 100, &bytes, 16), 0)
  }
  func testNetworkGroupingUsesStartIdentityAndCompleteDirectionRatesBeforeSorting() throws {
    let group = try XCTUnwrap(ProcessGroupIdentity(executablePath: path))
    let rows = [
      ProcessNetworkReading(
        pid: 1, startTime: 101, name: "Main", received: 0, sent: 0, download: 10, upload: 100),
      ProcessNetworkReading(
        pid: 2, startTime: 102, name: "Helper", received: 0, sent: 0, download: nil, upload: 200),
      ProcessNetworkReading(
        pid: 3, startTime: 103, name: "Other", received: 0, sent: 0, download: 20, upload: 0),
    ]
    let groups = [
      ProcessIdentity(pid: 1, startTime: 101): group,
      ProcessIdentity(pid: 2, startTime: 102): group,
      ProcessIdentity(pid: 3, startTime: 999): group,
    ]
    let byUpload = ProcessPresentation.network(rows, groups: groups, enabled: true, sort: .upload)
    XCTAssertEqual(byUpload.count, 2); XCTAssertEqual(byUpload[0].members, 2)
    XCTAssertEqual(byUpload[0].upload, 300); XCTAssertNil(byUpload[0].download)
    XCTAssertEqual(byUpload[1].name, "Other")
    let byDownload = ProcessPresentation.network(
      rows, groups: groups, enabled: true, sort: .download)
    XCTAssertEqual(byDownload[0].name, "Other")
    XCTAssertEqual(
      ProcessPresentation.network(rows, groups: groups, enabled: false, sort: .automatic).count, 3)
    var snapshot = Snapshot(); snapshot.networkProcesses = rows;
    snapshot.networkProcessGroups = groups
    snapshot.releaseActiveViewState(module: .cpu, suspended: false)
    XCTAssertTrue(snapshot.networkProcesses.isEmpty);
    XCTAssertTrue(snapshot.networkProcessGroups.isEmpty)
  }
  func testStableIndependentSortingPutsUnavailableAfterValidZero() {
    var missing = row(4, cpu: nil, memory: 40); missing.name = "Missing"
    let rows = [
      missing, row(2, cpu: 0.5, memory: 20), row(1, cpu: 0.5, memory: 10),
      row(3, cpu: 0, memory: 30),
    ]
    XCTAssertEqual(
      ProcessPresentation.sorted(rows, by: .cpu, automatic: { _, _ in false }).map(\.pid),
      [1, 2, 3, 4])
    XCTAssertEqual(
      ProcessPresentation.sorted(rows, by: .memory, automatic: { _, _ in false }).map(\.pid),
      [4, 3, 2, 1])
    XCTAssertEqual(
      ProcessPresentation.sorted(rows, by: .automatic, automatic: { $0.memory > $1.memory }).map(
        \.pid), [4, 3, 2, 1])
  }
  func testClosingOrSuspendingViewsClearsAllVolatileGroupingMetadata() throws {
    let group = try XCTUnwrap(ProcessGroupIdentity(executablePath: path))
    for (module, suspended) in [
      (nil, false), (Module.sensors, false), (.cpu, true), (.network, true),
    ] as [(Module?, Bool)] {
      var snapshot = Snapshot(); snapshot.processes = [row(1, cpu: 0, memory: 0, group: group)]
      snapshot.networkProcessGroups = [ProcessIdentity(pid: 2, startTime: 102): group]
      snapshot.releaseActiveViewState(module: module, suspended: suspended)
      XCTAssertTrue(snapshot.processes.isEmpty);
      XCTAssertTrue(snapshot.networkProcessGroups.isEmpty)
    }
  }
  func testNativeConfigurationAndDashboardApplyGroupingAndModuleSortOffWindow() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let preferences = PreferencesController(settings: Settings()); defer { preferences.close() }
      let content = try XCTUnwrap(preferences.window?.contentView)
      @MainActor func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
      }
      let tabs = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTabView }.first)
      let views = tabs.tabViewItems.compactMap(\.view).flatMap { descendants($0) }
      let toggle = try XCTUnwrap(
        views.compactMap { $0 as? NSButton }.first {
          $0.title == "Combine application and executable processes"
        })
      XCTAssertEqual(toggle.state, .off); toggle.state = .on
      let sort = try XCTUnwrap(
        views.compactMap { $0 as? NSPopUpButton }.first {
          $0.accessibilityLabel() == "CPU process sorting"
        })
      sort.selectItem(withTitle: "Memory")
      var settings: Settings?
      preferences.onApply = { settings = $0 }
      try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Apply" })
        .performClick(nil)
      let applied = try XCTUnwrap(settings)
      XCTAssertTrue(applied.effectiveCombineProcesses);
      XCTAssertEqual(applied.processSorts?[.cpu], .memory)
      XCTAssertFalse(applied.weather.enabled); XCTAssertFalse(preferences.window?.isVisible ?? true)
      let dashboard = DashboardController(); dashboard.settings = applied; _ = dashboard.view
      let group = try XCTUnwrap(ProcessGroupIdentity(executablePath: self.path))
      var other = self.row(3, cpu: 0.8, memory: 1000); other.name = "Other"
      dashboard.snapshot.processes = [
        self.row(1, cpu: 0.2, memory: 100, group: group),
        self.row(2, cpu: 0.3, memory: 200, group: group), other,
      ]
      dashboard.show(.cpu)
      let processRows = dashboard.canvas.rows.compactMap { row -> String? in
        if case .metric(let title, _) = row, title == "Other" || title == "Synthetic · 2 processes"
        {
          return title
        }; return nil
      }
      XCTAssertEqual(processRows, ["Other", "Synthetic · 2 processes"])
      XCTAssertTrue(
        dashboard.canvas.rows.contains {
          if case .note(let text) = $0 { return text == "Process order: Memory" }; return false
        })
      dashboard.canvas.releaseInteractiveRows()
    }
  }
}
