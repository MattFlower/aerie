import AerieCore
import Foundation

/// One opted-in request per five minutes, without another polling timer or address persistence.
final class PublicAddressReader {
  private let fetch: () async throws -> PublicAddressReading
  private var task: Task<Void, Never>?
  private var generation = 0
  private var enabled = false
  private var suspended = false
  private var lastAttempt: Double?
  private var previousTime: Double?
  private var route: String?
  private(set) var reading: PublicAddressReading?
  private(set) var status = "Public IP lookup is off"
  var onUpdate: (() -> Void)?
  init(
    fetch: @escaping () async throws -> PublicAddressReading = {
      try await PublicAddressProvider().fetch()
    }
  ) { self.fetch = fetch }
  func configure(enabled: Bool, suspended: Bool) {
    precondition(Thread.isMainThread)
    guard self.enabled != enabled || self.suspended != suspended else { return }
    self.enabled = enabled; self.suspended = suspended
    cancel(); reading = nil; route = nil
    if !enabled {
      lastAttempt = nil; previousTime = nil; status = "Public IP lookup is off"
    } else {
      status = suspended ? "Public IP lookup is paused" : "Public IP lookup is waiting"
    }
    onUpdate?()
  }
  func tick(time: Double, route: String?) {
    precondition(Thread.isMainThread)
    guard enabled, !suspended, time.isFinite else { return }
    if let previousTime, time < previousTime { cancel(); reading = nil; lastAttempt = nil }
    previousTime = time
    guard let route else {
      if self.route != nil || task != nil || reading != nil { cancel(); reading = nil }
      self.route = nil; status = "Public IP unavailable · network path missing"; return
    }
    if self.route != route {
      cancel(); reading = nil; self.route = route
      status = "Public IP lookup is waiting · network path changed"
    }
    guard task == nil, lastAttempt.map({ time - $0 >= 300 }) ?? true else { return }
    lastAttempt = time; status = "Fetching public IP"; onUpdate?()
    let token = generation, fetch = fetch
    task = Task { @MainActor [weak self] in
      do {
        let reading = try await fetch()
        guard !Task.isCancelled, let self, self.generation == token, self.enabled,
          !self.suspended
        else { return }
        self.reading = reading; self.status = "Updated · refresh 5 min"; self.task = nil
        self.onUpdate?()
      } catch {
        guard !Task.isCancelled, let self, self.generation == token else { return }
        self.reading = nil; self.status = "Public IP unavailable · retry after 5 min"
        self.task = nil; self.onUpdate?()
      }
    }
  }
  private func cancel() { generation += 1; task?.cancel(); task = nil }
  func stop() {
    precondition(Thread.isMainThread)
    cancel(); reading = nil; enabled = false; route = nil; previousTime = nil; lastAttempt = nil
    status = "Public IP lookup is off"
  }
  deinit { task?.cancel() }
}
