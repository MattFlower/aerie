import AerieCore
import Foundation

struct CPUData {
  var user: Double?
  var system: Double?
  var cores: [Double] = []
  var groups: [(String, Int)] = []
  var load: [Double] = []
  var uptime = Double.nan
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
  var device: String?
  var usedFraction: Double { total > 0 ? max(0, min(1, 1 - free / total)) : 0 }
}
struct StorageDeviceData {
  var registryID: UInt64
  var device: String?
  var read, write: Double?
  var received, sent: UInt64?
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
  var counterBits = 64
  var session: NetworkSessionReading?
}
struct ProcessData {
  var pid: Int
  var name: String
  var cpu: Double?
  var memory: Double
  var read: Double?
  var write: Double?
  var wakeups: Double?
  var group: ProcessGroupIdentity? = nil
  var members = 1
}
enum SensorReadState { case live, deferred, unavailable }
struct SensorData {
  var key: String
  var label: String
  var value: Double?
  var unit: String
  var state = SensorReadState.live
  func title(names: [String: String]?) -> String {
    let name = names?[key] ?? label
    return name == key ? key : "\(name) [\(key)]"
  }
}
struct PowerData {
  var inventory = PowerSourceInventory()
  var source: String?
  var present = false
  var percent: Double?
  var charging: Bool?
  var external: Bool?
  var minutes: Int?
  var health: Double?
  var cycles: Int?
  var watts: Double?
  var voltage: Double?
  var amperage: Double?
  var temperature: Double?
  var peripherals: [(String, Double)] = []
  var sourceLabel: String {
    switch source {
    case "AC Power": return "AC"
    case "Battery Power": return "BAT"
    case "UPS Power": return "UPS"
    default: return "—"
    }
  }
}
struct Snapshot {
  var clockSubscriptions: Int? = nil
  var clockResidencies: [ClockResidency] = []
  var clockResidencyStatus = "Clock-state telemetry unavailable"
  var date = Date()
  var cpu = CPUData()
  var gpu = [GPUData]()
  var memory = MemoryData()
  var volumes = [VolumeData]()
  var mountedVolumePaths: [String]?
  var interfaces = [InterfaceData]()
  var networkAvailable = false
  var networkPathVersion: UInt64 = 0
  var networkSelection = NetworkSelection()
  var sensors = [SensorData]()
  var power = PowerData()
  var processes = [ProcessData]()
  var networkProcesses = [ProcessNetworkReading]()
  var networkProcessGroups = [ProcessIdentity: ProcessGroupIdentity]()
  var processNetworkStatus = "Process traffic begins when this panel opens."
  var storageDevices = [StorageDeviceData]()
  var storageMetadata = StorageMetadataReading()
  var diskRead: Double?
  var diskWrite: Double?
  var wifi: WiFiReading?
  var thermal = "Nominal"
  var thermalLevel = 0.0
  var lowPower = false
  var connectivity = "Checking"
  var sensorStatus = "Checking sensor access"
  var processDenied = 0
  /// Every owner applies demand again, including late snapshots queued before a close/pause.
  mutating func releaseActiveViewState(module: Module?, suspended: Bool) {
    if suspended || module != .storage { storageMetadata = StorageMetadataReading() }
    if suspended || module != .network {
      networkProcesses.removeAll(); networkProcessGroups.removeAll(); wifi = nil
    }
    if suspended || !(module.map { ProcessDemand.required(module: $0, visible: true) } ?? false) {
      processes.removeAll()
    }
  }
  var download: Double? {
    networkTotal(\.download)
  }
  var upload: Double? {
    networkTotal(\.upload)
  }
  private func networkTotal(_ rate: KeyPath<InterfaceData, Double?>) -> Double? {
    guard networkAvailable else { return nil }
    var total = 0.0, count = 0
    for interface in interfaces
    where networkSelection.includes(name: interface.name, active: interface.active) {
      guard let value = interface[keyPath: rate], value.isFinite, value >= 0 else { return nil }
      total += value
      guard total.isFinite else { return nil }
      count += 1
    }
    return count > 0 ? total : nil
  }
  var metrics: [String: Double] {
    var values: [String: Double] = ["thermal": thermalLevel]
    values["cpu"] = cpu.total.map { $0 * 100 }
    values["gpu"] = gpu.first?.utilization.map { $0 * 100 }
    values["memory"] = memory.validity.live(memory.usedFraction).map { $0 * 100 }
    values["battery"] = power.percent.map { $0 * 100 }
    values["temperature"] = sensors.filter { $0.unit == "°C" && $0.state == .live }.compactMap(
      \.value
    ).max()
    values["diskFree"] = volumes.first.map { $0.free / 1_073_741_824 }
    values["download"] = download
    values["upload"] = upload
    values["diskRead"] = diskRead
    values["diskWrite"] = diskWrite
    return values
  }
  /// Only explicitly configured sensor inputs are copied. History keeps its fixed series.
  func ruleMetrics(
    rules: [ThresholdRule], base: [String: Double], suspended: Bool = false
  ) -> [String: Double] {
    guard !suspended else { return [:] }
    let required = Set(
      rules.filter {
        $0.enabled && $0.valid && SensorIdentity.key(metric: $0.metric) != nil
      }.map(\.valueKey))
    guard !required.isEmpty else { return base }
    var values = base
    for sensor in sensors {
      let key = "sensor:" + sensor.key + ":" + sensor.unit
      guard required.contains(key), sensor.state == .live,
        let value = sensor.value, value.isFinite
      else { continue }
      values[key] = value
    }
    return values
  }
  var changeStates: [ChangeKind: String] {
    let zone = TimeZone.autoupdatingCurrent
    var values: [ChangeKind: String] = [
      .thermal: thermal, .lowPower: lowPower ? "Enabled" : "Disabled",
      .daylightSaving: zone.isDaylightSavingTime(for: date) ? "Active" : "Inactive",
      .timeZone: zone.identifier,
    ]
    if connectivity != "Checking" { values[.connectivity] = connectivity }
    values[.powerSource] = power.source
    if power.present, let charging = power.charging {
      values[.charging] = charging ? "Charging" : "Not charging"
    }
    values[.volumes] = mountedVolumePaths.map { $0.sorted().joined(separator: "\n") }
    return values
  }
}
