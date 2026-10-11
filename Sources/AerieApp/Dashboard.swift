import AerieCore
import AppKit
import EventKit

enum DashboardRow {
  case heading(String)
  case metric(String, String)
  case note(String)
  case chart(String, String, NSColor, Double?)
  case cores([Double])
  case calendar(CalendarMonth)
  case action(String, String, String)
  var height: CGFloat {
    switch self {
    case .heading: return 34
    case .metric: return 27
    case .note: return 47
    case .chart: return 100
    case .cores(let c): return CGFloat((c.count + 11) / 12) * 42 + 18
    case .calendar(let model): return CalendarMonthView.height(model)
    case .action: return 34
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

private final class HistoryChartAccessibilityElement: NSAccessibilityElement {
  weak var owner: DashboardView?
  override func accessibilityPerformPress() -> Bool { owner?.selectHistory(fraction: 0.5) ?? false }
}

final class DashboardView: NSView {
  var rows: [DashboardRow] = []
  var points: [HistoryPoint] = []
  var selectedPoint: HistoryPoint?
  var expectedInterval = 1.0
  private let chartFormatter = DateFormatter()
  private var calendarView: CalendarMonthView?
  private var actionButtons: [Int: NSButton] = [:]
  private var textElements: [Int: NSAccessibilityElement] = [:]
  private var accessibilityGroups: [Int: NSAccessibilityElement] = [:]
  static let accessibilityGroupSize = 64
  var onSelectDate: ((Date) -> Void)?
  var onMoveMonth: ((Int) -> Void)?
  var onToday: (() -> Void)?
  var onAction: ((String) -> Void)?
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
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
    var elements: [Any] = []
    var hasCalendar = false
    var actionIndexes: Set<Int> = []
    var textIndexes: Set<Int> = []
    for (index, row) in rows.enumerated() {
      if case .calendar(let model) = row {
        let calendar = calendarView ?? CalendarMonthView(frame: .zero)
        calendarView = calendar; hasCalendar = true
        calendar.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: row.height)
        calendar.onSelect = { [weak self] in self?.onSelectDate?($0) }
        calendar.onMove = { [weak self] in self?.onMoveMonth?($0) }
        calendar.onToday = { [weak self] in self?.onToday?() }
        if calendar.superview == nil { addSubview(calendar) }
        calendar.update(model); elements.append(calendar)
        y += row.height; continue
      }
      if case .action(let title, let value, _) = row {
        let button =
          actionButtons[index]
          ?? NSButton(title: "", target: self, action: #selector(performRowAction(_:)))
        actionButtons[index] = button; actionIndexes.insert(index)
        button.tag = index; button.title = "\(title) · \(value)"
        button.bezelStyle = .inline; button.alignment = .left
        button.font = .systemFont(ofSize: 11); button.lineBreakMode = .byTruncatingTail
        button.frame = NSRect(x: 14, y: y + 3, width: bounds.width - 28, height: 28)
        button.setAccessibilityLabel("\(title), \(value), show details")
        if button.superview == nil { addSubview(button) }
        elements.append(button); y += row.height; continue
      }
      let label: String
      switch row {
      case .heading(let s), .note(let s): label = s
      case .metric(let k, let v): label = "\(k): \(v)"
      case .chart(let key, let title, _, _):
        if let selectedPoint, let value = selectedPoint.values[key] {
          chartFormatter.dateStyle = .short; chartFormatter.timeStyle = .medium
          label =
            "\(title) history, \(points.count) samples. Selected \(chartFormatter.string(from: selectedPoint.date)): \(String(format: "%.2f", value)). Activate to inspect the middle sample."
        } else {
          label =
            "\(title) history, \(points.count) samples. Click to inspect a sample; activate to inspect the middle sample."
        }
      case .cores(let c):
        label = c.enumerated().map { "Core \($0.offset + 1): \(Format.percent($0.element))" }
          .joined(separator: ", ")
      case .calendar, .action: label = ""
      }
      let chart: Bool
      if case .chart = row { chart = true } else { chart = false }
      let e: NSAccessibilityElement
      if let existing = textElements[index], (existing is HistoryChartAccessibilityElement) == chart
      {
        e = existing
      } else {
        textElements[index]?.setAccessibilityParent(nil)
        e = chart ? HistoryChartAccessibilityElement() : NSAccessibilityElement()
        textElements[index] = e
      }
      textIndexes.insert(index)
      if let e = e as? HistoryChartAccessibilityElement { e.owner = self }
      e.setAccessibilityParent(self)
      e.setAccessibilityRole(chart ? .button : .staticText)
      e.setAccessibilityEnabled(true)
      e.setAccessibilityLabel(label)
      if let window {
        e.setAccessibilityFrame(
          window.convertToScreen(
            convert(NSRect(x: 12, y: y, width: bounds.width - 24, height: row.height), to: nil)))
      }
      elements.append(e)
      y += row.height
    }
    if !hasCalendar {
      calendarView?.setAccessibilityParent(nil)
      calendarView?.removeFromSuperview(); calendarView = nil
    }
    for index in Array(actionButtons.keys) where !actionIndexes.contains(index) {
      let button = actionButtons.removeValue(forKey: index)
      button?.setAccessibilityParent(nil); button?.removeFromSuperview()
    }
    for index in Array(textElements.keys) where !textIndexes.contains(index) {
      textElements.removeValue(forKey: index)?.setAccessibilityParent(nil)
    }
    updateAccessibilityHierarchy(elements)
  }
  private func updateAccessibilityHierarchy(_ elements: [Any]) {
    // A bounded hierarchy lets native clients traverse a long inventory without losing any rows.
    guard elements.count > Self.accessibilityGroupSize * 2 else {
      clearAccessibilityGroups()
      for element in elements { Self.setParent(self, of: element) }
      setAccessibilityChildren(elements)
      return
    }
    var groups: [NSAccessibilityElement] = []
    for start in stride(from: 0, to: elements.count, by: Self.accessibilityGroupSize) {
      let index = start / Self.accessibilityGroupSize
      let end = min(elements.count, start + Self.accessibilityGroupSize)
      let group = accessibilityGroups[index] ?? NSAccessibilityElement()
      accessibilityGroups[index] = group
      group.setAccessibilityRole(.group); group.setAccessibilityParent(self)
      group.setAccessibilityLabel("Statistics rows \(start + 1)–\(end)")
      let children = Array(elements[start..<end])
      var frame = NSRect.null
      for child in children {
        Self.setParent(group, of: child)
        if let childFrame = Self.frame(of: child) { frame = frame.union(childFrame) }
      }
      group.setAccessibilityChildren(children)
      group.setAccessibilityFrame(frame.isNull ? .zero : frame)
      groups.append(group)
    }
    for index in Array(accessibilityGroups.keys) where index >= groups.count {
      let group = accessibilityGroups.removeValue(forKey: index)
      group?.setAccessibilityChildren([]); group?.setAccessibilityParent(nil)
    }
    setAccessibilityChildren(groups)
  }
  private func clearAccessibilityGroups() {
    accessibilityGroups.values.forEach {
      $0.setAccessibilityChildren([]); $0.setAccessibilityParent(nil)
    }
    accessibilityGroups.removeAll()
  }
  private static func setParent(_ parent: Any?, of element: Any) {
    if let element = element as? NSAccessibilityElement {
      element.setAccessibilityParent(parent)
    } else if let view = element as? NSView {
      view.setAccessibilityParent(parent)
    }
  }
  private static func frame(of element: Any) -> NSRect? {
    if let element = element as? NSAccessibilityElement { return element.accessibilityFrame() }
    if let view = element as? NSView { return view.accessibilityFrame() }
    return nil
  }
  override func accessibilityFrame() -> NSRect {
    guard let window else { return super.accessibilityFrame() }
    // The scroll document can be thousands of points tall; its visible root is the viewport.
    return window.convertToScreen(convert(visibleRect, to: nil))
  }
  override func accessibilityVisibleChildren() -> [Any]? {
    guard window != nil else { return accessibilityChildren() }
    let viewport = accessibilityFrame()
    return accessibilityChildren()?.filter {
      guard let frame = Self.frame(of: $0) else { return true }
      return frame.intersects(viewport)
    }
  }
  func releaseInteractiveRows() {
    calendarView?.setAccessibilityParent(nil); calendarView?.removeFromSuperview();
    calendarView = nil
    actionButtons.values.forEach {
      $0.setAccessibilityParent(nil); $0.removeFromSuperview()
    }; actionButtons.removeAll()
    textElements.values.forEach { $0.setAccessibilityParent(nil) }; textElements.removeAll()
    clearAccessibilityGroups()
    rows.removeAll(); points.removeAll(); selectedPoint = nil; setAccessibilityChildren([])
    // A large inventory must not leave a tall, empty native document backing after close.
    frame.size.height = 16
    needsDisplay = true
  }
  @objc private func performRowAction(_ sender: NSButton) {
    guard rows.indices.contains(sender.tag), case .action(_, _, let identifier) = rows[sender.tag]
    else { return }
    onAction?(identifier)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.intersection(bounds).fill()
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
      case .calendar, .action: break
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
    _ = selectHistory(fraction: Double(fraction))
  }
  @discardableResult func selectHistory(fraction: Double) -> Bool {
    guard !points.isEmpty, fraction.isFinite else { return false }
    selectedPoint = HistoryPlot.nearest(points, fraction: max(0, min(1, fraction)))
    update(rows: rows, points: points)
    return selectedPoint != nil
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
  private var daylightConfiguration: DaylightConfiguration?
  private(set) var daylightReading: SolarDay?
  var suspended = false
  func releaseDaylight() { daylightConfiguration = nil; daylightReading = nil }
  let canvas = DashboardView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
  let modules = NSPopUpButton(frame: .zero, pullsDown: false)
  let windowPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  let zoomPicker = NSPopUpButton(frame: .zero, pullsDown: false)
  let historyPosition = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let zoomReset = NSButton(title: "Reset", target: nil, action: nil)
  let stateLabel = NSTextField(labelWithString: "Sampling")
  var onSettings: (() -> Void)?
  var onMaps: (() -> Void)?
  var onExportHistory: ((Int, [HistoryPoint]) -> Void)?
  private let mapsButton = NSButton(title: "Maps…", target: nil, action: nil)
  var onModule: ((Module) -> Void)?
  var module = Module.overview
  var snapshot = Snapshot()
  func releaseWiFi() {
    snapshot.wifi = nil
    if module == .network { canvas.releaseInteractiveRows(); refresh() }
  }
  var settings = Settings()
  var history = HistoryStore()
  var historyStatus = "History archive is off"
  var weather: WeatherReport?
  var weatherStatus = "Weather is off"
  var shortcutStatus: String?
  var publicAddress: PublicAddressReading?
  var publicAddressStatus = "Public IP lookup is off"
  func updatePublicAddress(_ reading: PublicAddressReading?, status: String) {
    let released = publicAddress != nil && reading == nil
    publicAddress = reading; publicAddressStatus = status
    if released && module == .network { canvas.releaseInteractiveRows(); refresh() }
  }
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
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 45, width: 416, height: 490))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = canvas
    scroll.drawsBackground = false
    view.addSubview(scroll)
    zoomPicker.addItems(withTitles: ["Full range", "Zoom 2×", "Zoom 4×", "Zoom 8×"])
    zoomPicker.frame = NSRect(x: 16, y: 543, width: 114, height: 26)
    zoomPicker.target = self; zoomPicker.action = #selector(changeZoom)
    zoomPicker.setAccessibilityLabel("History zoom")
    historyPosition.frame = NSRect(x: 140, y: 546, width: 174, height: 22)
    historyPosition.target = self; historyPosition.action = #selector(changeZoom)
    historyPosition.isContinuous = true
    historyPosition.setAccessibilityLabel("History position, oldest to latest")
    historyPosition.toolTip =
      "Pan from the oldest retained time to the latest; right edge follows new readings."
    zoomReset.frame = NSRect(x: 325, y: 543, width: 72, height: 26)
    zoomReset.target = self; zoomReset.action = #selector(resetZoom)
    [zoomPicker, historyPosition, zoomReset].forEach { view.addSubview($0) }
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
    export.toolTip = "Export the visible system series and time range as CSV"
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
  var displayedHistory: [HistoryPoint] {
    HistoryWindow.visible(
      history.points(window: windowPicker.indexOfSelectedItem),
      zoom: [1, 2, 4, 8][max(0, zoomPicker.indexOfSelectedItem)],
      position: historyPosition.doubleValue)
  }
  @objc private func exportHistory() {
    onExportHistory?(windowPicker.indexOfSelectedItem, displayedHistory)
  }
  @objc private func changeZoom() { canvas.selectedPoint = nil; refresh() }
  @objc private func resetZoom() {
    zoomPicker.selectItem(at: 0); historyPosition.doubleValue = 1; changeZoom()
  }
  @objc private func changeWindow() {
    resetZoom()
  }
  func show(_ module: Module) {
    if module != .time { releaseDaylight() }
    self.module = module
    modules.selectItem(at: Module.allCases.firstIndex(of: module) ?? 0)
    refresh()
  }
  func refresh() {
    guard isViewLoaded else { return }
    mapsButton.isHidden = module != .weather; windowPicker.isHidden = module == .weather
    zoomPicker.isHidden = module == .weather
    historyPosition.isHidden = module == .weather; zoomReset.isHidden = module == .weather
    historyPosition.isEnabled = zoomPicker.indexOfSelectedItem > 0
    mapsButton.title = settings.weather.mapsValid ? "Maps…" : "Enable Maps…"
    let age = max(0, Date().timeIntervalSince(snapshot.date))
    stateLabel.stringValue =
      suspended
      ? "Paused"
      : age > settings.interval * 3
        ? "Stale · \(Int(age))s" : "Live · \(settings.interval.formatted())s"
    let rows = makeRows()
    canvas.expectedInterval =
      windowPicker.indexOfSelectedItem == 0
      ? settings.interval : windowPicker.indexOfSelectedItem == 1 ? 60 : 3600
    canvas.update(
      rows: rows + (shortcutStatus.map { [.note("Global shortcuts: " + $0)] } ?? [])
        + (settings.effectivePersistentHistory || historyStatus != "History archive is off"
          ? [.note(historyStatus)] : []),
      points: displayedHistory)
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
    let combined = ProcessPresentation.combine(
      snapshot.processes, enabled: settings.effectiveCombineProcesses)
    let order = settings.processSorts?[module] ?? .automatic
    let list = ProcessPresentation.sorted(combined, by: order, automatic: sort).prefix(
      settings.processCount)
    if list.isEmpty {
      return [
        .note("Process details begin when this menu opens. Protected processes may be unavailable.")
      ]
    }
    var rows = list.map { DashboardRow.metric($0.name, value($0)) }
    if settings.effectiveCombineProcesses {
      let missing = snapshot.processes.filter { $0.group == nil }.count
      rows.append(
        .note(
          "Combined by application bundle or executable. \(missing) readable processes have no grouping identity and stay separate. Group rates require every member's baseline; memory is summed process footprint and can include shared-accounting overlap."
        ))
    }
    if order != .automatic { rows.append(.note("Process order: " + order.title)) }
    return rows + [
      .note(
        "\(snapshot.processDenied) protected processes unavailable. CPU format: \(settings.normalizedProcessCPU ? "0–100% of machine" : "100% per logical core")."
      )
    ]
  }
  private func clockRows(kinds: [ClockChannelKind]) -> [DashboardRow] {
    var rows: [DashboardRow] = []
    var lastKind: ClockChannelKind?
    for (index, reading) in snapshot.clockResidencies.enumerated()
    where kinds.contains(reading.kind) {
      if lastKind != reading.kind {
        let title: String
        switch reading.kind {
        case .cpuComplex: title = "CPU-complex clock states"
        case .cpuCore: title = "CPU-core clock states"
        case .gpu: title = "GPU clock states"
        }
        rows.append(.heading(title)); lastKind = reading.kind
      }
      rows.append(
        .action(
          reading.name, Format.percent(reading.activeFraction) + " active-labelled",
          "clock-state:\(index)"))
      if let frequency = reading.activeGHz {
        rows.append(.metric("Active interval average", String(format: "%.3f GHz", frequency)))
      }
    }
    rows.append(.note(snapshot.clockResidencyStatus))
    return rows
  }
  private func daylightRows(now: Date) -> [DashboardRow] {
    guard !suspended else { releaseDaylight(); return [] }
    guard let configuration = settings.daylight, configuration.enabled, configuration.valid else {
      releaseDaylight(); return []
    }
    if daylightConfiguration != configuration
      || daylightReading.map({
        now < $0.interval.start || now >= $0.interval.end
      }) != false
    {
      daylightConfiguration = configuration
      daylightReading = SolarDay.make(date: now, configuration: configuration)
    }
    guard let reading = daylightReading else {
      return [
        .heading("Offline daylight · " + configuration.name),
        .note("Solar estimates are unavailable for this date; supported years are 1901–2099."),
      ]
    }
    let formatter = DateFormatter(); formatter.timeZone = reading.zone
    formatter.timeStyle = .short
    func times(_ dates: [Date]) -> String {
      dates.isEmpty
        ? "No crossing today" : dates.map { formatter.string(from: $0) }.joined(separator: ", ")
    }
    let dateFormatter = DateFormatter(); dateFormatter.timeZone = reading.zone;
    dateFormatter.dateStyle = .medium
    var rows: [DashboardRow] = [
      .heading("Offline daylight · " + configuration.name),
      .note(dateFormatter.string(from: reading.interval.start) + " · " + reading.zone.identifier),
      .metric("Approx. solar noon", times(reading.transits)),
    ]
    for boundary in reading.boundaries {
      let rise, set: String
      switch boundary.band {
      case .daylight: rise = "Approx. sunrise"; set = "Approx. sunset"
      case .civil: rise = "Civil dawn"; set = "Civil dusk"
      case .nautical: rise = "Nautical dawn"; set = "Nautical dusk"
      case .astronomical: rise = "Astronomical dawn"; set = "Astronomical dusk"
      }
      rows += [.metric(rise, times(boundary.rises)), .metric(set, times(boundary.sets))]
      if boundary.band == .daylight {
        rows.append(.metric("Daylight in this local day", Format.duration(boundary.secondsAbove)))
      }
      switch boundary.state {
      case .transitions: break
      case .continuousAbove:
        rows.append(
          .note("Sun stays above the \(boundary.band.rawValue) boundary throughout this local day.")
        )
      case .continuousBelow:
        rows.append(
          .note("Sun stays below the \(boundary.band.rawValue) boundary throughout this local day.")
        )
      }
    }
    rows.append(
      .note(
        "Calculated locally from the manual point; no coordinates are sent. Standard horizon/refraction estimates exclude terrain and variable atmospheric conditions; polar timing has greater uncertainty."
      ))
    return rows
  }
  static func powerSourceRows(_ inventory: PowerSourceInventory) -> [DashboardRow] {
    var rows: [DashboardRow] = [.heading("Power sources")]
    guard inventory.available else { return rows + [.note("Power source inventory unavailable.")] }
    if !inventory.complete {
      rows.append(
        .note(
          "Partial inventory: \(inventory.sources.count) readable of \(inventory.reportedCount) reported sources; retained limit \(PowerSourceInventory.limit)."
        ))
    }
    if inventory.sources.isEmpty {
      rows.append(.note("No battery or UPS descriptions reported by macOS."))
    }
    for source in inventory.sources {
      rows += [
        .heading(source.name),
        .metric(
          "Type",
          source.kind == .internalBattery
            ? "Internal battery" : source.kind == .ups ? "UPS" : "Unknown"),
        .metric("Present", source.present.map { $0 ? "Yes" : "No" } ?? "Unavailable"),
        .metric(
          "Input",
          source.input == .ac
            ? "External AC"
            : source.input == .battery
              ? "Battery" : source.input == .offline ? "Offline" : "Unavailable"),
        .metric("Charging", source.charging.map { $0 ? "Yes" : "No" } ?? "Unavailable"),
        .metric("Charge", Format.percent(source.percent)),
        .metric(
          source.charging == true ? "Time to full" : "Time remaining",
          Format.powerTime(source.minutes, charging: source.charging, input: source.input)),
      ]
      if let transport = source.transport { rows.append(.metric("Transport", transport)) }
      if let value = source.voltage {
        rows.append(.metric("Voltage", String(format: "%.2f V", value)))
      }
      if let value = source.amperage {
        rows.append(.metric("Current", String(format: "%.2f A", value)))
      }
      if let value = source.watts { rows.append(.metric("Power", String(format: "%.2f W", value))) }
      if let value = source.temperature {
        rows.append(.metric("Temperature", String(format: "%.1f °C", value)))
      }
    }
    return rows
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
      var rows: [DashboardRow] = [
        DashboardRow.heading("Processor"),
        DashboardRow.metric("Total", Format.percent(s.cpu.total)),
        DashboardRow.metric("User", Format.percent(s.cpu.user)),
        DashboardRow.metric("System", Format.percent(s.cpu.system)),
        DashboardRow.chart("cpu", "CPU %", AeriePalette.cpu, 100),
        DashboardRow.heading("Logical cores"), DashboardRow.cores(s.cpu.cores),
      ]
      rows += s.cpu.groups.map { DashboardRow.metric($0.0, "\($0.1) logical cores") }
      rows += [
        DashboardRow.metric(
          "Nominal frequency",
          s.cpu.frequency.map { String(format: "%.2f GHz", $0) } ?? "Unavailable"),
        DashboardRow.metric(
          "Load 1 / 5 / 15 min",
          s.cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " / ")),
        DashboardRow.metric("Uptime", Format.duration(s.cpu.uptime)),
      ]
      rows += clockRows(kinds: [.cpuComplex, .cpuCore])
      rows.append(.heading("Top CPU processes"))
      rows += top({ ($0.cpu ?? 0) > ($1.cpu ?? 0) }, value: { Format.percent($0.cpu) })
      rows += [
        DashboardRow.note(
          "Logical-core bars show scheduler load. Clock-state residency reports separate hardware activity; channel names come from the system. Dynamic GHz remains unavailable for unnamed frequency states."
        )
      ]
      return rows
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
      return rows + clockRows(kinds: [.gpu])
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
      rows.append(.heading("Per-device I/O sources"))
      for device in s.storageDevices {
        rows += [
          .metric(
            device.device ?? "Unassociated I/O source",
            "R \(rate(device.read))  W \(rate(device.write))")
        ]
      }
      rows += [.heading("OS drive health"), .note(s.storageMetadata.status)]
      if let date = s.storageMetadata.queriedAt {
        rows.append(.metric("Metadata read", date.formatted(date: .omitted, time: .standard)))
      }
      for identifier in s.storageMetadata.topology?.physicalDisks ?? [] {
        guard let drive = s.storageMetadata.drives[identifier] else {
          rows.append(.metric(identifier, "Health query unavailable")); continue
        }
        let status: String
        switch drive.smart {
        case .verified: status = "SMART threshold status: Verified"
        case .failing: status = "SMART threshold status: Failing"
        case .unsupported: status = "SMART status not supported"
        case .unknown: status = "SMART status not reported"
        }
        rows += [
          .heading(identifier), .metric("Reported status", status),
          .metric("Bus", drive.bus ?? "Unavailable"),
          .metric(
            "Media", drive.solidState.map { $0 ? "Solid state" : "Rotating" } ?? "Unavailable"),
        ]
      }
      for volume in s.volumes {
        if let device = volume.device {
          let backing = s.storageMetadata.topology?.underlyingDisks(for: device) ?? []
          rows.append(
            .metric(
              volume.name + " · " + device,
              backing.isEmpty ? "Backing device unavailable" : backing.joined(separator: ", ")))
        }
      }
      rows.append(
        .note(
          "SMART is the OS-reported drive threshold state, not a diagnostic scan or remaining-life estimate. Read-only metadata refreshes once per minute only while visible. Temperature and endurance remain unavailable when no supported telemetry source exists. Virtual/image APFS stores are identified as backing devices without claiming physical drive health."
        ))
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
          "Disk rates are physical-device totals; process I/O uses OS accounting. Per-device association uses native whole-media registry records and read-only OS/APFS metadata; unassociated sources remain explicit. No drive scan, repair, device write or elevated helper is performed."
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
          s.networkSelection.description
            + ". Collection still includes every reported interface. Aggregate rates require a valid baseline for every selected active interface."
        ),
      ]
      rows.append(.heading("External address"))
      if let publicAddress {
        rows.append(.metric(publicAddress.family, publicAddress.address))
        rows.append(
          .note(
            "Provider reply from "
              + publicAddress.fetched.formatted(date: .omitted, time: .shortened)))
      }
      rows.append(.note(publicAddressStatus))
      if settings.effectivePublicAddress {
        rows.append(
          .note(
            "ipify observes the HTTP route. VPNs, proxies or NAT may affect its reply independently of the aggregate interface selection."
          ))
      }
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
      rows.append(.heading("Wi-Fi"))
      if let wifi = s.wifi {
        rows += wifi.fields.map { DashboardRow.metric($0.0, $0.1) }
        rows.append(.note(wifi.identityNote))
        rows.append(
          .note(
            "Passive interface sample · " + wifi.fetched.formatted(date: .omitted, time: .shortened)
          ))
      } else {
        rows.append(.note("No Wi-Fi interface reading is available."))
      }
      rows.append(
        .note(
          "Radio details refresh every 30 seconds while this panel is open, or when the network path or authorization changes. Zero error sentinels are unavailable. Identity is discarded on close, pause or sleep; no network scan is performed."
        ))
      rows.append(.heading("Process traffic"))
      rows.append(.note(s.processNetworkStatus))
      let networkOrder = settings.processSorts?[.network] ?? .automatic
      let sortedProcesses = ProcessPresentation.network(
        s.networkProcesses, groups: s.networkProcessGroups,
        enabled: settings.effectiveCombineProcesses, sort: networkOrder)
      for process in sortedProcesses.prefix(settings.processCount) {
        let title = process.members > 1 ? process.name : "\(process.name) · \(process.pid)"
        let incoming = rate(process.download, domain: .network)
        let outgoing = rate(process.upload, domain: .network)
        rows.append(.metric(title, "↓ \(incoming)  ↑ \(outgoing)"))
      }
      if settings.effectiveCombineProcesses {
        let missing = s.networkProcesses.filter {
          s.networkProcessGroups[ProcessIdentity(pid: Int($0.pid), startTime: $0.startTime)] == nil
        }.count
        rows.append(
          .note(
            "Combined by application bundle or executable. \(missing) readable traffic identities stay separate. Group rates require every member's baseline."
          ))
      }
      if networkOrder != .automatic { rows.append(.note("Process order: " + networkOrder.title)) }
      rows.append(
        .note(
          "Process totals cover OS-reported TCP/UDP activity across interfaces, including loopback; they use independent process-start baselines and do not follow the aggregate interface filter. Protected, missing or reset readings have unavailable rates. The app owns one OS logger only while this panel is visible."
        ))
      rows.append(
        DashboardRow.note(
          "Virtual tunnels may count the same traffic again. Choose aggregate interfaces in Network Settings; all interfaces remain sampled and displayed. Observed sessions rebase after unavailable/reset/disappearing counters."
        ))
      return rows
    case .sensors:
      var rows: [DashboardRow] = [
        DashboardRow.heading("Hardware"), DashboardRow.metric("Thermal state", s.thermal),
        DashboardRow.note(s.sensorStatus),
        DashboardRow.note(
          settings.effectiveSensorSampling == .all
            ? "All supported sensors are sampled at the selected system interval."
            : "On-demand sampling keeps all temperatures and enabled individual-rule sensors live; other readings wait until this panel opens."
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
          return DashboardRow.metric($0.title(names: settings.sensorNames), value)
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
          "System supply", p.source ?? "Unavailable"),
        DashboardRow.metric("Low Power Mode", s.lowPower ? "On" : "Off"),
        DashboardRow.metric("Thermal state", s.thermal),
      ]
      if p.present {
        rows += [
          DashboardRow.metric("Charge", Format.percent(p.percent)),
          DashboardRow.metric("Charging", p.charging.map { $0 ? "Yes" : "No" } ?? "Unavailable"),
          DashboardRow.metric(
            p.charging == true ? "Time to full" : "Time remaining",
            Format.powerTime(
              p.minutes, charging: p.charging,
              input: p.external.map { $0 ? .ac : .battery } ?? .unknown)),
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
      if p.present && p.inventory.primaryBattery == nil {
        rows += [
          .note(
            "Battery summary unavailable: multiple, unknown or unreadable sources. Each source is shown separately; no combined capacity is inferred."
          )
        ]
      }
      rows += Self.powerSourceRows(p.inventory)
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
      rows += daylightRows(now: now)
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
      let f = DateFormatter()
      f.dateFormat = "EEE d MMM HH:mm z"
      f.timeZone = w.timeContext.instantZone
      if let station = w.observationStation { rows.append(.metric("Observation station", station)) }
      if let time = w.observationTime {
        rows.append(.metric("Observation time", f.string(from: time)))
      }
      if let time = w.forecastUpdated {
        rows.append(.metric("Forecast updated", f.string(from: time)))
      }
      for note in w.notes { rows.append(.note(note)) }
      rows += [
        DashboardRow.metric("Conditions", w.condition ?? WeatherCondition.describe(w.code)),
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
      f.dateFormat = "EEE HH:mm"
      for h in w.hours.filter({ $0.date >= Date().addingTimeInterval(-3600) }).prefix(24) {
        rows += [
          DashboardRow.metric(
            f.string(from: h.date),
            "\(h.temperature.map { Format.temperature($0, unit: settings.temperature) } ?? "Unavailable")  \(h.precipitation.map { String(format: "%.0f%% rain", $0) } ?? "")"
          )
        ]
        if let condition = h.condition, !condition.isEmpty { rows.append(.note(condition)) }
      }
      if !w.periods.isEmpty {
        rows.append(.heading("Named forecast periods"))
        for (index, period) in w.periods.enumerated() {
          rows.append(
            .action(
              period.name,
              period.temperature.map { Format.temperature($0, unit: settings.temperature) }
                ?? "Temperature unavailable", "weather-period:\(index)"))
          rows.append(.note(period.condition + (period.wind.isEmpty ? "" : " · " + period.wind)))
        }
      }
      if !w.days.isEmpty { rows += [DashboardRow.heading("Daily forecast")] }
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
      if let alerts = w.alertReport {
        rows.append(.heading("Current alerts at the manual point"))
        f.dateFormat = "EEE d MMM HH:mm z"
        f.timeZone = w.timeContext.instantZone
        rows.append(
          .note(
            "Fetched " + f.string(from: alerts.fetched)
              + ". Alert validity is separate from forecast-period times."))
        if alerts.alerts.isEmpty {
          rows.append(.note("No active point alerts returned at fetch time."))
        }
        for (index, alert) in alerts.alerts.enumerated() {
          rows.append(.action(alert.event, alert.severity, "weather-alert:\(index)"))
        }
        if alerts.moreAvailable {
          rows.append(
            .note("Additional provider results exist; this view is bounded to 100 messages."))
        }
      }
      rows += [
        DashboardRow.heading("Source"),
        DashboardRow.note(
          w.source == "NWS"
            ? "Weather data: NWS · https://www.weather.gov/ · Station observations and issued forecasts. Public-domain source data; Aerie is not endorsed by NOAA/NWS. Coverage and delivery vary."
            : "Weather data: Open-Meteo · CC BY 4.0 · https://open-meteo.com/ · Model-derived forecasts. Official severe alerts are not supplied by this forecast provider."
        ),
      ]
      return rows
    }
  }
}
