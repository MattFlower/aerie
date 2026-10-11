import AerieCore
import Foundation
import XCTest
@testable import AerieApp

private final class SyntheticHistoryFile: HistoryFileStore {
  var data: Data?, writes = 0, reads = 0, removes = 0
  var readStarted: (() -> Void)?
  var readBlock: DispatchSemaphore?
  var writeStarted: (() -> Void)?
  var writeBlock: DispatchSemaphore?
  func read() throws -> Data? { reads += 1; readStarted?(); readBlock?.wait(); return data }
  func write(_ data: Data) throws {
    XCTAssertFalse(Thread.isMainThread); writes += 1; writeStarted?(); writeBlock?.wait();
    self.data = data
  }
  func remove() throws { removes += 1; data = nil }
}
final class HistoryPersistenceTests: XCTestCase {
  private func history(_ date: Date) -> HistoryStore {
    var store = HistoryStore(); store.append(.init(date: date, values: ["cpu": 10])); return store
  }
  func testOptInSaveCadenceAndDisableErasureAreOrderedAndBounded() throws {
    let file = SyntheticHistoryFile(), persistence = HistoryPersistence(file: file),
      now = Date(timeIntervalSince1970: 100)
    let store = history(now)
    persistence.save(store, interval: 1, selection: .init(), now: now, monotonicTime: 0);
    persistence.finish()
    XCTAssertEqual(file.writes, 0)
    persistence.configure(enabled: true)
    persistence.save(store, interval: 1, selection: .init(), now: now, monotonicTime: 0);
    persistence.finish()
    persistence.save(store, interval: 1, selection: .init(), now: now, monotonicTime: 59);
    persistence.finish()
    XCTAssertEqual(file.writes, 1)
    persistence.save(store, interval: 1, selection: .init(), now: now, monotonicTime: 60);
    persistence.finish()
    XCTAssertEqual(file.writes, 2); XCTAssertLessThan(file.data!.count, 2_000_000)
    persistence.configure(enabled: false, erase: true); persistence.finish()
    XCTAssertNil(file.data); XCTAssertEqual(file.removes, 1)
    persistence.save(
      store, interval: 1, selection: .init(), now: now, monotonicTime: 200, force: true);
    persistence.finish()
    XCTAssertEqual(file.writes, 2)
  }
  func testDisabledOrCancelledLoadCannotDeliverLateHistoryOrWriteOverIt() async throws {
    let file = SyntheticHistoryFile(), persistence = HistoryPersistence(file: file),
      now = Date(timeIntervalSince1970: 100)
    file.data = try history(now).checkpoint(interval: 1, networkSelection: .init(), now: now).data()
    persistence.load(interval: 1, selection: .init(), now: now) { _ in
      XCTFail("Disabled load delivered")
    }
    persistence.finish(); XCTAssertEqual(file.reads, 0)
    let started = expectation(description: "Read started"), block = DispatchSemaphore(value: 0)
    file.readStarted = { started.fulfill() }; file.readBlock = block
    persistence.configure(enabled: true)
    persistence.load(interval: 1, selection: .init(), now: now) { _ in
      XCTFail("Cancelled load delivered")
    }
    await fulfillment(of: [started], timeout: 1)
    persistence.save(history(now), interval: 1, selection: .init(), now: now, monotonicTime: 0)
    persistence.configure(enabled: false, erase: true); block.signal(); persistence.finish()
    XCTAssertEqual(file.writes, 0); XCTAssertNil(file.data)
    await Task.yield()
  }
  func testAtomicLocalFileUsesPrivatePermissionsRejectsOversizeAndRemovesOnlyArchive() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "aerie-history-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = LocalHistoryFile(url: directory.appendingPathComponent("history.json"))
    XCTAssertNil(try file.read())
    try file.write(Data("synthetic".utf8)); XCTAssertEqual(try file.read(), Data("synthetic".utf8))
    let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertThrowsError(try file.write(Data(repeating: 0, count: 2_000_001)))
    XCTAssertEqual(try file.read(), Data("synthetic".utf8))
    let sibling = directory.appendingPathComponent("other.txt");
    try Data("keep".utf8).write(to: sibling)
    try file.remove(); XCTAssertNil(try file.read());
    XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path), ["other.txt"])
  }
  func testSlowFileWorkCannotAccumulateUnboundedPendingCheckpoints() async {
    let file = SyntheticHistoryFile(), persistence = HistoryPersistence(file: file)
    let started = expectation(description: "Write started"), block = DispatchSemaphore(value: 0)
    file.writeStarted = { started.fulfill() }; file.writeBlock = block
    persistence.configure(enabled: true)
    let now = Date(timeIntervalSince1970: 100), store = history(Date(timeIntervalSince1970: 100))
    persistence.save(store, interval: 1, selection: .init(), now: now, monotonicTime: 0)
    await fulfillment(of: [started], timeout: 1)
    for minute in 1...50 {
      persistence.save(
        store, interval: 1, selection: .init(), now: now, monotonicTime: Double(minute * 60))
    }
    block.signal(); persistence.finish()
    XCTAssertEqual(file.writes, 1)
  }

}
