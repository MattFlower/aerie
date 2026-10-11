import AerieNative
import Darwin
import Foundation
import XCTest

final class InterfaceTests: XCTestCase {
  private func bytes<T>(_ value: T) -> Data { withUnsafeBytes(of: value) { Data($0) } }
  private func interface(_ index: UInt16, loopback: Bool = false) -> if_msghdr2 {
    var message = if_msghdr2()
    message.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
    message.ifm_version = UInt8(RTM_VERSION); message.ifm_type = UInt8(RTM_IFINFO2)
    message.ifm_index = index
    message.ifm_flags = Int32(IFF_UP | IFF_RUNNING | (loopback ? IFF_LOOPBACK : 0))
    message.ifm_data.ifi_ibytes = 6_000_000_000; message.ifm_data.ifi_obytes = 9_000_000_000
    message.ifm_data.ifi_ierrors = 4
    return message
  }
  private func parse(_ data: Data, capacity: Int = 4) -> (Int, [AerieInterfaceCounter]) {
    var values = [AerieInterfaceCounter](repeating: AerieInterfaceCounter(), count: capacity)
    let count = data.withUnsafeBytes { buffer in
      aerie_interface_counters(buffer.baseAddress, buffer.count, &values, Int32(capacity))
    }
    return (Int(count), Array(values.prefix(max(0, Int(count)))))
  }
  func testShortAddressMessageBetweenLoopbackAndInterfaceDoesNotEndEnumeration() {
    var address = ifa_msghdr()
    address.ifam_msglen = UInt16(MemoryLayout<ifa_msghdr>.size)
    address.ifam_version = UInt8(RTM_VERSION); address.ifam_type = UInt8(RTM_NEWADDR)
    XCTAssertLessThan(MemoryLayout<ifa_msghdr>.size, MemoryLayout<if_msghdr>.size)
    let data = bytes(interface(1, loopback: true)) + bytes(address) + bytes(interface(7))
    let (count, values) = parse(data)
    XCTAssertEqual(count, 1); XCTAssertEqual(values.first?.index, 7)
    XCTAssertEqual(values.first?.received, 6_000_000_000)
    XCTAssertEqual(values.first?.sent, 9_000_000_000)
    XCTAssertEqual(values.first?.errors_in, 4); XCTAssertEqual(values.first?.active, 1)
  }
  func testMalformedTruncatedAndCapacityExceededSnapshotsAreRejected() {
    let valid = bytes(interface(7))
    XCTAssertEqual(parse(Data(valid.dropLast())).0, -1)
    XCTAssertEqual(parse(Data([0, 0, UInt8(RTM_VERSION), UInt8(RTM_IFINFO2)])).0, -1)
    var wrongVersion = interface(7); wrongVersion.ifm_version = 0
    XCTAssertEqual(parse(bytes(wrongVersion)).0, -1)
    XCTAssertEqual(parse(valid + bytes(interface(8)), capacity: 1).0, -1)
  }
}
