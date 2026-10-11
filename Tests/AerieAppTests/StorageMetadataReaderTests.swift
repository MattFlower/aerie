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
  func testOutputOverflowStopsAndReapsOwnedHelper() async throws {
    var records: [StorageCommandMeasurement] = []
    let command = StorageCommand(
      executable: URL(fileURLWithPath: "/usr/bin/head"), measurement: { records.append($0) })
    do {
      _ = try await Task.detached { try command.run(["-c", "2000001", "/dev/zero"]) }.value;
      XCTFail("Oversized body accepted")
    } catch StorageCommandError.oversized {}
    XCTAssertEqual(records.first?.phase, "started"); XCTAssertEqual(records.last?.phase, "reaped")
    XCTAssertEqual(records.last?.confirmedExit, true);
    XCTAssertEqual(records.last?.helper.footprint, 0)
    XCTAssertNotNil(records.first?.registeredPID)
  }
  func testSIGTERMResistantSyntheticChildIsKilledReapedAndFullyRegistered() async throws {
    var records: [StorageCommandMeasurement] = []
    let command = StorageCommand(
      executable: URL(fileURLWithPath: "/bin/sh"), terminateAfter: 0.2, killAfter: 0.3,
      measurement: { records.append($0) })
    let start = ProcessInfo.processInfo.systemUptime
    do {
      _ = try await Task.detached { try command.run(["-c", "trap '' TERM; exec /bin/sleep 30"]) }
        .value;
      XCTFail("Timed out helper succeeded")
    } catch StorageCommandError.failed {}
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
    XCTAssertEqual(records.first?.phase, "started"); XCTAssertEqual(records.last?.phase, "reaped")
    XCTAssertEqual(records.last?.exitStatus, 9); XCTAssertEqual(records.last?.confirmedExit, true)
    XCTAssertTrue(records.contains { $0.phase == "running" && $0.helper.footprint != nil })
    XCTAssertTrue(
      records.allSatisfy {
        $0.registeredPID == records[0].registeredPID
          && $0.registeredBirth == records[0].registeredBirth
      })
    XCTAssertGreaterThan(records[0].registeredBirth, 0)
  }
  func testRapidReopenCannotPublishOldGenerationAndClearsLatestMetadata() async throws {
    let old = SyntheticStorageCommand(), new = SyntheticStorageCommand()
    let started = expectation(description: "Old query"), block = DispatchSemaphore(value: 0)
    old.block = block; old.started = started
    var created = 0
    let reader = StorageMetadataReader(factory: {
      created += 1; return created == 1 ? old : new
    })
    reader.configure(visible: true, time: 0); await fulfillment(of: [started], timeout: 1)
    reader.configure(visible: false, time: 1); reader.configure(visible: true, time: 2)
    try await ready(reader)
    XCTAssertEqual(old.callCount, 1); XCTAssertEqual(new.callCount, 3)
    XCTAssertEqual(reader.reading().drives["disk0"]?.smart, .verified)
    reader.configure(visible: false, time: 3)
    XCTAssertNil(reader.reading().topology); XCTAssertTrue(reader.reading().drives.isEmpty)
  }

}
