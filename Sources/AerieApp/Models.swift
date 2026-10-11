import AerieCore
import Foundation

struct CPUData {
  var user: Double?
  var system: Double?
  var cores: [Double] = []
  var groups: [(String, Int)] = []
  var load: [Double] = []
  var uptime = 0.0
  var frequency: Double?
  var total: Double? {
    if let user, let system { return user + system }
    return nil
  }
}
struct GPUData {
  var name = "GPU"
  var utilization: Double?
  var renderer: Double?
  var tiler: Double?
  var memory: Double?
  var temperature: Double?
  var frequency: Double?
  var fps: Double?
}
struct MemoryData {
  var validity = ReadingValidity.unavailable
  var sampledAt: Date?
  var total = 0.0
  var app = 0.0
  var wired = 0.0
  var compressed = 0.0
  var free = 0.0
  var cached = 0.0
  var purgeable = 0.0
  var swap = 0.0
  var swapTotal = 0.0
  var pressure = "Unavailable"
  var usedFraction: Double?
  var pageIn: Double?
  var pageOut: Double?
  var swapIn: Double?
  var swapOut: Double?
}
struct VolumeData {
  var name: String
  var path: String
  var total: Double
  var free: Double
  var important: Double?
  var removable: Bool
  var local: Bool
  var readOnly: Bool
  var usedFraction: Double { total > 0 ? max(0, min(1, 1 - free / total)) : 0 }
}
struct InterfaceData {
  var name: String
  var active: Bool
  var addresses: String
  var received: UInt64
  var sent: UInt64
  var download: Double?
  var upload: Double?
  var errors: UInt64
}
struct ProcessData {
  var pid: Int
  var name: String
  var cpu: Double?
  var memory: Double
  var read: Double?
  var write: Double?
  var wakeups: Double?
}
struct SensorData {
  var key: String
  var label: String
  var value: Double
  var unit: String
}
struct PowerData {
  var present = false
  var percent: Double?
  var charging = false
  var external = false
  var minutes: Int?
  var health: Double?
  var cycles: Int?
  var watts: Double?
  var voltage: Double?
  var amperage: Double?
  var temperature: Double?
  var peripherals: [(String, Double)] = []
}
struct Snapshot {
  var date = Date()
  var cpu = CPUData()
  var gpu = [GPUData]()
  var memory = MemoryData()
  var volumes = [VolumeData]()
  var interfaces = [InterfaceData]()
  var sensors = [SensorData]()
  var power = PowerData()
  var processes = [ProcessData]()
  var diskRead: Double?
  var diskWrite: Double?
  var wifi: [String: String] = [:]
  var thermal = "Nominal"
  var thermalLevel = 0.0
  var lowPower = false
  var connectivity = "Checking"
  var sensorStatus = "Checking sensor access"
  var processDenied = 0
  var download: Double? {
    let values = interfaces.filter(\.active).compactMap(\.download)
    return values.isEmpty ? nil : values.reduce(0, +)
  }
  var upload: Double? {
    let values = interfaces.filter(\.active).compactMap(\.upload)
    return values.isEmpty ? nil : values.reduce(0, +)
  }
  var metrics: [String: Double] {
    var values: [String: Double] = ["thermal": thermalLevel]
    values["cpu"] = cpu.total.map { $0 * 100 }
    values["gpu"] = gpu.first?.utilization.map { $0 * 100 }
    values["memory"] = memory.validity.live(memory.usedFraction).map { $0 * 100 }
    values["battery"] = power.percent.map { $0 * 100 }
    values["temperature"] = sensors.filter { $0.unit == "°C" }.map(\.value).max()
    values["diskFree"] = volumes.first.map { $0.free / 1_073_741_824 }
    values["download"] = download
    values["upload"] = upload
    values["diskRead"] = diskRead
    values["diskWrite"] = diskWrite
    return values
  }
}
