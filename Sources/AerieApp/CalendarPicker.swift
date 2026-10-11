import AerieCore
import AppKit
import EventKit

final class CalendarPickerController: NSWindowController, NSWindowDelegate {
  private let access: CalendarAccess
  private let reader: CalendarInventoryReader
  private var selection: [String]?
  private var items: [EventCalendarItem] = []
  private var buttons: [NSButton] = []
  private let status = NSTextField(wrappingLabelWithString: "Reading event calendar names…")
  private let calendarList = CalendarListView(frame: .zero)
  private var observer: NSObjectProtocol?
  var onChoose: (([String]?) -> Void)?
  var onClose: (() -> Void)?
  init(selection: [String]?, access: CalendarAccess) {
    self.selection = selection; self.access = access;
    reader = CalendarInventoryReader(access: access)
    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 590),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Aerie · Event Calendars"; window.isReleasedWhenClosed = false
    super.init(window: window); window.delegate = self
    guard let content = window.contentView else { return }
    status.frame = NSRect(x: 18, y: 520, width: 484, height: 50)
    status.font = .systemFont(ofSize: 12); content.addSubview(status)
    let scroll = NSScrollView(frame: NSRect(x: 18, y: 120, width: 484, height: 390))
    scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.documentView = calendarList; content.addSubview(scroll)
    let all = NSButton(title: "All calendars", target: self, action: #selector(allCalendars))
    all.frame = NSRect(x: 18, y: 80, width: 150, height: 28); content.addSubview(all)
    let none = NSButton(title: "No events", target: self, action: #selector(noCalendars))
    none.frame = NSRect(x: 175, y: 80, width: 130, height: 28); content.addSubview(none)
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancel.keyEquivalent = "\u{1b}"; cancel.frame = NSRect(x: 280, y: 22, width: 100, height: 28)
    content.addSubview(cancel)
    let choose = NSButton(title: "Use selection", target: self, action: #selector(choose))
    choose.keyEquivalent = "\r"; choose.frame = NSRect(x: 383, y: 22, width: 119, height: 28)
    content.addSubview(choose)
    observer = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: nil, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      if self.window?.occlusionState.contains(.visible) == true {
        self.reload()
      } else {
        self.reader.cancel(); self.clearNames()
      }
    }
    window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func showWindow(_ sender: Any?) { super.showWindow(sender); reload() }
  func windowDidBecomeKey(_ notification: Notification) {
    validateAccess()
  }
  func windowDidChangeOcclusionState(_ notification: Notification) {
    if window?.occlusionState.contains(.visible) == true {
      reload()
    } else {
      reader.cancel(); clearNames()
    }
  }
  private func clearNames() {
    items.removeAll(); buttons.removeAll();
    calendarList.subviews.forEach { $0.removeFromSuperview() }
    calendarList.setFrameSize(NSSize(width: 484, height: 0))
  }
  func validateAccess() {
    guard !access.hasAccess else { return }
    reader.cancel(); clearNames()
    status.stringValue =
      "Calendar access is unavailable; names and query state are cleared. All/No events need no grant. Use Settings → Permissions to enable reading names and events."
  }
  private func reload() {
    reader.cancel(); clearNames()
    guard access.hasAccess else { validateAccess(); return }
    status.stringValue = "Reading event calendar names…"
    reader.load { [weak self] result in
      guard let self else { return }
      if result.denied { self.validateAccess(); return }
      if result.invalid { self.status.stringValue = "Calendar metadata is unavailable."; return }
      self.items = result.items
      self.calendarList.setFrameSize(NSSize(width: 484, height: CGFloat(result.items.count * 32)))
      for (index, item) in result.items.enumerated() {
        let button = NSButton(
          checkboxWithTitle: item.title, target: self, action: #selector(self.toggled(_:)))
        button.tag = index;
        button.frame = NSRect(x: 4, y: CGFloat(index * 32), width: 468, height: 30)
        button.setAccessibilityLabel(item.title); self.calendarList.addSubview(button);
        self.buttons.append(button)
      }
      self.refreshChecks()
      let available = Set(result.items.map(\.identifier))
      let missing = self.selection?.filter { !available.contains($0) }.count ?? 0
      self.status.stringValue =
        "All includes every calendar. Individual choices apply through Settings → Apply."
      if missing > 0 {
        self.status.stringValue +=
          " \(missing) saved choices are currently unavailable and will be preserved."
      }
      if result.truncated {
        self.status.stringValue =
          "Showing the first 128 calendars. All still includes every calendar; individual selection includes checked shown and saved choices."
      }
    }
  }
  private func refreshChecks() {
    for (item, button) in zip(items, buttons) {
      let included = selection.map { $0.contains(item.identifier) } ?? true
      button.state = included ? .on : .off
    }
  }
  @objc private func toggled(_ sender: NSButton) {
    guard items.indices.contains(sender.tag) else { return }
    var next = Set(selection ?? items.map(\.identifier))
    let identifier = items[sender.tag].identifier
    if sender.state == .on { next.insert(identifier) } else { next.remove(identifier) }
    guard EventCalendarSelection.valid(Array(next)) else {
      refreshChecks();
      status.stringValue = "Choose at most 128 individual calendars, or use All calendars."; return
    }
    selection = next.sorted()
  }
  @objc private func allCalendars() {
    selection = nil; refreshChecks()
    status.stringValue =
      "All event calendars will be included when access is available. Save through Settings → Apply."
  }
  @objc private func noCalendars() {
    selection = []; refreshChecks()
    status.stringValue = "No calendar events will be read. Save through Settings → Apply."
  }
  @objc private func choose() {
    guard EventCalendarSelection.valid(selection) else { return }
    onChoose?(selection); close()
  }
  @objc private func cancel() { close() }
  func windowWillClose(_ notification: Notification) {
    reader.cancel(); clearNames()
    if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    onClose?()
  }
  deinit {
    reader.cancel()
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}
private final class CalendarListView: NSView { override var isFlipped: Bool { true } }
