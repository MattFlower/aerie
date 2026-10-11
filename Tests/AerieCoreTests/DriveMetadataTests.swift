import XCTest
@testable import AerieCore

final class DriveMetadataTests: XCTestCase {
  private func plist(_ value: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
  }
  func testStrictDeviceIdentifiersRejectPathsShellTextAndIncompleteComponents() {
    for value in ["disk0", "disk123s2", "disk5s1s1"] { XCTAssertTrue(DiskDevice.valid(value)) }
    for value in ["/dev/disk0", "disk", "disk0s", "disk0;echo", "disk-1", "disk0s1s2s3", "disk０"] {
      XCTAssertFalse(DiskDevice.valid(value))
    }
    XCTAssertEqual(DiskDevice.whole("disk123s2"), "disk123")
    XCTAssertEqual(DiskDevice.snapshotBase("disk5s1s1"), "disk5s1")
  }
  func testAPFSAssociatesMultiStoreVolumesAndSnapshotsWithoutInventingUnknownMapping() throws {
    let data = try plist([
      "Containers": [
        [
          "PhysicalStores": [["DeviceIdentifier": "disk0s2"], ["DeviceIdentifier": "disk1s2"]],
          "Volumes": [["DeviceIdentifier": "disk5s1"]],
        ]
      ]
    ])
    let topology = try DiskutilMetadata.topology(physical: ["disk0", "disk1"], apfs: data)
    XCTAssertEqual(topology.underlyingDisks(for: "disk5s1"), ["disk0", "disk1"])
    XCTAssertEqual(topology.underlyingDisks(for: "disk5s1s1"), ["disk0", "disk1"])
    XCTAssertEqual(topology.underlyingDisks(for: "disk0s2"), ["disk0"])
    XCTAssertTrue(topology.underlyingDisks(for: "disk99s1").isEmpty)
  }
  func testPhysicalInventoryAndHealthKeepUnsupportedMissingAndFailingDistinct() throws {
    XCTAssertEqual(
      try DiskutilMetadata.physicalDisks(plist(["WholeDisks": ["disk1", "disk0"]])),
      ["disk0", "disk1"])
    for (raw, expected) in [
      ("Verified", DriveSMARTStatus.verified), ("Failing", .failing),
      ("Not Supported", .unsupported), ("Unexpected", .unknown),
    ] {
      let result = try DiskutilMetadata.drive(
        plist([
          "DeviceIdentifier": "disk0", "WholeDisk": true, "SMARTStatus": raw,
          "TotalSize": 500_000_000_000,
        ]), expected: "disk0")
      XCTAssertEqual(result.smart, expected); XCTAssertEqual(result.sizeBytes, 500_000_000_000)
    }
    XCTAssertEqual(
      try DiskutilMetadata.drive(
        plist(["DeviceIdentifier": "disk0", "WholeDisk": true]), expected: "disk0"
      ).smart, .unknown)
    XCTAssertThrowsError(
      try DiskutilMetadata.drive(
        plist(["DeviceIdentifier": "disk1", "WholeDisk": true]), expected: "disk0"))
  }
  func testMalformedAmbiguousAndOversizedMetadataCannotProducePartialAssociations() throws {
    XCTAssertThrowsError(
      try DiskutilMetadata.physicalDisks(plist(["WholeDisks": ["disk0", "disk0"]])))
    XCTAssertThrowsError(try DiskutilMetadata.physicalDisks(plist(["WholeDisks": ["disk0s1"]])))
    XCTAssertThrowsError(
      try DiskutilMetadata.topology(
        physical: [],
        apfs: plist([
          "Containers": [["PhysicalStores": [["DeviceIdentifier": "invalid"]], "Volumes": []]]
        ])))
    XCTAssertThrowsError(try DiskutilMetadata.physicalDisks(Data(repeating: 0, count: 2_000_001)))
  }
}
