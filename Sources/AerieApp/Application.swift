import AerieCore
import AppKit
import EventKit
import ServiceManagement
import UserNotifications
import UniformTypeIdentifiers

final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let defaults = UserDefaults.standard
  private var settings = Settings()
  private var items: [(MenuConfiguration, NSStatusItem)] = []
  private var collector: Collector?
  private var snapshot = Snapshot()
  private var history = HistoryStore()
  private var historyPersistence: HistoryPersistence?
  private var rules = RuleEngine()
  private var changeRules = ChangeRuleEngine()
  private var dashboard = DashboardController()
  private var popover = NSPopover()
  private var preferences: PreferencesController?
  private var keyboardShortcuts: KeyboardShortcuts?
  private var shortcutStatus: String?
  private var publicAddressReader: PublicAddressReader?
  private let samplingProfiler: SamplingProfiler? =
    CommandLine.arguments.contains("--sampling-profile")
    ? SamplingProfiler(scope: "presentation") : nil
  private var wifiAccess: WiFiAccess?
  private let calendarAccess = CalendarAccess()
  private lazy var calendarReader = CalendarEventReader(access: calendarAccess)
  private var calendarAuthorized = false
  private var calendarSelection = CalendarSelection()
  private var lastCalendarRefresh = Date.distantPast
  private var calendarDetails: [String: (title: String, text: String)] = [:]
  private var calendarObserver: NSObjectProtocol?
  private var clockObservers: [NSObjectProtocol] = []
  private var weatherTask: Task<Void, Never>?
  private var weatherGeneration = 0
  private var weatherReport: WeatherReport?
  private var weatherFetchTime = Date.distantPast
  private var weatherStatus = "Weather is off"
  private var weatherMaps: WeatherMapWindowController?
  private var weatherDetails: WeatherDetailWindow?
  private var paused = false
  private var sleeping = false
  private var selfCheckSamples = 0
  private var observers: [NSObjectProtocol] = []
  private lazy var ridgeMark = ridgeImage()
  private let clockFormatter = DateFormatter()
  private var graphValues: [Module: [Double?]] = [:]
  private var stackedValues: [Module: [String]] = [:]
  private var accessibilityValues: [Module: String] = [:]

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    if let data = defaults.data(forKey: "settings"),
      let decoded = try? JSONDecoder().decode(Settings.self, from: data),
      let valid = try? decoded.validated()
    {
      settings = valid
    }
    if CommandLine.arguments.contains("--sensor-sampling-demand") {
      settings.sensorSampling = .whenNeeded
    }
    if CommandLine.arguments.contains("--history-archive-path") {
      settings.persistentHistory = true
    }
    history.configure(interval: settings.interval)
    configureHistoryPersistence(load: true)
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 416, height: 620)
    popover.contentViewController = dashboard
    popover.delegate = self
    dashboard.canvas.onSelectDate = { [weak self] date in
      self?.calendarSelection.select(date); self?.updateCalendar()
    }
    dashboard.canvas.onMoveMonth = { [weak self] offset in
      guard let self else { return }
      self.calendarSelection.move(months: offset, now: Date(), calendar: self.menuCalendar)
      self.updateCalendar()
    }
    dashboard.canvas.onToday = { [weak self] in
      self?.calendarSelection.today(); self?.updateCalendar()
    }
    dashboard.canvas.onAction = { [weak self] identifier in
      if let self, identifier.hasPrefix("clock-state:"),
        let index = Int(identifier.dropFirst(12)),
        self.dashboard.snapshot.clockResidencies.indices.contains(index)
      {
        let reading = self.dashboard.snapshot.clockResidencies[index]
        let frequency = reading.activeGHz.map { String(format: "%.3f GHz", $0) } ?? "Unavailable"
        let states = reading.states.map {
          "\($0.name): \(String(format: "%.3f%%", $0.fraction * 100))"
        }.joined(separator: "\n")
        self.showWeatherDetail(
          title: reading.name + " · clock states",
          message:
            "Interval: \(self.settings.interval) seconds\nActive-labelled state residency: \(Format.percent(reading.activeFraction))\nActive interval-weighted frequency: \(frequency)\n\n\(states.isEmpty ? "No valid counter baseline." : states)\n\nPercentages describe the distribution within each reported channel, separately from scheduler CPU load. Channels can cover different power domains. Active percentage requires a named inactive bucket; GHz requires explicit frequency labels for every occupied active state."
        )
        return
      }
      if let self, self.dashboard.module == .weather, identifier.hasPrefix("weather-alert:"),
        let index = Int(identifier.dropFirst(14)), let report = self.dashboard.weather?.alertReport,
        report.alerts.indices.contains(index)
      {
        self.showWeatherDetail(
          title: report.alerts[index].event,
          message: "Current point alerts fetched: \(report.fetched.formatted())\n\n"
            + AlertPresentation.message(report.alerts[index]));
        return
      }
      if let self, self.dashboard.module == .weather, identifier.hasPrefix("weather-period:"),
        let index = Int(identifier.dropFirst(15)), let report = self.dashboard.weather,
        report.periods.indices.contains(index)
      {
        let period = report.periods[index]
        let formatter = DateFormatter(); formatter.timeZone = report.timeContext.instantZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        let temperature =
          period.temperature.map { Format.temperature($0, unit: self.settings.temperature) }
          ?? "Unavailable"
        let text =
          "Valid: \(formatter.string(from: period.start)) – \(formatter.string(from: period.end))\nForecast-period temperature: \(temperature)\nWind: \(period.wind)\nPrecipitation probability: \(period.precipitation.map { String(format: "%.0f%%", $0) } ?? "Unavailable")\n\n\(period.condition)\n\n\(period.detail)\n\nSource: \(report.source) · fetched \(report.fetched.formatted())"
        self.showWeatherDetail(title: period.name, message: text); return
      }
      guard let self, let detail = self.calendarDetails[identifier],
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
      else { return }
      let alert = NSAlert(); alert.messageText = detail.title; alert.informativeText = detail.text
      alert.addButton(withTitle: "Close"); alert.runModal()
    }
    calendarObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: nil, queue: .main
    ) { [weak self] _ in
      self?.lastCalendarRefresh = .distantPast
      self?.calendarReader.cancel()
      self?.calendarDetails.removeAll()
      self?.updateCalendar()
    }
    for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
      clockObservers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          self?.clockFormatter.timeZone = .current
          self?.updateItems()
          self?.updateCalendar()
        })
    }
    dashboard.onSettings = { [weak self] in self?.showSettings() }
    dashboard.onMaps = { [weak self] in self?.showMaps() }
    dashboard.onExportHistory = { [weak self] in self?.exportHistory(window: $0, points: $1) }
    dashboard.onModule = { [weak self] module in
      self?.collector?.setVisibleModule(module)
      self?.releaseViewMetadata(module: module)
      self?.updateCalendar()
    }
    rebuildItems()
    applyAppearance()
    configureShortcuts()
    configurePublicAddress()
    let collector = Collector()
    self.collector = collector
    collector.onSample = { [weak self] in self?.receive($0) }
    collector.configure(settings)
    if CommandLine.arguments.contains("--process-network-self-check") {
      collector.setVisibleModule(.network)
    }
    if CommandLine.arguments.contains("--storage-self-check") {
      collector.setVisibleModule(.storage)
    }
    if CommandLine.arguments.contains("--network-demand-cycles") {
      for start in [3.0, 68.0, 133.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + start) { [weak collector] in
          collector?.setVisibleModule(.network)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + start + 45) { [weak collector] in
          collector?.setVisibleModule(nil)
        }
      }
    }
    if CommandLine.arguments.contains("--storage-demand-cycles") {
      for start in [3.0, 38.0, 73.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + start) { [weak collector] in
          collector?.setVisibleModule(.storage)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + start + 12) { [weak collector] in
          collector?.setVisibleModule(nil)
        }
      }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.sleeping = true
        self?.cancelWiFiPermission()
        self?.configurePublicAddress()
        self?.dashboard.suspended = true
        self?.collector?.setSuspended(true)
        self?.releaseViewMetadata(module: nil)
        self?.clearCalendar()
        self?.rules.reset()
        self?.changeRules.reset()
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        guard let self else { return }
        self.sleeping = false
        self.configurePublicAddress()
        self.dashboard.suspended = self.paused
        self.collector?.setSuspended(self.paused)
        self.weatherFetchTime = .distantPast
        if self.popover.isShown { self.updateCalendar() }
      })
    if !CommandLine.arguments.contains("--self-check"),
      !CommandLine.arguments.contains("--background"), !defaults.bool(forKey: "hasShownWelcome")
    {
      defaults.set(true, forKey: "hasShownWelcome"); showSettings()
    }
  }
  func applicationDidHide(_ notification: Notification) {
    cancelWiFiPermission()
    popover.performClose(nil); collector?.setVisibleModule(nil)
  }
  func applicationWillTerminate(_ notification: Notification) {
    if let calendarObserver { NotificationCenter.default.removeObserver(calendarObserver) }
    for observer in clockObservers { NotificationCenter.default.removeObserver(observer) }
    clockObservers.removeAll()
    historyPersistence?.save(
      history, interval: settings.interval, selection: settings.networkSelection, force: true)
    historyPersistence?.finish()
    clearCalendar()
    calendarAccess.cancel()
    cancelWiFiPermission()
    keyboardShortcuts?.stop(); keyboardShortcuts = nil
    weatherTask?.cancel()
    weatherMaps?.releaseResources(); weatherMaps = nil
    weatherDetails?.close(); weatherDetails = nil
    collector = nil
    publicAddressReader?.stop(); publicAddressReader = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
  private func receive(_ reading: Snapshot) {
    samplingProfiler?.begin(.appReceive)
    defer { samplingProfiler?.finish() }
    dashboard.suspended = paused || sleeping
    preferences?.validateCalendarAccess()
    var snapshot = reading; snapshot.networkSelection = settings.networkSelection
    snapshot.releaseActiveViewState(
      module: popover.isShown ? dashboard.module : nil, suspended: paused || sleeping)
    if snapshot.wifi != nil {
      snapshot.wifi?.recheckAuthorization(WiFiAccess.nativeAuthorization())
    }
    self.snapshot = snapshot
    publicAddressReader?.tick(
      time: ProcessInfo.processInfo.systemUptime,
      route: snapshot.networkAvailable && snapshot.connectivity == "Connected"
        ? String(snapshot.networkPathVersion) : nil)
    samplingProfiler?.mark(.appHistory)
    let metrics = snapshot.metrics
    history.append(HistoryPoint(date: snapshot.date, values: metrics))
    historyPersistence?.save(
      history, interval: settings.interval, selection: settings.networkSelection)
    samplingProfiler?.mark(.appRules)
    for rule in rules.evaluate(
      rules: settings.rules,
      values: snapshot.ruleMetrics(
        rules: settings.rules, base: metrics, suspended: paused || sleeping),
      time: ProcessInfo.processInfo.systemUptime)
    {
      notify(rule)
    }
    if !paused, !sleeping, let configured = settings.changeRules,
      configured.contains(where: \.enabled)
    {
      for event in changeRules.evaluate(
        rules: configured, values: snapshot.changeStates,
        time: ProcessInfo.processInfo.systemUptime)
      {
        notify(event)
      }
    }
    samplingProfiler?.mark(.appMenu)
    updateItems()
    samplingProfiler?.mark(.appVisible)
    if popover.isShown {
      if dashboard.module == .time { updateCalendar(force: false) }
      dashboard.snapshot = snapshot
      dashboard.history = history
      dashboard.historyStatus = historyPersistence?.status ?? "History archive is off"
      dashboard.settings = settings
      dashboard.weather = weatherReport
      dashboard.weatherStatus = weatherStatus
      dashboard.shortcutStatus = shortcutStatus
      updatePublicAddressView()
      dashboard.refresh()
    }
    samplingProfiler?.mark(.appWeather)
    updateWeather()
    if CommandLine.arguments.contains("--storage-self-check") {
      selfCheckSamples += 1
      if (selfCheckSamples >= 12 && reading.storageMetadata.queriedAt != nil)
        || selfCheckSamples == 30
      {
        collector?.setVisibleModule(nil)
        let metadata = reading.storageMetadata
        let topology = metadata.topology
        let output: [String: Any] = [
          "scenario": "headless read-only Storage demand; no actual open panel",
          "ioSources": snapshot.storageDevices.count,
          "associatedIOSources": snapshot.storageDevices.filter { $0.device != nil }.count,
          "volumesWithBSDName": snapshot.volumes.filter { $0.device != nil }.count,
          "volumesWithBacking": snapshot.volumes.filter { volume in
            volume.device.map { !(topology?.underlyingDisks(for: $0) ?? []).isEmpty } ?? false
          }.count,
          "physicalDrives": topology?.physicalDisks.count ?? 0,
          "healthReports": metadata.drives.count,
          "smartVerified": metadata.drives.values.filter { $0.smart == .verified }
            .count,
          "status": metadata.status,
        ]
        selfCheckSamples = -1000
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
          if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
          {
            print(text)
          }
          NSApp.terminate(nil)
        }
      }
    }
    if CommandLine.arguments.contains("--process-network-self-check") {
      selfCheckSamples += 1
      if selfCheckSamples == 12 {
        collector?.setVisibleModule(nil)
        let output: [String: Any] = [
          "scenario": "headless logical network demand; no actual open panel",
          "processRows": snapshot.networkProcesses.count,
          "liveRates": snapshot.networkProcesses.filter { $0.download != nil && $0.upload != nil }
            .count,
          "status": snapshot.processNetworkStatus, "systemInterval": settings.interval,
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
          if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
          {
            print(text)
          }
          NSApp.terminate(nil)
        }
      }
    }
    if CommandLine.arguments.contains("--self-check") {
      selfCheckSamples += 1
      if selfCheckSamples >= 3 {
        let output: [String: Any] = [
          "cpu": snapshot.cpu.total != nil, "cores": snapshot.cpu.cores.count,
          "memory": snapshot.memory.total > 0, "interfaces": snapshot.interfaces.count,
          "networkCountersAvailable": snapshot.networkAvailable,
          "networkFullWidthCounters": !snapshot.interfaces.isEmpty
            && snapshot.interfaces.allSatisfy { $0.counterBits == 64 },
          "volumes": snapshot.volumes.count, "gpu": snapshot.gpu.count,
          "sensors": snapshot.sensors.count, "sensorStatus": snapshot.sensorStatus,
          "sensorSampling": settings.effectiveSensorSampling.rawValue,
          "publicAddressLookup": settings.effectivePublicAddress,
          "publicAddressReaderAllocated": publicAddressReader != nil,
          "liveSensors": snapshot.sensors.filter { $0.state == .live }.count,
          "deferredSensors": snapshot.sensors.filter { $0.state == .deferred }.count,
          "temperatureInventory": snapshot.sensors.filter { $0.unit == "°C" }.count,
          "liveTemperatures": snapshot.sensors.filter { $0.unit == "°C" && $0.state == .live }
            .count,
          "battery": snapshot.power.present,
          "powerSources": snapshot.power.inventory.sources.count,
          "powerSourcesComplete": snapshot.power.inventory.complete,
          "internalPowerSources": snapshot.power.inventory.sources.filter {
            $0.kind == .internalBattery
          }.count,
          "upsPowerSources": snapshot.power.inventory.sources.filter { $0.kind == .ups }.count,
          "unambiguousBattery": snapshot.power.inventory.primaryBattery != nil,
          "diskActivity": snapshot.diskRead != nil,
          "refreshInterval": settings.interval, "weatherOptIn": settings.weather.enabled,
          "clockStateSubscriptions": snapshot.clockSubscriptions ?? -1,
          "clockStateChannels": snapshot.clockResidencies.count,
          "cpuComplexClockChannels": snapshot.clockResidencies.filter { $0.kind == .cpuComplex }
            .count,
          "cpuCoreClockChannels": snapshot.clockResidencies.filter { $0.kind == .cpuCore }.count,
          "gpuClockChannels": snapshot.clockResidencies.filter { $0.kind == .gpu }.count,
          "liveClockResidencies": snapshot.clockResidencies.filter { $0.activeFraction != nil }
            .count,
          "explicitClockFrequencies": snapshot.clockResidencies.filter { $0.activeGHz != nil }
            .count,
          "clockStateStatus": snapshot.clockResidencyStatus,
          "persistentHistory": settings.effectivePersistentHistory,
          "configuredShortcuts": (settings.shortcuts ?? []).count,
          "registeredShortcuts": keyboardShortcuts?.registeredCount ?? 0,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
        {
          print(text)
        }
        NSApp.terminate(nil)
      }
    }
  }
  private func configureHistoryPersistence(load: Bool = false, erase: Bool = false) {
    if historyPersistence == nil, settings.effectivePersistentHistory {
      let arguments = CommandLine.arguments
      let url: URL?
      if let index = arguments.firstIndex(of: "--history-archive-path"),
        index + 1 < arguments.count, arguments[index + 1].hasPrefix("/")
      {
        url = URL(fileURLWithPath: arguments[index + 1])
      } else {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
          .first?.appendingPathComponent("Aerie/history-v1.json")
      }
      if let url { historyPersistence = HistoryPersistence(file: LocalHistoryFile(url: url)) }
    }
    historyPersistence?.configure(enabled: settings.effectivePersistentHistory, erase: erase)
    if load {
      let loadingSelection = settings.networkSelection
      historyPersistence?.load(interval: settings.interval, selection: settings.networkSelection) {
        [weak self] restored in
        guard let self, var restored, self.settings.effectivePersistentHistory,
          self.history.recent.count < self.history.recent.capacity
        else { return }
        // Only merge when every sample since launch is still retained; no partial replay.
        for point in self.history.recent.values { restored.append(point) }
        if self.settings.networkSelection != loadingSelection {
          restored.removeMetrics(["download", "upload"])
        }
        restored.configure(interval: self.settings.interval)
        self.history = restored
      }
    }
  }
  private func exportHistory(window: Int, points: [HistoryPoint]) {
    let data = HistoryCSV.data(
      points: points,
      resolutionSeconds: window == 0 ? settings.interval : window == 1 ? 60 : 3600,
      aggregateScope: settings.networkSelection.description)
    popover.performClose(nil)
    let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "Aerie-history.csv"
    panel.message =
      "Export retained numeric system history. Dates, readings and selected interface names stay in the file you choose. Missing readings are blank; aggregate sample counts describe observed coverage."
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { result in
      guard result == .OK, let url = panel.url else { return }
      do { try data.write(to: url, options: .atomic) } catch {
        let alert = NSAlert(); alert.messageText = "History export failed"
        alert.informativeText = "The selected file could not be written."; alert.runModal()
      }
    }
  }
  private func rebuildItems() {
    for (_, item) in items { NSStatusBar.system.removeStatusItem(item) }
    items.removeAll()
    graphValues.removeAll(); stackedValues.removeAll()
    accessibilityValues.removeAll()
    clockFormatter.dateFormat = settings.clockFormat
    let menus =
      settings.combined
      ? [
        MenuConfiguration(
          module: .overview, style: settings.combinedStyle ?? .text,
          colorHex: settings.combinedColorHex)
      ]
      : settings.menus.filter(\.visible)
    for menu in menus {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item.isVisible = true
      if let button = item.button {
        button.target = self
        button.action = #selector(clickedStatus(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Aerie \(menu.module.title)")
      }
      items.append((menu, item))
    }
    updateItems()
  }
  @objc private func clickedStatus(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      for (title, action) in [
        ("Aerie Settings…", #selector(showSettings)),
        (paused ? "Resume Sampling" : "Pause Sampling", #selector(togglePaused)),
        ("Open Activity Monitor", #selector(activityMonitor)), ("Quit Aerie", #selector(quit)),
      ] {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
      }
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
      return
    }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    let module = items.first { $0.1.button === sender }?.0.module ?? .overview
    showModule(module, anchoredTo: sender)
  }
  private func showModule(_ module: Module, anchoredTo button: NSStatusBarButton) {
    if popover.isShown { popover.performClose(nil) }
    dashboard.snapshot = snapshot
    dashboard.settings = settings
    updatePublicAddressView()
    dashboard.history = history
    dashboard.historyStatus = historyPersistence?.status ?? "History archive is off"
    dashboard.weather = weatherReport
    dashboard.weatherStatus = weatherStatus
    dashboard.shortcutStatus = shortcutStatus
    _ = dashboard.view
    dashboard.show(module)
    updateCalendar(opening: true)
    collector?.setVisibleModule(module)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }
  func popoverDidClose(_ notification: Notification) {
    collector?.setVisibleModule(nil); releaseViewMetadata(module: nil)
    dashboard.history = HistoryStore(interval: settings.interval);
    dashboard.canvas.points.removeAll(); dashboard.canvas.selectedPoint = nil
    clearCalendar(); dashboard.canvas.releaseInteractiveRows()
    calendarSelection.today()
  }
  private func releaseViewMetadata(module: Module?) {
    snapshot.releaseActiveViewState(module: module, suspended: paused || sleeping)
    dashboard.snapshot.releaseActiveViewState(module: module, suspended: paused || sleeping)
    if paused || sleeping || module != .network { dashboard.releaseWiFi() }
  }
  private func updateItems() {
    for (configuration, item) in items {
      guard let button = item.button else { continue }
      let module = configuration.module
      let components = (settings.combined ? settings.effectiveCombinedModules : [module]).map {
        menuValue($0)
      }
      let value = MenuPresentation.combined(components, compact: false)
      let color = MenuRenderer.color(configuration.colorHex)
      button.contentTintColor = color
      if configuration.style == .stacked {
        let lines = MenuPresentation.stacked(components)
        let first = (paused ? "⏸ " : "") + lines.0
        let identity = [first, lines.1, configuration.colorHex ?? "system"]
        if stackedValues[module] != identity {
          button.title = ""; button.image = MenuRenderer.stacked(first, lines.1, color: color)
          stackedValues[module] = identity
        }
      } else if configuration.style == .graph, let key = graphKey(module) {
        let points = history.recent.suffix(48).map { $0.values[key] }
        if graphValues[module] != points {
          if !button.title.isEmpty { button.title = "" }
          button.image = graphImage(points, key: key, color: color)
          graphValues[module] = points
        }
      } else {
        if module == .overview {
          if button.image !== ridgeMark { button.image = ridgeMark }
        } else if button.image != nil {
          button.image = nil
        }
        let title = MenuPresentation.combined(components, compact: configuration.style == .compact)
        let displayed = paused ? "⏸ " + title : title
        if button.attributedTitle.string != displayed {
          let font = NSFont.monospacedDigitSystemFont(
            ofSize: settings.compactSpacing ? 10 : 11, weight: .medium)
          button.attributedTitle = NSAttributedString(
            string: displayed,
            attributes: [.font: font, .foregroundColor: color ?? NSColor.labelColor])
        }
      }
      let accessible: String
      if configuration.style == .stacked {
        let lines = MenuPresentation.stacked(components)
        accessible = lines.0 + " · " + lines.1 + (paused ? " · sampling paused" : "")
      } else {
        accessible = value + (paused ? " · sampling paused" : "")
      }
      let tooltip = "Aerie \(module.title): \(accessible)\(paused ? " · sampling paused" : "")"
      if button.toolTip != tooltip { button.toolTip = tooltip }
      if accessibilityValues[module] != accessible {
        button.setAccessibilityValue(accessible); accessibilityValues[module] = accessible
      }
    }
  }
  private func menuValue(_ module: Module) -> MenuValue {
    switch module {
    case .overview:
      return MenuValue(full: "Aerie", secondary: "CPU " + Format.percent(snapshot.cpu.total))
    case .cpu:
      return MenuValue(
        full: "CPU " + Format.percent(snapshot.cpu.total),
        compact: Format.percent(snapshot.cpu.total),
        secondary: "U " + Format.percent(snapshot.cpu.user) + " S "
          + Format.percent(snapshot.cpu.system))
    case .gpu:
      return MenuValue(
        full: "GPU " + Format.percent(snapshot.gpu.first?.utilization),
        compact: Format.percent(snapshot.gpu.first?.utilization),
        secondary: snapshot.gpu.first?.memory.map {
          "MEM " + Format.bytes($0, binary: settings.binaryBytes)
        } ?? "MEM —")
    case .memory:
      return MenuValue(
        full: "MEM " + Format.percent(snapshot.memory.usedFraction),
        compact: Format.percent(snapshot.memory.usedFraction),
        secondary: snapshot.memory.usedFraction.map {
          Format.bytes($0 * snapshot.memory.total, binary: settings.binaryBytes)
        } ?? "Unavailable")
    case .storage:
      return MenuValue(
        full: "SSD " + (snapshot.volumes.first.map { Format.percent($0.usedFraction) } ?? "—"),
        compact: snapshot.volumes.first.map { Format.percent($0.usedFraction) } ?? "—",
        secondary: "R " + shortRate(snapshot.diskRead) + " W " + shortRate(snapshot.diskWrite))
    case .network:
      return MenuValue(
        full: "↓" + shortRate(snapshot.download) + " ↑" + shortRate(snapshot.upload),
        secondary: "↑" + shortRate(snapshot.upload),
        stackedPrimary: "↓" + shortRate(snapshot.download))
    case .sensors:
      let temperatures = snapshot.sensors.filter { $0.unit == "°C" && $0.state == .live }
        .compactMap(\.value)
      let current =
        temperatures.first.map { Format.temperature($0, unit: settings.temperature) } ?? "TEMP —"
      return MenuValue(
        full: current,
        secondary: temperatures.max().map {
          "MAX " + Format.temperature($0, unit: settings.temperature)
        } ?? "Unavailable")
    case .power:
      return MenuValue(
        full: snapshot.power.present
          ? "BAT " + Format.percent(snapshot.power.percent) : "PWR " + snapshot.power.sourceLabel,
        compact: snapshot.power.present
          ? Format.percent(snapshot.power.percent) : snapshot.power.sourceLabel,
        secondary: snapshot.power.minutes.map { Format.duration(Double($0) * 60) } ?? snapshot.power
          .source ?? "Time unavailable")
    case .time:
      return MenuValue(
        full: clockFormatter.string(from: Date()),
        secondary: TimeZone.current.abbreviation() ?? "Local")
    case .weather:
      return MenuValue(
        full: weatherReport?.temperature.map { Format.temperature($0, unit: settings.temperature) }
          ?? "WX —",
        secondary: weatherReport?.condition ?? weatherReport.map {
          WeatherCondition.describe($0.code)
        } ?? "Weather unavailable")
    }
  }
  private func shortRate(_ value: Double?) -> String {
    guard let value else { return "—" }
    let bytes = settings.networkBits ? value * 8 : value
    let divisor = settings.networkBits || !settings.binaryBytes ? 1000.0 : 1024.0
    if bytes >= divisor * divisor { return String(format: "%.1fM", bytes / divisor / divisor) }
    return String(format: "%.0fK", bytes / divisor)
  }
  private func graphKey(_ module: Module) -> String? {
    switch module {
    case .cpu: return "cpu"
    case .gpu: return "gpu"
    case .memory: return "memory"
    case .network: return "download"
    case .storage: return "diskRead"
    case .power: return "battery"
    case .sensors: return "temperature"
    default: return nil
    }
  }
  private func graphImage(_ points: [Double?], key: String, color: NSColor?) -> NSImage {
    let image = NSImage(size: NSSize(width: 48, height: 18), flipped: true) { rect in
      let maxValue =
        ["cpu", "gpu", "memory", "battery"].contains(key)
        ? 100 : max(1, points.compactMap { $0 }.max() ?? 1)
      drawSparkline(
        points, in: rect.insetBy(dx: 2, dy: 2), color: color ?? .labelColor, maximum: maxValue)
      return true
    }
    image.isTemplate = color == nil
    return image
  }
  private func ridgeImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
      let path = NSBezierPath()
      path.lineWidth = 1.7
      path.lineJoinStyle = .round
      path.move(to: NSPoint(x: 1, y: 3))
      path.line(to: NSPoint(x: 6, y: 13))
      path.line(to: NSPoint(x: 10, y: 6))
      path.line(to: NSPoint(x: 13, y: 10))
      path.line(to: NSPoint(x: 18, y: 3))
      NSColor.labelColor.setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }
  @objc private func showSettings() {
    popover.performClose(nil)
    if let preferences {
      preferences.showWindow(nil); NSApp.activate(ignoringOtherApps: true); return
    }
    preferences = PreferencesController(settings: settings)
    preferences?.onApply = { [weak self] in self?.apply($0) }
    preferences?.onClose = { [weak self] in
      self?.cancelWiFiPermission(); self?.preferences = nil
    }
    preferences?.onDashboard = { [weak self] in
      guard let self, let button = self.items.first?.1.button else { return };
      self.preferences?.close(); self.clickedStatus(button)
    }
    preferences?.onNotifications = { [weak self] in self?.requestNotifications() }
    preferences?.onCalendar = { [weak self] in self?.requestCalendar() }
    preferences?.onWiFiPermission = { [weak self] in self?.requestWiFiPermission() }
    preferences?.onLogin = { [weak self] in self?.requestLogin() }
    preferences?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private func apply(_ settings: Settings) {
    guard let valid = try? settings.validated() else { return }
    let weatherChanged = self.settings.weather != valid.weather
    let networkChanged = self.settings.networkSelection != valid.networkSelection
    let persistenceChanged =
      self.settings.effectivePersistentHistory != valid.effectivePersistentHistory
    self.settings = valid
    snapshot.networkSelection = valid.networkSelection
    if networkChanged { history.removeMetrics(["download", "upload"]) }
    history.configure(interval: valid.interval)
    if persistenceChanged { configureHistoryPersistence(erase: !valid.effectivePersistentHistory) }
    if let data = try? JSONEncoder().encode(valid) { defaults.set(data, forKey: "settings") }
    collector?.configure(valid)
    rebuildItems()
    applyAppearance()
    configureShortcuts()
    configurePublicAddress()
    lastCalendarRefresh = .distantPast
    if popover.isShown { updateCalendar() }
    rules.reset()
    changeRules.reset()
    if weatherChanged {
      weatherDetails?.close(); weatherDetails = nil
      weatherMaps?.close(); weatherMaps = nil
      weatherGeneration += 1
      weatherTask?.cancel()
      weatherTask = nil
      weatherReport = nil
      weatherFetchTime = .distantPast
      weatherStatus = valid.weather.valid ? "Fetching forecast" : "Weather is off"
      updateWeather()
    }
  }
  private func configureShortcuts() {
    let configured = settings.shortcuts ?? []
    guard !configured.isEmpty else {
      keyboardShortcuts?.stop(); keyboardShortcuts = nil; shortcutStatus = nil; return
    }
    if keyboardShortcuts == nil {
      keyboardShortcuts = KeyboardShortcuts()
      keyboardShortcuts?.onPress = { [weak self] binding in
        guard let self else { return }
        guard let module = binding.module else { self.showSettings(); return }
        if self.popover.isShown, self.dashboard.module == module {
          self.popover.performClose(nil); return
        }
        guard
          let button = self.items.first(where: { $0.0.module == module })?.1.button
            ?? self.items.first?.1.button
        else { return }
        NSApp.activate(ignoringOtherApps: true)
        self.showModule(module, anchoredTo: button)
      }
      keyboardShortcuts?.onReconfigured = { [weak self] failures in
        self?.shortcutStatus = failures.isEmpty ? nil : failures.joined(separator: " · ")
      }
    }
    let failures = keyboardShortcuts?.configure(configured) ?? []
    shortcutStatus = failures.isEmpty ? nil : failures.joined(separator: " · ")
  }
  private func configurePublicAddress() {
    guard settings.effectivePublicAddress else {
      publicAddressReader?.stop(); publicAddressReader = nil; updatePublicAddressView(); return
    }
    if publicAddressReader == nil {
      publicAddressReader = PublicAddressReader()
      publicAddressReader?.onUpdate = { [weak self] in
        guard let self else { return }; self.updatePublicAddressView()
        if self.popover.isShown && self.dashboard.module == .network { self.dashboard.refresh() }
      }
    }
    publicAddressReader?.configure(enabled: true, suspended: paused || sleeping)
    updatePublicAddressView()
  }
  private func updatePublicAddressView() {
    dashboard.updatePublicAddress(
      publicAddressReader?.reading,
      status: publicAddressReader?.status ?? "Public IP lookup is off")
  }
  private func showMaps() {
    popover.performClose(nil)
    guard settings.weather.mapsValid else { showSettings(); return }
    if let weatherMaps {
      weatherMaps.showWindow(nil); NSApp.activate(ignoringOtherApps: true); return
    }
    do {
      let controller = try WeatherMapWindowController(configuration: settings.weather)
      weatherMaps = controller
      controller.onClose = { [weak self] in self?.weatherMaps = nil }
      controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    } catch { notice("Enable NOAA maps and choose a manual location in Weather Settings.") }
  }
  private func showWeatherDetail(title: String, message: String) {
    weatherDetails?.close()
    let controller = WeatherDetailWindow(title: title, message: message)
    controller.onClose = { [weak self] in self?.weatherDetails = nil }
    weatherDetails = controller; controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private func applyAppearance() {
    switch settings.theme {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
  }
  @objc private func togglePaused() {
    paused.toggle()
    configurePublicAddress()
    dashboard.suspended = paused || sleeping
    collector?.setSuspended(paused || sleeping)
    if paused {
      cancelWiFiPermission()
      releaseViewMetadata(module: nil); clearCalendar()
    } else if popover.isShown {
      updateCalendar()
    }
    rules.reset()
    changeRules.reset()
    updateItems()
  }
  @objc private func activityMonitor() {
    if let url = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.apple.ActivityMonitor")
    {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
  }
  @objc private func quit() { NSApp.terminate(nil) }
  private func notify(_ rule: ThresholdRule) {
    let content = UNMutableNotificationContent()
    let sensor = SensorIdentity.key(metric: rule.metric).flatMap { key in
      snapshot.sensors.first { $0.key == key && $0.unit == rule.sensorUnit }
    }
    content.title = "Aerie · \(sensor?.title(names: settings.sensorNames) ?? rule.metric)"
    let unit = rule.sensorUnit.map { " " + $0 } ?? ""
    content.body =
      "\(rule.comparison.rawValue.capitalized) \(rule.threshold)\(unit) for \(Int(rule.duration)) seconds."
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: rule.id.uuidString, content: content, trigger: nil))
  }
  private func requestNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
      if error != nil {
        DispatchQueue.main.async {
          self.notice("Notifications could not be enabled. Review the macOS permission setting.")
        }
      }
    }
  }
  private func notify(_ event: ChangeEvent) {
    let content = UNMutableNotificationContent()
    content.title = "Aerie · \(event.rule.kind.title)"
    content.body =
      event.rule.kind == .volumes
      ? "The mounted volume inventory changed."
      : "\(event.previous) → \(event.current)"
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: event.rule.id.uuidString, content: content, trigger: nil))
  }
  private func requestCalendar() {
    calendarAccess.request { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else { return }
        if granted {
          self.updateCalendar()
        } else {
          self.clearCalendar(); self.notice("Calendar access remains unavailable.")
        }
      }
    }
  }
  private func cancelWiFiPermission() { wifiAccess?.cancel(); wifiAccess = nil }
  private func requestWiFiPermission() {
    guard !paused, !sleeping else {
      notice("Resume sampling before requesting Wi-Fi identity access."); return
    }
    if wifiAccess == nil { wifiAccess = WiFiAccess() }
    wifiAccess?.request(foreground: NSApp.isActive && preferences?.window?.isVisible == true) {
      [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let status):
        self.notice(status.description + ". Open Network to refresh available details.")
      case .failure(.requiresForeground):
        self.notice("Activate Aerie Settings before requesting Wi-Fi identity access.")
      case .failure(.alreadyRequesting): break
      }
    }
  }
  private func requestLogin() {
    do {
      try SMAppService.mainApp.register()
      notice("Launch at Login enabled. You can disable Aerie in macOS Login Items.")
    } catch {
      notice(
        "Launch at Login could not be enabled for this build. Use a packaged Aerie.app in a stable location."
      )
    }
  }
  private func notice(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Aerie"
    alert.informativeText = message
    alert.runModal()
  }
  private var menuCalendar: Calendar {
    var calendar = Calendar.current
    calendar.firstWeekday = settings.weekStartsMonday ? 2 : 1
    return calendar
  }
  private func clearCalendar() {
    dashboard.releaseDaylight()
    calendarReader.cancel(); calendarDetails.removeAll(); dashboard.calendarRows.removeAll()
    if dashboard.module == .time { dashboard.canvas.releaseInteractiveRows() }
    lastCalendarRefresh = .distantPast
  }
  private func updateCalendar(force: Bool = true, opening: Bool = false) {
    guard !paused, !sleeping, dashboard.module == .time, popover.isShown || opening else {
      clearCalendar(); return
    }
    let now = Date(), calendar = menuCalendar
    let selectedCalendarDate = calendarSelection.date(now: now)
    let authorized = calendarAccess.hasAccess
    guard
      force || authorized != calendarAuthorized || now.timeIntervalSince(lastCalendarRefresh) >= 60
        || !calendar.isDate(now, inSameDayAs: lastCalendarRefresh)
    else { return }
    calendarAuthorized = authorized
    calendarReader.cancel()
    lastCalendarRefresh = now
    calendarDetails.removeAll()
    guard
      let month = CalendarMonth.make(
        displayedMonth: selectedCalendarDate, selected: selectedCalendarDate, now: now,
        calendar: calendar, showsWeekNumbers: settings.showWeekNumbers)
    else {
      calendarReader.cancel()
      dashboard.calendarRows = [.note("The current calendar could not produce this month.")]
      dashboard.refresh(); return
    }
    var rows: [DashboardRow] = [.calendar(month), .heading(month.selectedDayTitle)]
    if settings.eventCalendars?.isEmpty == true {
      rows.append(
        .note("No event calendars selected. Choose calendars in Time Settings to include events."))
    } else if !authorized {
      rows.append(
        .note(
          "Enable Calendar Events in Settings → Permissions to show local events. Date selection works without access."
        ))
    } else {
      rows.append(.note("Reading local events…"))
      let upcomingEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now
      let ranges = [month.dayInterval, DateInterval(start: now, end: upcomingEnd)]
      calendarReader.load(ranges: ranges, calendars: settings.eventCalendars) {
        [weak self] result in
        guard let self, !self.paused, self.dashboard.module == .time, self.popover.isShown else {
          return
        }
        self.calendarDetails.removeAll()
        var eventRows: [DashboardRow] = [.calendar(month), .heading(month.selectedDayTitle)]
        if result.denied {
          eventRows.append(.note("Calendar access is unavailable. No event details are retained."))
        } else {
          if result.unavailableCalendars > 0 {
            eventRows.append(
              .note(
                "\(result.unavailableCalendars) saved calendars are unavailable. Review the selection in Time Settings."
              ))
          }
          let formatter = DateFormatter(); formatter.calendar = calendar;
          formatter.timeZone = calendar.timeZone
          formatter.setLocalizedDateFormatFromTemplate("EEE jmm z")
          let detailFormatter = DateFormatter(); detailFormatter.calendar = calendar;
          detailFormatter.timeZone = calendar.timeZone
          detailFormatter.setLocalizedDateFormatFromTemplate("EEE MMM d y jmm z")
          for (index, section) in result.ranges.enumerated() {
            if index == 1 { eventRows.append(.heading("Upcoming events · next seven days")) }
            if section.events.isEmpty {
              eventRows.append(
                .note(index == 0 ? "No events on this day." : "No events in the next seven days."))
            }
            for event in section.events {
              let identifier = UUID().uuidString
              eventRows.append(
                .action(
                  event.title, event.allDay ? "All day" : formatter.string(from: event.start),
                  identifier))
              var lines = [
                "Starts: " + detailFormatter.string(from: event.start),
                "Ends: " + detailFormatter.string(from: event.end),
              ]
              if event.allDay { lines.append("All-day event; the end date is exclusive.") }
              if !event.calendar.isEmpty { lines.append("Calendar: " + event.calendar) }
              if !event.location.isEmpty { lines.append("Location: " + event.location) }
              if !event.notes.isEmpty { lines.append(event.notes) }
              self.calendarDetails[identifier] = (event.title, lines.joined(separator: "\n"))
            }
            if section.truncated {
              eventRows.append(
                .note(
                  "Scan stopped at 2,000 events. Showing the earliest 20 within that scanned subset; more events may exist."
                ))
            } else if section.scanned > 20 {
              eventRows.append(
                .note("Showing the earliest 20 of \(section.scanned) scanned events."))
            }
          }
          eventRows.append(
            .note("Events remain local. Refreshes each minute while this menu is open."))
        }
        self.dashboard.calendarRows = eventRows; self.dashboard.refresh()
      }
    }
    dashboard.calendarRows = rows
    dashboard.refresh()
  }
  private func updateWeather() {
    guard settings.weather.valid, weatherTask == nil,
      Date().timeIntervalSince(weatherFetchTime) >= 900
    else { return }
    let configuration = settings.weather
    let generation = weatherGeneration
    weatherFetchTime = Date()
    weatherStatus = "Fetching forecast"
    weatherTask = Task { @MainActor [weak self] in
      do {
        let report: WeatherReport
        if configuration.provider == "nws" {
          report = try await NWSProvider().fetch(configuration: configuration)
        } else {
          report = try await OpenMeteoProvider().fetch(configuration: configuration)
        }
        guard !Task.isCancelled else { return }
        guard let self, self.weatherGeneration == generation else { return }
        self.weatherReport = report
        self.weatherStatus =
          "Updated \(report.fetched.formatted(date: .omitted, time: .shortened)) · refresh 15 min"
        self.weatherTask = nil
      } catch {
        guard !Task.isCancelled else { return }
        guard let self, self.weatherGeneration == generation else { return }
        self.weatherStatus =
          self.weatherReport == nil
          ? "Forecast unavailable; retry in 15 minutes"
          : "Cached forecast is stale; retry in 15 minutes"
        self.weatherTask = nil
      }
    }
  }
}
