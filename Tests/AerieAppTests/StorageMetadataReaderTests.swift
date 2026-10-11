import AerieCore
import Foundation
import XCTest
@testable import AerieApp

private final class SyntheticStorageCommand: StorageCommandTransport {
  private let lock = NSLock()
  private var calls: [[String]] = []
  private var cancelled = false
  var block: DispatchSemaphore?
  var started: XCTestExpectation?
  var failInfo = false
  var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
  func run(_ arguments: [String]) throws -> Data {
    lock.lock(); calls.append(arguments); lock.unlock()
    if arguments[0] == "list" { started?.fulfill(); block?.wait() }
    lock.lock(); let wasCancelled = cancelled; lock.unlock()
    if wasCancelled { throw StorageCommandError.cancelled }
    let value: [String: Any]
    switch arguments[0] {
    case "list": value = ["WholeDisks": ["disk0"]]
    case "apfs":
      value = [
        "Containers": [
          [
            "PhysicalStores": [["DeviceIdentifier": "disk0s2"]],
            "Volumes": [["DeviceIdentifier": "disk5s1"]],
          ]
        ]
      ]
    case "info":
      if failInfo { throw StorageCommandError.failed }
      value = ["DeviceIdentifier": "disk0", "WholeDisk": true, "SMARTStatus": "Verified"]
    default: throw StorageCommandError.failed
    }
    return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
  }
  func cancel() { lock.lock(); cancelled = true; lock.unlock(); block?.signal() }
}
final class StorageMetadataReaderTests: XCTestCase {
  private func ready(_ reader: StorageMetadataReader) async throws {
    for _ in 0..<100 {
      if reader.reading().queriedAt != nil { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Synthetic metadata did not arrive")
  }
  func testVisibilityCadenceAndIndependentFailedHealthKeepTopologyExplicit() async throws {
    let command = SyntheticStorageCommand(); command.failInfo = true
    let reader = StorageMetadataReader(factory: { command })
    reader.configure(visible: false, time: 0); XCTAssertEqual(command.callCount, 0)
    reader.configure(visible: true, time: 0); try await ready(reader)
    let reading = reader.reading()
    XCTAssertEqual(reading.topology?.underlyingDisks(for: "disk5s1s1"), ["disk0"])
    XCTAssertTrue(reading.drives.isEmpty);
    XCTAssertTrue(reading.status.contains("1 queries unavailable"))
    reader.configure(visible: true, time: 59); XCTAssertEqual(command.callCount, 3)
    reader.configure(visible: false, time: 59)
    XCTAssertNil(reader.reading().queriedAt); XCTAssertNil(reader.reading().topology)
  }
  func testClosingCannotPublishLateMetadataOrStartFollowupQueries() async throws {
    let command = SyntheticStorageCommand(),
      started = expectation(description: "Synthetic first query")
    command.block = DispatchSemaphore(value: 0); command.started = started
    let reader = StorageMetadataReader(factory: { command })
    reader.configure(visible: true, time: 0)
    await fulfillment(of: [started], timeout: 1)
    reader.configure(visible: false, time: 1)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertNil(reader.reading().topology); XCTAssertNil(reader.reading().queriedAt)
    XCTAssertEqual(command.callCount, 1)
  }
  func testFiniteSyntheticCommandOutputAndCancellationDoNotLeaveAHelper() async throws {
    let echo = StorageCommand(executable: URL(fileURLWithPath: "/bin/echo"))
    let result = try await Task.detached { try echo.run(["synthetic"]) }.value
    XCTAssertEqual(result, Data("synthetic\n".utf8))
    let sleep = StorageCommand(executable: URL(fileURLWithPath: "/bin/sleep"))
    let task = Task.detached { try sleep.run(["30"]) }
    try await Task.sleep(nanoseconds: 50_000_000); sleep.cancel()
    do {
      _ = try await task.value; XCTFail("Cancelled query must not complete successfully")
    } catch StorageCommandError.cancelled {} catch { XCTFail("Unexpected failure: \(error)") }
  }
}
