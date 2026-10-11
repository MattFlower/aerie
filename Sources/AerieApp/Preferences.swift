import AerieCore
import AppKit

final class PreferencesController: NSWindowController, NSWindowDelegate {
  private var settings: Settings
  var onApply: ((Settings) -> Void)?
  var onProfileReview: ((SettingsProfile) -> Bool)?
  var onClose: (() -> Void)?
  var onDashboard: (() -> Void)?
  var onNotifications: (() -> Void)?
  var onCalendar: (() -> Void)?
  var onWiFiPermission: (() -> Void)?
  var onLogin: (() -> Void)?
  var onWindowCreated: ((NSWindow) -> Void)?
  private var fields: [String: NSTextField] = [:]
  private var toggles: [String: NSButton] = [:]
  private var choices: [String: NSPopUpButton] = [:]
  private var menuToggles: [Module: NSButton] = [:]
  private var menuStyles: [Module: NSPopUpButton] = [:]
  private var menuOrders: [Module: NSPopUpButton] = [:]
  private var menuColors: [Module: NSTextField] = [:]
  private var clocksField = NSTextView()
  private var shortcutsField = NSTextView()
  private var sensorNamesField = NSTextView()
  private var calendarPicker: CalendarPickerController?
  private let calendarAccess = CalendarAccess()
  private let calendarSelectionLabel = NSTextField(wrappingLabelWithString: "")
  private let rulesPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  private let ruleMetrics = [
    "cpu", "gpu", "memory", "battery", "temperature", "diskFree", "download", "upload", "thermal",
    "diskRead", "diskWrite", "sensor",
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
  func windowWillClose(_ notification: Notification) {
    calendarPicker?.close(); calendarPicker = nil
    if let window { MenuPanel.releaseContent(of: window) }
    onClose?()
  }
  func validateCalendarAccess() { calendarPicker?.validateAccess() }
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
    let restore = NSButton(
      title: "Restore Defaults…", target: self, action: #selector(restoreDefaults))
    restore.frame = NSRect(x: 372, y: 468, width: 193, height: 28)
    general.addSubview(restore)
    label(
      "Format 1 profiles: import and defaults are reviewed and staged before Apply. Locations and calendar choices are cleared; current numeric archive preference is preserved.",
      y: 511, in: general, height: 45)

    let dashboard = NSButton(
      title: "Open Dashboard", target: self, action: #selector(openDashboard))
    dashboard.frame = NSRect(x: 18, y: 580, width: 170, height: 28); general.addSubview(dashboard)
    choice(
      "sensors", title: "Hardware sensor sampling",
      values: ["All supported sensors", "Other families on demand"],
      selected: settings.effectiveSensorSampling == .all ? 0 : 1, y: 621, in: general)
    label(
      "Full sampling is the default. On demand keeps every temperature and enabled individual-rule sensor at the chosen interval; other readings wait for the Sensors panel. Inventory stays complete; deferred readings remain unavailable.",
      y: 661, in: general, height: 92)
    toggle(
      "persistentHistory", title: "Keep numeric history between launches",
      value: settings.effectivePersistentHistory, y: 765, in: general)
    label(
      "Local archive: 2 MB maximum, saved once per minute and on normal exit. Turning this off deletes the archive. No process, calendar, weather or sensor names are saved.",
      y: 805, in: general, height: 62)
    toggle(
      "combineProcesses", title: "Combine application and executable processes",
      value: settings.effectiveCombineProcesses, y: 880, in: general)
    label(
      "Combining uses application-bundle or executable identity. Unknown identities stay separate; partial rates remain unavailable. Process sorting can be chosen independently for each panel.",
      y: 920, in: general, height: 70)
    for (index, module) in ProcessSort.modules.enumerated() {
      let options = ProcessSort.options(for: module)
      choice(
        "processSort.\(module.rawValue)", title: module.title + " process sorting",
        values: options.map(\.title),
        selected: options.firstIndex(of: settings.processSorts?[module] ?? .automatic) ?? 0,
        y: CGFloat(1000 + index * 42), in: general)
    }
    general.setFrameSize(NSSize(width: 600, height: 1240))
    let menus = tab("Menus", in: tabs)
    toggle(
      "combined", title: "Use one combined menu-bar item", value: settings.combined, y: 14,
      in: menus)
    label("Visible items", y: 60, in: menus)
    let columnLabels = NSTextField(
      labelWithString: "Style                               Order              Color")
    columnLabels.frame = NSRect(x: 194, y: 60, width: 400, height: 22);
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
      style.addItems(withTitles: ["Text", "Graph", "Compact", "Stacked"])
      style.selectItem(at: DisplayStyle.allCases.firstIndex(of: menu.style) ?? 0)
      style.setAccessibilityLabel(menu.module.title + " display style")
      menus.addSubview(style)
      menuStyles[menu.module] = style
      let order = NSPopUpButton(
        frame: NSRect(x: 395, y: y, width: 135, height: 28), pullsDown: false)
      order.addItems(withTitles: (1...settings.menus.count).map(String.init))
      order.selectItem(at: index)
      order.setAccessibilityLabel(menu.module.title + " menu order")
      menus.addSubview(order)
      menuOrders[menu.module] = order
      let color = NSTextField(string: menu.colorHex ?? "")
      color.placeholderString = "Auto"; color.frame = NSRect(x: 538, y: y, width: 60, height: 26)
      color.setAccessibilityLabel(
        menu.module.title + " color, hexadecimal RGB or empty for automatic")
      menus.addSubview(color); menuColors[menu.module] = color
    }
    label(
      "Assign each item a different order. You can also Command-drag visible items in the macOS menu bar. Hiding an item does not remove its data from the combined dashboard.",
      y: 492, in: menus, height: 60)
    field(
      "combinedModules", title: "Combined items (names, ordered)",
      value: settings.effectiveCombinedModules.map(\.title).joined(separator: ","), y: 565,
      in: menus)
    choice(
      "combinedStyle", title: "Combined display", values: ["Text", "Compact", "Stacked"],
      selected: [DisplayStyle.text, .compact, .stacked].firstIndex(
        of: settings.combinedStyle ?? .text) ?? 0, y: 607, in: menus)
    field(
      "combinedColor", title: "Combined color (#RRGGBB or empty)",
      value: settings.combinedColorHex ?? "", y: 649, in: menus)
    label(
      "Choose 1–6 unique names: CPU, GPU, Memory, Storage, Network, Sensors, Power, Time, Weather. Empty colors follow macOS appearance; custom colors need sufficient contrast. Stacked items show two lines. Hidden items are still sampled.",
      y: 690, in: menus, height: 82)
    menus.setFrameSize(NSSize(width: 600, height: 792))

    let shortcuts = tab("Shortcuts", in: tabs)
    label(
      "Global shortcuts are off until you add a combination and Apply. Enter one item per line, using its menu name or Settings, followed by | and the combination.",
      y: 16, in: shortcuts, height: 62)
    label(
      "Example: CPU | Command+Option+C\nSettings | Command+Control+A", y: 88, in: shortcuts,
      height: 48)
    shortcutsField.string = (settings.shortcuts ?? []).map {
      $0.targetTitle + " | " + $0.combination
    }.joined(separator: "\n")
    shortcutsField.isRichText = false;
    shortcutsField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    shortcutsField.setAccessibilityLabel("Global shortcut combinations")
    let shortcutScroll = NSScrollView(frame: NSRect(x: 18, y: 151, width: 550, height: 275))
    shortcutScroll.hasVerticalScroller = true; shortcutScroll.documentView = shortcutsField
    shortcutsField.frame = NSRect(x: 0, y: 0, width: 550, height: 275);
    shortcuts.addSubview(shortcutScroll)
    label(
      "Choose unique combinations containing Command or Control, with optional Option/Shift and a letter, digit, Space or F1–F20. Character keys resolve through the current keyboard layout. OS-reserved keys, conflicts, secure input or an unavailable layout can prevent registration; Aerie reports those failures. Clear all lines to release every shortcut.",
      y: 445, in: shortcuts, height: 116)

    let sensors = tab("Sensors", in: tabs)
    label("Local sensor names", y: 18, in: sensors)
    label(
      "Use the four-character firmware key shown in Sensors, then | and your name. Example: T001 | Enclosure probe",
      y: 55, in: sensors, height: 55)
    sensorNamesField.string = (settings.sensorNames ?? [:]).sorted { $0.key < $1.key }.map {
      $0.key + " | " + $0.value
    }.joined(separator: "\n")
    sensorNamesField.isRichText = false
    sensorNamesField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    sensorNamesField.setAccessibilityLabel("Local sensor names by firmware key")
    let sensorScroll = NSScrollView(frame: NSRect(x: 18, y: 130, width: 550, height: 300))
    sensorScroll.hasVerticalScroller = true; sensorScroll.documentView = sensorNamesField
    sensorNamesField.frame = NSRect(x: 0, y: 0, width: 550, height: 300)
    sensors.addSubview(sensorScroll)
    label(
      "Names are local aliases; firmware keys stay visible. A name does not verify a sensor's hardware role. Missing keys remain saved for reconnection. Use Rules to alert on a specific key and its native unit. Clear a line to restore its original name, then Apply.",
      y: 453, in: sensors, height: 104)

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
    toggle(
      "publicAddress", title: "Allow public IP lookup through ipify",
      value: settings.effectivePublicAddress, y: 436, in: network)
    label(
      "When enabled, ipify sees your network address and returns the HTTP route's IPv4 or IPv6. VPN/proxy/NAT can affect that address. Refresh is five minutes; disabling, pause and sleep cancel requests. No location lookup, credentials or address history is used.",
      y: 478, in: network, height: 100)
    let addressTerms = NSButton(
      title: "Read ipify Service Details…", target: self, action: #selector(openAddressTerms))
    addressTerms.frame = NSRect(x: 18, y: 597, width: 245, height: 28);
    network.addSubview(addressTerms)

    let weather = tab("Weather", in: tabs)
    weather.frame.size.height = 885
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

    choice(
      "hourlyForecastHours", title: "Hourly forecast rows", values: ["24", "48", "72", "168"],
      selected: [24, 48, 72, 168].firstIndex(of: settings.effectiveHourlyForecastHours) ?? 0,
      y: 748, in: weather)
    label(
      "Hourly details use the current cached report and make no extra requests. Provider fields can be unavailable; precipitation probability and amount are distinct. More rows change only the open-panel presentation, not fetch cadence.",
      y: 790, in: weather, height: 70)

    let time = tab("Time", in: tabs)
    field("clockFormat", title: "Date format", value: settings.clockFormat, y: 18, in: time)
    time.frame.size.height = 970
    let calendarOptions = settings.effectiveCalendarOptions
    choice(
      "firstWeekday", title: "First weekday",
      values: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
      selected: calendarOptions.firstWeekday - 1, y: 65, in: time)
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
      "Calendar events remain local. Access is requested only through the Permissions tab. Lunar phase is an offline approximation. Offline daylight uses a separate manual point and makes no network requests.",
      y: 434, in: time, height: 70)
    let calendars = NSButton(
      title: "Choose Event Calendars…", target: self,
      action: #selector(chooseEventCalendars))
    calendars.frame = NSRect(x: 18, y: 519, width: 240, height: 28); time.addSubview(calendars)
    calendarSelectionLabel.frame = NSRect(x: 18, y: 559, width: 550, height: 48)
    calendarSelectionLabel.font = .systemFont(ofSize: 12); time.addSubview(calendarSelectionLabel)
    updateCalendarSelectionLabel()
    choice(
      "worldClockStyle", title: "World clock style", values: WorldClockStyle.allCases.map(\.title),
      selected: WorldClockStyle.allCases.firstIndex(of: settings.worldClockStyle ?? .compact) ?? 0,
      y: 620, in: time)
    choice(
      "worldClockOrder", title: "World clock ordering",
      values: WorldClockOrder.allCases.map(\.title),
      selected: WorldClockOrder.allCases.firstIndex(of: settings.worldClockOrder ?? .manual) ?? 0,
      y: 660, in: time)
    choice(
      "calendarSystem", title: "Calendar system", values: CalendarSystem.allCases.map(\.title),
      selected: CalendarSystem.allCases.firstIndex(of: calendarOptions.system) ?? 0, y: 700,
      in: time)
    choice(
      "weekNumbers", title: "Week number convention", values: WeekNumberStyle.allCases.map(\.title),
      selected: WeekNumberStyle.allCases.firstIndex(of: calendarOptions.weekNumbers) ?? 0, y: 740,
      in: time)
    field(
      "upcomingDays", title: "Upcoming event days (1–31)",
      value: String(calendarOptions.upcomingDays), y: 780, in: time)
    label(
      "Manual order follows the world-clock lines above. Clock styles share the existing system tick. ISO week numbers label each calendar row by its Thursday; selected-calendar weeks use that calendar's rules. Event dates use calendar arithmetic across daylight saving changes; these controls request no event access.",
      y: 825, in: time, height: 100)

    let daylight = tab("Daylight", in: tabs)
    let point = settings.daylight ?? DaylightConfiguration()
    toggle(
      "daylightEnabled", title: "Enable offline sunrise, sunset and twilight estimates",
      value: point.enabled, y: 18, in: daylight)
    field("daylightName", title: "Manual point name", value: point.name, y: 68, in: daylight)
    field(
      "daylightLatitude", title: "Latitude (north positive)", value: String(point.latitude), y: 110,
      in: daylight)
    field(
      "daylightLongitude", title: "Longitude (east positive)", value: String(point.longitude),
      y: 152, in: daylight)
    field("daylightZone", title: "IANA time zone", value: point.zone, y: 194, in: daylight)
    label(
      "Coordinates stay in local settings and are never sent by this feature. Enter the point and its time zone yourself; no device location, IP lookup or permission request is used. Weather and map consent remain separate. Turning this option off removes the saved daylight point; settings export also removes it.",
      y: 246, in: daylight, height: 106)
    label(
      "The Time panel shows the point's current local day, solar noon, daylight duration and civil/nautical/astronomical boundaries. These are approximate standard-horizon calculations for 1901–2099; terrain, refraction and polar conditions affect observed times. They do not enable weather or read calendars.",
      y: 374, in: daylight, height: 106)

    let rules = tab("Rules", in: tabs)
    rules.frame.size.height = 1150
    label("Sustained threshold notifications", y: 18, in: rules)
    label(
      "Missing values and sleep gaps reset the sustain timer. Notifications have a cooldown and require your permission. The rule engine keeps evaluating while menus are closed.",
      y: 50, in: rules, height: 70)
    choice(
      "ruleMetric", title: "Metric",
      values: [
        "CPU %", "GPU %", "Memory used %", "Battery %", "Maximum temperature °C",
        "First volume free GiB", "Download bytes/s", "Upload bytes/s", "Thermal severity 0–3",
        "Storage read bytes/s", "Storage write bytes/s", "Individual sensor",
      ], selected: 0, y: 132, in: rules)
    choices["ruleMetric"]?.target = self
    choices["ruleMetric"]?.action = #selector(ruleMetricChanged)
    field("ruleSensorKey", title: "Sensor firmware key (4 chars)", value: "", y: 172, in: rules)
    choice(
      "ruleSensorUnit", title: "Sensor native unit", values: SensorIdentity.units, selected: 0,
      y: 212, in: rules)
    ruleMetricChanged()
    choice(
      "ruleComparison", title: "Condition", values: RuleComparison.allCases.map(\.title),
      selected: 0, y: 252,
      in: rules)
    choices["ruleComparison"]?.target = self;
    choices["ruleComparison"]?.action = #selector(ruleComparisonChanged)
    field("ruleThreshold", title: "Threshold", value: "90", y: 292, in: rules)
    field("ruleDuration", title: "Sustain seconds", value: "30", y: 332, in: rules)
    field("ruleCooldown", title: "Cooldown seconds", value: "300", y: 372, in: rules)
    for (title, action, x, width) in [
      ("Add", #selector(addRule), 18.0, 80.0),
      ("Save Selected", #selector(saveRule), 104.0, 130.0),
      ("Delete", #selector(deleteRule), 240.0, 85.0),
      ("Enable/Disable", #selector(toggleRule), 330.0, 130.0),
      ("Clear All", #selector(clearRules), 465.0, 100.0),
    ] {
      let button = NSButton(title: title, target: self, action: action)
      button.frame = NSRect(x: x, y: 417, width: width, height: 28); rules.addSubview(button)
    }
    rulesPicker.frame = NSRect(x: 18, y: 460, width: 550, height: 28)
    rulesPicker.target = self; rulesPicker.action = #selector(selectRule);
    rules.addSubview(rulesPicker)
    label(
      "Sensor thresholds use native units, including °C when display units are °F. A missing key or different unit does not fire. Rules keep their keys live in on-demand mode and do not add history series.",
      y: 500, in: rules, height: 73)
    field("ruleUpper", title: "Upper bound (ranges only)", value: "100", y: 588, in: rules)
    field("ruleHysteresis", title: "Recovery band (native units)", value: "0", y: 630, in: rules)
    toggle(
      "ruleRepeat", title: "Repeat while active after each cooldown", value: true, y: 672, in: rules
    )
    ruleComparisonChanged()
    rulesLabel.frame = NSRect(x: 18, y: 724, width: 550, height: 280); rules.addSubview(rulesLabel)
    label(
      "A recovery band extends an already-active condition; it never starts one. Outside-range bands must be at most half the range width. Turn repeats off for one notification per active episode. Missing data, edits, pause or sleep reset the episode; cooldown remains separate.",
      y: 1018, in: rules, height: 100)
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
      ("Allow Wi-Fi Identity…", #selector(wifiPermission), 295),
    ] {
      let b = NSButton(title: title, target: self, action: action)
      b.frame = NSRect(x: 18, y: y, width: 270, height: 30)
      permissions.addSubview(b)
    }
    label(
      "macOS requires Location Services access to reveal Wi-Fi SSID, BSSID and country. The button requests access only while Settings is active. Aerie never requests device coordinates or background location updates. Signal, noise, rate and channel remain subject to OS availability. Close Settings to cancel the pending attempt; this does not revoke an OS grant.",
      y: 345, in: permissions, height: 125)
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
  @objc private func openAddressTerms() {
    NSWorkspace.shared.open(URL(string: "https://www.ipify.org/")!)
  }
  @objc private func notifications() { onNotifications?() }
  @objc private func calendar() { onCalendar?() }
  @objc private func wifiPermission() { onWiFiPermission?() }
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
    s.combineProcesses = toggles["combineProcesses"]!.state == .on
    var sorts: [Module: ProcessSort] = [:]
    for module in ProcessSort.modules {
      let options = ProcessSort.options(for: module)
      let index = choices["processSort.\(module.rawValue)"]!.indexOfSelectedItem
      guard options.indices.contains(index) else { throw SettingsError.invalid }
      if options[index] != .automatic { sorts[module] = options[index] }
    }
    s.processSorts = sorts.isEmpty ? nil : sorts
    s.binaryBytes = toggles["binary"]!.state == .on
    s.networkBits = toggles["bits"]!.state == .on
    s.publicAddress = toggles["publicAddress"]!.state == .on
    s.networkInterfaces =
      toggles["networkAll"]!.state == .on
      ? nil
      : fields["networkNames"]!.stringValue.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    s.compactSpacing = toggles["spacing"]!.state == .on
    s.persistentHistory = toggles["persistentHistory"]!.state == .on
    s.shortcuts = try KeyboardShortcut.parse(shortcutsField.string)
    s.sensorSampling = choices["sensors"]!.indexOfSelectedItem == 0 ? .all : .whenNeeded
    s.sensorNames = try SensorIdentity.parseNames(sensorNamesField.string)
    s.combined = toggles["combined"]!.state == .on
    s.combinedModules = try MenuPresentation.modules(
      fromTitles: fields["combinedModules"]!.stringValue)
    s.combinedStyle =
      [DisplayStyle.text, .compact, .stacked][choices["combinedStyle"]!.indexOfSelectedItem]
    let combinedColor = fields["combinedColor"]!.stringValue.trimmingCharacters(
      in: .whitespacesAndNewlines)
    s.combinedColorHex = combinedColor.isEmpty ? nil : combinedColor
    s.clockFormat = fields["clockFormat"]!.stringValue
    var calendarOptions = settings.effectiveCalendarOptions
    calendarOptions.firstWeekday = choices["firstWeekday"]!.indexOfSelectedItem + 1
    calendarOptions.system = CalendarSystem.allCases[choices["calendarSystem"]!.indexOfSelectedItem]
    calendarOptions.weekNumbers =
      WeekNumberStyle.allCases[choices["weekNumbers"]!.indexOfSelectedItem]
    guard let upcomingDays = Int(fields["upcomingDays"]!.stringValue) else {
      throw SettingsError.invalid
    }
    calendarOptions.upcomingDays = upcomingDays
    s.calendarOptions = calendarOptions; s.weekStartsMonday = calendarOptions.firstWeekday == 2
    s.worldClockStyle = WorldClockStyle.allCases[choices["worldClockStyle"]!.indexOfSelectedItem]
    s.worldClockOrder = WorldClockOrder.allCases[choices["worldClockOrder"]!.indexOfSelectedItem]
    s.showWeekNumbers = toggles["weeks"]!.state == .on
    if toggles["daylightEnabled"]!.state == .on {
      var point = DaylightConfiguration(); point.enabled = true
      point.name = fields["daylightName"]!.stringValue.trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard let latitude = Double(fields["daylightLatitude"]!.stringValue),
        let longitude = Double(fields["daylightLongitude"]!.stringValue)
      else { throw SettingsError.invalid }
      point.latitude = latitude; point.longitude = longitude
      point.zone = fields["daylightZone"]!.stringValue.trimmingCharacters(
        in: .whitespacesAndNewlines)
      s.daylight = point
    } else {
      s.daylight = nil
    }
    s.clocks = try clocksField.string.split(separator: "\n").map { line in
      let parts = line.split(separator: "|", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard parts.count == 2, !parts[0].isEmpty else { throw SettingsError.invalid }
      return WorldClock(name: parts[0], zone: parts[1])
    }
    s.hourlyForecastHours = [24, 48, 72, 168][choices["hourlyForecastHours"]!.indexOfSelectedItem]
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
        style: DisplayStyle.allCases[menuStyles[$0.0]!.indexOfSelectedItem],
        colorHex: menuColors[$0.0]!.stringValue.isEmpty ? nil : menuColors[$0.0]!.stringValue)
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
        "Check values, time zones, unique menu order/modules, #RRGGBB colors, and a visible or combined item."
    }
  }
  private func ruleFromForm() -> ThresholdRule? {
    guard let threshold = Double(fields["ruleThreshold"]!.stringValue),
      let duration = Double(fields["ruleDuration"]!.stringValue),
      let cooldown = Double(fields["ruleCooldown"]!.stringValue),
      let hysteresis = Double(fields["ruleHysteresis"]!.stringValue)
    else {
      errorLabel.stringValue = "Rules require numeric values."; return nil
    }
    let metric = ruleMetrics[choices["ruleMetric"]!.indexOfSelectedItem]
    let individual = metric == "sensor"
    let comparison = RuleComparison.allCases[choices["ruleComparison"]!.indexOfSelectedItem]
    let upper = comparison.requiresUpperBound ? Double(fields["ruleUpper"]!.stringValue) : nil
    let rule = ThresholdRule(
      metric: individual ? "sensor:" + fields["ruleSensorKey"]!.stringValue : metric,
      threshold: threshold,
      comparison: comparison,
      duration: duration, cooldown: cooldown,
      sensorUnit: individual
        ? SensorIdentity.units[choices["ruleSensorUnit"]!.indexOfSelectedItem] : nil,
      upperThreshold: upper, hysteresis: hysteresis,
      repeatWhileMet: toggles["ruleRepeat"]!.state == .on)
    guard rule.valid else {
      errorLabel.stringValue =
        "Check sensor key/unit, ordered bounds/recovery band, sustain 0–86400s and cooldown 10–604800s.";
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
    let key = SensorIdentity.key(metric: rule.metric)
    choices["ruleMetric"]?.selectItem(
      at: key != nil ? ruleMetrics.count - 1 : ruleMetrics.firstIndex(of: rule.metric) ?? 0)
    fields["ruleSensorKey"]?.stringValue = key ?? ""
    choices["ruleSensorUnit"]?.selectItem(
      at: SensorIdentity.units.firstIndex(of: rule.sensorUnit ?? "") ?? 0)
    ruleMetricChanged()
    choices["ruleComparison"]?.selectItem(
      at: RuleComparison.allCases.firstIndex(of: rule.comparison) ?? 0)
    fields["ruleUpper"]?.stringValue = String(rule.upperThreshold ?? 100)
    fields["ruleHysteresis"]?.stringValue = String(rule.recoveryBand)
    toggles["ruleRepeat"]?.state = rule.repeats ? .on : .off
    ruleComparisonChanged()
    fields["ruleThreshold"]?.stringValue = String(rule.threshold)
    fields["ruleDuration"]?.stringValue = String(rule.duration)
    fields["ruleCooldown"]?.stringValue = String(rule.cooldown)
  }
  @objc private func ruleComparisonChanged() {
    guard let selected = choices["ruleComparison"]?.indexOfSelectedItem,
      RuleComparison.allCases.indices.contains(selected)
    else { return }
    fields["ruleUpper"]?.isEnabled = RuleComparison.allCases[selected].requiresUpperBound
  }
  @objc private func ruleMetricChanged() {
    let individual = choices["ruleMetric"]?.indexOfSelectedItem == ruleMetrics.count - 1
    fields["ruleSensorKey"]?.isEnabled = individual
    choices["ruleSensorUnit"]?.isEnabled = individual
  }
  @objc private func clearRules() {
    settings.rules.removeAll()
    refreshRules()
  }
  private func refreshRules(selected id: UUID? = nil) {
    rulesPicker.removeAllItems(); rulesPicker.addItem(withTitle: "New rule")
    rulesPicker.addItems(
      withTitles: settings.rules.map {
        "\($0.enabled ? "On" : "Off") · \($0.metric) \($0.conditionDescription)"
      })
    if let id, let index = settings.rules.firstIndex(where: { $0.id == id }) {
      rulesPicker.selectItem(at: index + 1)
    }
    rulesPicker.isEnabled = !settings.rules.isEmpty
    rulesLabel.stringValue =
      settings.rules.isEmpty
      ? "No rules. Add a rule, then Apply."
      : settings.rules.map {
        "\($0.metric) \($0.conditionDescription) for \($0.duration)s; cooldown \($0.cooldown)s; recovery \($0.recoveryBand); \($0.repeats ? "repeating" : "once per episode")"
      }.joined(separator: "\n")
  }
  @objc private func exportSettings() {
    do {
      let data = try SettingsProfile.exported(readSettings())
      let panel = NSSavePanel()
      panel.nameFieldStringValue = "Aerie-settings.json"
      if panel.runModal() == .OK, let url = panel.url {
        try data.write(to: url, options: .atomic)
      }
    } catch { errorLabel.stringValue = "Could not export valid settings." }
  }
  private func updateCalendarSelectionLabel() {
    calendarSelectionLabel.stringValue =
      settings.eventCalendars.map {
        $0.isEmpty
          ? "No event calendars selected."
          : "\($0.count) event calendars selected. Missing saved choices stay unavailable."
      }
      ?? "All event calendars. Names are read only when you open the selector with existing permission."
  }
  @objc private func chooseEventCalendars() {
    calendarPicker?.close()
    let picker = CalendarPickerController(
      selection: settings.eventCalendars, access: calendarAccess)
    calendarPicker = picker
    if let window = picker.window { onWindowCreated?(window) }
    picker.onChoose = { [weak self] selected in
      self?.settings.eventCalendars = selected; self?.updateCalendarSelectionLabel()
    }
    picker.onClose = { [weak self] in self?.calendarPicker = nil }
    picker.showWindow(nil)
  }
  @objc private func restoreDefaults() {
    _ = reviewAndStage(.defaults(preservingHistory: settings.effectivePersistentHistory))
  }
  /// Testable without showing a confirmation or writing application preferences.
  @discardableResult func reviewAndStage(_ profile: SettingsProfile) -> Bool {
    let accepted: Bool
    if let onProfileReview {
      accepted = onProfileReview(profile)
    } else {
      let alert = NSAlert(); alert.messageText = profile.title
      alert.informativeText = profile.summary; alert.alertStyle = .informational
      alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Stage Changes")
      accepted = alert.runModal() == .alertSecondButtonReturn
    }
    guard accepted else { return false }
    calendarPicker?.close(); calendarPicker = nil
    settings = profile.settings
    for subview in window?.contentView?.subviews ?? [] { subview.removeFromSuperview() }
    fields.removeAll(); toggles.removeAll(); choices.removeAll()
    menuToggles.removeAll(); menuStyles.removeAll(); menuOrders.removeAll(); menuColors.removeAll()
    build()
    errorLabel.stringValue =
      "Changes staged. Review the options, then Apply; closing discards this draft."
    return true
  }
  @objc private func importSettings() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
      let data = try file.read(upToCount: SettingsProfile.maximumBytes + 1) ?? Data()
      let profile = try SettingsProfile.imported(
        data, preservingHistory: settings.effectivePersistentHistory)
      _ = reviewAndStage(profile)
    } catch SettingsProfileError.unsupportedVersion(let version) {
      errorLabel.stringValue = "Unsupported profile format \(version). Aerie supports format 1."
    } catch {
      errorLabel.stringValue = "This file does not contain valid Aerie settings (1 MB maximum)."
    }
  }
}
private final class FlippedView: NSView { override var isFlipped: Bool { true } }
