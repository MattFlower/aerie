import AerieCore
import Darwin
import Foundation

protocol HistoryFileStore: AnyObject {
  func read() throws -> Data?
  func write(_ data: Data) throws
  func remove() throws
}
final class LocalHistoryFile: HistoryFileStore {
  let url: URL
  init(url: URL) { self.url = url }
  func read() throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber,
      size.int64Value <= HistoryCheckpoint.maximumBytes
    else { throw HistoryArchiveError.oversized }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while let chunk = try handle.read(upToCount: 8192), !chunk.isEmpty {
      guard chunk.count <= HistoryCheckpoint.maximumBytes - data.count else {
        throw HistoryArchiveError.oversized
      }
      data.append(chunk)
    }
    return data
  }
  func write(_ data: Data) throws {
    guard data.count <= HistoryCheckpoint.maximumBytes else { throw HistoryArchiveError.oversized }
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let temporary = directory.appendingPathComponent(".history-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }
    guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
  }
  func remove() throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
/// All file work/serialization is ordered on one utility queue. Disabled mode performs no I/O.
final class HistoryPersistence {
  private let queue = DispatchQueue(label: "app.aerie.history-archive", qos: .utility)
  private let lock = NSLock()
  private let file: HistoryFileStore
  private var enabled = false, generation = 0
  private var loading = false
  private var writing = false
  private var lastAttempt = -Double.infinity
  private var message = "History archive is off"
  var status: String { lock.lock(); defer { lock.unlock() }; return message }
  private func report(_ value: String, token: Int) {
    lock.lock(); if generation == token, enabled { message = value }; lock.unlock()
  }
  init(file: HistoryFileStore) { self.file = file }
  private func valid(_ token: Int) -> Bool {
    lock.lock(); defer { lock.unlock() }; return enabled && generation == token
  }
  func configure(enabled: Bool, erase: Bool = false) {
    lock.lock(); self.enabled = enabled; generation += 1; lastAttempt = -.infinity; loading = false
    message = enabled ? "Local numeric archive · saves once per minute" : "History archive is off";
    lock.unlock()
    if erase {
      lock.lock(); let token = generation; lock.unlock()
      queue.async { [weak self] in
        guard let self else { return }
        do { try self.file.remove() } catch {
          self.lock.lock();
          if self.generation == token {
            self.message = "History archive could not be deleted; check local file access."
          }; self.lock.unlock()
        }
      }
    }
  }
  func load(
    interval: Double, selection: NetworkSelection, now: Date = Date(),
    completion: @escaping (HistoryStore?) -> Void
  ) {
    lock.lock(); let token = generation, enabled = enabled; loading = enabled; lock.unlock()
    guard enabled else { return }
    queue.async { [weak self] in
      guard let self, self.valid(token) else { return }
      let restored: HistoryStore?
      do {
        if let data = try self.file.read() {
          restored = try HistoryStore.restore(
            HistoryCheckpoint.decode(data, now: now), interval: interval,
            networkSelection: selection, now: now)
        } else {
          restored = nil
        }
      } catch {
        restored = nil;
        self.report(
          "Previous archive unavailable; current history remains in memory.", token: token)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.valid(token) else { return }; completion(restored)
        self.lock.lock(); if self.generation == token { self.loading = false }; self.lock.unlock()
      }
    }
  }
  func save(
    _ store: HistoryStore, interval: Double, selection: NetworkSelection, now: Date = Date(),
    monotonicTime: Double = ProcessInfo.processInfo.systemUptime, force: Bool = false
  ) {
    lock.lock()
    guard enabled, !loading, !writing, force || monotonicTime - lastAttempt >= 60 else {
      lock.unlock(); return
    }
    lastAttempt = monotonicTime; writing = true; let token = generation; lock.unlock()
    queue.async { [weak self] in
      guard let self else { return }
      defer { self.lock.lock(); self.writing = false; self.lock.unlock() }
      guard self.valid(token) else { return }
      do {
        let data = try store.checkpoint(interval: interval, networkSelection: selection, now: now)
          .data()
        guard self.valid(token) else { return }
        try self.file.write(data)
        self.report("Numeric history saved locally · refresh 60s · 2 MB limit", token: token)
      } catch {
        self.report(
          "History archive write unavailable; current history remains in memory.", token: token)
      }
    }
  }
  func finish() { queue.sync {} }
}
