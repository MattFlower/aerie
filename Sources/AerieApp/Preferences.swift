import AerieCore
import AppKit

private enum PreferencesValidationError: Error { case daylightTimeZoneRequired }

final class PreferencesController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate,
  NSTextViewDelegate
{
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
  var onMenuPreview: ((Settings) -> [StatusWidget])? { didSet { refreshMenuPreview() } }
  private var menuPreview = MenuBarPreview(frame: .zero)
  private var menuFootprint = NSTextField(wrappingLabelWithString: "")
  private var fields: [String: NSTextField] = [:]
  private var toggles: [String: NSButton] = [:]
  private var choices: [String: NSPopUpButton] = [:]
  private var menuToggles: [Module: NSButton] = [:]
  private var menuStyles: [Module: NSPopUpButton] = [:]
  private var menuOrders: [Module: NSPopUpButton] = [:]
  private var menuColors: [Module: NSTextField] = [:]
  private var menuLabels: [Module: NSPopUpButton] = [:]
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
  private var notificationExample = NSTextField(wrappingLabelWithString: "")
  private var notificationUnits = NSTextField(labelWithString: "")
  private var notificationAdvanced: SettingsForm?
  private var sensorRuleChoices: [SensorData] = []
  private var localTimeZoneLabel = NSTextField(wrappingLabelWithString: "")
  private var errorLabel = NSTextField(wrappingLabelWithString: "")
  init(
    settings: Settings, interfaces: [InterfaceData] = [], sensors: [SensorData] = [],
    interfaceDescriptions: [String: InterfaceDescription] = [:]
  ) {
    self.settings = settings
    interfaceDescriptionsStore = interfaceDescriptions
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Aerie Settings"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    window.minSize = NSSize(width: 840, height: 560)
    interfaceInventory = Array(interfaces.prefix(256));
    sensorInventory = Array(sensors.prefix(4096))
    build()
    for name in [
      Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange,
      NSLocale.currentLocaleDidChangeNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(systemClockChanged), name: name, object: nil)
    }
    window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
    let size = NSSize(width: min(defaultFrame.width, 1040), height: min(defaultFrame.height, 820))
    return NSRect(
      x: defaultFrame.midX - size.width / 2, y: defaultFrame.midY - size.height / 2,
      width: size.width, height: size.height)
  }
  func windowWillClose(_ notification: Notification) {
    NotificationCenter.default.removeObserver(self)
    locationSession.cancel(); locationChoices.removeAll()
    calendarPicker?.close(); calendarPicker = nil
    if let window { MenuPanel.releaseContent(of: window) }
    sidebar = nil; tabs = nil
    fields.removeAll(); toggles.removeAll(); choices.removeAll(); interfaceButtons.removeAll()
    menuToggles.removeAll(); menuStyles.removeAll(); menuOrders.removeAll(); menuColors.removeAll();
    menuLabels.removeAll(); notificationAdvanced = nil; sensorRuleChoices.removeAll()
    sensorInventory.removeAll(); interfaceInventory.removeAll(); locationChoices.removeAll()
    onClose?()
  }
  func validateCalendarAccess() { calendarPicker?.validateAccess() }
  private var tabs: NSTabView?
  private var sidebar: SettingsSidebar?
  private var dateExample = NSTextField(wrappingLabelWithString: "")
  private var draftLabel = NSTextField(labelWithString: "")
  private var interfaceButtons: [String: NSButton] = [:]
  private var interfaceInventory: [InterfaceData] = []
  private var interfaceDescriptionsStore: [String: InterfaceDescription] = [:]
  private var sensorInventory: [SensorData] = []
  var locationSession = LocationLookupSession()
  private var locationChoices: [LocationChoice] = []
  private var locationStatus = NSTextField(wrappingLabelWithString: "")
  private var locationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  private func field(_ id: String, title: String, value: String, in form: SettingsForm) {
    let text = NSTextField(string: value); text.delegate = self
    text.setAccessibilityLabel(title); fields[id] = text; form.row(title, control: text)
  }
  private func toggle(_ id: String, title: String, value: Bool, in form: SettingsForm) {
    let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(draftChanged))
    button.state = value ? .on : .off; toggles[id] = button; form.append(button)
  }
  private func choice(
    _ id: String, title: String, values: [String], selected: Int, in form: SettingsForm
  ) {
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    popup.addItems(withTitles: values); popup.selectItem(at: selected)
    popup.target = self; popup.action = #selector(draftChanged)
    popup.setAccessibilityLabel(title); choices[id] = popup; form.row(title, control: popup)
  }
  private func button(_ title: String, _ action: Selector) -> NSButton {
    NSButton(title: title, target: self, action: action)
  }
  private func form(_ section: SettingsSection, detail: String, tabs: NSTabView) -> SettingsForm {
    let form = SettingsForm(title: section.rawValue, detail: detail)
    let scroll = NSScrollView(); scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = form
    form.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    let item = NSTabViewItem(identifier: section.rawValue); item.label = section.rawValue;
    item.view = scroll
    tabs.addTabViewItem(item); return form
  }
  func selectSection(_ section: SettingsSection) {
    tabs?.selectTabViewItem(withIdentifier: section.rawValue)
    if let index = SettingsSection.allCases.firstIndex(of: section) {
      sidebar?.table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    if section == .menus { refreshMenuPreview() }
  }
  private func build() {
    let split = NSSplitViewController()
    let navigation = SettingsSidebar(); sidebar = navigation
    let sideItem = NSSplitViewItem(sidebarWithViewController: navigation)
    sideItem.minimumThickness = 180; sideItem.maximumThickness = 220
    split.addSplitViewItem(sideItem)
    let detail = NSViewController(); detail.view = NSView()
    let tabs = NSTabView(); self.tabs = tabs; tabs.tabViewType = .noTabsNoBorder
    tabs.translatesAutoresizingMaskIntoConstraints = false; detail.view.addSubview(tabs)
    let footer = NSStackView(); footer.orientation = .horizontal; footer.alignment = .centerY;
    footer.spacing = 8
    footer.translatesAutoresizingMaskIntoConstraints = false; detail.view.addSubview(footer)
    draftLabel.font = .systemFont(ofSize: 12); draftLabel.textColor = .secondaryLabelColor
    let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let close = button("Close", #selector(closeWindow))
    let apply = button("Apply", #selector(applySettings)); apply.keyEquivalent = "\r"
    for view in [draftLabel, spacer, close, apply] { footer.addArrangedSubview(view) }
    errorLabel = NSTextField(wrappingLabelWithString: "")
    errorLabel.font = .systemFont(ofSize: 12); errorLabel.textColor = .systemRed
    errorLabel.setAccessibilityLabel("Settings error")
    errorLabel.translatesAutoresizingMaskIntoConstraints = false; detail.view.addSubview(errorLabel)
    NSLayoutConstraint.activate([
      tabs.leadingAnchor.constraint(equalTo: detail.view.leadingAnchor),
      tabs.trailingAnchor.constraint(equalTo: detail.view.trailingAnchor),
      tabs.topAnchor.constraint(equalTo: detail.view.topAnchor),
      tabs.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -8),
      errorLabel.leadingAnchor.constraint(equalTo: detail.view.leadingAnchor, constant: 24),
      errorLabel.trailingAnchor.constraint(equalTo: detail.view.trailingAnchor, constant: -24),
      errorLabel.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
      footer.leadingAnchor.constraint(equalTo: detail.view.leadingAnchor, constant: 24),
      footer.trailingAnchor.constraint(equalTo: detail.view.trailingAnchor, constant: -24),
      footer.bottomAnchor.constraint(equalTo: detail.view.bottomAnchor, constant: -18),
    ])
    split.addSplitViewItem(NSSplitViewItem(viewController: detail))
    window?.contentViewController = split
    navigation.onSelect = { [weak self] section in
      self?.tabs?.selectTabViewItem(withIdentifier: section.rawValue)
    }
    buildGeneral(
      form(
        .general, detail: "Choose how Aerie collects and presents your Mac's activity.", tabs: tabs)
    )
    buildMenus(form(.menus, detail: "Keep the information you use close at hand.", tabs: tabs))
    buildNetwork(
      form(
        .network,
        detail: "Choose the interfaces used for bandwidth, history and speed notifications.",
        tabs: tabs))
    buildWeather(
      form(
        .weather, detail: "Choose a location, then decide which weather services to enable.",
        tabs: tabs))
    buildTime(
      form(
        .time, detail: "Local time, world clocks, calendars and daylight in one place.", tabs: tabs)
    )
    buildSensors(
      form(
        .sensors, detail: "Readable hardware readings with stable sensor identities.", tabs: tabs))
    buildNotifications(
      form(
        .notifications,
        detail: "Be notified when a value crosses a limit or your Mac's state changes.", tabs: tabs)
    )
    buildShortcuts(form(.shortcuts, detail: "Open Aerie from the keyboard.", tabs: tabs))
    buildPermissions(
      form(
        .permissions,
        detail: "Choose access for the features you want. Aerie requests no permissions at launch.",
        tabs: tabs))
    updateDateExample(); draftLabel.stringValue = "Changes take effect when you Apply."
  }
  private func buildGeneral(_ page: SettingsForm) {
    page.section("Collection")
    choice(
      "interval", title: "Refresh every",
      values: ["0.5 seconds", "1 second", "2 seconds", "3 seconds", "5 seconds"],
      selected: [0.5, 1, 2, 3, 5].firstIndex(of: settings.interval) ?? 1, in: page)
    choice(
      "sensors", title: "Hardware sensor sampling",
      values: ["All supported sensors", "Other families on demand"],
      selected: settings.effectiveSensorSampling == .all ? 0 : 1, in: page)
    page.note(
      "Full sampling reads every supported sensor at your chosen interval. On demand keeps temperatures and notification sensors current while other families wait for the Sensors menu."
    )
    field(
      "processCount", title: "Top process count (1–20)", value: String(settings.processCount),
      in: page)
    toggle(
      "normalizedCPU", title: "Show process CPU as a percentage of the whole Mac",
      value: settings.normalizedProcessCPU, in: page)
    toggle(
      "combineProcesses", title: "Combine processes belonging to the same application",
      value: settings.effectiveCombineProcesses, in: page)
    for module in ProcessSort.modules {
      let options = ProcessSort.options(for: module)
      choice(
        "processSort.\(module.rawValue)", title: module.title + " process sorting",
        values: options.map(\.title),
        selected: options.firstIndex(of: settings.processSorts?[module] ?? .automatic) ?? 0,
        in: page)
    }
    page.section("Units and appearance")
    choice(
      "theme", title: "Appearance", values: ["System", "Light", "Dark"],
      selected: Theme.allCases.firstIndex(of: settings.theme) ?? 0, in: page)
    choice(
      "temperature", title: "Temperature", values: ["Celsius", "Fahrenheit"],
      selected: settings.temperature == .celsius ? 0 : 1, in: page)
    toggle(
      "binary", title: "Use binary byte units (KiB, MiB, GiB)", value: settings.binaryBytes,
      in: page)
    toggle(
      "bits", title: "Show network speeds in bits per second", value: settings.networkBits, in: page
    )
    page.section("History and settings")
    toggle(
      "persistentHistory", title: "Keep numeric history between launches",
      value: settings.effectivePersistentHistory, in: page)
    page.note(
      "The local numeric archive is limited to 2 MB. Turning this off deletes it. Process, sensor, calendar and weather names are never archived."
    )
    page.buttons([
      button("Export Settings…", #selector(exportSettings)),
      button("Import Settings…", #selector(importSettings)),
      button("Restore Defaults…", #selector(restoreDefaults)),
    ])
    page.note(
      "Imports and defaults are reviewed before they enter this draft. Apply commits the draft; Close discards unapplied changes. Exported profiles exclude locations and calendar selections."
    )
    page.buttons([button("Open Dashboard", #selector(openDashboard))])
  }
  private func buildMenus(_ page: SettingsForm) {
    page.section("Preview and space")
    page.buttons([button("Use Compact Layout", #selector(compactMenus))])
    page.note(
      "Compact uses vertical labels, an icon-only Aerie control and tighter spacing. Every enabled module and sampling setting is preserved. Changes enter this draft until Apply."
    )
    menuPreview = MenuBarPreview(frame: .zero)
    let previewScroll = NSScrollView(); previewScroll.hasHorizontalScroller = true
    previewScroll.autohidesScrollers = true; previewScroll.drawsBackground = false
    previewScroll.documentView = menuPreview
    previewScroll.heightAnchor.constraint(equalToConstant: 42).isActive = true
    page.append(previewScroll)
    menuFootprint = NSTextField(wrappingLabelWithString: "")
    menuFootprint.font = .systemFont(ofSize: 12); menuFootprint.textColor = .secondaryLabelColor
    menuFootprint.setAccessibilityLabel("Menu-bar point width")
    page.append(menuFootprint)
    page.section("Layout")
    choice(
      "menuLayout", title: "Menu-bar layout",
      values: ["Grouped modules", "Separate items", "Combined dashboard"],
      selected: settings.combined ? 2 : settings.effectiveGroupedMenus ? 0 : 1, in: page)
    choices["menuLayout"]?.action = #selector(menuLayoutChanged)
    choice(
      "menuPadding", title: "Padding inside each module", values: (0...12).map { "\($0) points" },
      selected: settings.effectiveMenuPadding, in: page)
    choice(
      "menuGap", title: "Gap between grouped modules", values: (0...12).map { "\($0) points" },
      selected: settings.effectiveMenuGap, in: page)
    toggle(
      "spacing", title: "Compact spacing in combined dashboard", value: settings.compactSpacing,
      in: page)
    menuLayoutChanged()
    page.note(
      "A grouped display controls Aerie's own gaps. Separate items follow macOS placement. Other applications and system spacing are unchanged."
    )
    page.section("Visible modules")
    page.note(
      "Each row sets visibility, display style, order, label position and optional RGB color.")
    for (index, menu) in settings.menus.enumerated() {
      let toggle = NSButton(
        checkboxWithTitle: menu.module.title, target: self, action: #selector(draftChanged))
      toggle.state = menu.visible ? .on : .off; menuToggles[menu.module] = toggle
      let style = NSPopUpButton(frame: .zero, pullsDown: false)
      style.addItems(withTitles: ["Text", "Graph", "Compact", "Stacked"])
      style.selectItem(at: DisplayStyle.allCases.firstIndex(of: menu.style) ?? 0)
      style.setAccessibilityLabel(menu.module.title + " display style");
      menuStyles[menu.module] = style
      let order = NSPopUpButton(frame: .zero, pullsDown: false)
      order.addItems(withTitles: (1...settings.menus.count).map(String.init));
      order.selectItem(at: index)
      order.setAccessibilityLabel(menu.module.title + " menu order");
      menuOrders[menu.module] = order
      let color = NSTextField(string: menu.colorHex ?? ""); color.placeholderString = "Auto"
      color.setAccessibilityLabel(
        menu.module.title + " color, hexadecimal RGB or empty for automatic");
      menuColors[menu.module] = color
      style.target = self; style.action = #selector(draftChanged); order.target = self;
      order.action = #selector(draftChanged); color.delegate = self
      let label = NSPopUpButton(frame: .zero, pullsDown: false)
      label.addItems(withTitles: ["Automatic", "No label", "Inline", "Vertical", "Icon"])
      label.selectItem(
        at: MenuLabelPlacement.allCases.firstIndex(of: menu.labelPlacement ?? .automatic) ?? 0)
      label.setAccessibilityLabel(menu.module.title + " label position"); label.target = self;
      label.action = #selector(draftChanged)
      menuLabels[menu.module] = label
      label.widthAnchor.constraint(equalToConstant: 100).isActive = true
      let row = NSStackView(views: [toggle, style, order, label, color]);
      row.orientation = .horizontal;
      row.spacing = 8
      toggle.widthAnchor.constraint(equalToConstant: 92).isActive = true
      style.widthAnchor.constraint(equalToConstant: 100).isActive = true
      order.widthAnchor.constraint(equalToConstant: 48).isActive = true
      color.widthAnchor.constraint(equalToConstant: 76).isActive = true
      page.append(row, fullWidth: false)
    }
    page.note(
      "Order numbers must be unique. Unconfigured weather stays hidden; a configured location keeps its item while data is stale or unavailable."
    )
    page.section("Combined dashboard")
    field(
      "combinedModules", title: "Combined items (names, ordered)",
      value: settings.effectiveCombinedModules.map(\.title).joined(separator: ","), in: page)
    choice(
      "combinedStyle", title: "Combined display", values: ["Text", "Compact", "Stacked"],
      selected: [DisplayStyle.text, .compact, .stacked].firstIndex(
        of: settings.combinedStyle ?? .text) ?? 0, in: page)
    field(
      "combinedColor", title: "Combined color (#RRGGBB or empty)",
      value: settings.combinedColorHex ?? "", in: page)
    page.note(
      "Choose 1–6 module names. Automatic colors follow macOS. Hiding a menu item does not stop collection or remove its dashboard."
    )
  }
  private func buildNetwork(_ page: SettingsForm) {
    page.section("Bandwidth sources")
    toggle(
      "networkAll", title: "Aggregate all active interfaces",
      value: settings.networkInterfaces == nil, in: page)
    toggles["networkAll"]?.action = #selector(networkScopeChanged)
    let descriptions = interfaceDescriptionsStore
    let missing = (settings.networkInterfaces ?? []).filter { name in
      !interfaceInventory.contains { $0.name == name }
    }
    for entry in interfaceInventory.sorted(by: { $0.name < $1.name }) {
      let selected = settings.networkInterfaces?.contains(entry.name) ?? false
      let button = NSButton(
        checkboxWithTitle: InterfaceCatalog.title(
          identifier: entry.name, active: entry.active, description: descriptions[entry.name]),
        target: self,
        action: #selector(draftChanged))
      button.state = selected ? .on : .off; interfaceButtons[entry.name] = button;
      page.append(button)
    }
    for name in missing {
      let button = NSButton(
        checkboxWithTitle: name + " · Not currently available", target: self,
        action: #selector(draftChanged))
      button.state = .on; interfaceButtons[name] = button; page.append(button)
    }
    if interfaceButtons.isEmpty {
      page.note(
        "No interfaces are present in the current sample. A saved selection remains available when its interface returns."
      )
    }
    page.note(
      "Turn All off to select interfaces. An empty selection means None. Virtual tunnels can duplicate physical traffic; select one side to avoid counting it twice. Every interface is still collected at the original interval."
    )
    networkScopeChanged()
    page.section("External address")
    toggle(
      "publicAddress", title: "Look up external IP address through api.ipify.org",
      value: settings.effectivePublicAddress, in: page)
    page.note(
      "This optional lookup sends your network IP to api.ipify.org every five minutes. Reply data stays in memory. It is separate from local interface monitoring."
    )
    page.buttons([button("Read Address Service Terms…", #selector(openAddressTerms))])
  }
  private func buildWeather(_ page: SettingsForm) {
    page.section("Location")
    field("locationQuery", title: "City or ZIP / postal code", value: "", in: page)
    page.buttons([
      button("Find Location", #selector(findLocation)),
      button("Use My Mac Location", #selector(useMacLocation)),
    ])
    page.note(
      "Find sends your search and network IP to Apple's geocoding service. Use My Mac Location requests one location through macOS and may ask for permission. Neither action enables weather or maps."
    )
    locationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    locationPicker.addItem(withTitle: "Choose a location")
    locationPicker.target = self; locationPicker.action = #selector(chooseLocation)
    locationPicker.setAccessibilityLabel("Location search results")
    locationPicker.isHidden = true; page.append(locationPicker)
    locationStatus = NSTextField(wrappingLabelWithString: "Choose a location to get started.")
    locationStatus.textColor = .secondaryLabelColor; locationStatus.font = .systemFont(ofSize: 12)
    page.append(locationStatus)
    toggle(
      "reuseDaylightLocation", title: "Use the chosen location for offline daylight too",
      value: true, in: page)
    field("weatherName", title: "Location display name", value: settings.weather.name, in: page)
    page.section("Coordinates")
    page.note("These are filled by the location chooser. You can also enter a point manually.")
    field(
      "latitude", title: "Latitude (−90…90)", value: String(settings.weather.latitude), in: page)
    field(
      "longitude", title: "Longitude (−180…180)", value: String(settings.weather.longitude),
      in: page)
    page.section("Forecasts")
    choice(
      "weatherProvider", title: "Forecast provider",
      values: ["Open-Meteo (global models)", "NWS (US land forecasts/stations)"],
      selected: settings.weather.provider == "nws" ? 1 : 0, in: page)
    page.note(
      "Enabling forecasts sends your network IP and rounded coordinates to the selected provider. Open-Meteo permits personal, noncommercial use and may retain troubleshooting logs for up to 90 days. NWS provides US land forecasts, station observations and point alerts."
    )
    page.buttons([button("Read Provider Terms…", #selector(openTerms))])
    toggle(
      "weather", title: "Enable weather and send this location to the selected provider",
      value: settings.weather.enabled, in: page)
    choice(
      "hourlyForecastHours", title: "Hourly forecast rows", values: ["24", "48", "72", "168"],
      selected: [24, 48, 72, 168].firstIndex(of: settings.effectiveHourlyForecastHours) ?? 0,
      in: page)
    page.note(
      "Forecasts refresh every 15 minutes. Cached details show source and observation times; they are not real-time warning delivery. Choosing a location alone does not enable forecasts."
    )
    page.section("Maps")
    toggle(
      "maps", title: "Enable NOAA/NWS maps for this location", value: settings.weather.mapsEnabled,
      in: page)
    page.note(
      "Opening Maps sends the chosen map area and your IP to NOAA services. Point alert details also send the rounded center point. Map consent is separate from forecast consent, and maps load only while open."
    )
  }
  private func buildTime(_ page: SettingsForm) {
    page.section("Menu-bar date and time")
    localTimeZoneLabel = NSTextField(
      wrappingLabelWithString: "Time zone: " + TimeZone.autoupdatingCurrent.identifier
        + " · Follows Mac automatically")
    localTimeZoneLabel.font = .systemFont(ofSize: 12);
    localTimeZoneLabel.textColor = .secondaryLabelColor
    page.append(localTimeZoneLabel)
    choice(
      "clockMode", title: "Date and time format", values: ["Follow Mac settings", "Custom format"],
      selected: settings.clockFormat.isEmpty ? 0 : 1, in: page)
    choices["clockMode"]?.action = #selector(dateFormatChanged)
    field("clockFormat", title: "Date format", value: settings.clockFormat, in: page)
    dateExample.font = .systemFont(ofSize: 16, weight: .medium);
    dateExample.setAccessibilityLabel("Date format example")
    page.append(dateExample)
    page.note(
      "Automatic format follows the Mac's locale and 12/24-hour preference. The local clock follows the Mac's time zone. Custom formats use date-pattern syntax; the example updates as you type."
    )
    let options = settings.effectiveCalendarOptions
    choice(
      "firstWeekday", title: "First weekday",
      values: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
      selected: options.firstWeekday - 1, in: page)
    choice(
      "calendarSystem", title: "Calendar system", values: CalendarSystem.allCases.map(\.title),
      selected: CalendarSystem.allCases.firstIndex(of: options.system) ?? 0, in: page)
    toggle("weeks", title: "Show calendar week numbers", value: settings.showWeekNumbers, in: page)
    choice(
      "weekNumbers", title: "Week number convention", values: WeekNumberStyle.allCases.map(\.title),
      selected: WeekNumberStyle.allCases.firstIndex(of: options.weekNumbers) ?? 0, in: page)
    page.section("World clocks")
    clocksField = NSTextView(); clocksField.delegate = self;
    clocksField.string = (try? WorldClockForm.text(settings.clocks)) ?? ""
    clocksField.isAutomaticQuoteSubstitutionEnabled = false;
    clocksField.isAutomaticDashSubstitutionEnabled = false;
    clocksField.isAutomaticTextReplacementEnabled = false
    clocksField.setAccessibilityLabel("World clocks"); page.editor(clocksField, height: 150)
    page.note(
      "One Name | IANA time zone per line. Quote names that contain a pipe. Example: Home | Europe/London."
    )
    choice(
      "worldClockStyle", title: "World clock style", values: WorldClockStyle.allCases.map(\.title),
      selected: WorldClockStyle.allCases.firstIndex(of: settings.worldClockStyle ?? .compact) ?? 0,
      in: page)
    choice(
      "worldClockOrder", title: "World clock ordering",
      values: WorldClockOrder.allCases.map(\.title),
      selected: WorldClockOrder.allCases.firstIndex(of: settings.worldClockOrder ?? .manual) ?? 0,
      in: page)
    page.section("Calendar events")
    page.buttons([button("Choose Event Calendars…", #selector(chooseEventCalendars))])
    updateCalendarSelectionLabel(); page.append(calendarSelectionLabel)
    field(
      "upcomingDays", title: "Upcoming event days (1–31)", value: String(options.upcomingDays),
      in: page)
    page.section("Daylight")
    let point = settings.daylight ?? DaylightConfiguration()
    toggle(
      "daylightEnabled", title: "Show offline sunrise, sunset and twilight estimates",
      value: point.enabled, in: page)
    field("daylightName", title: "Daylight location", value: point.name, in: page)
    field("daylightLatitude", title: "Daylight latitude", value: String(point.latitude), in: page)
    field(
      "daylightLongitude", title: "Daylight longitude", value: String(point.longitude), in: page)
    field("daylightZone", title: "Daylight time zone", value: point.zone, in: page)
    page.note(
      "Daylight calculations stay on your Mac and do not enable weather, maps or calendar access. Solar and lunar estimates are approximate."
    )
  }
  private func buildSensors(_ page: SettingsForm) {
    page.section("Sensor names")
    page.note(
      "Names come from hardware-specific mappings. A community label does not prove a physical core or component identity; the original code stays available in details. Unknown sensors remain labeled honestly."
    )
    if !sensorInventory.isEmpty {
      let list = SensorNameList(sensors: sensorInventory, names: settings.sensorNames ?? [:])
      list.onNameChanged = { [weak self] key, alias in
        guard let self else { return false }
        do {
          var names = try SensorIdentity.parseNames(self.sensorNamesField.string) ?? [:]
          names[key] = alias
          guard SensorIdentity.valid(names: names) else { throw SettingsError.invalid }
          self.sensorNamesField.string = names.sorted { $0.key < $1.key }.map {
            $0.key + " | " + $0.value
          }.joined(separator: "\n")
          self.draftChanged(); return true
        } catch {
          self.errorLabel.stringValue = "Check saved aliases before editing a sensor name."
          return false
        }
      }
      page.append(list)
      page.note(
        "Edit a name directly in the list; clear it to restore the supplied name. Readings reflect the sample when Settings opened."
      )
    } else {
      page.note("No readable sensors are present in this sample. Saved names are preserved.")
    }
    page.section("Saved aliases")
    sensorNamesField = NSTextView(); sensorNamesField.delegate = self
    sensorNamesField.string = (settings.sensorNames ?? [:]).sorted { $0.key < $1.key }.map {
      $0.key + " | " + $0.value
    }.joined(separator: "\n")
    sensorNamesField.setAccessibilityLabel("Local sensor names by firmware key");
    page.editor(sensorNamesField, height: 220)
    page.note(
      "Optional aliases: code | name, one per line. Clear an alias to use the supplied name. Saved aliases remain when a sensor is missing; aliases do not change its measurement or unit."
    )
  }
  private func buildNotifications(_ page: SettingsForm) {
    page.section("Value notifications")
    page.note(
      "Choose a value, a limit and how long it must stay there. Missing readings, pause and sleep restart that waiting period. Notifications require permission and continue while menus are closed."
    )
    choice(
      "ruleMetric", title: "Notify me when",
      values: ruleMetrics.map {
        $0 == "sensor" ? "Individual sensor" : NotificationPresentation.title($0)
      }, selected: 0, in: page)
    choices["ruleMetric"]?.action = #selector(ruleMetricChanged)
    choice(
      "ruleComparison", title: "Condition", values: RuleComparison.allCases.map(\.title),
      selected: 0, in: page)
    choices["ruleComparison"]?.action = #selector(ruleComparisonChanged)
    field("ruleThreshold", title: "Limit", value: "90", in: page)
    field("ruleDuration", title: "Stays this way for (seconds)", value: "30", in: page)
    field("ruleCooldown", title: "Wait between notifications (seconds)", value: "300", in: page)
    sensorRuleChoices = sensorInventory.sorted { $0.label < $1.label }
    choice(
      "ruleSensorChoice", title: "Choose a sensor",
      values: ["Choose a sensor"]
        + sensorRuleChoices.map { $0.title(names: settings.sensorNames) + " (" + $0.unit + ")" },
      selected: 0, in: page)
    choices["ruleSensorChoice"]?.action = #selector(sensorRuleChanged)
    let advanced = SettingsForm(
      title: "Advanced options",
      detail: "Range limits, sensor identity, recovery and repeat behavior.")
    notificationAdvanced = advanced
    toggle(
      "notificationAdvanced", title: "Show advanced notification options", value: false, in: page)
    toggles["notificationAdvanced"]?.action = #selector(toggleNotificationAdvanced)
    field("ruleSensorKey", title: "Sensor code (4 characters)", value: "", in: advanced)
    choice(
      "ruleSensorUnit", title: "Sensor native unit", values: SensorIdentity.units, selected: 0,
      in: advanced)
    field("ruleUpper", title: "Upper bound (ranges only)", value: "100", in: advanced)
    field("ruleHysteresis", title: "Recovery margin", value: "0", in: advanced)
    toggle(
      "ruleRepeat", title: "Repeat while active after each cooldown", value: true, in: advanced)
    advanced.isHidden = true; page.append(advanced)
    notificationUnits.font = .systemFont(ofSize: 12);
    notificationUnits.textColor = .secondaryLabelColor
    page.append(notificationUnits)
    notificationExample.font = .systemFont(ofSize: 14, weight: .medium)
    notificationExample.setAccessibilityLabel("Notification example");
    page.append(notificationExample)
    page.note(
      "Cooldown is the minimum time between notifications. Recovery margin prevents repeated alerts around a boundary. Turn repeats off for one notification until the condition clears."
    )
    page.buttons([
      button("Add to Draft", #selector(addRule)), button("Update Draft", #selector(saveRule)),
      button("Remove", #selector(deleteRule)), button("Enable/Disable", #selector(toggleRule)),
      button("Clear All", #selector(clearRules)),
    ])
    rulesPicker.setAccessibilityLabel("Saved value notifications")
    rulesPicker.target = self; rulesPicker.action = #selector(selectRule); page.append(rulesPicker)
    rulesLabel = NSTextField(wrappingLabelWithString: ""); page.append(rulesLabel)
    ruleMetricChanged(); ruleComparisonChanged(); refreshRules()
    page.note("Add or update a notification in the draft, then Apply to activate it.")
    page.section("State changes")
    page.note(
      "Choose which changes notify you. Each switch has its own minimum time between notifications. Aerie establishes a baseline before notifying; mounted volumes refresh every 30 seconds."
    )
    for kind in ChangeKind.allCases {
      toggle(
        "change.\(kind.rawValue)", title: kind.title,
        value: settings.changeRules?.first(where: { $0.kind == kind })?.enabled ?? false, in: page)
      field(
        "changeCooldown.\(kind.rawValue)", title: kind.title + " cooldown seconds (10–604800)",
        value: String(settings.changeRules?.first(where: { $0.kind == kind })?.cooldown ?? 300),
        in: page)
    }
  }
  private func buildShortcuts(_ page: SettingsForm) {
    page.section("Keyboard shortcuts")
    shortcutsField = NSTextView(); shortcutsField.delegate = self
    shortcutsField.string = (settings.shortcuts ?? []).map {
      $0.targetTitle + " | " + $0.combination
    }.joined(separator: "\n")
    shortcutsField.setAccessibilityLabel("Global shortcut combinations");
    page.editor(shortcutsField, height: 220)
    page.note(
      "One target | combination per line. Examples: CPU | Command+Option+C and Settings | Command+Control+A. Use unique combinations with Command or Control; shortcuts stay off until you Apply."
    )
  }
  private func buildPermissions(_ page: SettingsForm) {
    page.section("Access")
    page.buttons([button("Enable Notifications…", #selector(notifications))])
    page.note("Allow Aerie's value and state-change notifications.")
    page.buttons([button("Allow Calendar Events…", #selector(calendar))])
    page.note("Show your chosen event calendars locally in Date & Time.")
    page.buttons([button("Allow Wi-Fi Identity…", #selector(wifiPermission))])
    page.note(
      "macOS uses Location Services permission to reveal Wi-Fi network names. Signal and channel information depend on OS availability. Requesting identity access does not start location tracking."
    )
    page.buttons([button("Enable Launch at Login…", #selector(login))])
    page.note(
      "Start Aerie when you sign in. No privileged helper or security-setting change is installed.")
  }
  @objc private func toggleNotificationAdvanced() {
    notificationAdvanced?.isHidden = toggles["notificationAdvanced"]?.state != .on
  }
  @objc private func sensorRuleChanged() {
    let index = (choices["ruleSensorChoice"]?.indexOfSelectedItem ?? 0) - 1
    guard sensorRuleChoices.indices.contains(index) else { return }
    let sensor = sensorRuleChoices[index]
    fields["ruleSensorKey"]?.stringValue = sensor.key
    choices["ruleSensorUnit"]?.selectItem(withTitle: sensor.unit)
    updateNotificationExample(); draftChanged()
  }
  @objc private func findLocation() {
    locationStatus.stringValue = "Finding locations…"; locationPicker.isHidden = true
    locationSession.search(fields["locationQuery"]?.stringValue ?? "") { [weak self] result in
      self?.receiveLocations(result)
    }
  }
  @objc private func useMacLocation() {
    locationStatus.stringValue = "Waiting for the Mac's location…"; locationPicker.isHidden = true
    locationSession.macLocation(foreground: NSApp.isActive && window?.isKeyWindow == true) {
      [weak self] result in self?.receiveLocations(result)
    }
  }
  private func receiveLocations(_ result: Result<[LocationChoice], LocationLookupError>) {
    switch result {
    case .failure(let error): locationStatus.stringValue = error.message
    case .success(let choices):
      locationChoices = Array(choices.filter(\.valid).prefix(10))
      guard !locationChoices.isEmpty else {
        locationStatus.stringValue = LocationLookupError.unavailable.message; return
      }
      if locationChoices.count == 1 { stageLocation(locationChoices[0]); return }
      locationPicker.removeAllItems(); locationPicker.addItem(withTitle: "Choose a location")
      locationPicker.addItems(withTitles: locationChoices.map(\.name));
      locationPicker.isHidden = false
      locationStatus.stringValue =
        "Choose the matching location. Forecasts and maps remain unchanged."
    }
  }
  @objc private func chooseLocation() {
    let index = locationPicker.indexOfSelectedItem - 1
    guard locationChoices.indices.contains(index) else { return };
    stageLocation(locationChoices[index])
  }
  func stageLocation(_ point: LocationChoice) {
    guard point.valid else { return }
    fields["weatherName"]?.stringValue = String(point.name.prefix(64))
    fields["latitude"]?.stringValue = String(point.latitude);
    fields["longitude"]?.stringValue = String(point.longitude)
    if toggles["reuseDaylightLocation"]?.state == .on {
      fields["daylightName"]?.stringValue = String(point.name.prefix(64))
      fields["daylightLatitude"]?.stringValue = String(point.latitude);
      fields["daylightLongitude"]?.stringValue = String(point.longitude)
      fields["daylightZone"]?.stringValue = point.zone ?? ""
    }
    locationPicker.isHidden = true
    locationStatus.stringValue =
      point.zone == nil && toggles["reuseDaylightLocation"]?.state == .on
      ? "Location staged. Daylight time zone unavailable; choose it in Date & Time before enabling daylight. Forecasts and maps remain under their own switches."
      : "Location staged. Forecasts, maps and daylight each stay under their own switch. Apply to save."
    draftChanged()
  }
  func windowDidMiniaturize(_ notification: Notification) {
    locationSession.cancel();
    locationStatus.stringValue = "Location lookup cancelled. Try again when Settings is active."
  }
  @objc private func menuLayoutChanged() {
    let layout = choices["menuLayout"]?.indexOfSelectedItem ?? 0
    choices["menuGap"]?.isEnabled = layout == 0
    choices["menuPadding"]?.isEnabled = layout != 2
    toggles["spacing"]?.isEnabled = layout == 2
    draftChanged()
  }
  @objc private func networkScopeChanged() {
    let all = toggles["networkAll"]?.state == .on
    for button in interfaceButtons.values { button.isEnabled = !all }
    draftChanged()
  }
  @objc private func dateFormatChanged() {
    if choices["clockMode"]?.indexOfSelectedItem == 1
      && fields["clockFormat"]?.stringValue.isEmpty == true
    {
      let formatter = DateFormatter(); LocalClockFormat.configure(formatter, pattern: "")
      fields["clockFormat"]?.stringValue = formatter.dateFormat
    }
    updateDateExample(); draftChanged()
  }
  private func cancelPendingLocation() {
    let pending = locationSession.isPending; locationSession.cancel()
    if pending {
      locationChoices.removeAll(); locationPicker.isHidden = true
      locationStatus.stringValue = "Location lookup cancelled to keep your current draft."
    }
  }
  func controlTextDidChange(_ notification: Notification) {
    if let edited = notification.object as? NSTextField,
      [
        "locationQuery", "weatherName", "latitude", "longitude", "daylightName", "daylightLatitude",
        "daylightLongitude", "daylightZone",
      ].contains(where: { fields[$0] === edited })
    {
      cancelPendingLocation()
    }
    updateDateExample(); draftChanged()
  }
  func textDidChange(_ notification: Notification) { draftChanged() }
  private func ruleSummary(_ rule: ThresholdRule) -> String {
    let key = SensorIdentity.key(metric: rule.metric)
    let aliases = (try? SensorIdentity.parseNames(sensorNamesField.string)) ?? settings.sensorNames
    let name = key.flatMap { sensorKey in
      aliases?[sensorKey] ?? sensorInventory.first(where: { $0.key == sensorKey })?.label
    }
    return NotificationPresentation.summary(rule, sensorName: name)
  }
  @objc private func draftChanged() {
    guard !fields.isEmpty else { return }
    updateNotificationExample()
    draftLabel.stringValue = "Unapplied changes. Apply to save, or Close to discard."
    refreshMenuPreview()
  }
  private func refreshMenuPreview() {
    guard let onMenuPreview else { return }
    guard let draft = try? readSettings() else {
      menuFootprint.stringValue = "Preview needs a valid draft. Review the values and module order."
      return
    }
    guard !draft.combined else {
      menuPreview.update([], padding: 0, gap: 0)
      menuFootprint.stringValue =
        "Combined dashboard uses one control. Choose Grouped modules or Separate items for a per-module width preview."
      return
    }
    let widgets = onMenuPreview(draft)
    let padding = CGFloat(
      draft.combined ? (draft.compactSpacing ? 1 : 4) : draft.effectiveMenuPadding)
    let gap = CGFloat(
      draft.combined
        ? (draft.compactSpacing ? 2 : 6) : draft.effectiveGroupedMenus ? draft.effectiveMenuGap : 0)
    let width = menuPreview.update(widgets, padding: padding, gap: gap)
    let rows = menuPreview.moduleWidths.map { "\($0.0.title) \(Int(ceil($0.1)))" }.joined(
      separator: " · ")
    menuFootprint.stringValue =
      "\(Int(ceil(width))) pt in Aerie modules · \(rows). "
      + (draft.effectiveGroupedMenus && !draft.combined
        ? "Grouped gaps included." : "macOS also places space between separate items.")
  }
  @objc private func compactMenus() {
    choices["menuLayout"]?.selectItem(at: 0)
    choices["menuPadding"]?.selectItem(at: 1); choices["menuGap"]?.selectItem(at: 2)
    toggles["spacing"]?.state = .on
    for module in menuStyles.keys {
      menuStyles[module]?.selectItem(
        at: DisplayStyle.allCases.firstIndex(of: module == .time ? .text : .compact)!)
      let label: MenuLabelPlacement =
        module == .overview || module == .weather ? .icon : module == .time ? .none : .vertical
      menuLabels[module]?.selectItem(at: MenuLabelPlacement.allCases.firstIndex(of: label)!)
    }
    menuLayoutChanged()
  }
  private func updateNotificationExample() {
    guard let index = choices["ruleMetric"]?.indexOfSelectedItem,
      ruleMetrics.indices.contains(index)
    else { return }
    let metric = ruleMetrics[index]
    let unit = NotificationPresentation.unit(
      metric, sensorUnit: choices["ruleSensorUnit"]?.titleOfSelectedItem)
    notificationUnits.stringValue =
      metric == "thermal"
      ? "Thermal levels: 0 normal, 1 fair, 2 serious, 3 critical." : "Limits use " + unit + "."
    guard let threshold = Double(fields["ruleThreshold"]?.stringValue ?? ""),
      let seconds = Double(fields["ruleDuration"]?.stringValue ?? ""), threshold.isFinite,
      seconds.isFinite,
      let condition = choices["ruleComparison"]?.indexOfSelectedItem,
      RuleComparison.allCases.indices.contains(condition)
    else {
      notificationExample.stringValue = "Enter a limit and waiting time to see the notification.";
      return
    }
    let rule = ThresholdRule(
      metric: metric == "sensor"
        ? "sensor:" + (fields["ruleSensorKey"]?.stringValue ?? "") : metric,
      threshold: threshold * NotificationPresentation.scale(metric),
      comparison: RuleComparison.allCases[condition],
      duration: seconds, sensorUnit: metric == "sensor" ? unit : nil,
      upperThreshold: Double(fields["ruleUpper"]?.stringValue ?? "").map {
        $0 * NotificationPresentation.scale(metric)
      })
    notificationExample.stringValue = "Notify when " + ruleSummary(rule) + "."
  }
  @objc private func systemClockChanged() { updateDateExample() }
  private func updateDateExample() {
    let custom = choices["clockMode"]?.indexOfSelectedItem == 1
    fields["clockFormat"]?.isEnabled = custom
    let formatter = DateFormatter()
    LocalClockFormat.configure(
      formatter, pattern: custom ? fields["clockFormat"]?.stringValue ?? "" : "")
    localTimeZoneLabel.stringValue =
      "Time zone: " + TimeZone.autoupdatingCurrent.identifier
      + " · Follows Mac automatically"
    dateExample.stringValue = formatter.string(from: Date())
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
      ? nil : interfaceButtons.filter { $0.value.state == .on }.map(\.key).sorted()
    s.compactSpacing = toggles["spacing"]!.state == .on
    s.persistentHistory = toggles["persistentHistory"]!.state == .on
    s.shortcuts = try KeyboardShortcut.parse(shortcutsField.string)
    s.sensorSampling = choices["sensors"]!.indexOfSelectedItem == 0 ? .all : .whenNeeded
    s.sensorNames = try SensorIdentity.parseNames(sensorNamesField.string)
    s.combined = choices["menuLayout"]!.indexOfSelectedItem == 2
    s.groupedMenus = choices["menuLayout"]!.indexOfSelectedItem == 0
    s.menuPadding = choices["menuPadding"]!.indexOfSelectedItem
    s.menuGap = choices["menuGap"]!.indexOfSelectedItem
    s.combinedModules = try MenuPresentation.modules(
      fromTitles: fields["combinedModules"]!.stringValue)
    s.combinedStyle =
      [DisplayStyle.text, .compact, .stacked][choices["combinedStyle"]!.indexOfSelectedItem]
    let combinedColor = fields["combinedColor"]!.stringValue.trimmingCharacters(
      in: .whitespacesAndNewlines)
    s.combinedColorHex = combinedColor.isEmpty ? nil : combinedColor
    s.clockFormat =
      choices["clockMode"]!.indexOfSelectedItem == 0 ? "" : fields["clockFormat"]!.stringValue
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
      guard TimeZone(identifier: point.zone) != nil else {
        throw PreferencesValidationError.daylightTimeZoneRequired
      }
      s.daylight = point
    } else {
      s.daylight = nil
    }
    s.clocks = try WorldClockForm.parse(clocksField.string)
    s.hourlyForecastHours = [24, 48, 72, 168][choices["hourlyForecastHours"]!.indexOfSelectedItem]
    s.weather.enabled = toggles["weather"]!.state == .on
    s.weather.provider = choices["weatherProvider"]!.indexOfSelectedItem == 1 ? "nws" : "openMeteo"
    s.weather.mapsEnabled = toggles["maps"]!.state == .on
    s.weather.mapsProvider = "noaa"
    s.weather.name = fields["weatherName"]!.stringValue
    s.weather.latitude = latitude
    s.weather.longitude = longitude
    var changeCooldowns: [ChangeKind: Double] = [:]
    for kind in ChangeKind.allCases {
      guard let value = Double(fields["changeCooldown.\(kind.rawValue)"]!.stringValue),
        value.isFinite, (10...604800).contains(value)
      else { throw SettingsError.invalid }
      changeCooldowns[kind] = value
    }
    // Keep imported identities and order, including disabled rules. Add only newly enabled kinds.
    var changes = settings.changeRules ?? []
    for index in changes.indices {
      let kind = changes[index].kind
      changes[index].enabled = toggles["change.\(kind.rawValue)"]!.state == .on
      changes[index].cooldown = changeCooldowns[kind]!
    }
    for kind in ChangeKind.allCases where !changes.contains(where: { $0.kind == kind }) {
      if toggles["change.\(kind.rawValue)"]!.state == .on {
        changes.append(ChangeRule(kind: kind, cooldown: changeCooldowns[kind]!))
      }
    }
    s.changeRules = changes.isEmpty ? nil : changes
    let order = settings.menus.map { ($0.module, menuOrders[$0.module]!.indexOfSelectedItem) }
    guard Set(order.map(\.1)).count == order.count else { throw SettingsError.invalid }
    s.menus = order.sorted { $0.1 < $1.1 }.map {
      MenuConfiguration(
        module: $0.0, visible: menuToggles[$0.0]!.state == .on,
        style: DisplayStyle.allCases[menuStyles[$0.0]!.indexOfSelectedItem],
        colorHex: menuColors[$0.0]!.stringValue.isEmpty ? nil : menuColors[$0.0]!.stringValue,
        labelPlacement: MenuLabelPlacement.allCases[menuLabels[$0.0]!.indexOfSelectedItem])
    }
    return try s.validated()
  }
  @objc private func applySettings() {
    cancelPendingLocation()
    do {
      let s = try readSettings()
      settings = s
      onApply?(s)
      errorLabel.stringValue = ""; draftLabel.stringValue = "Settings applied."
    } catch PreferencesValidationError.daylightTimeZoneRequired {
      errorLabel.stringValue = "Choose a daylight time zone in Date & Time, or turn off daylight."
    } catch {
      errorLabel.stringValue =
        "Check values, clock names/time zones, rule cooldowns, unique menu order, #RRGGBB colors, and a visible or combined item."
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
      threshold: threshold * NotificationPresentation.scale(metric),
      comparison: comparison,
      duration: duration, cooldown: cooldown,
      sensorUnit: individual
        ? SensorIdentity.units[choices["ruleSensorUnit"]!.indexOfSelectedItem] : nil,
      upperThreshold: upper.map { $0 * NotificationPresentation.scale(metric) },
      hysteresis: hysteresis * NotificationPresentation.scale(metric),
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
    settings.rules.append(rule); refreshRules(selected: rule.id); draftChanged()
  }
  @objc private func saveRule() {
    guard let index = selectedRuleIndex, let replacement = ruleFromForm() else { return }
    let current = settings.rules[index]
    settings.rules[index] = RuleEdits.replacing(current, with: replacement)
    refreshRules(selected: current.id); draftChanged()
  }
  @objc private func deleteRule() {
    guard let index = selectedRuleIndex else { return }; settings.rules.remove(at: index);
    refreshRules(); draftChanged()
  }
  @objc private func toggleRule() {
    guard let index = selectedRuleIndex else { return }; settings.rules[index].enabled.toggle()
    refreshRules(selected: settings.rules[index].id); draftChanged()
  }
  @objc private func selectRule() {
    guard let index = selectedRuleIndex else { return }; let rule = settings.rules[index]
    let key = SensorIdentity.key(metric: rule.metric)
    choices["ruleMetric"]?.selectItem(
      at: key != nil ? ruleMetrics.count - 1 : ruleMetrics.firstIndex(of: rule.metric) ?? 0)
    fields["ruleSensorKey"]?.stringValue = key ?? ""
    if let key, let index = sensorRuleChoices.firstIndex(where: { $0.key == key }) {
      choices["ruleSensorChoice"]?.selectItem(at: index + 1)
    } else {
      choices["ruleSensorChoice"]?.selectItem(at: 0)
    }
    choices["ruleSensorUnit"]?.selectItem(
      at: SensorIdentity.units.firstIndex(of: rule.sensorUnit ?? "") ?? 0)
    ruleMetricChanged()
    choices["ruleComparison"]?.selectItem(
      at: RuleComparison.allCases.firstIndex(of: rule.comparison) ?? 0)
    fields["ruleUpper"]?.stringValue = String(
      (rule.upperThreshold ?? 100) / NotificationPresentation.scale(rule.metric))
    fields["ruleHysteresis"]?.stringValue = String(
      rule.recoveryBand / NotificationPresentation.scale(rule.metric))
    toggles["ruleRepeat"]?.state = rule.repeats ? .on : .off
    ruleComparisonChanged()
    fields["ruleThreshold"]?.stringValue = String(
      rule.threshold / NotificationPresentation.scale(rule.metric))
    fields["ruleDuration"]?.stringValue = String(rule.duration)
    fields["ruleCooldown"]?.stringValue = String(rule.cooldown)
    updateNotificationExample()
  }
  @objc private func ruleComparisonChanged() {
    guard let selected = choices["ruleComparison"]?.indexOfSelectedItem,
      RuleComparison.allCases.indices.contains(selected)
    else { return }
    let requiresRange = RuleComparison.allCases[selected].requiresUpperBound
    fields["ruleUpper"]?.isEnabled = requiresRange
    if requiresRange {
      toggles["notificationAdvanced"]?.state = .on; notificationAdvanced?.isHidden = false
    }
    updateNotificationExample()
  }
  @objc private func ruleMetricChanged() {
    let individual = choices["ruleMetric"]?.indexOfSelectedItem == ruleMetrics.count - 1
    choices["ruleSensorChoice"]?.isEnabled = individual
    fields["ruleSensorKey"]?.isEnabled = individual
    choices["ruleSensorUnit"]?.isEnabled = individual
    updateNotificationExample()
  }
  @objc private func clearRules() {
    settings.rules.removeAll()
    refreshRules(); draftChanged()
  }
  private func refreshRules(selected id: UUID? = nil) {
    rulesPicker.removeAllItems(); rulesPicker.addItem(withTitle: "New notification")
    rulesPicker.addItems(
      withTitles: settings.rules.map {
        "\($0.enabled ? "On" : "Off") · \(ruleSummary($0))"
      })
    if let id, let index = settings.rules.firstIndex(where: { $0.id == id }) {
      rulesPicker.selectItem(at: index + 1)
    }
    rulesPicker.isEnabled = !settings.rules.isEmpty
    rulesLabel.stringValue =
      settings.rules.isEmpty
      ? "No value notifications. Add one to the draft, then Apply."
      : settings.rules.map {
        "\($0.enabled ? "Enabled" : "Disabled"): \(ruleSummary($0)). \($0.repeats ? "Repeats" : "Once until it clears"); at least \(String(format: "%g", $0.cooldown)) seconds between notifications."
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
    locationSession.cancel(); locationChoices.removeAll()
    calendarPicker?.close(); calendarPicker = nil
    settings = profile.settings
    for subview in window?.contentView?.subviews ?? [] { subview.removeFromSuperview() }
    fields.removeAll(); toggles.removeAll(); choices.removeAll()
    menuToggles.removeAll(); menuStyles.removeAll(); menuOrders.removeAll(); menuColors.removeAll();
    menuLabels.removeAll();
    interfaceButtons.removeAll()
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
