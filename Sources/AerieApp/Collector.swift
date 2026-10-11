import AerieCore
import AerieNative
import Darwin
import DiskArbitration
import Foundation
import IOKit
import IOKit.ps
import Network

private func text<T>(_ tuple: T) -> String {
  withUnsafeBytes(of: tuple) {
    String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
  }
}
private func sysNumber(_ name: String) -> UInt64? {
  var value: UInt64 = 0
  var size = MemoryLayout<UInt64>.size
  guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
  return value
}
private func sysText(_ name: String) -> String? {
  var size = 0
  guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
  var bytes = [CChar](repeating: 0, count: size)
  guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
  return String(cString: bytes)
}
private func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
  IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
    .takeRetainedValue()
}
private func services(_ name: String) -> [io_registry_entry_t] {
  var iterator: io_iterator_t = 0
  guard
    IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator)
      == KERN_SUCCESS
  else { return [] }
  defer { IOObjectRelease(iterator) }
  var result: [io_registry_entry_t] = []
  while case let service = IOIteratorNext(iterator), service != 0 { result.append(service) }
  return result
}

final class Collector {
  private let queue = DispatchQueue(label: "app.aerie.sampling", qos: .utility)
  private lazy var schedule = SamplingSchedule { [queue] interval, tick in
    DispatchSamplingTimer(queue: queue, interval: interval, tick: tick)
  }
  private var previousCPU: [UInt64] = []
  private var counters: [String: CounterSample] = [:]
  private var networkSession = NetworkSessionTracker()
  private lazy var processNetwork = ProcessNetworkReader(queue: queue)
  private var networkPanelVisible = false
  private var wifiReader: WiFiReader?
  private var storagePanelVisible = false
  private let storageMetadata = StorageMetadataReader()
  private let diskSession = DASessionCreate(kCFAllocatorDefault)
  private var diskNames: [UInt64: String] = [:]
  private var previousProcesses: [Int32: AerieProcess] = [:]
  private var processTime: Double?
  private var sensorSources:
    [(source: AerieSensorSource, key: String, label: String, unit: String)] = []
  private var accelerators = services("IOAccelerator")
  private var disks = services("IOBlockStorageDriver")
  private var groups: [(String, Int)] = []
  private let clockStates = ClockStateReader()
  private var storageIDs: Set<UInt64> = []
  private var inventoryTime = -Double.infinity
  private var cache = Snapshot()
  private var pathMonitor = NWPathMonitor()
  private var connection = "Checking"
  private var pathVersion: UInt64 = 0
  private var settings = Settings()
  private var detailed = false
  private var sensorPanelVisible = false
  private var ruleSensorKeys = Set<String>()
  private var suspended = false
  var onSample: ((Snapshot) -> Void)?

