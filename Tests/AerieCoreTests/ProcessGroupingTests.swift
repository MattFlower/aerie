import XCTest
@testable import AerieCore

final class ProcessGroupingTests: XCTestCase {
  func testApplicationHelpersShareOuterBundleIdentityAndCopiesRemainSeparate() throws {
    let main = try XCTUnwrap(
      ProcessGroupIdentity(executablePath: "/Applications/Synthetic.app/Contents/MacOS/Main"))
    let helper = try XCTUnwrap(
      ProcessGroupIdentity(
        executablePath:
          "/Applications/Synthetic.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"))
    XCTAssertEqual(main, helper); XCTAssertEqual(main.name, "Synthetic")
    XCTAssertNotEqual(
      main, ProcessGroupIdentity(executablePath: "/Other/Synthetic.app/Contents/MacOS/Main"))
    XCTAssertNotEqual(
      ProcessGroupIdentity(executablePath: "/bin/synthetic"),
      ProcessGroupIdentity(executablePath: "/other/synthetic"))
    XCTAssertEqual(ProcessGroupIdentity(executablePath: "/bin/synthetic")?.name, "synthetic")
  }
  func testMalformedOrTruncatedPathNeverAcquiresAnInferredIdentity() {
    for path in [
      "", "/", "relative/name", "/bin//name", "/bin/./name", "/bin/../name", "/bin/name\n",
      "/bin/name\0", "/" + String(repeating: "x", count: 4096),
    ] {
      XCTAssertNil(ProcessGroupIdentity(executablePath: path))
    }
    XCTAssertNotEqual(
      ProcessGroupIdentity(executablePath: "/ordinary.app/fileA"),
      ProcessGroupIdentity(executablePath: "/ordinary.app/fileB"))
  }
  func testOldSettingsKeepIndependentProcessesAndSortOptionsRejectUnsupportedScope() throws {
    var settings = Settings()
    XCTAssertFalse(settings.effectiveCombineProcesses); XCTAssertNil(settings.processSorts)
    XCTAssertFalse(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        .effectiveCombineProcesses)
    settings.combineProcesses = true;
    settings.processSorts = [.cpu: .memory, .network: .upload, .storage: .write]
    XCTAssertEqual(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).validated(),
      settings)
    for choice in [
      [Module.cpu: ProcessSort.download], [.network: .cpu], [.time: .automatic],
      [.overview: .memory],
    ] {
      settings.processSorts = choice; XCTAssertThrowsError(try settings.validated())
    }
  }
}
