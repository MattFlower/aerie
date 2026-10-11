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
  private var rules = RuleEngine()
  private var changeRules = ChangeRuleEngine()
  private var dashboard = DashboardController()
  private var popover = NSPopover()
  private var preferences: PreferencesController?
  private var eventStore: EKEventStore?
  private var selectedCalendarDate = Date()
  private var lastCalendarRefresh = Date.distantPast
  private var calendarDetails: [String: (title: String, text: String)] = [:]
  private var calendarObserver: NSObjectProtocol?
  private var weatherTask: Task<Void, Never>?
  private var weatherGeneration = 0
  private var weatherReport: WeatherReport?
  private var weatherFetchTime = Date.distantPast
  private var weatherStatus = "Weather is off"
  private var weatherMaps: WeatherMapWindowController?
  private var weatherDetails: WeatherDetailWindow?
  private var paused = false
  private var selfCheckSamples = 0
  private var observers: [NSObjectProtocol] = []
  private lazy var ridgeMark = ridgeImage()
  private let clockFormatter = DateFormatter()
  private var graphValues: [Module: [Double?]] = [:]
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
    history.configure(interval: settings.interval)
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 416, height: 620)
    popover.contentViewController = dashboard
    popover.delegate = self
    dashboard.canvas.onSelectDate = { [weak self] date in
      self?.selectedCalendarDate = date; self?.updateCalendar()
    }
    dashboard.canvas.onMoveMonth = { [weak self] offset in
      guard let self,
        let date = CalendarMonth.movedSelection(
          self.selectedCalendarDate, months: offset, calendar: self.menuCalendar)
      else { return }
      self.selectedCalendarDate = date; self.updateCalendar()
    }
    dashboard.canvas.onToday = { [weak self] in
      self?.selectedCalendarDate = Date(); self?.updateCalendar()
    }
    dashboard.canvas.onAction = { [weak self] identifier in
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
    }
    dashboard.onSettings = { [weak self] in self?.showSettings() }
    dashboard.onMaps = { [weak self] in self?.showMaps() }
    dashboard.onExportHistory = { [weak self] in self?.exportHistory(window: $0) }
    dashboard.onModule = { [weak self] module in
      self?.collector?.setVisibleModule(module)
      self?.updateCalendar()
    }
    rebuildItems()
    applyAppearance()
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
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.collector?.setSuspended(true)
        self?.rules.reset()
        self?.changeRules.reset()
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        guard let self else { return }
        self.collector?.setSuspended(self.paused)
        self.weatherFetchTime = .distantPast
      })
    if !CommandLine.arguments.contains("--self-check"),
      !CommandLine.arguments.contains("--background"), !defaults.bool(forKey: "hasShownWelcome")
    {
      defaults.set(true, forKey: "hasShownWelcome"); showSettings()
    }
  }
  func applicationDidHide(_ notification: Notification) {
    popover.performClose(nil); collector?.setVisibleModule(nil)
  }
  func applicationWillTerminate(_ notification: Notification) {
    if let calendarObserver { NotificationCenter.default.removeObserver(calendarObserver) }
    clearCalendar()
    weatherTask?.cancel()
    weatherMaps?.releaseResources(); weatherMaps = nil
    weatherDetails?.close(); weatherDetails = nil
    collector = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
  private func receive(_ reading: Snapshot) {
    var snapshot = reading; snapshot.networkSelection = settings.networkSelection
    self.snapshot = snapshot
    let metrics = snapshot.metrics
    history.append(HistoryPoint(date: snapshot.date, values: metrics))
    for rule in rules.evaluate(
      rules: settings.rules, values: metrics, time: ProcessInfo.processInfo.systemUptime)
    {
      notify(rule)
    }
    if let configured = settings.changeRules, configured.contains(where: \.enabled) {
      for event in changeRules.evaluate(
        rules: configured, values: snapshot.changeStates,
        time: ProcessInfo.processInfo.systemUptime)
      {
        notify(event)
      }
    }
    updateItems()
    if popover.isShown {
      if dashboard.module == .time { updateCalendar(force: false) }
      dashboard.snapshot = snapshot
      dashboard.history = history
      dashboard.settings = settings
      dashboard.weather = weatherReport
      dashboard.weatherStatus = weatherStatus
      dashboard.refresh()
    }
    updateWeather()
    if CommandLine.arguments.contains("--storage-self-check") {
      selfCheckSamples += 1
      if (selfCheckSamples >= 12 && snapshot.storageMetadata.queriedAt != nil)
        || selfCheckSamples == 30
      {
        collector?.setVisibleModule(nil)
        let topology = snapshot.storageMetadata.topology
        let output: [String: Any] = [
          "scenario": "headless read-only Storage demand; no actual open panel",
          "ioSources": snapshot.storageDevices.count,
          "associatedIOSources": snapshot.storageDevices.filter { $0.device != nil }.count,
          "volumesWithBSDName": snapshot.volumes.filter { $0.device != nil }.count,
          "volumesWithBacking": snapshot.volumes.filter { volume in
            volume.device.map { !(topology?.underlyingDisks(for: $0) ?? []).isEmpty } ?? false
          }.count,
          "physicalDrives": topology?.physicalDisks.count ?? 0,
          "healthReports": snapshot.storageMetadata.drives.count,
          "smartVerified": snapshot.storageMetadata.drives.values.filter { $0.smart == .verified }
            .count,
          "status": snapshot.storageMetadata.status,
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
          "liveSensors": snapshot.sensors.filter { $0.state == .live }.count,
          "deferredSensors": snapshot.sensors.filter { $0.state == .deferred }.count,
          "temperatureInventory": snapshot.sensors.filter { $0.unit == "°C" }.count,
          "liveTemperatures": snapshot.sensors.filter { $0.unit == "°C" && $0.state == .live }
            .count,
          "battery": snapshot.power.present, "diskActivity": snapshot.diskRead != nil,
          "refreshInterval": settings.interval, "weatherOptIn": settings.weather.enabled,
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
  private func exportHistory(window: Int) {
    let data = HistoryCSV.data(
      points: history.points(window: window),
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
    graphValues.removeAll()
    accessibilityValues.removeAll()
    clockFormatter.dateFormat = settings.clockFormat
    let menus =
      settings.combined
      ? [MenuConfiguration(module: .overview, style: settings.menus.first?.style ?? .text)]
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
    dashboard.snapshot = snapshot
    dashboard.settings = settings
    dashboard.history = history
    dashboard.weather = weatherReport
    dashboard.weatherStatus = weatherStatus
    _ = dashboard.view
    dashboard.show(module)
    updateCalendar(opening: true)
    collector?.setVisibleModule(module)
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }
  func popoverDidClose(_ notification: Notification) {
    collector?.setVisibleModule(nil); dashboard.snapshot.processes.removeAll();
    dashboard.snapshot.networkProcesses.removeAll();
    dashboard.history = HistoryStore(interval: settings.interval);
    dashboard.canvas.points.removeAll(); dashboard.canvas.selectedPoint = nil
    clearCalendar(); dashboard.canvas.releaseInteractiveRows()
    selectedCalendarDate = Date()
  }
  private func updateItems() {
    for (configuration, item) in items {
      guard let button = item.button else { continue }
      let module = configuration.module
      let value: String
      switch module {
      case .overview: value = "Aerie"
      case .cpu: value = "CPU \(Format.percent(snapshot.cpu.total))"
      case .gpu: value = "GPU \(Format.percent(snapshot.gpu.first?.utilization))"
      case .memory: value = "MEM \(Format.percent(snapshot.memory.usedFraction))"
      case .storage:
        value = snapshot.volumes.first.map { "SSD \(Format.percent($0.usedFraction))" } ?? "SSD —"
      case .network: value = "↓\(shortRate(snapshot.download)) ↑\(shortRate(snapshot.upload))"
      case .sensors:
        value =
          snapshot.sensors.first(where: { $0.unit == "°C" && $0.state == .live }).flatMap(\.value)
          .map {
            Format.temperature($0, unit: settings.temperature)
          } ?? "TEMP —"
      case .power:
        value = snapshot.power.present ? "BAT \(Format.percent(snapshot.power.percent))" : "PWR AC"
      case .time:
        value = clockFormatter.string(from: Date())
      case .weather:
        value =
          weatherReport?.temperature.map { Format.temperature($0, unit: settings.temperature) }
          ?? "WX —"
      }
      if configuration.style == .graph, let key = graphKey(module) {
        let points = history.recent.suffix(48).map { $0.values[key] }
        if graphValues[module] != points {
          if !button.title.isEmpty { button.title = "" }
          button.image = graphImage(points, key: key)
          graphValues[module] = points
        }
      } else {
        if module == .overview {
          if button.image !== ridgeMark { button.image = ridgeMark }
        } else if button.image != nil {
          button.image = nil
        }
        let title =
          configuration.style == .compact
          ? value.replacingOccurrences(
            of: "\(module == .memory ? "MEM" : module.title.uppercased()) ", with: "") : value
        let displayed = paused ? "⏸ " + title : title
        if button.attributedTitle.string != displayed {
          let font = NSFont.monospacedDigitSystemFont(
            ofSize: settings.compactSpacing ? 10 : 11, weight: .medium)
          button.attributedTitle = NSAttributedString(string: displayed, attributes: [.font: font])
        }
      }
      let tooltip = "Aerie \(module.title): \(value)\(paused ? " · sampling paused" : "")"
      if button.toolTip != tooltip { button.toolTip = tooltip }
      if accessibilityValues[module] != value {
        button.setAccessibilityValue(value); accessibilityValues[module] = value
      }
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
  private func graphImage(_ points: [Double?], key: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 48, height: 18), flipped: true) { rect in
      let maxValue =
        ["cpu", "gpu", "memory", "battery"].contains(key)
        ? 100 : max(1, points.compactMap { $0 }.max() ?? 1)
      drawSparkline(points, in: rect.insetBy(dx: 2, dy: 2), color: .labelColor, maximum: maxValue)
      return true
    }
    image.isTemplate = true
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
    preferences?.onClose = { [weak self] in self?.preferences = nil }
    preferences?.onDashboard = { [weak self] in
      guard let self, let button = self.items.first?.1.button else { return };
      self.preferences?.close(); self.clickedStatus(button)
    }
    preferences?.onNotifications = { [weak self] in self?.requestNotifications() }
    preferences?.onCalendar = { [weak self] in self?.requestCalendar() }
    preferences?.onLogin = { [weak self] in self?.requestLogin() }
    preferences?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private func apply(_ settings: Settings) {
    guard let valid = try? settings.validated() else { return }
    let weatherChanged = self.settings.weather != valid.weather
    let networkChanged = self.settings.networkSelection != valid.networkSelection
    self.settings = valid
    snapshot.networkSelection = valid.networkSelection
    if networkChanged { history.removeMetrics(["download", "upload"]) }
    history.configure(interval: valid.interval)
    if let data = try? JSONEncoder().encode(valid) { defaults.set(data, forKey: "settings") }
    collector?.configure(valid)
    rebuildItems()
    applyAppearance()
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
    collector?.setSuspended(paused)
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
    content.title = "Aerie · \(rule.metric)"
    content.body =
      "\(rule.comparison.rawValue.capitalized) \(rule.threshold) for \(Int(rule.duration)) seconds."
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
    let store = eventStore ?? EKEventStore()
    eventStore = store
    store.requestFullAccessToEvents { granted, _ in
      DispatchQueue.main.async {
        if granted {
          self.updateCalendar()
        } else {
          self.notice("Calendar access remains unavailable.")
        }
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
    eventStore = nil; calendarDetails.removeAll(); dashboard.calendarRows.removeAll()
    lastCalendarRefresh = .distantPast
  }
  private func updateCalendar(force: Bool = true, opening: Bool = false) {
    guard dashboard.module == .time, popover.isShown || opening else {
      clearCalendar(); return
    }
    let now = Date(), calendar = menuCalendar
    guard force || now.timeIntervalSince(lastCalendarRefresh) >= 60 else { return }
    lastCalendarRefresh = now
    calendarDetails.removeAll()
    guard
      let month = CalendarMonth.make(
        displayedMonth: selectedCalendarDate, selected: selectedCalendarDate, now: now,
        calendar: calendar, showsWeekNumbers: settings.showWeekNumbers)
    else {
      eventStore = nil
      dashboard.calendarRows = [.note("The current calendar could not produce this month.")]
      dashboard.refresh(); return
    }
    var rows: [DashboardRow] = [.calendar(month), .heading(month.selectedDayTitle)]
    let authorization = EKEventStore.authorizationStatus(for: .event)
    if authorization == .fullAccess {
      let store = eventStore ?? EKEventStore(); eventStore = store
      let formatter = DateFormatter(); formatter.calendar = calendar;
      formatter.timeZone = calendar.timeZone
      formatter.setLocalizedDateFormatFromTemplate("EEE jmm z")
      func appendEvents(start: Date, end: Date, empty: String) {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        if events.isEmpty { rows.append(.note(empty)); return }
        for event in events.prefix(20) {
          let identifier = UUID().uuidString
          let title = String((event.title ?? "Event").prefix(256))
          let time = event.isAllDay ? "All day" : formatter.string(from: event.startDate)
          rows.append(.action(title, time, identifier))
          let detailFormatter = DateFormatter(); detailFormatter.calendar = calendar;
          detailFormatter.timeZone = calendar.timeZone
          detailFormatter.setLocalizedDateFormatFromTemplate("EEE MMM d y jmm z")
          var lines = [
            "Starts: \(detailFormatter.string(from: event.startDate))",
            "Ends: \(detailFormatter.string(from: event.endDate))",
          ]
          if event.isAllDay { lines.append("All-day event; the end date is exclusive.") }
          if let name = event.calendar?.title {
            lines.append("Calendar: " + String(name.prefix(128)))
          }
          if let location = event.location, !location.isEmpty {
            lines.append("Location: " + String(location.prefix(512)))
          }
          if let notes = event.notes, !notes.isEmpty { lines.append(String(notes.prefix(2048))) }
          calendarDetails[identifier] = (title, lines.joined(separator: "\n"))
        }
        if events.count > 20 {
          rows.append(.note("Showing the first 20 of \(events.count) events in this range."))
        }
      }
      appendEvents(
        start: month.dayInterval.start, end: month.dayInterval.end, empty: "No events on this day.")
      rows.append(.heading("Upcoming events · next seven days"))
      if let end = calendar.date(byAdding: .day, value: 7, to: now) {
        appendEvents(start: now, end: end, empty: "No events in the next seven days.")
      }
      rows.append(
        .note(
          "Events remain local. Select an event to read its details. Refreshes each minute while this menu is open."
        ))
    } else {
      eventStore = nil
      rows.append(
        .note(
          "Enable Calendar Events in Settings → Permissions to show local events. Date selection works without access."
        ))
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
