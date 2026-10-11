import AerieCore
import AppKit
import EventKit

enum DashboardRow {
  case heading(String)
  case metric(String, String)
  case note(String)
  case chart(String, String, NSColor, Double?)
  case cores([Double])
  var height: CGFloat {
    switch self {
    case .heading: return 34
    case .metric: return 27
    case .note: return 47
    case .chart: return 100
    case .cores(let c): return CGFloat((c.count + 11) / 12) * 42 + 18
    }
  }
}
enum AeriePalette {
  static let cpu = NSColor(red: 0.14, green: 0.43, blue: 0.64, alpha: 1)
  static let memory = NSColor(red: 0.08, green: 0.61, blue: 0.58, alpha: 1)
  static let incoming = NSColor(red: 0.21, green: 0.54, blue: 0.81, alpha: 1)
  static let outgoing = NSColor(red: 0.79, green: 0.33, blue: 0.44, alpha: 1)
  static let power = NSColor(red: 0.83, green: 0.61, blue: 0.20, alpha: 1)
}

final class DashboardView: NSView {
  var rows: [DashboardRow] = []
  var points: [HistoryPoint] = []
  var selectedPoint: HistoryPoint?
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityRole(.group)
    setAccessibilityLabel("System statistics")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func update(rows: [DashboardRow], points: [HistoryPoint]) {
    self.rows = rows
    self.points = points
    frame.size.height = rows.reduce(16) { $0 + $1.height }
    needsDisplay = true
    var y: CGFloat = 8
    var elements: [NSAccessibilityElement] = []
    for row in rows {
      let label: String
      switch row {
      case .heading(let s), .note(let s): label = s
      case .metric(let k, let v): label = "\(k): \(v)"
      case .chart(_, let title, _, _):
        label = "\(title) history, \(points.count) samples. Click to inspect a sample."
      case .cores(let c):
        label = c.enumerated().map { "Core \($0.offset + 1): \(Format.percent($0.element))" }
          .joined(separator: ", ")
      }
      let e = NSAccessibilityElement()
      e.setAccessibilityParent(self)
      e.setAccessibilityRole(.staticText)
      e.setAccessibilityLabel(label)
      if let window {
        e.setAccessibilityFrame(
          window.convertToScreen(
            convert(NSRect(x: 12, y: y, width: bounds.width - 24, height: row.height), to: nil)))
      }
      elements.append(e)
      y += row.height
    }
    setAccessibilityChildren(elements)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    var y: CGFloat = 8
    for row in rows {
      let rect = NSRect(x: 14, y: y, width: bounds.width - 28, height: row.height)
      defer { y += row.height }
      guard rect.intersects(dirtyRect) else { continue }
      switch row {
      case .heading(let title):
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 14, y: y + 1))
        line.line(to: NSPoint(x: bounds.width - 14, y: y + 1))
        line.stroke()
        drawText(
          title, rect: rect.insetBy(dx: 0, dy: 10),
          font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
      case .metric(let key, let value):
        drawText(
          key, rect: NSRect(x: 14, y: y + 5, width: 165, height: 20), font: .systemFont(ofSize: 12),
          color: .labelColor)
        drawText(
          value, rect: NSRect(x: 174, y: y + 5, width: bounds.width - 188, height: 20),
          font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: .labelColor,
          alignment: .right)
      case .note(let s):
        drawText(
          s, rect: rect.insetBy(dx: 0, dy: 6), font: .systemFont(ofSize: 11),
          color: .secondaryLabelColor, wrap: true)
      case .chart(let key, let title, let color, let fixedMaximum):
        let values = points.map { $0.values[key] }
        drawText(
          title, rect: NSRect(x: 14, y: y + 6, width: 170, height: 18),
          font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        let graph = NSRect(x: 14, y: y + 31, width: bounds.width - 28, height: 52)
        let maximum = fixedMaximum ?? max(1, values.compactMap { $0 }.max() ?? 1)
        drawSparkline(values, in: graph, color: color, maximum: maximum)
        if let selected = selectedPoint, let value = selected.values[key] {
          let formatter = DateFormatter()
          formatter.timeStyle = .medium
          drawText(
            "\(formatter.string(from: selected.date))  \(String(format: "%.2f", value))",
            rect: NSRect(x: 180, y: y + 6, width: bounds.width - 194, height: 18),
            font: .systemFont(ofSize: 10), color: color, alignment: .right)
        } else if let latest = values.last ?? nil {
          drawText(
            String(format: "%.1f", latest),
            rect: NSRect(x: 180, y: y + 6, width: bounds.width - 194, height: 18),
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium), color: color,
            alignment: .right)
        }
      case .cores(let values):
        for (index, value) in values.enumerated() {
          let col = index % 12
          let line = index / 12
          let width = (bounds.width - 28) / 12
          let x = 14 + CGFloat(col) * width
          let base = NSRect(x: x + 3, y: y + CGFloat(line) * 42 + 2, width: width - 6, height: 24)
          NSColor.quaternaryLabelColor.setFill()
          NSBezierPath(roundedRect: base, xRadius: 3, yRadius: 3).fill()
          AeriePalette.cpu.setFill()
          NSBezierPath(
            roundedRect: NSRect(
              x: base.minX, y: base.maxY - base.height * value, width: base.width,
              height: base.height * value), xRadius: 2, yRadius: 2
          ).fill()
          drawText(
            "\(index + 1)", rect: NSRect(x: x, y: base.maxY + 3, width: width, height: 14),
            font: .systemFont(ofSize: 9), color: .secondaryLabelColor, alignment: .center)
        }
      }
    }
  }
  override func mouseDown(with event: NSEvent) {
    guard !points.isEmpty else { return }
    let point = convert(event.locationInWindow, from: nil)
    let fraction = max(0, min(1, (point.x - 14) / (bounds.width - 28)))
    selectedPoint = points[Int((fraction * Double(points.count - 1)).rounded())]
    needsDisplay = true
  }
}

