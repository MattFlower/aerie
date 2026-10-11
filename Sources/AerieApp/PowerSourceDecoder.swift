import AerieCore
import Foundation
import IOKit.ps

/// Copy documented IOPS values while their snapshot owns the borrowed dictionary.
enum PowerSourceDecoder {
  static func number(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let value = number.doubleValue
    return value.isFinite ? value : nil
  }
  static func boolean(_ value: Any?) -> Bool? {
    guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
      return nil
    }
    return value.boolValue
  }
  static func integer(_ value: Any?, maximum: Int = Int.max / 60) -> Int? {
    guard let value = number(value), value >= 0, value < Double(Int.max),
      value.rounded(.towardZero) == value
    else { return nil }
    let integer = Int(value)
    return integer <= maximum ? integer : nil
  }
  static func decode(_ details: [String: Any]) -> PowerSourceReading {
    let kind: PowerSourceKind
    switch details[kIOPSTypeKey] as? String {
    case kIOPSInternalBatteryType: kind = .internalBattery
    case kIOPSUPSType: kind = .ups
    default: kind = .unknown
    }
    let input: PowerInputState
    switch details[kIOPSPowerSourceStateKey] as? String {
    case kIOPSACPowerValue: input = .ac
    case kIOPSBatteryPowerValue: input = .battery
    case kIOPSOffLineValue: input = .offline
    default: input = .unknown
    }
    let charging = boolean(details[kIOPSIsChargingKey])
    let time: Int?
    if charging == true {
      time = integer(details[kIOPSTimeToFullChargeKey])
    } else if charging == false, input == .battery {
      time = integer(details[kIOPSTimeToEmptyKey])
    } else {
      // IOPS time-to-empty is valid only on battery power while not charging.
      time = nil
    }
    return PowerSourceReading(
      name: details[kIOPSNameKey] as? String, kind: kind,
      transport: details[kIOPSTransportTypeKey] as? String,
      present: boolean(details[kIOPSIsPresentKey]), input: input, charging: charging,
      current: number(details[kIOPSCurrentCapacityKey]),
      maximum: number(details[kIOPSMaxCapacityKey]),
      minutes: time, voltage: number(details[kIOPSVoltageKey]).map { $0 / 1000 },
      amperage: number(details[kIOPSCurrentKey]).map { $0 / 1000 },
      temperature: number(details[kIOPSTemperatureKey]))
  }
  static func data(
    descriptions: [[String: Any]?], reportedCount: Int, suppliedSource: String?
  ) -> PowerData {
    let bounded = descriptions.prefix(PowerSourceInventory.limit)
    let inventory = PowerSourceInventory(
      sources: bounded.compactMap { $0.map(decode) }, available: true,
      reportedCount: reportedCount, unreadableCount: bounded.filter { $0 == nil }.count)
    var power = PowerData()
    power.source = suppliedSource; power.inventory = inventory
    power.present = !inventory.batteries.isEmpty
    if let battery = inventory.primaryBattery {
      power.percent = battery.percent; power.charging = battery.charging
      power.external = battery.input == .unknown ? nil : battery.input == .ac
      power.minutes = battery.minutes
    }
    return power
  }
}
