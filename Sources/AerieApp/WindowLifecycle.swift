import AppKit
import Darwin
import Foundation

/// Opt-in diagnostics. Weak ownership, fixed role names, no titles, coordinates or user content.
final class WindowLifecycle {
  enum Role: String, Encodable {
    case dashboard, settings, detail, maps, calendar, statusBar, auxiliary
  }
  enum Event: String, Encodable {
    case launched, registered, shown, willClose, becameKey, resignedKey, minimized, restored
    case occlusion, becameActive, resignedActive, hidden, unhidden, reopened, closeAll, tick,
      terminating
  }
  struct WindowState: Encodable {
    let id: Int
    let role: Role
    let visible, occluded, minimized, key, closing, contentAttached: Bool
  }
  struct Report: Encodable {
    let kind = "windowLifecycle"
    let schema = 1
    let date: Date
    let monotonicTime: Double
    let event: Event
    let eventWindow: Int?
    let active, hidden: Bool
    let windows: [WindowState]
    let omittedWindows, droppedEvents: Int
    let allPresentationWindowsClosed: Bool?
    let app: StorageProcessResources
  }
  private final class Entry {
    weak var window: NSWindow?
    let id: Int
    var role: Role
    var closing = false
    init(_ window: NSWindow, id: Int, role: Role) {
      self.window = window; self.id = id; self.role = role
    }
  }
  private let clock: () -> Double
  private let date: () -> Date
  private let resources: () -> StorageProcessResources
  private let emit: (Report) -> Void
  private var entries: [ObjectIdentifier: Entry] = [:]
  private var observers: [NSObjectProtocol] = []
  private var nextID = 0
  private var eventSecond = -1.0
  private var eventsThisSecond = 0
  private var droppedEvents = 0
  static let maximumWindows = 256
  static let maximumEventsPerSecond = 128
  init(
    clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
    date: @escaping () -> Date = { Date() },
    resources: @escaping () -> StorageProcessResources = { StorageProcessResources(pid: getpid()) },
    emit: @escaping (Report) -> Void = { report in
      let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
      // Epoch seconds retain subsecond alignment with external samples and direct helper records.
      encoder.dateEncodingStrategy = .secondsSince1970
      if let data = try? encoder.encode(report), let line = String(data: data, encoding: .utf8) {
        print(line); fflush(stdout)
      }
    }
  ) {
    self.clock = clock; self.date = date; self.resources = resources; self.emit = emit
  }
  deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
  func start() {
    guard observers.isEmpty else { return }
    let windowEvents: [(Notification.Name, Event)] = [
      (NSWindow.willCloseNotification, .willClose),
      (NSWindow.didBecomeKeyNotification, .becameKey),
      (NSWindow.didResignKeyNotification, .resignedKey),
      (NSWindow.didMiniaturizeNotification, .minimized),
      (NSWindow.didDeminiaturizeNotification, .restored),
      (NSWindow.didChangeOcclusionStateNotification, .occlusion),
    ]
    for (name, event) in windowEvents {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] notification in
          guard let self, let window = notification.object as? NSWindow else { return }
          let entry = self.entry(window)
          if event == .willClose { entry?.closing = true }
          self.capture(event, window: window)
        })
    }
    let applicationEvents: [(Notification.Name, Event)] = [
      (NSApplication.didBecomeActiveNotification, .becameActive),
      (NSApplication.didResignActiveNotification, .resignedActive),
      (NSApplication.didHideNotification, .hidden),
      (NSApplication.didUnhideNotification, .unhidden),
    ]
    for (name, event) in applicationEvents {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: NSApp, queue: .main) {
          [weak self] _ in self?.capture(event)
        })
    }
    capture(.launched)
  }
  private func entry(_ window: NSWindow, role: Role? = nil) -> Entry? {
    let key = ObjectIdentifier(window)
    if let entry = entries[key], entry.window === window {
      if let role { entry.role = role }
      return entry
    }
    entries = entries.filter { $0.value.window != nil }
    guard entries.count < Self.maximumWindows else { return nil }
    nextID += 1
    let entry = Entry(
      window, id: nextID,
      role: role ?? (window.level == .statusBar ? .statusBar : .auxiliary))
    entries[key] = entry
    return entry
  }
  func register(_ window: NSWindow?, role: Role) {
    guard let window else { return }
    if let current = entries[ObjectIdentifier(window)], current.window === window,
      current.role == role
    {
      return
    }
    _ = entry(window, role: role); capture(.registered, window: window)
  }
  func capture(_ event: Event, window: NSWindow? = nil) {
    let now = clock()
    let second = floor(now)
    if eventSecond != second {
      eventSecond = second; eventsThisSecond = 0
    }
    guard eventsThisSecond < Self.maximumEventsPerSecond else { droppedEvents += 1; return }
    eventsThisSecond += 1
    entries = entries.filter { $0.value.window != nil }
    var omitted = 0
    for window in NSApp.windows where entry(window) == nil { omitted += 1 }
    let eventID = window.flatMap { entry($0)?.id }
    let states = entries.values.compactMap { entry -> WindowState? in
      guard let window = entry.window else { return nil }
      return WindowState(
        id: entry.id, role: entry.role, visible: window.isVisible,
        occluded: !window.occlusionState.contains(.visible), minimized: window.isMiniaturized,
        key: window.isKeyWindow, closing: entry.closing, contentAttached: window.contentView != nil)
    }.sorted { $0.id < $1.id }
    // Minimized windows are retained presentations; unknown native windows prevent a false idle label.
    let closed = states.filter { $0.role != .statusBar }.allSatisfy { !$0.visible && !$0.minimized }
    emit(
      Report(
        date: date(), monotonicTime: now, event: event, eventWindow: eventID,
        active: NSApp.isActive, hidden: NSApp.isHidden, windows: states,
        omittedWindows: omitted, droppedEvents: droppedEvents,
        allPresentationWindowsClosed: omitted == 0 ? closed : nil, app: resources()))
    droppedEvents = 0
  }
}
