import EventKit
import Foundation

protocol CalendarPermissionRequest: AnyObject {
  func request(_ completion: @escaping (Bool) -> Void)
}
private final class NativeCalendarPermission: CalendarPermissionRequest {
  private let store = EKEventStore()
  func request(_ completion: @escaping (Bool) -> Void) {
    store.requestFullAccessToEvents { granted, _ in completion(granted) }
  }
}
/// Permission objects exist only during an explicitly requested authorization attempt.
final class CalendarAccess {
  private let lock = NSLock()
  private let status: () -> Bool
  private let factory: () -> CalendarPermissionRequest
  private var requestStore: CalendarPermissionRequest?
  private var generation = 0
  init(
    status: @escaping () -> Bool = { EKEventStore.authorizationStatus(for: .event) == .fullAccess },
    factory: @escaping () -> CalendarPermissionRequest = { NativeCalendarPermission() }
  ) {
    self.status = status; self.factory = factory
  }
  var hasAccess: Bool { status() }
  var requesting: Bool { lock.lock(); defer { lock.unlock() }; return requestStore != nil }
  func request(_ completion: @escaping (Bool) -> Void) {
    let store = factory()
    lock.lock(); generation += 1; let token = generation; requestStore = store; lock.unlock()
    store.request { [weak self] granted in
      guard let self else { return }
      self.lock.lock()
      guard self.generation == token else { self.lock.unlock(); return }
      self.requestStore = nil; self.lock.unlock()
      completion(granted && self.hasAccess)
    }
  }
  func cancel() { lock.lock(); generation += 1; requestStore = nil; lock.unlock() }
}
struct CalendarEventRecord {
  let start, end: Date
  let allDay: Bool
  let title, calendar, location, notes: String
  init(
    start: Date, end: Date, allDay: Bool = false, title: String, calendar: String = "",
    location: String = "", notes: String = ""
  ) {
    self.start = start; self.end = end; self.allDay = allDay
    self.title = String(title.prefix(256)); self.calendar = String(calendar.prefix(128))
    self.location = String(location.prefix(512)); self.notes = String(notes.prefix(2048))
  }
}
protocol CalendarEventSource: AnyObject {
  func enumerate(
    range: DateInterval, cancelled: @escaping () -> Bool,
    visit: @escaping (CalendarEventRecord) -> Bool)
  func close()
}
private final class NativeCalendarEventSource: CalendarEventSource {
  // Created, queried, reset and destroyed exclusively on the reader's serial queue.
  private let store = EKEventStore()
  func enumerate(
    range: DateInterval, cancelled: @escaping () -> Bool,
    visit: @escaping (CalendarEventRecord) -> Bool
  ) {
    let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
    store.enumerateEvents(matching: predicate) { event, stop in
      autoreleasepool {
        guard !cancelled(), let start = event.startDate, let end = event.endDate else {
          stop.pointee = true; return
        }
        let value = CalendarEventRecord(
          start: start, end: end, allDay: event.isAllDay,
          title: event.title ?? "Event", calendar: event.calendar?.title ?? "",
          location: event.location ?? "", notes: event.notes ?? "")
        if !visit(value) { stop.pointee = true }
      }
    }
  }
  func close() { store.reset() }
}
struct CalendarEventRangeResult {
  var events: [CalendarEventRecord] = []
  var scanned = 0
  var truncated = false
}
struct CalendarEventResult {
  var ranges: [CalendarEventRangeResult] = []
  var denied = false
}
private final class CalendarQueryToken {
  private let lock = NSLock()
  private var stopped = false
  var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
  func cancel() { lock.lock(); stopped = true; lock.unlock() }
}
/// A synchronous framework query never runs on the main thread or retains an event array.
final class CalendarEventReader {
  static let maximumDisplayed = 20, maximumScanned = 2000
  private let queue = DispatchQueue(label: "app.aerie.calendar-events", qos: .utility)
  private let access: CalendarAccess
  private let factory: () -> CalendarEventSource
  private let lock = NSLock()
  private var token: CalendarQueryToken?
  init(
    access: CalendarAccess,
    factory: @escaping () -> CalendarEventSource = { NativeCalendarEventSource() }
  ) {
    self.access = access; self.factory = factory
  }
  func cancel() { lock.lock(); token?.cancel(); token = nil; lock.unlock() }
  func load(ranges: [DateInterval], completion: @escaping (CalendarEventResult) -> Void) {
    let current = CalendarQueryToken()
    lock.lock(); token?.cancel(); token = current; lock.unlock()
    queue.async { [weak self] in
      guard let self, !current.cancelled else { return }
      var result = CalendarEventResult()
      if !self.access.hasAccess {
        result.denied = true
      } else {
        let source = self.factory()
        defer { source.close() }
        for range in ranges.prefix(2) {
          guard !current.cancelled, self.access.hasAccess else { break }
          var section = CalendarEventRangeResult()
          source.enumerate(range: range, cancelled: { current.cancelled || !self.access.hasAccess })
          { value in
            guard !current.cancelled, self.access.hasAccess else { return false }
            section.scanned += 1
            let timestamp = value.start.timeIntervalSince1970
            if timestamp.isFinite, abs(timestamp) < 1e12, value.end >= value.start {
              let index =
                section.events.firstIndex { $0.start > value.start } ?? section.events.count
              if index < Self.maximumDisplayed {
                section.events.insert(value, at: index)
                if section.events.count > Self.maximumDisplayed { section.events.removeLast() }
              }
            }
            if section.scanned >= Self.maximumScanned { section.truncated = true; return false }
            return true
          }
          result.ranges.append(section)
        }
        if !self.access.hasAccess { result = CalendarEventResult(denied: true) }
      }
      guard !current.cancelled else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, !current.cancelled else { return }
        self.lock.lock(); let valid = self.token === current; self.lock.unlock()
        guard valid else { return }
        completion(self.access.hasAccess ? result : CalendarEventResult(denied: true))
      }
    }
  }
  deinit { cancel() }
}
