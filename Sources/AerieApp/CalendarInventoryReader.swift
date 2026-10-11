import AerieCore
import EventKit
import Foundation

struct EventCalendarItem {
  let identifier, title: String
  init(identifier: String, title: String) {
    self.identifier = identifier; self.title = String(title.prefix(128))
  }
}
struct CalendarInventory {
  var items: [EventCalendarItem] = []
  var truncated = false
  var denied = false
  var invalid = false
}
protocol CalendarInventorySource: AnyObject {
  func read() -> CalendarInventory
  func close()
}
private final class NativeCalendarInventorySource: CalendarInventorySource {
  // All EventKit objects remain on the inventory worker and are released before delivery.
  private let store = EKEventStore()
  func read() -> CalendarInventory {
    autoreleasepool {
      let calendars = store.calendars(for: .event)
      let items = calendars.prefix(128).compactMap { calendar -> EventCalendarItem? in
        let identifier = calendar.calendarIdentifier
        guard EventCalendarSelection.valid([identifier])
        else { return nil }
        return EventCalendarItem(identifier: identifier, title: calendar.title)
      }
      return CalendarInventory(items: items, truncated: calendars.count > 128)
    }
  }
  func close() { store.reset() }
}
private final class InventoryCancellation {
  private let lock = NSLock()
  private var stopped = false
  var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
  func cancel() { lock.lock(); stopped = true; lock.unlock() }
}
final class CalendarInventoryReader {
  private let queue = DispatchQueue(label: "app.aerie.event-calendars", qos: .utility)
  private let access: CalendarAccess
  private let factory: () -> CalendarInventorySource
  private let lock = NSLock()
  private var token: InventoryCancellation?
  init(
    access: CalendarAccess,
    factory: @escaping () -> CalendarInventorySource = { NativeCalendarInventorySource() }
  ) {
    self.access = access; self.factory = factory
  }
  func cancel() { lock.lock(); token?.cancel(); token = nil; lock.unlock() }
  private func readInventory() -> CalendarInventory {
    let source = factory(); defer { source.close() }; return source.read()
  }
  func load(_ completion: @escaping (CalendarInventory) -> Void) {
    let current = InventoryCancellation()
    lock.lock(); token?.cancel(); token = current; lock.unlock()
    queue.async { [weak self] in
      guard let self, !current.cancelled else { return }
      var result = CalendarInventory(denied: true)
      if self.access.hasAccess {
        // A limited copied result does not bound EventKit's internal calendar-list allocation.
        result = self.readInventory()
        if result.items.count > 128 || !EventCalendarSelection.valid(result.items.map(\.identifier))
        {
          result = CalendarInventory(invalid: true)
        } else {
          result.items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
      }
      guard !current.cancelled else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, !current.cancelled else { return }
        self.lock.lock(); let matches = self.token === current; self.lock.unlock()
        guard matches else { return }
        completion(self.access.hasAccess ? result : CalendarInventory(denied: true))
      }
    }
  }
  deinit { cancel() }
}
