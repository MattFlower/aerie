import AerieCore
import AppKit

final class PreferencesController: NSWindowController, NSWindowDelegate {
  private var settings: Settings
  var onApply: ((Settings) -> Void)?
  var onClose: (() -> Void)?
  var onDashboard: (() -> Void)?
  var onNotifications: (() -> Void)?
  var onCalendar: (() -> Void)?
  var onLogin: (() -> Void)?
  private var fields: [String: NSTextField] = [:]
  private var toggles: [String: NSButton] = [:]
  private var choices: [String: NSPopUpButton] = [:]
  private var menuToggles: [Module: NSButton] = [:]
  private var menuStyles: [Module: NSPopUpButton] = [:]
  private var menuOrders: [Module: NSPopUpButton] = [:]
  private var clocksField = NSTextView()
  private let rulesPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  private let ruleMetrics = [
    "cpu", "gpu", "memory", "battery", "temperature", "diskFree", "download", "upload", "thermal",
  ]
  private var rulesLabel = NSTextField(wrappingLabelWithString: "")
  private var errorLabel = NSTextField(wrappingLabelWithString: "")
  init(settings: Settings) {
    self.settings = settings
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 650, height: 650),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Aerie Settings"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    build()
    window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowWillClose(_ notification: Notification) { onClose?() }
  private func tab(_ title: String, in tabs: NSTabView) -> NSView {
    let item = NSTabViewItem(identifier: title)
    item.label = title
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 610, height: 505))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    let body = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 730))
    scroll.documentView = body
    item.view = scroll
    tabs.addTabViewItem(item)
    return body
  }
  private func label(_ title: String, y: CGFloat, in view: NSView, height: CGFloat = 22) {
    let label = NSTextField(wrappingLabelWithString: title)
    label.font = .systemFont(ofSize: 12)
    label.frame = NSRect(x: 18, y: y, width: 560, height: height)
    view.addSubview(label)
  }
  private func field(_ id: String, title: String, value: String, y: CGFloat, in view: NSView) {
    label(title, y: y + 5, in: view)
    let text = NSTextField(string: value)
    text.frame = NSRect(x: 275, y: y, width: 290, height: 26)
    text.setAccessibilityLabel(title)
    view.addSubview(text)
    fields[id] = text
  }
  private func toggle(_ id: String, title: String, value: Bool, y: CGFloat, in view: NSView) {
    let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
    button.state = value ? .on : .off
    button.frame = NSRect(x: 18, y: y, width: 555, height: 26)
    view.addSubview(button)
    toggles[id] = button
  }
  private func choice(
    _ id: String, title: String, values: [String], selected: Int, y: CGFloat, in view: NSView
  ) {
    label(title, y: y + 5, in: view)
    let popup = NSPopUpButton(frame: NSRect(x: 275, y: y, width: 290, height: 28), pullsDown: false)
    popup.addItems(withTitles: values)
    popup.selectItem(at: selected)
    popup.setAccessibilityLabel(title)
    view.addSubview(popup)
    choices[id] = popup
  }
  private func build() {
    guard let content = window?.contentView else { return }
    let tabs = NSTabView(frame: NSRect(x: 15, y: 100, width: 620, height: 535))
    content.addSubview(tabs)
    let general = tab("General", in: tabs)
    label(
      "One native sampler, bounded history, and no installed privileged helper.", y: 16,
      in: general, height: 40)
    choice(
      "interval", title: "System refresh interval",
      values: ["0.5 seconds", "1 second", "2 seconds", "3 seconds", "5 seconds"],
      selected: [0.5, 1, 2, 3, 5].firstIndex(of: settings.interval) ?? 1, y: 62, in: general)
    choice(
      "theme", title: "Appearance", values: ["System", "Light", "Dark"],
      selected: Theme.allCases.firstIndex(of: settings.theme) ?? 0, y: 104, in: general)
    choice(
      "temperature", title: "Temperature", values: ["Celsius", "Fahrenheit"],
      selected: settings.temperature == .celsius ? 0 : 1, y: 146, in: general)
    field(
      "processCount", title: "Top process count (1–20)", value: String(settings.processCount),
      y: 188, in: general)
    toggle(
      "normalizedCPU", title: "Process CPU uses 0–100% of the whole machine",
      value: settings.normalizedProcessCPU, y: 232, in: general)
    toggle(
      "binary", title: "Use binary byte units (KiB, MiB, GiB)", value: settings.binaryBytes, y: 266,
      in: general)
    toggle(
      "bits", title: "Display network bandwidth in bits per second", value: settings.networkBits,
      y: 300, in: general)
    toggle(
      "spacing", title: "Compact menu-bar spacing", value: settings.compactSpacing, y: 334,
      in: general)
    label(
      "Process details are collected only while CPU, memory, storage or power panels need them. Pausing and system sleep cancel the sampling timer. Timer tolerance is 100 ms; the chosen interval is never silently reduced.",
      y: 378, in: general, height: 70)
    let export = NSButton(
      title: "Export Settings…", target: self, action: #selector(exportSettings))
    export.frame = NSRect(x: 18, y: 468, width: 170, height: 28)
    general.addSubview(export)
    let importButton = NSButton(
      title: "Import Settings…", target: self, action: #selector(importSettings))
    importButton.frame = NSRect(x: 195, y: 468, width: 170, height: 28)
    general.addSubview(importButton)
    label(
      "Exports remove location and disable forecasts/maps. Imports keep both off until you opt in again.",
      y: 511, in: general, height: 45)

    let dashboard = NSButton(
      title: "Open Dashboard", target: self, action: #selector(openDashboard))
    dashboard.frame = NSRect(x: 18, y: 580, width: 170, height: 28); general.addSubview(dashboard)
    choice(
      "sensors", title: "Hardware sensor sampling",
      values: ["All supported sensors", "Other families on demand"],
      selected: settings.effectiveSensorSampling == .all ? 0 : 1, y: 621, in: general)
    label(
      "Full sampling is the default. On demand still samples every temperature at the chosen interval for history and rules; fans, power, voltage and current are read at that same interval while Sensors is open. Inventory is always retained; deferred readings are never treated as zero or stale live values.",
      y: 661, in: general, height: 92)
    general.setFrameSize(NSSize(width: 600, height: 775))
    let menus = tab("Menus", in: tabs)
    toggle(
      "combined", title: "Use one combined menu-bar item", value: settings.combined, y: 14,
      in: menus)
    label("Visible items", y: 60, in: menus)
    let columnLabels = NSTextField(labelWithString: "Style                               Order")
    columnLabels.frame = NSRect(x: 194, y: 60, width: 350, height: 22);
    menus.addSubview(columnLabels)
    for (index, menu) in settings.menus.enumerated() {
      let y = CGFloat(96 + index * 38)
      let toggle = NSButton(checkboxWithTitle: menu.module.title, target: nil, action: nil)
      toggle.frame = NSRect(x: 18, y: y, width: 150, height: 28)
      toggle.state = menu.visible ? .on : .off
      menus.addSubview(toggle)
      menuToggles[menu.module] = toggle
      let style = NSPopUpButton(
        frame: NSRect(x: 190, y: y, width: 180, height: 28), pullsDown: false)
      style.addItems(withTitles: ["Text", "Graph", "Compact"])
      style.selectItem(at: DisplayStyle.allCases.firstIndex(of: menu.style) ?? 0)
      menus.addSubview(style)
      menuStyles[menu.module] = style
      let order = NSPopUpButton(
        frame: NSRect(x: 395, y: y, width: 135, height: 28), pullsDown: false)
      order.addItems(withTitles: (1...settings.menus.count).map(String.init))
      order.selectItem(at: index)
      menus.addSubview(order)
      menuOrders[menu.module] = order
    }
    label(
      "Assign each item a different order. You can also Command-drag visible items in the macOS menu bar. Hiding an item does not remove its data from the combined dashboard.",
      y: 492, in: menus, height: 60)

    let network = tab("Network", in: tabs)
    label(
      "Interface collection stays complete. Choose which active interfaces feed aggregate bandwidth, history and download/upload rules.",
      y: 18, in: network, height: 60)
    toggle(
      "networkAll", title: "Aggregate all active interfaces",
      value: settings.networkInterfaces == nil, y: 92, in: network)
    field(
      "networkNames", title: "Selected interface names",
      value: settings.networkInterfaces?.joined(separator: ", ") ?? "", y: 136, in: network)
    label(
      "Enter comma-separated names from the Network dashboard, for example en0. Virtual tunnels can duplicate physical-interface traffic; select one side when you want to avoid summing the same traffic twice. Inactive or missing selected interfaces do not contribute. All interfaces are still read at the chosen interval and remain visible.",
      y: 185, in: network, height: 110)
    label(
      "Changing aggregate selection clears only the download/upload history series and resets rule sustain state, so old scope cannot be presented as the new scope. Other histories remain. Per-interface session totals start at first observation and rebase on counter resets, source changes, interface disappearance or a failed read.",
      y: 310, in: network, height: 100)

    let weather = tab("Weather", in: tabs)
    weather.frame.size.height = 840
    label("Optional weather", y: 18, in: weather)
    choice(
      "weatherProvider", title: "Forecast provider",
      values: ["Open-Meteo (global models)", "NWS (US land forecasts/stations)"],
      selected: settings.weather.provider == "nws" ? 1 : 0, y: 48, in: weather)
    label(
      "Requests send your network IP and manual coordinates rounded to two decimal places to the selected provider. Open-Meteo is personal/noncommercial and may retain troubleshooting logs up to 90 days. NWS offers free US land forecasts, nearby station observations and point alerts; coverage and freshness vary. No device location or city search is used.",
      y: 93, in: weather, height: 100)
    let terms = NSButton(title: "Read Provider Terms…", target: self, action: #selector(openTerms))
    terms.frame = NSRect(x: 18, y: 205, width: 210, height: 28)
    weather.addSubview(terms)
    field(
      "weatherName", title: "Location display name", value: settings.weather.name, y: 252,
      in: weather)
    field(
      "latitude", title: "Latitude (−90…90)", value: String(settings.weather.latitude), y: 294,
      in: weather)
    field(
      "longitude", title: "Longitude (−180…180)", value: String(settings.weather.longitude), y: 336,
      in: weather)
    toggle(
      "weather", title: "Enable weather and send this location to the selected provider",
      value: settings.weather.enabled, y: 383, in: weather)
    label(
      "Applying enabled weather sends requests to the selected provider. Refresh is 15 minutes, including NWS station/point-alert data; it is not real-time warning delivery. Values retain observation/forecast times. Requests and data stay ephemeral and cancel when disabled. Public tests/CI use synthetic data. Attribution appears in the menu.",
      y: 429, in: weather, height: 100)
    toggle(
      "maps", title: "Enable NOAA/NWS maps for this manual location",
      value: settings.weather.mapsEnabled, y: 585, in: weather)
    label(
      "Map provider: NOAA/NWS. Opening Maps sends the selected map area and your IP to NOAA services. Alert details also send the rounded map-center point. Maps load only on demand; forecast consent above is separate. NOAA boundaries are used; no device location is requested.",
      y: 626, in: weather, height: 96)

    let time = tab("Time", in: tabs)
    field("clockFormat", title: "Date format", value: settings.clockFormat, y: 18, in: time)
    toggle(
      "monday", title: "Calendar week starts Monday", value: settings.weekStartsMonday, y: 65,
      in: time)
    toggle(
      "weeks", title: "Show calendar week numbers", value: settings.showWeekNumbers, y: 99, in: time
    )
    label("World clocks: one Name | IANA time zone per line", y: 147, in: time)
    label("Examples: UTC | Etc/UTC and Tokyo | Asia/Tokyo", y: 177, in: time)
    let clockScroll = NSScrollView(frame: NSRect(x: 18, y: 216, width: 545, height: 195))
    clockScroll.hasVerticalScroller = true
    clockScroll.borderType = .bezelBorder
    clocksField = NSTextView(frame: clockScroll.bounds)
    clocksField.isRichText = false
    clocksField.font = .systemFont(ofSize: 13)
    clocksField.string = settings.clocks.map { "\($0.name) | \($0.zone)" }.joined(separator: "\n")
    clocksField.setAccessibilityLabel("World clocks")
    clockScroll.documentView = clocksField
    time.addSubview(clockScroll)
    label(
      "Calendar events remain local. Access is requested only through the Permissions tab. Lunar phase is an offline approximation; daylight times are shown from an opted-in weather forecast.",
      y: 434, in: time, height: 70)

    let rules = tab("Rules", in: tabs)
    label("Sustained threshold notifications", y: 18, in: rules)
    label(
      "Missing values and sleep gaps reset the sustain timer. Notifications have a cooldown and require your permission. The rule engine keeps evaluating while menus are closed.",
      y: 50, in: rules, height: 70)
    choice(
      "ruleMetric", title: "Metric",
      values: [
        "CPU %", "GPU %", "Memory used %", "Battery %", "Maximum temperature °C",
        "First volume free GiB", "Download bytes/s", "Upload bytes/s", "Thermal severity 0–3",
      ], selected: 0, y: 132, in: rules)
    choice(
      "ruleComparison", title: "Condition", values: ["Above", "Below"], selected: 0, y: 172,
      in: rules)
    field("ruleThreshold", title: "Threshold", value: "90", y: 212, in: rules)
    field("ruleDuration", title: "Sustain seconds", value: "30", y: 252, in: rules)
    field("ruleCooldown", title: "Cooldown seconds", value: "300", y: 292, in: rules)
    for (title, action, x, width) in [
      ("Add", #selector(addRule), 18.0, 80.0),
      ("Save Selected", #selector(saveRule), 104.0, 130.0),
      ("Delete", #selector(deleteRule), 240.0, 85.0),
      ("Enable/Disable", #selector(toggleRule), 330.0, 130.0),
      ("Clear All", #selector(clearRules), 465.0, 100.0),
    ] {
      let button = NSButton(title: title, target: self, action: action)
      button.frame = NSRect(x: x, y: 337, width: width, height: 28); rules.addSubview(button)
    }
    rulesPicker.frame = NSRect(x: 18, y: 380, width: 550, height: 28)
    rulesPicker.target = self; rulesPicker.action = #selector(selectRule);
    rules.addSubview(rulesPicker)
    rulesLabel.frame = NSRect(x: 18, y: 422, width: 550, height: 280); rules.addSubview(rulesLabel)
    refreshRules()

    let changes = tab("Changes", in: tabs)
    label("Notify when a system state changes", y: 18, in: changes)
    label(
      "Each enabled rule establishes a baseline first. Missing data, pausing and sleep reset it. Changes during cooldown are suppressed. Mounted-volume detection refreshes every 30 seconds; other states use the selected system interval. Enable notifications in Permissions, then Apply.",
      y: 52, in: changes, height: 100)
    for (index, kind) in ChangeKind.allCases.enumerated() {
      toggle(
        "change.\(kind.rawValue)", title: kind.title,
        value: settings.changeRules?.first(where: { $0.kind == kind })?.enabled ?? false,
        y: CGFloat(168 + index * 36), in: changes)
    }
    field(
      "changeCooldown", title: "Cooldown seconds (each rule)",
      value: String(settings.changeRules?.first?.cooldown ?? 300), y: 480, in: changes)

    let permissions = tab("Permissions", in: tabs)
    label("Aerie does not request permissions at launch.", y: 18, in: permissions)
    label(
      "Use these controls only when you want the corresponding feature. No elevated helper, fan writes, automatic location lookup, or security-setting changes are installed.",
      y: 54, in: permissions, height: 65)
    for (title, action, y) in [
      ("Enable Notifications…", #selector(notifications), 145),
      ("Allow Calendar Events…", #selector(calendar), 195),
      ("Enable Launch at Login…", #selector(login), 245),
    ] {
      let b = NSButton(title: title, target: self, action: action)
      b.frame = NSRect(x: 18, y: y, width: 270, height: 30)
      permissions.addSubview(b)
    }
    label(
      "Wi-Fi SSID may require macOS Location Services permission. Aerie does not request that permission yet. Available signal, noise, rate, and channel information still appears.",
      y: 308, in: permissions, height: 80)
    let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
    close.frame = NSRect(x: 440, y: 18, width: 85, height: 30)
    content.addSubview(close)
    let apply = NSButton(title: "Apply", target: self, action: #selector(applySettings))
    apply.frame = NSRect(x: 535, y: 18, width: 95, height: 30)
    apply.keyEquivalent = "\r"
    content.addSubview(apply)
    errorLabel.textColor = .systemRed
    errorLabel.font = .systemFont(ofSize: 11)
    errorLabel.frame = NSRect(x: 20, y: 53, width: 610, height: 35)
    content.addSubview(errorLabel)
  }
  @objc private func openTerms() {
    NSWorkspace.shared.open(
      URL(
        string: choices["weatherProvider"]?.indexOfSelectedItem == 1
          ? "https://www.weather.gov/disclaimer" : "https://open-meteo.com/en/terms")!)
  }
  @objc private func openDashboard() { onDashboard?() }
  @objc private func notifications() { onNotifications?() }
  @objc private func calendar() { onCalendar?() }
  @objc private func login() { onLogin?() }
  @objc private func closeWindow() { close() }
  private func readSettings() throws -> Settings {
    var s = settings
    s.interval = [0.5, 1, 2, 3, 5][choices["interval"]!.indexOfSelectedItem]
    s.theme = Theme.allCases[choices["theme"]!.indexOfSelectedItem]
    s.temperature = choices["temperature"]!.indexOfSelectedItem == 0 ? .celsius : .fahrenheit
    guard let count = Int(fields["processCount"]!.stringValue),
      let latitude = Double(fields["latitude"]!.stringValue),
      let longitude = Double(fields["longitude"]!.stringValue)
    else { throw SettingsError.invalid }
    s.processCount = count
    s.normalizedProcessCPU = toggles["normalizedCPU"]!.state == .on
    s.binaryBytes = toggles["binary"]!.state == .on
    s.networkBits = toggles["bits"]!.state == .on
    s.networkInterfaces =
      toggles["networkAll"]!.state == .on
      ? nil
      : fields["networkNames"]!.stringValue.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    s.compactSpacing = toggles["spacing"]!.state == .on
    s.sensorSampling = choices["sensors"]!.indexOfSelectedItem == 0 ? .all : .whenNeeded
    s.combined = toggles["combined"]!.state == .on
    s.clockFormat = fields["clockFormat"]!.stringValue
    s.weekStartsMonday = toggles["monday"]!.state == .on
    s.showWeekNumbers = toggles["weeks"]!.state == .on
    s.clocks = try clocksField.string.split(separator: "\n").map { line in
      let parts = line.split(separator: "|", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard parts.count == 2, !parts[0].isEmpty else { throw SettingsError.invalid }
      return WorldClock(name: parts[0], zone: parts[1])
    }
    s.weather.enabled = toggles["weather"]!.state == .on
    s.weather.provider = choices["weatherProvider"]!.indexOfSelectedItem == 1 ? "nws" : "openMeteo"
    s.weather.mapsEnabled = toggles["maps"]!.state == .on
    s.weather.mapsProvider = "noaa"
    s.weather.name = fields["weatherName"]!.stringValue
    s.weather.latitude = latitude
    s.weather.longitude = longitude
    guard let changeCooldown = Double(fields["changeCooldown"]!.stringValue),
      changeCooldown.isFinite, (10...604800).contains(changeCooldown)
    else { throw SettingsError.invalid }
    s.changeRules = ChangeKind.allCases.compactMap { kind in
      let enabled = toggles["change.\(kind.rawValue)"]!.state == .on
      if var rule = settings.changeRules?.first(where: { $0.kind == kind }) {
        rule.enabled = enabled; rule.cooldown = changeCooldown; return rule
      }
      return enabled ? ChangeRule(kind: kind, cooldown: changeCooldown) : nil
    }
    let order = settings.menus.map { ($0.module, menuOrders[$0.module]!.indexOfSelectedItem) }
    guard Set(order.map(\.1)).count == order.count else { throw SettingsError.invalid }
    s.menus = order.sorted { $0.1 < $1.1 }.map {
      MenuConfiguration(
        module: $0.0, visible: menuToggles[$0.0]!.state == .on,
        style: DisplayStyle.allCases[menuStyles[$0.0]!.indexOfSelectedItem])
    }
    return try s.validated()
  }
  @objc private func applySettings() {
    do {
      let s = try readSettings()
      settings = s
      onApply?(s)
      errorLabel.stringValue = "Settings applied"
    } catch {
      errorLabel.stringValue =
        "Check numeric values, valid time zones, unique menu order, and at least one visible item."
    }
  }
  private func ruleFromForm() -> ThresholdRule? {
    guard let threshold = Double(fields["ruleThreshold"]!.stringValue),
      let duration = Double(fields["ruleDuration"]!.stringValue),
      let cooldown = Double(fields["ruleCooldown"]!.stringValue)
    else {
      errorLabel.stringValue = "Rules require numeric values."; return nil
    }
    let rule = ThresholdRule(
      metric: ruleMetrics[choices["ruleMetric"]!.indexOfSelectedItem],
      threshold: threshold,
      comparison: choices["ruleComparison"]!.indexOfSelectedItem == 0 ? .above : .below,
      duration: duration, cooldown: cooldown)
    guard rule.valid else {
      errorLabel.stringValue = "Use a valid threshold, sustain 0–86400s, and cooldown 10–604800s.";
      return nil
    }
    return rule
  }
  private var selectedRuleIndex: Int? {
    let index = rulesPicker.indexOfSelectedItem - 1
    return settings.rules.indices.contains(index) ? index : nil
  }
  @objc private func addRule() {
    guard settings.rules.count < 50, let rule = ruleFromForm() else { return }
    settings.rules.append(rule); refreshRules(selected: rule.id)
  }
  @objc private func saveRule() {
    guard let index = selectedRuleIndex, let replacement = ruleFromForm() else { return }
    let current = settings.rules[index]
    settings.rules[index] = RuleEdits.replacing(current, with: replacement)
    refreshRules(selected: current.id)
  }
  @objc private func deleteRule() {
    guard let index = selectedRuleIndex else { return }; settings.rules.remove(at: index);
    refreshRules()
  }
  @objc private func toggleRule() {
    guard let index = selectedRuleIndex else { return }; settings.rules[index].enabled.toggle()
    refreshRules(selected: settings.rules[index].id)
  }
  @objc private func selectRule() {
    guard let index = selectedRuleIndex else { return }; let rule = settings.rules[index]
    choices["ruleMetric"]?.selectItem(at: ruleMetrics.firstIndex(of: rule.metric) ?? 0)
    choices["ruleComparison"]?.selectItem(at: rule.comparison == .above ? 0 : 1)
    fields["ruleThreshold"]?.stringValue = String(rule.threshold)
    fields["ruleDuration"]?.stringValue = String(rule.duration)
    fields["ruleCooldown"]?.stringValue = String(rule.cooldown)
  }
  @objc private func clearRules() {
    settings.rules.removeAll()
    refreshRules()
  }
  private func refreshRules(selected id: UUID? = nil) {
    rulesPicker.removeAllItems(); rulesPicker.addItem(withTitle: "New rule")
    rulesPicker.addItems(
      withTitles: settings.rules.map {
        "\($0.enabled ? "On" : "Off") · \($0.metric) \($0.comparison.rawValue) \($0.threshold)"
      })
    if let id, let index = settings.rules.firstIndex(where: { $0.id == id }) {
      rulesPicker.selectItem(at: index + 1)
    }
    rulesPicker.isEnabled = !settings.rules.isEmpty
    rulesLabel.stringValue =
      settings.rules.isEmpty
      ? "No rules. Add a rule, then Apply."
      : settings.rules.map {
        "\($0.metric) \($0.comparison.rawValue) \($0.threshold) for \($0.duration)s; cooldown \($0.cooldown)s"
      }.joined(separator: "\n")
  }
  @objc private func exportSettings() {
    do {
      var s = try readSettings()
      s.weather = WeatherConfiguration()
      let panel = NSSavePanel()
      panel.nameFieldStringValue = "Aerie-settings.json"
      if panel.runModal() == .OK, let url = panel.url {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(s).write(to: url, options: .atomic)
      }
    } catch { errorLabel.stringValue = "Could not export valid settings." }
  }
  @objc private func importSettings() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      guard data.count < 1_000_000 else { throw SettingsError.invalid }
      var s = try JSONDecoder().decode(Settings.self, from: data)
      s.weather.enabled = false
      s.weather.mapsEnabled = false
      s = try s.validated()
      settings = s
      onApply?(s)
      for subview in window?.contentView?.subviews ?? [] { subview.removeFromSuperview() }
      fields.removeAll()
      toggles.removeAll()
      choices.removeAll()
      menuToggles.removeAll()
      menuStyles.removeAll()
      menuOrders.removeAll()
      build()
      errorLabel.stringValue = "Settings imported. Weather remains off."
    } catch { errorLabel.stringValue = "This file does not contain valid Aerie settings." }
  }
}
private final class FlippedView: NSView { override var isFlipped: Bool { true } }