func drawText(
  _ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left,
  wrap: Bool = false
) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = alignment
  paragraph.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
  (text as NSString).draw(
    in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}
func drawSparkline(_ values: [Double?], in rect: NSRect, color: NSColor, maximum: Double) {
  NSColor.quaternaryLabelColor.setStroke()
  for fraction in [0.0, 0.5, 1.0] {
    let grid = NSBezierPath()
    grid.lineWidth = 0.5
    grid.move(to: NSPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
    grid.line(to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
    grid.stroke()
  }
  guard values.count > 1 else { return }
  let path = NSBezierPath()
  path.lineWidth = 1.7
  var connected = false
  for (index, value) in values.enumerated() {
    guard let value, value.isFinite else {
      connected = false
      continue
    }
    let point = NSPoint(
      x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
      y: rect.maxY - rect.height * max(0, min(1, value / maximum)))
    if connected {
      path.line(to: point)
    } else {
      path.move(to: point)
      connected = true
    }
  }
  color.setStroke()
  path.stroke()
}

final class DashboardController: NSViewController {
  let canvas = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
  let modules = NSPopUpButton(frame: .zero, pullsDown: false)
  let windowPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  let stateLabel = NSTextField(labelWithString: "Sampling")
  var onSettings: (() -> Void)?
  var onModule: ((Module) -> Void)?
  var module = Module.overview
  var snapshot = Snapshot()
  var settings = Settings()
  var history = HistoryStore()
  var weather: WeatherReport?
  var weatherStatus = "Weather is off"
  var calendarRows: [DashboardRow] = []
  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 416, height: 620))
    let title = NSTextField(labelWithString: "Aerie")
    title.font = .systemFont(ofSize: 18, weight: .semibold)
    title.frame = NSRect(x: 16, y: 580, width: 90, height: 26)
    view.addSubview(title)
    modules.addItems(withTitles: Module.allCases.map(\.title))
    modules.target = self
    modules.action = #selector(selectModule)
    modules.frame = NSRect(x: 245, y: 580, width: 155, height: 28)
    view.addSubview(modules)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 45, width: 416, height: 525))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = canvas
    scroll.drawsBackground = false
    view.addSubview(scroll)
    let settingsButton = NSButton(title: "Settings…", target: self, action: #selector(openSettings))
    settingsButton.frame = NSRect(x: 12, y: 9, width: 95, height: 28)
    view.addSubview(settingsButton)
    windowPicker.addItems(withTitles: ["10 minutes", "24 hours", "7 days"])
    windowPicker.frame = NSRect(x: 110, y: 9, width: 122, height: 28)
    windowPicker.target = self
    windowPicker.action = #selector(changeWindow)
    view.addSubview(windowPicker)
    stateLabel.font = .systemFont(ofSize: 10)
    stateLabel.textColor = .secondaryLabelColor
    stateLabel.alignment = .right
    stateLabel.frame = NSRect(x: 236, y: 16, width: 164, height: 16)
    view.addSubview(stateLabel)
  }
  @objc private func selectModule() {
    module = Module.allCases[modules.indexOfSelectedItem]
    onModule?(module)
    refresh()
    if let scroll = canvas.enclosingScrollView {
      scroll.contentView.scroll(to: .zero)
      scroll.reflectScrolledClipView(scroll.contentView)
    }
  }
  @objc private func openSettings() { onSettings?() }
  @objc private func changeWindow() {
    canvas.selectedPoint = nil
    refresh()
  }
  func show(_ module: Module) {
    self.module = module
    modules.selectItem(at: Module.allCases.firstIndex(of: module) ?? 0)
    refresh()
  }
  func refresh() {
    guard isViewLoaded else { return }
    let age = max(0, Date().timeIntervalSince(snapshot.date))
    stateLabel.stringValue =
      age > settings.interval * 3
      ? "Stale · \(Int(age))s" : "Live · \(settings.interval.formatted())s"
    let rows = makeRows()
    canvas.update(rows: rows, points: history.points(window: windowPicker.indexOfSelectedItem))
  }
  private func bytes(_ value: Double) -> String {
    Format.bytes(value, binary: settings.binaryBytes)
  }
  private func rate(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    if settings.networkBits {
      return Format.bytes(value * 8, binary: false).replacingOccurrences(of: "B", with: "bit")
        + "/s"
    }
    return bytes(value) + "/s"
  }
  private func top(_ sort: (ProcessData, ProcessData) -> Bool, value: (ProcessData) -> String)
    -> [DashboardRow]
  {
    let list = snapshot.processes.sorted(by: sort).prefix(settings.processCount)
    if list.isEmpty {
      return [
        .note("Process details begin when this menu opens. Protected processes may be unavailable.")
      ]
    }
    return list.map { .metric($0.name, value($0)) } + [
      .note(
        "\(snapshot.processDenied) protected processes unavailable. CPU format: \(settings.normalizedProcessCPU ? "0–100% of machine" : "100% per logical core")."
      )
    ]
  }
  private func makeRows() -> [DashboardRow] {
    let s = snapshot
    switch module {
    case .overview:
      return [
        .heading("System"), .metric("CPU", Format.percent(s.cpu.total)),
        .metric("GPU", Format.percent(s.gpu.first?.utilization)),
        .metric("Memory used", Format.percent(s.memory.usedFraction)),
        .metric("Memory pressure", s.memory.pressure),
        .metric("Download", rate(s.download)), .metric("Upload", rate(s.upload)),
        .metric("Disk read", rate(s.diskRead)), .metric("Disk write", rate(s.diskWrite)),
        .metric("Thermal state", s.thermal),
        .metric("Power", s.power.present ? Format.percent(s.power.percent) : "No battery"),
        .chart("cpu", "CPU %", AeriePalette.cpu, 100),
        .chart("memory", "Memory %", AeriePalette.memory, 100),
        .heading("Storage"),
      ] + s.volumes.prefix(4).map { .metric($0.name, bytes($0.free) + " free") } + [
        .heading("Monitoring"), .metric("Refresh interval", "\(settings.interval)s"),
        .note(
          "All enabled system collectors share one scheduler. History is bounded to ten minutes, one day of minute averages, and one week of hourly averages."
        ),
      ]
    case .cpu:
      return [
        .heading("Processor"), .metric("Total", Format.percent(s.cpu.total)),
        .metric("User", Format.percent(s.cpu.user)),
        .metric("System", Format.percent(s.cpu.system)),
        .chart("cpu", "CPU %", AeriePalette.cpu, 100),
        .heading("Logical cores"), .cores(s.cpu.cores),
      ] + s.cpu.groups.map { .metric($0.0, "\($0.1) logical cores") } + [
        .metric(
          "Frequency", s.cpu.frequency.map { String(format: "%.2f GHz", $0) } ?? "Unavailable"),
        .metric(
          "Load 1 / 5 / 15 min",
          s.cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " / ")),
        .metric("Uptime", Format.duration(s.cpu.uptime)), .heading("Top CPU processes"),
      ] + top({ ($0.cpu ?? 0) > ($1.cpu ?? 0) }, value: { Format.percent($0.cpu) }) + [
        .note(
          "Dynamic core frequencies and group residency require telemetry this OS may restrict. Counts above describe topology; individual bars show actual logical-core utilization."
        )
      ]
    case .gpu:
      var rows: [DashboardRow] = [.chart("gpu", "GPU %", AeriePalette.cpu, 100)]
      for gpu in s.gpu {
        rows += [
          .heading(gpu.name), .metric("Device utilization", Format.percent(gpu.utilization)),
          .metric("Renderer", Format.percent(gpu.renderer)),
          .metric("Tiler", Format.percent(gpu.tiler)),
          .metric("In-use shared memory", gpu.memory.map(bytes) ?? "Unavailable"),
          .metric(
            "Temperature",
            gpu.temperature.map { Format.temperature($0, unit: settings.temperature) }
              ?? "Unavailable"),
          .metric(
            "Frequency", gpu.frequency.map { String(format: "%.2f GHz", $0) } ?? "Unavailable"),
          .metric("Frame rate", gpu.fps.map { String(format: "%.0f FPS", $0) } ?? "Unavailable"),
        ]
      }
      rows.append(
        .note(
          "Driver-exposed statistics vary by GPU. Global FPS and per-process GPU utilization are unavailable when the driver does not publish them."
        ))
      return rows
    case .memory:
      let m = s.memory
      return [
        .heading("Memory"), .metric("Pressure", m.pressure),
        .metric("Used", Format.percent(m.usedFraction)),
        .chart("memory", "Used memory %", AeriePalette.memory, 100),
        .metric("Physical", bytes(m.total)),
        .metric("App", bytes(m.app)), .metric("Wired", bytes(m.wired)),
        .metric("Compressed", bytes(m.compressed)),
        .metric("Free", bytes(m.free)), .metric("File cache", bytes(m.cached)),
        .metric("Purgeable", bytes(m.purgeable)),
        .heading("Virtual memory"), .metric("Swap", "\(bytes(m.swap)) / \(bytes(m.swapTotal))"),
        .metric("Page in", rate(m.pageIn)), .metric("Page out", rate(m.pageOut)),
        .metric("Swap in", rate(m.swapIn)), .metric("Swap out", rate(m.swapOut)),
        .heading("Top memory processes"),
      ] + top({ $0.memory > $1.memory }, value: { bytes($0.memory) })
    case .storage:
      var rows: [DashboardRow] = [
        .heading("Disk activity"), .metric("Read", rate(s.diskRead)),
        .metric("Write", rate(s.diskWrite)),
        .chart("diskRead", "Read bytes/s", AeriePalette.incoming, nil),
        .chart("diskWrite", "Write bytes/s", AeriePalette.outgoing, nil),
      ]
      for v in s.volumes {
        rows += [
          .heading(v.name), .metric("Capacity", bytes(v.total)),
          .metric("Available", bytes(v.free)),
          .metric("Used", Format.percent(v.usedFraction)),
          .metric("Important-use capacity", v.important.map(bytes) ?? "Unavailable"),
          .metric(
            "Kind",
            "\(v.local ? "Local" : "Network")\(v.removable ? ", removable" : "")\(v.readOnly ? ", read only" : "")"
          ),
        ]
      }
      return rows + [.heading("Top process I/O")]
        + top(
          { ($0.read ?? 0) + ($0.write ?? 0) > ($1.read ?? 0) + ($1.write ?? 0) },
          value: { "R \(rate($0.read))  W \(rate($0.write))" }) + [
          .note(
            "Disk rates are physical-device totals; process I/O uses OS accounting. Volume health and temperature depend on an accessible drive telemetry interface and are not yet collected."
          )
        ]
    case .network:
      var rows: [DashboardRow] = [
        .heading("Traffic"), .metric("Connectivity", s.connectivity),
        .metric("Download", rate(s.download)),
        .metric("Upload", rate(s.upload)),
        .chart("download", "Download bytes/s", AeriePalette.incoming, nil),
        .chart("upload", "Upload bytes/s", AeriePalette.outgoing, nil),
      ]
      for i in s.interfaces.sorted(by: { $0.active && !$1.active }) {
        rows += [
          .heading(i.name + (i.active ? " · active" : " · inactive")),
          .metric("Download / upload", "\(rate(i.download)) / \(rate(i.upload))"),
          .metric("Received since boot", bytes(Double(i.received))),
          .metric("Sent since boot", bytes(Double(i.sent))),
          .metric("Errors", "\(i.errors)"),
          .note(i.addresses.isEmpty ? "No assigned IP address" : i.addresses),
        ]
      }
      if !s.wifi.isEmpty {
        rows +=
          [.heading("Wi-Fi")] + s.wifi.sorted { $0.key < $1.key }.map { .metric($0.key, $0.value) }
      }
      rows.append(
        .note(
          "Virtual tunnels may count the same traffic again; aggregate totals include active interfaces. Public IP lookup is off. Per-process traffic collection remains unimplemented."
        ))
      return rows
    case .sensors:
      var rows: [DashboardRow] = [
        .heading("Hardware"), .metric("Thermal state", s.thermal), .note(s.sensorStatus),
      ]
      for unit in ["°C", "rpm", "W", "V", "A"] {
        let sensors = s.sensors.filter { $0.unit == unit }
        guard !sensors.isEmpty else { continue }
        rows += [
          .heading(
            ["°C": "Temperature", "rpm": "Fans", "W": "Power", "V": "Voltage", "A": "Current"][
              unit]!)
        ]
        rows += sensors.map {
          .metric(
            $0.label,
            unit == "°C"
              ? Format.temperature($0.value, unit: settings.temperature)
              : String(format: "%.1f %@", $0.value, unit))
        }
      }
      rows += [
        .note(
          "Firmware key names appear when a sensor label is unknown. Aerie only reads sensors. Fan profiles require a separately approved and safety-tested control implementation."
        )
      ]
      return rows
    case .power:
      let p = s.power
      var rows: [DashboardRow] = [
        .heading("Power"),
        .metric(
          "Source", p.present ? (p.external ? "Power adapter" : "Battery") : "No battery reported"),
        .metric("Low Power Mode", s.lowPower ? "On" : "Off"), .metric("Thermal state", s.thermal),
      ]
      if p.present {
        rows += [
          .metric("Charge", Format.percent(p.percent)),
          .metric("Charging", p.charging ? "Yes" : "No"),
          .metric(
            p.charging ? "Time to full" : "Time remaining",
            p.minutes.map { Format.duration(Double($0 * 60)) } ?? "Calculating"),
          .chart("battery", "Battery %", AeriePalette.power, 100),
          .metric("Health", Format.percent(p.health)),
          .metric("Cycles", p.cycles.map(String.init) ?? "Unavailable"),
          .metric("Battery power", p.watts.map { String(format: "%.2f W", $0) } ?? "Unavailable"),
          .metric("Voltage", p.voltage.map { String(format: "%.2f V", $0) } ?? "Unavailable"),
          .metric("Current", p.amperage.map { String(format: "%.2f A", $0) } ?? "Unavailable"),
        ]
      }
      rows += [.heading("Peripheral batteries")]
      rows +=
        p.peripherals.isEmpty
        ? [.note("No supported peripheral battery is exposed by the device registry.")]
        : p.peripherals.map { .metric($0.0, Format.percent($0.1)) }
      return rows + [.heading("Process wakeups")]
        + top(
          { ($0.wakeups ?? 0) > ($1.wakeups ?? 0) },
          value: { $0.wakeups.map { String(format: "%.1f /s", $0) } ?? "Unavailable" }) + [
          .note(
            "Wakeups are interrupt wakeups, not a whole-system energy score. Changing power modes is not implemented."
          )
        ]
    case .time:
      let now = Date()
      let formatter = DateFormatter()
      formatter.dateFormat = settings.clockFormat
      var rows: [DashboardRow] = [
        .heading("Local time"),
        .metric(formatter.string(from: now), TimeZone.current.abbreviation() ?? "Local"),
        .metric("Moon phase (approx.)", Astronomy.moonName(at: now)),
        .metric("Lunar age", String(format: "%.1f days", Astronomy.moonAge(at: now))),
        .heading("World clocks"),
      ]
      for clock in settings.clocks {
        formatter.timeZone = TimeZone(identifier: clock.zone)
        rows += [.metric(clock.name, formatter.string(from: now))]
        if let next = formatter.timeZone.nextDaylightSavingTimeTransition(after: now) {
          let f = DateFormatter()
          f.dateStyle = .medium
          f.timeZone = formatter.timeZone
          rows += [.metric("Next daylight saving change", f.string(from: next))]
        }
      }
      rows += [.heading("Calendar")] + calendarRows
      return rows
    case .weather:
      guard settings.weather.valid else {
        return [
          .heading("Weather is off"),
          .note(
            "Choose a provider and a manual location in Settings to enable weather. No device location, IP geolocation, or background city search is used."
          ),
        ]
      }
      var rows: [DashboardRow] = [.heading(settings.weather.name), .note(weatherStatus)]
      guard let w = weather else { return rows }
      rows += [
        .metric("Conditions", WeatherCondition.describe(w.code)),
        .metric(
          "Temperature",
          w.temperature.map { Format.temperature($0, unit: settings.temperature) } ?? "Unavailable"),
        .metric(
          "Feels like",
          w.apparent.map { Format.temperature($0, unit: settings.temperature) } ?? "Unavailable"),
        .metric("Humidity", w.humidity.map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        .metric(
          "Wind / gusts",
          "\(w.wind.map { String(format: "%.1f", $0) } ?? "—") / \(w.gusts.map { String(format: "%.1f km/h", $0) } ?? "—")"
        ),
        .metric("Direction", w.direction.map { String(format: "%.0f°", $0) } ?? "Unavailable"),
        .metric("Pressure", w.pressure.map { String(format: "%.0f hPa", $0) } ?? "Unavailable"),
        .metric("Cloud cover", w.cloud.map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        .heading("Next 24 hours"),
      ]
      let f = DateFormatter()
      f.dateFormat = "EEE HH:mm"
      for h in w.hours.filter({ $0.date >= Date().addingTimeInterval(-3600) }).prefix(24) {
        rows += [
          .metric(
            f.string(from: h.date),
            "\(Format.temperature(h.temperature, unit: settings.temperature))  \(h.precipitation.map { String(format: "%.0f%% rain", $0) } ?? "")"
          )
        ]
      }
      rows += [.heading("Daily forecast")]
      f.dateFormat = "EEE d MMM"
      for d in w.days {
        rows += [
          .metric(
            f.string(from: d.date),
            "\(Format.temperature(d.low, unit: settings.temperature)) / \(Format.temperature(d.high, unit: settings.temperature))"
          ),
          .metric(
            WeatherCondition.describe(d.code), d.uv.map { String(format: "UV %.1f", $0) } ?? ""),
        ]
        let t = DateFormatter()
        t.timeStyle = .short
        if let sunrise = d.sunrise, let sunset = d.sunset {
          rows += [.metric("Daylight", "\(t.string(from: sunrise)) – \(t.string(from: sunset))")]
        }
      }
      rows += [
        .heading("Source"),
        .note(
          "Weather data: \(w.source). Open-Meteo data is CC BY 4.0. https://open-meteo.com/ · Model-derived forecasts. Official severe alerts and radar are not available from this provider."
        ),
      ]
      return rows
    }
  }
}
