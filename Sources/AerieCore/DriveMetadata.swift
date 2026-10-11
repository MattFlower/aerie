import Foundation

public enum DriveMetadataError: Error { case malformed, oversized }
public enum DriveSMARTStatus: String { case verified, failing, unsupported, unknown }
public struct DriveMetadata: Equatable {
  public let identifier: String
  public let bus: String?
  public let solidState, internalDevice: Bool?
  public let sizeBytes: UInt64?
  public let smart: DriveSMARTStatus
}
public struct DriveTopology {
  public let physicalDisks: [String]
  public let physicalStoresByVolume: [String: [String]]
  public init(physicalDisks: [String], physicalStoresByVolume: [String: [String]]) {
    self.physicalDisks = physicalDisks; self.physicalStoresByVolume = physicalStoresByVolume
  }
  public func underlyingDisks(for device: String) -> [String] {
    guard DiskDevice.valid(device) else { return [] }
    if let stores = physicalStoresByVolume[device] { return stores }
    // An APFS snapshot is a third numeric component of a published volume identifier.
    if let base = DiskDevice.snapshotBase(device), let stores = physicalStoresByVolume[base] {
      return stores
    }
    if let whole = DiskDevice.whole(device), physicalDisks.contains(whole) { return [whole] }
    return []
  }
}
public enum DiskDevice {
  public static func valid(_ value: String) -> Bool {
    guard value.utf8.count <= 64, value.hasPrefix("disk") else { return false }
    let pieces = value.dropFirst(4).split(separator: "s", omittingEmptySubsequences: false)
    return (1...3).contains(pieces.count)
      && pieces.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
  }
  public static func whole(_ value: String) -> String? {
    valid(value) ? "disk" + value.dropFirst(4).split(separator: "s")[0] : nil
  }
  public static func snapshotBase(_ value: String) -> String? {
    guard valid(value) else { return nil }
    let pieces = value.dropFirst(4).split(separator: "s")
    return pieces.count == 3 ? "disk" + pieces.prefix(2).joined(separator: "s") : nil
  }
}
/// Documented read-only diskutil plist fallback; never treats unsupported status as verified.
public enum DiskutilMetadata {
  private static func object(_ data: Data) throws -> [String: Any] {
    guard data.count <= 2_000_000 else { throw DriveMetadataError.oversized }
    guard
      let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { throw DriveMetadataError.malformed }
    return value
  }
  public static func physicalDisks(_ data: Data) throws -> [String] {
    let root = try object(data)
    guard let disks = root["WholeDisks"] as? [String], disks.count <= 64,
      Set(disks).count == disks.count,
      disks.allSatisfy({ DiskDevice.valid($0) && DiskDevice.whole($0) == $0 })
    else { throw DriveMetadataError.malformed }
    return disks.sorted()
  }
  public static func topology(physical: [String], apfs data: Data) throws -> DriveTopology {
    let root = try object(data)
    guard let containers = root["Containers"] as? [[String: Any]], containers.count <= 256 else {
      throw DriveMetadataError.malformed
    }
    var associations: [String: [String]] = [:]
    var total = 0
    for container in containers {
      guard let stores = container["PhysicalStores"] as? [[String: Any]], stores.count <= 64,
        let volumes = container["Volumes"] as? [[String: Any]], volumes.count <= 1024
      else { throw DriveMetadataError.malformed }
      let identifiers = stores.compactMap { $0["DeviceIdentifier"] as? String }
      guard identifiers.count == stores.count, identifiers.allSatisfy(DiskDevice.valid) else {
        throw DriveMetadataError.malformed
      }
      let whole = Array(Set(identifiers.compactMap(DiskDevice.whole))).sorted()
      total += volumes.count; guard total <= 4096 else { throw DriveMetadataError.oversized }
      for volume in volumes {
        guard let identifier = volume["DeviceIdentifier"] as? String, DiskDevice.valid(identifier),
          associations[identifier] == nil
        else { throw DriveMetadataError.malformed }
        // Virtual/image stores remain visible associations, even when not physical health-query targets.
        associations[identifier] = whole
      }
    }
    return DriveTopology(physicalDisks: physical, physicalStoresByVolume: associations)
  }
  public static func drive(_ data: Data, expected: String) throws -> DriveMetadata {
    let root = try object(data)
    guard DiskDevice.valid(expected), root["DeviceIdentifier"] as? String == expected,
      root["WholeDisk"] as? Bool == true
    else { throw DriveMetadataError.malformed }
    let raw = (root["SMARTStatus"] as? String ?? "").lowercased().replacingOccurrences(
      of: " ", with: "")
    let status: DriveSMARTStatus =
      raw == "verified"
      ? .verified
      : raw == "failing"
        ? .failing : ["notsupported", "unsupported"].contains(raw) ? .unsupported : .unknown
    let bus = (root["BusProtocol"] as? String).flatMap { $0.utf8.count <= 64 ? $0 : nil }
    let size = (root["TotalSize"] as? NSNumber).flatMap {
      $0.doubleValue.isFinite && $0.doubleValue >= 0 && $0.doubleValue < Double(UInt64.max)
        ? $0.uint64Value : nil
    }
    return DriveMetadata(
      identifier: expected, bus: bus, solidState: root["SolidState"] as? Bool,
      internalDevice: root["Internal"] as? Bool, sizeBytes: size, smart: status)
  }
}
