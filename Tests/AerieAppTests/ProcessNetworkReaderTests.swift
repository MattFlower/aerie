import AerieNative
import Darwin
import XCTest
@testable import AerieApp

final class ProcessNetworkReaderTests: XCTestCase {
  func testClosingOwnedTerminalSendsHangupAndReapsSyntheticChild() async throws {
    var master: Int32 = -1, child: Int32 = -1
    let result = "/bin/sleep".withCString { path in
      "60".withCString { aerie_network_spawn(path, $0, 1, &master, &child) }
    }
    XCTAssertEqual(result, 0); guard result == 0 else { return }
    // Let the child open its controlling terminal before emulating abrupt parent FD loss.
    try await Task.sleep(nanoseconds: 100_000_000)
    Darwin.close(master)
    var status: Int32 = 0
    for _ in 0..<60 {
      if Darwin.waitpid(child, &status, WNOHANG) == child {
        XCTAssertEqual(status & 0x7f, SIGHUP); return
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    Darwin.kill(child, SIGKILL); Darwin.waitpid(child, &status, 0)
    XCTFail("Loss of the app-owned terminal must hang up the isolated helper")
  }
  func testOneSyntheticHelperFollowsDemandAndIntervalChangesAndIsReaped() async throws {
    let queue = DispatchQueue(label: "aerie.synthetic.network-reader")
    let reader = ProcessNetworkReader(
      queue: queue, executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"])
    let first: Int32 = try queue.sync {
      reader.configure(visible: false, interval: 1); XCTAssertNil(reader.helperPID)
      reader.configure(visible: true, interval: 1)
      let pid = try XCTUnwrap(reader.helperPID)
      reader.configure(visible: true, interval: 1); XCTAssertEqual(reader.helperPID, pid)
      return pid
    }
    let second: Int32 = try queue.sync {
      reader.configure(visible: true, interval: 2)
      return try XCTUnwrap(reader.helperPID)
    }
    XCTAssertNotEqual(first, second)
    queue.sync {
      reader.configure(visible: false, interval: 2); XCTAssertNil(reader.helperPID);
      XCTAssertTrue(reader.rows.isEmpty)
    }
    for _ in 0..<60 {
      if Darwin.kill(first, 0) != 0, errno == ESRCH, Darwin.kill(second, 0) != 0, errno == ESRCH {
        return
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("Both app-owned synthetic helpers must terminate promptly")
  }
}
