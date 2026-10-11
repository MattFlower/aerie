import AerieNative
@testable import AerieApp
import XCTest

final class SensorDecoderTests: XCTestCase {
  private func type(_ name: String) -> UInt32 { name.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
  private func decode(_ name: String, _ bytes: [UInt8]) -> Double? {
    var result = 123.0
    let status = bytes.withUnsafeBufferPointer {
      aerie_smc_decode(type(name), $0.baseAddress, UInt32(bytes.count), &result)
    }
    if status != 0 { XCTAssertEqual(result, 123); return nil }
    return result
  }
  func testFixedPointSignFractionsAndIntegerByteOrder() {
    XCTAssertEqual(decode("sp78", [0x19, 0x80]), 25.5)
    XCTAssertEqual(decode("sp78", [0xfe, 0x80]), -1.5)
    XCTAssertEqual(decode("fpe2", [0x1f, 0x40]), 2000)
    XCTAssertEqual(decode("fp88", [1, 0]), 1)
    XCTAssertEqual(decode("sp87", [0xff, 0x80]), -1)
    XCTAssertEqual(decode("ui8 ", [255]), 255)
    XCTAssertEqual(decode("ui16", [0x12, 0x34]), 4660)
    XCTAssertEqual(decode("ui32", [0xde, 0xad, 0xbe, 0xef]), 3735928559)
  }
  func testFloatPayloadsHaveExactWidthAndRejectNonfiniteValues() {
    XCTAssertEqual(decode("flt ", [0, 0, 0x48, 0x42]), 50)
    XCTAssertEqual(decode("flt ", [0, 0, 0, 0]), 0)
    XCTAssertNil(decode("flt ", [0, 0, 0x80, 0x7f]))
    XCTAssertNil(decode("flt ", [0, 0, 0xc0, 0x7f]))
    XCTAssertNil(decode("flt ", [0, 0, 0]))
  }
  func testFriendlyFirmwareRoleNamesNeverEstablishVerifiedHardwareMapping() {
    XCTAssertEqual(Collector.sensorLabel("TST0"), "TST0")
    XCTAssertTrue(Collector.sensorLabel("TC0D").contains("unverified role"))
    XCTAssertTrue(Collector.sensorLabel("PG0C").contains("unverified role"))
    XCTAssertTrue(Collector.sensorLabel("TA0P").contains("unverified role"))
    XCTAssertEqual(Collector.sensorLabel("F0Ac"), "Fan 1")
  }
  func testOnlyDeclaredSupportedNumericFamiliesAcquireExistingUnits() {
    var source = AerieSensorSource(); source.type = type("sp78"); source.size = 2
    XCTAssertEqual(Collector.sensorUnit(key: "TST0", source: source), "°C")
    XCTAssertEqual(Collector.sensorUnit(key: "IST0", source: source), "A")
    XCTAssertEqual(Collector.sensorUnit(key: "PST0", source: source), "W")
    XCTAssertEqual(Collector.sensorUnit(key: "VST0", source: source), "V")
    source.type = type("fpe2")
    XCTAssertEqual(Collector.sensorUnit(key: "F0Ac", source: source), "rpm")
    XCTAssertNil(Collector.sensorUnit(key: "F0Mn", source: source))
    XCTAssertNil(Collector.sensorUnit(key: "ALV0", source: source))
    XCTAssertNil(Collector.sensorUnit(key: "CLK0", source: source))
    source.type = type("ui16"); XCTAssertNil(Collector.sensorUnit(key: "TST0", source: source))
    source.type = type("none"); XCTAssertNil(Collector.sensorUnit(key: "TST0", source: source))
    source.type = type("sp78"); source.size = 1
    XCTAssertNil(Collector.sensorUnit(key: "TST0", source: source))
  }
  func testMalformedWidthsEncodingsAndPointersStayUnavailable() {
    for (name, bytes) in [
      ("sp78", [UInt8(1)]), ("fpe2", [1]), ("ui16", [1]), ("ui32", [1, 2]), ("ui8 ", [1, 2]),
      ("sp77", [1, 2]), ("fpG2", [1, 2]), ("none", [1, 2]), ("sp78", []),
    ] {
      XCTAssertNil(decode(name, bytes))
    }
    XCTAssertNil(decode("sp78", Array(repeating: 0, count: 33)))
    var value = 77.0
    XCTAssertEqual(aerie_smc_decode(type("sp78"), nil, 2, &value), -1)
    XCTAssertEqual(value, 77)
    XCTAssertEqual(
      [UInt8(1), 2].withUnsafeBufferPointer {
        aerie_smc_decode(type("sp78"), $0.baseAddress, 2, nil)
      }, -1)
  }
}
