import AerieCore
import AppKit
import EventKit
import ServiceManagement
import UserNotifications

final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let defaults = UserDefaults.standard
  private var settings = Settings()
  private var items: [(MenuConfiguration, NSStatusItem)] = []
  private var collector: Collector?
  private var snapshot = Snapshot()
  private var history = HistoryStore()
  private var rules = RuleEngine()
  private var dashboard = DashboardController()
  private var popover = NSPopover()
  private var preferences: PreferencesController?
  private var eventStore: EKEventStore?
  private var weatherTask: Task<Void, Never>?
  private var weatherGeneration = 0
  private var weatherReport: WeatherReport?
  private var weatherFetchTime = Date.distantPast
  private var weatherStatus = "Weather is off"
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
    history.configure(interval: settings.interval)
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 416, height: 620)
    popover.contentViewController = dashboard
    popover.delegate = self
    dashboard.onSettings = { [weak self] in self?.showSettings() }
    dashboard.onModule = { [weak self] module in
      self?.collector?.setDetailed(ProcessDemand.required(module: module, visible: true))
      self?.updateCalendar()
    }
    rebuildItems()
    applyAppearance()
    let collector = Collector()
    self.collector = collector
    collector.onSample = { [weak self] in self?.receive($0) }
    collector.configure(settings)
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.collector?.setSuspended(true)
        self?.rules.reset()
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
  func applicationWillTerminate(_ notification: Notification) {
    weatherTask?.cancel()
    collector = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
  private func receive(_ snapshot: Snapshot) {
    self.snapshot = snapshot
    history.append(HistoryPoint(date: snapshot.date, values: snapshot.metrics))
    for rule in rules.evaluate(
      rules: settings.rules, values: snapshot.metrics, time: ProcessInfo.processInfo.systemUptime)
    {
      notify(rule)
    }
    updateItems()
    if popover.isShown {
      dashboard.snapshot = snapshot
      dashboard.history = history
      dashboard.settings = settings
      dashboard.weather = weatherReport
      dashboard.weatherStatus = weatherStatus
      dashboard.refresh()
    }
    updateWeather()
    if CommandLine.arguments.contains("--self-check") {
      selfCheckSamples += 1
      if selfCheckSamples >= 3 {
        let output: [String: Any] = [
          "cpu": snapshot.cpu.total != nil, "cores": snapshot.cpu.cores.count,
          "memory": snapshot.memory.total > 0, "interfaces": snapshot.interfaces.count,
          "volumes": snapshot.volumes.count, "gpu": snapshot.gpu.count,
          "sensors": snapshot.sensors.count, "sensorStatus": snapshot.sensorStatus,
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
    updateCalendar()
    collector?.setDetailed(ProcessDemand.required(module: module, visible: true))
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }
  func popoverDidClose(_ notification: Notification) {
    collector?.setDetailed(false); dashboard.snapshot.processes.removeAll();
    dashboard.history = HistoryStore(interval: settings.interval);
    dashboard.canvas.points.removeAll(); dashboard.canvas.selectedPoint = nil
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
          snapshot.sensors.first(where: { $0.unit == "°C" }).map {
            Format.temperature($0.value, unit: settings.temperature)
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
    self.settings = valid
    history.configure(interval: valid.interval)
    if let data = try? JSONEncoder().encode(valid) { defaults.set(data, forKey: "settings") }
    collector?.configure(valid)
    rebuildItems()
    applyAppearance()
    rules.reset()
    if weatherChanged {
      weatherGeneration += 1
      weatherTask?.cancel()
      weatherTask = nil
      weatherReport = nil
      weatherFetchTime = .distantPast
      weatherStatus = valid.weather.valid ? "Fetching forecast" : "Weather is off"
      updateWeather()
    }
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
  private func updateCalendar() {
    let now = Date()
    var calendar = Calendar.current
    calendar.firstWeekday = settings.weekStartsMonday ? 2 : 1
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    var rows: [DashboardRow] = [.metric(formatter.string(from: now), "")]
    if let start = calendar.dateInterval(of: .month, for: now)?.start,
      let days = calendar.range(of: .day, in: .month, for: now)
    {
      let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
      let names =
        settings.weekStartsMonday
        ? "Mo   Tu   We   Th   Fr   Sa   Su" : "Su   Mo   Tu   We   Th   Fr   Sa"
      rows.append(.metric(names, settings.showWeekNumbers ? "Week" : ""))
      let cells = Array(repeating: "   ", count: offset) + days.map { String(format: "%2d ", $0) }
      for index in stride(from: 0, to: cells.count, by: 7) {
        let string = cells[index..<min(index + 7, cells.count)].joined(separator: " ")
        let date = calendar.date(byAdding: .day, value: index - offset, to: start) ?? start
        rows.append(
          .metric(
            string,
            settings.showWeekNumbers ? String(calendar.component(.weekOfYear, from: date)) : ""))
      }
    }
    let authorization = EKEventStore.authorizationStatus(for: .event)
    if authorization == .fullAccess {
      let store = eventStore ?? EKEventStore()
      eventStore = store
      let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now
      let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
      let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(
        20)
      formatter.dateFormat = "EEE HH:mm"
      rows += [.heading("Upcoming events")]
      rows +=
        events.isEmpty
        ? [.note("No events in the next seven days.")]
        : events.map {
          .metric(
            $0.title ?? "Event", $0.isAllDay ? "All day" : formatter.string(from: $0.startDate))
        }
    } else {
      rows += [.note("Enable Calendar Events in Settings → Permissions to show local events.")]
    }
    dashboard.calendarRows = rows
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
        let report = try await OpenMeteoProvider().fetch(configuration: configuration)
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