  init() {
    for index in 0..<8 {
      if let count = sysNumber("hw.perflevel\(index).logicalcpu"), count > 0 {
        groups.append((sysText("hw.perflevel\(index).name") ?? "Group \(index + 1)", Int(count)))
      }
    }
    cache.sensorStatus =
      aerie_smc_open() == 0
      ? "Read-only hardware sensors"
      : "Hardware sensor access unavailable; no elevated helper installed"
    if cache.sensorStatus == "Read-only hardware sensors" {
      var buffer = [CChar](repeating: 0, count: 4096 * 5)
      let count = aerie_smc_keys(&buffer, 4096)
      for i in 0..<Int(count) {
        let key = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress! + i * 5) }
        if key.hasPrefix("T") || key.hasPrefix("P") || key.hasPrefix("V") || key.hasPrefix("I")
          || (key.hasPrefix("F") && key.hasSuffix("Ac"))
        {
          var sensor = AerieSensor()
          if aerie_smc_read(key, &sensor) == 0, sensor.value.isFinite,
            !text(sensor.type).hasPrefix("ui")
          {
            var source = AerieSensorSource()
            if aerie_smc_source(key, &source) == 0 {
              let unit =
                key.hasPrefix("T")
                ? "°C"
                : key.hasPrefix("F")
                  ? "rpm" : key.hasPrefix("P") ? "W" : key.hasPrefix("V") ? "V" : "A"
              sensorSources.append((source, key, sensorLabel(key), unit))
            }
          }
        }
      }
      sensorSources.sort { $0.key < $1.key }
      if sensorSources.isEmpty {
        cache.sensorStatus = "Firmware exposes no supported sensors to this process"
      }
    }
    pathMonitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }; self.pathVersion &+= 1
      aerie_interfaces_invalidate()
      self.connection =
        path.status == .satisfied
        ? "Connected" : path.status == .requiresConnection ? "Connection required" : "Offline"
    }
    pathMonitor.start(queue: queue)
  }
  deinit {
    clockStates.close()
    processNetwork.stop()
    storageMetadata.configure(visible: false)
    pathMonitor.cancel()
    aerie_smc_close()
    for accelerator in accelerators { IOObjectRelease(accelerator) }
    for disk in disks { IOObjectRelease(disk) }
  }
  func configure(_ settings: Settings) {
    queue.async { [self] in
      self.settings = settings
      self.ruleSensorKeys = SensorIdentity.requiredKeys(rules: settings.rules)
      self.processNetwork.configure(
        visible: self.networkPanelVisible && !self.suspended, interval: settings.interval)
      schedule.configure(interval: settings.interval) { [weak self] in self?.sample() }
    }
  }
  func setVisibleModule(_ module: Module?) {
    queue.async {
      let value = module.map { ProcessDemand.required(module: $0, visible: true) } ?? false
      self.detailed = value;
      self.sensorPanelVisible = module == .sensors
      self.storagePanelVisible = module == .storage
      self.storageMetadata.configure(visible: self.storagePanelVisible && !self.suspended)
      self.cache.releaseActiveViewState(module: module, suspended: self.suspended)
      self.networkPanelVisible = module == .network
      self.configureWiFi()
      self.processNetwork.configure(
        visible: self.networkPanelVisible && !self.suspended, interval: self.settings.interval)
      if !self.networkPanelVisible { self.cache.networkProcesses.removeAll() }
      if !value {
        self.cache.processes.removeAll(); self.previousProcesses.removeAll(); self.processTime = nil
      }
    }
  }
  func setSuspended(_ value: Bool) {
    queue.async {
      self.suspended = value
      self.configureWiFi()
      if value { self.clockStates.close() }
      self.cache.releaseActiveViewState(
        module: self.storagePanelVisible ? .storage : self.networkPanelVisible ? .network : nil,
        suspended: value)
      self.storageMetadata.configure(visible: self.storagePanelVisible && !value)
      self.processNetwork.configure(
        visible: self.networkPanelVisible && !value, interval: self.settings.interval)
      if !value {
        self.counters.removeAll()
        self.previousCPU.removeAll()
        self.previousProcesses.removeAll()
        self.processTime = nil
        self.inventoryTime = -.infinity
        aerie_interfaces_invalidate()
      }
      self.schedule.setPaused(value)
    }
  }
  private func rate(_ key: String, _ value: UInt64, _ now: Double) -> Double? {
    let current = CounterSample(time: now, value: value)
    let result = CounterRate.rate(previous: counters[key], current: current)
    counters[key] = current
    return result
  }
  private func configureWiFi() {
    if networkPanelVisible && !suspended {
      if wifiReader == nil { wifiReader = WiFiReader() }
      wifiReader?.configure(visible: true)
    } else {
      wifiReader?.configure(visible: false); wifiReader = nil; cache.wifi = nil
    }
  }
  private func sample() {
    guard !suspended else { return }
    let now = ProcessInfo.processInfo.systemUptime
    var snapshot = cache
    snapshot.date = Date()
    storageMetadata.configure(visible: storagePanelVisible && !suspended, time: now)
    snapshot.storageMetadata = storageMetadata.reading()
    let processTraffic = processNetwork.current(time: now)
    snapshot.networkProcesses = processTraffic.rows;
    snapshot.processNetworkStatus = processTraffic.status
    if now - inventoryTime >= 30 {
      for item in accelerators { IOObjectRelease(item) }; accelerators = services("IOAccelerator")
      for item in disks { IOObjectRelease(item) }; disks = services("IOBlockStorageDriver")
      let latest = Set(
        disks.map { service -> UInt64 in
          var id: UInt64 = 0; IORegistryEntryGetRegistryEntryID(service, &id); return id
        })
      diskNames.removeAll()
      for service in disks {
        var id: UInt64 = 0; IORegistryEntryGetRegistryEntryID(service, &id)
        if let name = Self.wholeMediaName(service) { diskNames[id] = name }
      }
      if latest != storageIDs {
        counters.removeValue(forKey: "diskRead"); counters.removeValue(forKey: "diskWrite");
        for key in counters.keys where key.hasPrefix("device.") {
          counters.removeValue(forKey: key)
        }
        storageIDs = latest
      }
    }
    var ticks = [UInt64](repeating: 0, count: 256 * 4)
    let count = Int(aerie_cpu(&ticks, 256))
    ticks = Array(ticks.prefix(count * 4))
    snapshot.cpu = CPUData()
    snapshot.cpu.groups = groups
    if !ticks.isEmpty, ticks.count == previousCPU.count {
      var user = 0.0
      var system = 0.0
      var total = 0.0
      for i in 0..<count {
        let delta = (0..<4).map {
          Double(
            UInt32(truncatingIfNeeded: ticks[i * 4 + $0])
              &- UInt32(truncatingIfNeeded: previousCPU[i * 4 + $0]))
        }
        let sum = delta.reduce(0, +)
        snapshot.cpu.cores.append(sum > 0 ? (delta[0] + delta[1] + delta[3]) / sum : 0)
        user += delta[0] + delta[3]
        system += delta[1]
        total += sum
      }
      if total > 0 {
        snapshot.cpu.user = user / total
        snapshot.cpu.system = system / total
      }
    }
    previousCPU = ticks
    var loads = [Double](repeating: 0, count: 3)
    _ = getloadavg(&loads, 3)
    snapshot.cpu.load = loads
    snapshot.cpu.uptime = now
    snapshot.cpu.frequency = sysNumber("hw.cpufrequency").map { Double($0) / 1e9 }
    let clockReading = clockStates.sample(time: now)
    snapshot.clockResidencies = clockReading.rows
    snapshot.clockResidencyStatus = clockReading.status
    let memory = aerie_memory()
    snapshot.memory = Self.memoryReading(memory, previous: cache.memory, date: snapshot.date) {
      key, count in
      self.rate(key, count, now)
    }
    if snapshot.memory.validity != .fresh {
      for key in ["pageIn", "pageOut", "swapIn", "swapOut"] { counters.removeValue(forKey: key) }
    }
    var interfaces = [AerieInterface](repeating: AerieInterface(), count: 128)
    let networkCount = Int(aerie_interfaces(&interfaces, 128))
    snapshot.networkAvailable = networkCount >= 0
    snapshot.networkSelection = settings.networkSelection
    snapshot.interfaces = interfaces.prefix(max(0, networkCount)).map {
      let name = text($0.name)
      if let previous = cache.interfaces.first(where: { $0.name == name }),
        previous.counterBits != Int($0.counter_bits)
      {
        counters.removeValue(forKey: "\(name).in"); counters.removeValue(forKey: "\(name).out")
      }
      return InterfaceData(
        name: name, active: $0.active != 0, addresses: text($0.addresses),
        received: $0.received, sent: $0.sent, download: rate("\(name).in", $0.received, now),
        upload: rate("\(name).out", $0.sent, now), errors: $0.errors_in + $0.errors_out,
        counterBits: Int($0.counter_bits))
    }
    if networkCount < 0 {
      networkSession.reset()
      for key in counters.keys where key.hasSuffix(".in") || key.hasSuffix(".out") {
        counters.removeValue(forKey: key)
      }
    }
    let sessions = networkSession.update(
      snapshot.interfaces.map {
        NetworkCounterRecord(
          name: $0.name, received: $0.received, sent: $0.sent, bits: $0.counterBits)
      }, date: snapshot.date)
    for index in snapshot.interfaces.indices {
      snapshot.interfaces[index].session = sessions[snapshot.interfaces[index].name]
    }
    var reads: UInt64 = 0
    var writes: UInt64 = 0
    var diskValid = false
    snapshot.storageDevices.removeAll(keepingCapacity: true)
    for disk in disks {
      var id: UInt64 = 0; IORegistryEntryGetRegistryEntryID(disk, &id)
      var device = StorageDeviceData(registryID: id, device: diskNames[id])
      if let statistics = property(disk, "Statistics") as? [String: NSNumber],
        let read = statistics["Bytes (Read)"], let write = statistics["Bytes (Write)"]
      {
        reads += read.uint64Value
        writes += write.uint64Value
        diskValid = true
        device.received = read.uint64Value; device.sent = write.uint64Value
        device.read = rate("device.\(id).read", read.uint64Value, now)
        device.write = rate("device.\(id).write", write.uint64Value, now)
      }
      snapshot.storageDevices.append(device)
    }
    snapshot.diskRead = diskValid ? rate("diskRead", reads, now) : nil
    snapshot.diskWrite = diskValid ? rate("diskWrite", writes, now) : nil
    snapshot.gpu = accelerators.map { service in
      var gpu = GPUData()
      gpu.name = property(service, "model") as? String ?? "GPU"
      let stats = property(service, "PerformanceStatistics") as? [String: NSNumber] ?? [:]
      gpu.utilization = stats["Device Utilization %"].map { $0.doubleValue / 100 }
      gpu.renderer = stats["Renderer Utilization %"].map { $0.doubleValue / 100 }
      gpu.tiler = stats["Tiler Utilization %"].map { $0.doubleValue / 100 }
      gpu.memory = stats["In use system memory"]?.doubleValue
      gpu.temperature = stats["Temperature(C)"]?.doubleValue
      gpu.frequency = stats["Core Clock(MHz)"].map { $0.doubleValue / 1000 }
      gpu.fps = stats["Frames Per Second"]?.doubleValue
      return gpu
    }
    snapshot.sensors = sensorSources.map { entry in
      Self.sensorReading(
        SensorData(key: entry.key, label: entry.label, value: nil, unit: entry.unit),
        mode: settings.effectiveSensorSampling, panelVisible: sensorPanelVisible,
        ruleRequired: ruleSensorKeys.contains(entry.key)
      ) {
        var value = 0.0; return aerie_smc_value(entry.source, &value) == 0 ? value : nil
      }
    }
    snapshot.power = power()
    if now - inventoryTime >= 30 {
      let inventory = volumes()
      snapshot.volumes = inventory?.rows ?? []
      snapshot.mountedVolumePaths = inventory?.paths
      snapshot.power.peripherals = peripherals()
      inventoryTime = now
    } else {
      snapshot.power.peripherals = cache.power.peripherals
    }
    snapshot.connectivity = connection
    if let wifiReader {
      snapshot.wifi = wifiReader.current(
        time: now, path: pathVersion, authorization: WiFiAccess.nativeAuthorization())
    } else {
      snapshot.wifi = nil
    }
    snapshot.networkPathVersion = pathVersion
    let state = ProcessInfo.processInfo.thermalState
    snapshot.thermal = ["Nominal", "Fair", "Serious", "Critical"][min(3, state.rawValue)]
    snapshot.thermalLevel = Double(state.rawValue)
    snapshot.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    if detailed { snapshot.processes = processes(now, &snapshot.processDenied) }
    cache = snapshot
    DispatchQueue.main.async { [weak self] in self?.onSample?(snapshot) }
  }
  static func sensorReading(
    _ descriptor: SensorData, mode: SensorSamplingMode, panelVisible: Bool,
    ruleRequired: Bool = false,
    read: () -> Double?
  ) -> SensorData {
    var result = descriptor; result.value = nil
    guard
      SensorDemand.required(
        unit: descriptor.unit, mode: mode, panelVisible: panelVisible, ruleRequired: ruleRequired)
    else {
      result.state = .deferred; return result
    }
    guard let value = read(), value.isFinite,
      descriptor.unit != "°C" || (-50...150).contains(value)
    else {
      result.state = .unavailable; return result
    }
    result.value = value; result.state = .live; return result
  }
  static func memoryReading(
    _ memory: AerieMemory, previous: MemoryData, date: Date,
    rate: (String, UInt64) -> Double?
  ) -> MemoryData {
    guard memory.valid != 0, memory.total > 0 else {
      var missing = MemoryData()
      missing.sampledAt = previous.sampledAt
      missing.validity = previous.sampledAt.map { .stale(lastSuccess: $0) } ?? .unavailable
      return missing
    }
    return MemoryData(
      validity: .fresh, sampledAt: date,
      total: Double(memory.total),
      app: Double(memory.internal > memory.purgeable ? memory.internal - memory.purgeable : 0),
      wired: Double(memory.wired), compressed: Double(memory.compressed),
      free: Double(memory.free), cached: Double(memory.external),
      purgeable: Double(memory.purgeable),
      swap: Double(memory.swap_used), swapTotal: Double(memory.swap_total),
      pressure: memory.pressure == 1
        ? "Normal"
        : memory.pressure == 2 ? "Warning" : memory.pressure == 4 ? "Critical" : "Unavailable",
      usedFraction: memory.total > 0
        ? min(
          1,
          Double(
            memory.internal + memory.wired + memory.compressed
              - min(memory.internal, memory.purgeable)) / Double(memory.total)) : nil,
      pageIn: rate("pageIn", memory.pageins), pageOut: rate("pageOut", memory.pageouts),
      swapIn: rate("swapIn", memory.swapins), swapOut: rate("swapOut", memory.swapouts))
  }
  private func processes(_ now: Double, _ denied: inout Int) -> [ProcessData] {
    var buffer = [AerieProcess](repeating: AerieProcess(), count: 8192)
    let count = Int(aerie_processes(&buffer, 8192))
    var latest: [Int32: AerieProcess] = [:]
    var result: [ProcessData] = []
    denied = 0
    for p in buffer.prefix(count) {
      guard p.valid != 0 else {
        denied += 1
        continue
      }
      latest[p.pid] = p
      let previous = previousProcesses[p.pid]
      let compatible = previous?.start_time == p.start_time
      let dt = processTime.map { now - $0 } ?? 0
      func delta(_ current: UInt64, _ old: UInt64?) -> Double? {
        guard compatible, let old, current >= old, dt > 0, dt <= 30 else { return nil }
        return Double(current - old) / dt
      }
      let cpu = delta(p.cpu_ns, previous?.cpu_ns).map {
        $0 / 1e9 / Double(settings.normalizedProcessCPU ? max(1, cache.cpu.cores.count) : 1)
      }
      result.append(
        ProcessData(
          pid: Int(p.pid), name: text(p.name), cpu: cpu,
          memory: Double(p.footprint), read: delta(p.disk_read, previous?.disk_read),
          write: delta(p.disk_write, previous?.disk_write),
          wakeups: delta(p.wakeups, previous?.wakeups)))
    }
    previousProcesses = latest
    processTime = now
    return result
  }
  private static func wholeMediaName(_ service: io_registry_entry_t) -> String? {
    var iterator: io_iterator_t = 0
    guard
      IORegistryEntryCreateIterator(
        service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
        == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    var count = 0
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }; count += 1; if count > 4096 { return nil }
      if IOObjectConformsTo(entry, "IOMedia") != 0, property(entry, "Whole") as? Bool == true,
        let name = property(entry, "BSD Name") as? String, DiskDevice.valid(name)
      {
        return name
      }
    }
    return nil
  }
  private func volumes() -> (rows: [VolumeData], paths: [String])? {
    let keys: Set<URLResourceKey> = [
      .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey, .volumeIsRemovableKey, .volumeIsLocalKey,
      .volumeIsReadOnlyKey,
    ]
    guard
      let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes])
    else { return nil }
    let rows = urls.compactMap { url -> VolumeData? in
      guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity,
        let free = v.volumeAvailableCapacity, total > 0
      else { return nil }
      return VolumeData(
        name: v.volumeName ?? url.lastPathComponent, path: url.path,
        total: Double(total), free: Double(free),
        important: v.volumeAvailableCapacityForImportantUsage.map(Double.init),
        removable: v.volumeIsRemovable ?? false, local: v.volumeIsLocal ?? true,
        readOnly: v.volumeIsReadOnly ?? false,
        device: diskSession.flatMap { session in
          DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL).flatMap { disk in
            DADiskGetBSDName(disk).map { String(cString: $0) }
          }
        })
    }.sorted { $0.path == "/" || ($1.path != "/" && $0.name < $1.name) }
    return (rows, urls.map(\.path))
  }
  private func power() -> PowerData {
    var power = PowerData()
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    {
      if let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
        power.source = source as String
      }
      for source in sources {
        guard
          let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
            as? [String: Any],
          let current = details[kIOPSCurrentCapacityKey] as? Double,
          let maximum = details[kIOPSMaxCapacityKey] as? Double, maximum > 0
        else { continue }
        power.present = true
        power.percent = current / maximum
        power.charging = details[kIOPSIsChargingKey] as? Bool ?? false
        power.external = (details[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let remaining =
          details[power.charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
        power.minutes = remaining.flatMap { $0 >= 0 ? $0 : nil }
      }
    }
    let battery = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    if battery != 0 {
      defer { IOObjectRelease(battery) }
      func number(_ key: String) -> Double? { (property(battery, key) as? NSNumber)?.doubleValue }
      if let maximum = number("AppleRawMaxCapacity"), let design = number("DesignCapacity"),
        design > 0
      {
        power.health = maximum / design
      }
      power.cycles = number("CycleCount").map(Int.init)
      power.voltage = number("Voltage").map { $0 / 1000 }
      // Some drivers expose signed current using an unsigned 64-bit NSNumber.
      if let n = property(battery, "Amperage") as? NSNumber {
        power.amperage = Double(Int64(bitPattern: n.uint64Value)) / 1000
      }
      if let v = power.voltage, let a = power.amperage { power.watts = v * a }
      power.temperature = number("Temperature").map { $0 / 100 }
    }
    return power
  }
  private func peripherals() -> [(String, Double)] {
    var result: [(String, Double)] = []
    for device in services("AppleDeviceManagementHIDEventService") {
      defer { IOObjectRelease(device) }
      if let value = property(device, "BatteryPercent") as? NSNumber {
        result.append(
          (property(device, "Product") as? String ?? "Peripheral", value.doubleValue / 100))
      }
    }
    return result
  }
  private func sensorLabel(_ key: String) -> String {
    let known = [
      "TC0P": "CPU proximity", "TC0D": "CPU die", "TG0P": "GPU proximity", "TG0D": "GPU die",
      "TB0T": "Battery", "TA0P": "Ambient", "Ts0P": "Palm rest", "F0Ac": "Fan 1", "F1Ac": "Fan 2",
      "PC0C": "CPU power", "PG0C": "GPU power", "PSTR": "System power",
    ]
    return known[key] ?? key
  }
}
