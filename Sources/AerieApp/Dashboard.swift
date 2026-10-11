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
  var expectedInterval = 1.0
  private let chartFormatter = DateFormatter()
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
    if let selectedPoint, !points.contains(where: { $0.date == selectedPoint.date }) {
      self.selectedPoint = nil
    }
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
    chartFormatter.dateStyle = .short; chartFormatter.timeStyle = .medium
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
        drawHistoryPlot(
          HistoryPlot.samples(points, metric: key, expectedInterval: expectedInterval), in: graph,
          color: color, maximum: maximum)
        if let first = points.first, let last = points.last {
          for (date, x, alignment) in [
            (first.date, CGFloat(14), NSTextAlignment.left),
            (last.date, bounds.width / 2, NSTextAlignment.right),
          ] {
            drawText(
              chartFormatter.string(from: date),
              rect: NSRect(x: x, y: y + 86, width: bounds.width / 2 - 14, height: 12),
              font: .systemFont(ofSize: 9), color: .secondaryLabelColor, alignment: alignment)
          }
        }
        if let selected = selectedPoint, let value = selected.values[key] {
          drawText(
            "\(chartFormatter.string(from: selected.date))  \(String(format: "%.2f", value))",
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
    var y: CGFloat = 8
    let clickedChart = rows.contains { row in
      defer { y += row.height }
      if case .chart = row { return point.y >= y + 31 && point.y <= y + 83 }
      return false
    }
    guard clickedChart else { return }
    selectedPoint = HistoryPlot.nearest(points, fraction: Double(fraction))
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

func drawHistoryPlot(
  _ samples: [HistoryPlotSample], in rect: NSRect, color: NSColor, maximum: Double
) {
  drawSparkline([], in: rect, color: color, maximum: maximum)
  let path = NSBezierPath(); path.lineWidth = 1.7
  for sample in samples {
    guard let value = sample.value else { continue }
    let point = NSPoint(
      x: rect.minX + rect.width * sample.fraction,
      y: rect.maxY - rect.height * max(0, min(1, value / maximum)))
    if sample.startsSegment { path.move(to: point) } else { path.line(to: point) }
    if sample.startsSegment {
      color.setFill()
      NSBezierPath(ovalIn: NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)).fill()
    }
  }
  color.setStroke(); path.stroke()
}

final class DashboardController: NSViewController {
  let canvas = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
  let modules = NSPopUpButton(frame: .zero, pullsDown: false)
  let windowPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  let stateLabel = NSTextField(labelWithString: "Sampling")
  var onSettings: (() -> Void)?
  var onMaps: (() -> Void)?
  var onExportHistory: ((Int) -> Void)?
  private let mapsButton = NSButton(title: "Maps…", target: nil, action: nil)
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
    mapsButton.frame = NSRect(x: 110, y: 9, width: 122, height: 28)
    mapsButton.target = self; mapsButton.action = #selector(openMaps); mapsButton.isHidden = true
    view.addSubview(mapsButton)
    stateLabel.font = .systemFont(ofSize: 10)
    stateLabel.textColor = .secondaryLabelColor
    stateLabel.alignment = .right
    let export = NSButton(title: "Export…", target: self, action: #selector(exportHistory))
    export.frame = NSRect(x: 236, y: 9, width: 75, height: 28)
    export.toolTip = "Export retained system series for this time range as CSV"
    view.addSubview(export)
    stateLabel.frame = NSRect(x: 313, y: 16, width: 87, height: 16)
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
  @objc private func openMaps() { onMaps?() }
  @objc private func exportHistory() { onExportHistory?(windowPicker.indexOfSelectedItem) }
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
    mapsButton.isHidden = module != .weather; windowPicker.isHidden = module == .weather
    mapsButton.title = settings.weather.mapsValid ? "Maps…" : "Enable Maps…"
    let age = max(0, Date().timeIntervalSince(snapshot.date))
    stateLabel.stringValue =
      age > settings.interval * 3
      ? "Stale · \(Int(age))s" : "Live · \(settings.interval.formatted())s"
    let rows = makeRows()
    canvas.expectedInterval =
      windowPicker.indexOfSelectedItem == 0
      ? settings.interval : windowPicker.indexOfSelectedItem == 1 ? 60 : 3600
    canvas.update(rows: rows, points: history.points(window: windowPicker.indexOfSelectedItem))
  }
  private func bytes(_ value: Double) -> String {
    Format.bytes(value, binary: settings.binaryBytes)
  }
  private func rate(_ value: Double?, domain: RateDomain = .storage) -> String {
    Format.rate(
      value, domain: domain, binary: settings.binaryBytes, networkBits: settings.networkBits)
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
        DashboardRow.heading("System"), DashboardRow.metric("CPU", Format.percent(s.cpu.total)),
        DashboardRow.metric("GPU", Format.percent(s.gpu.first?.utilization)),
        DashboardRow.metric("Memory used", Format.percent(s.memory.usedFraction)),
        DashboardRow.metric("Memory pressure", s.memory.pressure),
        DashboardRow.metric("Download", rate(s.download, domain: .network)),
        DashboardRow.metric("Upload", rate(s.upload, domain: .network)),
        DashboardRow.metric("Disk read", rate(s.diskRead)),
        DashboardRow.metric("Disk write", rate(s.diskWrite)),
        DashboardRow.metric("Thermal state", s.thermal),
        DashboardRow.metric(
          "Power", s.power.present ? Format.percent(s.power.percent) : "No battery"),
        DashboardRow.chart("cpu", "CPU %", AeriePalette.cpu, 100),
        DashboardRow.chart("memory", "Memory %", AeriePalette.memory, 100),
        DashboardRow.heading("Storage"),
      ] + s.volumes.prefix(4).map { DashboardRow.metric($0.name, bytes($0.free) + " free") } + [
        DashboardRow.heading("Monitoring"),
        DashboardRow.metric("Refresh interval", "\(settings.interval)s"),
        DashboardRow.note(
          "All enabled system collectors share one scheduler. History is bounded to ten minutes, one day of minute averages, and one week of hourly averages."
        ),
      ]
    case .cpu:
      return [
        DashboardRow.heading("Processor"),
        DashboardRow.metric("Total", Format.percent(s.cpu.total)),
        DashboardRow.metric("User", Format.percent(s.cpu.user)),
        DashboardRow.metric("System", Format.percent(s.cpu.system)),
        DashboardRow.chart("cpu", "CPU %", AeriePalette.cpu, 100),
        DashboardRow.heading("Logical cores"), DashboardRow.cores(s.cpu.cores),
      ] + s.cpu.groups.map { DashboardRow.metric($0.0, "\($0.1) logical cores") } + [
        DashboardRow.metric(
          "Frequency", s.cpu.frequency.map { String(format: "%.2f GHz", $0) } ?? "Unavailable"),
        DashboardRow.metric(
          "Load 1 / 5 / 15 min",
          s.cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " / ")),
        DashboardRow.metric("Uptime", Format.duration(s.cpu.uptime)),
        DashboardRow.heading("Top CPU processes"),
      ] + top({ ($0.cpu ?? 0) > ($1.cpu ?? 0) }, value: { Format.percent($0.cpu) }) + [
        DashboardRow.note(
          "Dynamic core frequencies and group residency require telemetry this OS may restrict. Counts above describe topology; individual bars show actual logical-core utilization."
        )
      ]
    case .gpu:
      var rows: [DashboardRow] = [DashboardRow.chart("gpu", "GPU %", AeriePalette.cpu, 100)]
      for gpu in s.gpu {
        rows += [
          DashboardRow.heading(gpu.name),
          DashboardRow.metric("Device utilization", Format.percent(gpu.utilization)),
          DashboardRow.metric("Renderer", Format.percent(gpu.renderer)),
          DashboardRow.metric("Tiler", Format.percent(gpu.tiler)),
          DashboardRow.metric(
            "In-use shared memory", gpu.memory.map { self.bytes($0) } ?? "Unavailable"),
          DashboardRow.metric(
            "Temperature",
            gpu.temperature.map { Format.temperature($0, unit: settings.temperature) }
              ?? "Unavailable"),
          DashboardRow.metric(
            "Frequency", gpu.frequency.map { String(format: "%.2f GHz", $0) } ?? "Unavailable"),
          DashboardRow.metric(
            "Frame rate", gpu.fps.map { String(format: "%.0f FPS", $0) } ?? "Unavailable"),
        ]
      }
      rows.append(
        DashboardRow.note(
          "Driver-exposed statistics vary by GPU. Global FPS and per-process GPU utilization are unavailable when the driver does not publish them."
        ))
      return rows
    case .memory:
      let m = s.memory
      guard m.validity == .fresh else {
        return [
          .heading("Memory"), .note(m.validity.description),
          .note("Latest memory sample failed. Old values are excluded from history and rules."),
          .heading("Top memory processes"),
        ] + top({ $0.memory > $1.memory }, value: { bytes($0.memory) })
      }
      return [
        DashboardRow.heading("Memory"), DashboardRow.metric("Pressure", m.pressure),
        DashboardRow.metric("Used", Format.percent(m.usedFraction)),
        DashboardRow.chart("memory", "Used memory %", AeriePalette.memory, 100),
        DashboardRow.metric("Physical", bytes(m.total)),
        DashboardRow.metric("App", bytes(m.app)), DashboardRow.metric("Wired", bytes(m.wired)),
        DashboardRow.metric("Compressed", bytes(m.compressed)),
        DashboardRow.metric("Free", bytes(m.free)),
        DashboardRow.metric("File cache", bytes(m.cached)),
        DashboardRow.metric("Purgeable", bytes(m.purgeable)),
        DashboardRow.heading("Virtual memory"),
        DashboardRow.metric("Swap", "\(bytes(m.swap)) / \(bytes(m.swapTotal))"),
        DashboardRow.metric("Page in", rate(m.pageIn)),
        DashboardRow.metric("Page out", rate(m.pageOut)),
        DashboardRow.metric("Swap in", rate(m.swapIn)),
        DashboardRow.metric("Swap out", rate(m.swapOut)),
        DashboardRow.heading("Top memory processes"),
      ] + top({ $0.memory > $1.memory }, value: { bytes($0.memory) })
    case .storage:
      var rows: [DashboardRow] = [
        DashboardRow.heading("Disk activity"), DashboardRow.metric("Read", rate(s.diskRead)),
        DashboardRow.metric("Write", rate(s.diskWrite)),
        DashboardRow.chart("diskRead", "Read bytes/s", AeriePalette.incoming, nil),
        DashboardRow.chart("diskWrite", "Write bytes/s", AeriePalette.outgoing, nil),
      ]
      for v in s.volumes {
        rows += [
          DashboardRow.heading(v.name), DashboardRow.metric("Capacity", bytes(v.total)),
          DashboardRow.metric("Available", bytes(v.free)),
          DashboardRow.metric("Used", Format.percent(v.usedFraction)),
          DashboardRow.metric(
            "Important-use capacity", v.important.map { self.bytes($0) } ?? "Unavailable"),
          DashboardRow.metric(
            "Kind",
            "\(v.local ? "Local" : "Network")\(v.removable ? ", removable" : "")\(v.readOnly ? ", read only" : "")"
          ),
        ]
      }
      rows.append(.heading("Top process I/O"))
      let ioRows = top(
        { left, right in
          let leftBytes = (left.read ?? 0) + (left.write ?? 0)
          let rightBytes = (right.read ?? 0) + (right.write ?? 0)
          return leftBytes > rightBytes
        }, value: { process in "R \(rate(process.read))  W \(rate(process.write))" })
      rows.append(contentsOf: ioRows)
      rows.append(
        .note(
          "Disk rates are physical-device totals; process I/O uses OS accounting. Volume health and temperature depend on an accessible drive telemetry interface and are not yet collected."
        ))
      return rows
    case .network:
      var rows: [DashboardRow] = [
        DashboardRow.heading("Traffic"), DashboardRow.metric("Connectivity", s.connectivity),
        DashboardRow.metric("Download", rate(s.download, domain: .network)),
        DashboardRow.metric("Upload", rate(s.upload, domain: .network)),
        DashboardRow.chart("download", "Download bytes/s", AeriePalette.incoming, nil),
        DashboardRow.chart("upload", "Upload bytes/s", AeriePalette.outgoing, nil),
        DashboardRow.note(
          s.networkSelection.description + ". Collection still includes every reported interface."),
      ]
      if !s.networkAvailable {
        rows.append(.note("Interface counters are unavailable; no rates or totals are inferred."))
      } else if s.interfaces.isEmpty {
        rows.append(.note("No non-loopback interfaces were reported."))
      }
      for i in s.interfaces.sorted(by: { $0.active && !$1.active }) {
        rows += [
          DashboardRow.heading(i.name + (i.active ? " · active" : " · inactive")),
          DashboardRow.metric(
            "Download / upload",
            "\(rate(i.download, domain: .network)) / \(rate(i.upload, domain: .network))"),
          DashboardRow.metric(
            i.counterBits == 64 ? "OS cumulative received" : "Received · limited counter",
            bytes(Double(i.received))),
          DashboardRow.metric(
            i.counterBits == 64 ? "OS cumulative sent" : "Sent · limited counter",
            bytes(Double(i.sent))),
          DashboardRow.metric("Errors", "\(i.errors)"),
          DashboardRow.note(i.addresses.isEmpty ? "No assigned IP address" : i.addresses),
        ]
        if let session = i.session {
          rows += [
            DashboardRow.metric(
              "Observed session received",
              session.received.map { bytes(Double($0)) } ?? "Unavailable"),
            DashboardRow.metric(
              "Observed session sent", session.sent.map { bytes(Double($0)) } ?? "Unavailable"),
            DashboardRow.note(
              "Session baseline: \(session.started.formatted(date: .abbreviated, time: .standard))"
                + (session.rebased ? " · counter/source rebase" : "")),
          ]
        }
        if i.counterBits != 64 {
          rows.append(
            .note(
              "The OS route fallback rounds bytes to 1 KiB and limits counters to 32 bits. These values are not totals since boot; a wrap or source change resets the rate baseline."
            ))
        }
      }
      if !s.wifi.isEmpty {
        rows +=
          [DashboardRow.heading("Wi-Fi")]
          + s.wifi.sorted { $0.key < $1.key }.map { DashboardRow.metric($0.key, $0.value) }
      }
      rows.append(.heading("Process traffic"))
      rows.append(.note(s.processNetworkStatus))
      rows += s.networkProcesses.sorted {
        (($0.download ?? 0) + ($0.upload ?? 0)) > (($1.download ?? 0) + ($1.upload ?? 0))
      }.prefix(settings.processCount).map {
        .metric(
          "\($0.name) · \($0.pid)",
          "↓ \(rate($0.download, domain: .network))  ↑ \(rate($0.upload, domain: .network))")
      }
      rows.append(
        .note(
          "Process totals cover OS-reported TCP/UDP activity across interfaces, including loopback; they use independent process-start baselines and do not follow the aggregate interface filter. Protected, missing or reset readings have unavailable rates. The app owns one OS logger only while this panel is visible."
        ))
      rows.append(
        DashboardRow.note(
          "Virtual tunnels may count the same traffic again. Choose aggregate interfaces in Network Settings; all interfaces remain sampled and displayed. Observed sessions rebase after unavailable/reset/disappearing counters. Public IP lookup is off."
        ))
      return rows
    case .sensors:
      var rows: [DashboardRow] = [
        DashboardRow.heading("Hardware"), DashboardRow.metric("Thermal state", s.thermal),
        DashboardRow.note(s.sensorStatus),
        DashboardRow.note(
          settings.effectiveSensorSampling == .all
            ? "All supported sensors are sampled at the selected system interval."
            : "On-demand sensor sampling: all temperatures stay live for history and rules; other families become live when this panel is open."
        ),
      ]
      for unit in ["°C", "rpm", "W", "V", "A"] {
        let sensors = s.sensors.filter { $0.unit == unit }
        guard !sensors.isEmpty else { continue }
        rows += [
          DashboardRow.heading(
            ["°C": "Temperature", "rpm": "Fans", "W": "Power", "V": "Voltage", "A": "Current"][
              unit]!)
        ]
        rows += sensors.map {
          let value: String
          if let reading = $0.value, $0.state == .live {
            value =
              unit == "°C"
              ? Format.temperature(reading, unit: settings.temperature)
              : String(format: "%.1f %@", reading, unit)
          } else {
            value = $0.state == .deferred ? "Waiting for live read" : "Unavailable"
          }
          return DashboardRow.metric($0.label, value)
        }
      }
      rows += [
        DashboardRow.note(
          "Firmware key names appear when a sensor label is unknown. Aerie only reads sensors. Fan profiles require a separately approved and safety-tested control implementation."
        )
      ]
      return rows
    case .power:
      let p = s.power
      var rows: [DashboardRow] = [
        DashboardRow.heading("Power"),
        DashboardRow.metric(
          "Source", p.present ? (p.external ? "Power adapter" : "Battery") : "No battery reported"),
        DashboardRow.metric("Low Power Mode", s.lowPower ? "On" : "Off"),
        DashboardRow.metric("Thermal state", s.thermal),
      ]
      if p.present {
        rows += [
          DashboardRow.metric("Charge", Format.percent(p.percent)),
          DashboardRow.metric("Charging", p.charging ? "Yes" : "No"),
          DashboardRow.metric(
            p.charging ? "Time to full" : "Time remaining",
            p.minutes.map { Format.duration(Double($0 * 60)) } ?? "Calculating"),
          DashboardRow.chart("battery", "Battery %", AeriePalette.power, 100),
          DashboardRow.metric("Health", Format.percent(p.health)),
          DashboardRow.metric("Cycles", p.cycles.map { String($0) } ?? "Unavailable"),
          DashboardRow.metric(
            "Battery power", p.watts.map { String(format: "%.2f W", $0) } ?? "Unavailable"),
          DashboardRow.metric(
            "Voltage", p.voltage.map { String(format: "%.2f V", $0) } ?? "Unavailable"),
          DashboardRow.metric(
            "Current", p.amperage.map { String(format: "%.2f A", $0) } ?? "Unavailable"),
        ]
      }
      rows += [DashboardRow.heading("Peripheral batteries")]
      rows +=
        p.peripherals.isEmpty
        ? [DashboardRow.note("No supported peripheral battery is exposed by the device registry.")]
        : p.peripherals.map { DashboardRow.metric($0.0, Format.percent($0.1)) }
      return rows + [DashboardRow.heading("Process wakeups")]
        + top(
          { ($0.wakeups ?? 0) > ($1.wakeups ?? 0) },
          value: { $0.wakeups.map { String(format: "%.1f /s", $0) } ?? "Unavailable" }) + [
          DashboardRow.note(
            "Wakeups are interrupt wakeups, not a whole-system energy score. Changing power modes is not implemented."
          )
        ]
    case .time:
      let now = Date()
      let formatter = DateFormatter()
      formatter.dateFormat = settings.clockFormat
      var rows: [DashboardRow] = [
        DashboardRow.heading("Local time"),
        DashboardRow.metric(
          formatter.string(from: now), TimeZone.current.abbreviation() ?? "Local"),
        DashboardRow.metric("Moon phase (approx.)", Astronomy.moonName(at: now)),
        DashboardRow.metric("Lunar age", String(format: "%.1f days", Astronomy.moonAge(at: now))),
        DashboardRow.heading("World clocks"),
      ]
      for clock in settings.clocks {
        formatter.timeZone = TimeZone(identifier: clock.zone)
        rows += [DashboardRow.metric(clock.name, formatter.string(from: now))]
        if let next = formatter.timeZone.nextDaylightSavingTimeTransition(after: now) {
          let f = DateFormatter()
          f.dateStyle = .medium
          f.timeZone = formatter.timeZone
          rows += [DashboardRow.metric("Next daylight saving change", f.string(from: next))]
        }
      }
      rows += [DashboardRow.heading("Calendar")] + calendarRows
      return rows
    case .weather:
      guard settings.weather.valid else {
        return [
          DashboardRow.heading("Weather is off"),
          DashboardRow.note(
            "Choose a provider and a manual location in Settings to enable weather. No device location, IP geolocation, or background city search is used."
          ),
        ]
      }
      var rows: [DashboardRow] = [
        DashboardRow.heading(settings.weather.name), DashboardRow.note(weatherStatus),
      ]
      guard let w = weather else { return rows }
      rows += [
        DashboardRow.metric("Conditions", WeatherCondition.describe(w.code)),
        DashboardRow.metric(
          "Temperature",
          w.temperature.map { Format.temperature($0, unit: settings.temperature) } ?? "Unavailable"),
        DashboardRow.metric(
          "Feels like",
          w.apparent.map { Format.temperature($0, unit: settings.temperature) } ?? "Unavailable"),
        DashboardRow.metric(
          "Humidity", w.humidity.map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        DashboardRow.metric(
          "Wind / gusts",
          "\(w.wind.map { String(format: "%.1f", $0) } ?? "—") / \(w.gusts.map { String(format: "%.1f km/h", $0) } ?? "—")"
        ),
        DashboardRow.metric(
          "Direction", w.direction.map { String(format: "%.0f°", $0) } ?? "Unavailable"),
        DashboardRow.metric(
          "Pressure", w.pressure.map { String(format: "%.0f hPa", $0) } ?? "Unavailable"),
        DashboardRow.metric(
          "Cloud cover", w.cloud.map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        DashboardRow.note(w.timeContext.description),
        DashboardRow.heading("Next 24 hours"),
      ]
      let f = DateFormatter()
      f.dateFormat = "EEE HH:mm"
      f.timeZone = w.timeContext.instantZone
      for h in w.hours.filter({ $0.date >= Date().addingTimeInterval(-3600) }).prefix(24) {
        rows += [
          DashboardRow.metric(
            f.string(from: h.date),
            "\(Format.temperature(h.temperature, unit: settings.temperature))  \(h.precipitation.map { String(format: "%.0f%% rain", $0) } ?? "")"
          )
        ]
      }
      rows += [DashboardRow.heading("Daily forecast")]
      f.dateFormat = "EEE d MMM"
      f.timeZone = w.timeContext.dailyZone
      for d in w.days {
        rows += [
          DashboardRow.metric(
            f.string(from: d.date),
            "\(Format.temperature(d.low, unit: settings.temperature)) / \(Format.temperature(d.high, unit: settings.temperature))"
          ),
          DashboardRow.metric(
            WeatherCondition.describe(d.code), d.uv.map { String(format: "UV %.1f", $0) } ?? ""),
        ]
        let t = DateFormatter()
        t.timeStyle = .short
        t.timeZone = w.timeContext.instantZone
        if let sunrise = d.sunrise, let sunset = d.sunset {
          rows += [
            DashboardRow.metric(
              "Daylight", "\(t.string(from: sunrise)) – \(t.string(from: sunset))")
          ]
        }
      }
      rows += [
        DashboardRow.heading("Source"),
        DashboardRow.note(
          "Weather data: \(w.source). Open-Meteo data is CC BY 4.0. https://open-meteo.com/ · Model-derived forecasts. Official severe alerts and radar are not available from this provider."
        ),
      ]
      return rows
    }
  }
}
