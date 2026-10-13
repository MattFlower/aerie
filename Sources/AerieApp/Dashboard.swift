import AerieCore
import AppKit
import EventKit

enum DashboardRow {
  case heading(String)
  case metric(String, String)
  case gauge(String, String, Double?, NSColor)
  case note(String)
  case chart(String, String, NSColor, Double?)
  case trend(String, String, [DashboardSeries])
  case facts([(String, String)])
  case coreGrid([Double], String)
  case cores([Double])
  case calendar(CalendarMonth)
  case clock(WorldClockReading, WorldClockStyle)
  case action(String, String, String)
  var height: CGFloat {
    switch self {
    case .heading: return 24
    case .metric: return 23
    case .gauge: return 54
    case .note(let text):
      let bounds = (text as NSString).boundingRect(
        with: NSSize(width: 388, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: NSFont.systemFont(ofSize: 11)])
      return max(28, ceil(bounds.height) + 12)
    case .chart: return 100
    case .trend: return 104
    case .facts(let items): return CGFloat((items.count + 1) / 2) * 32
    case .coreGrid(let values, _): return 22 + CGFloat((values.count + 11) / 12) * 28
    case .cores(let c): return CGFloat((c.count + 11) / 12) * 42 + 18
    case .calendar(let model): return CalendarMonthView.height(model)
    case .clock(_, let style): return style == .compact ? 58 : 100
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
      case .facts(let items): label = items.map { "\($0.0): \($0.1)" }.joined(separator: "; ")
      case .coreGrid(let values, let detail):
        label =
          detail + "; "
          + values.enumerated().map {
            "Core \($0.offset + 1): \(Format.percent($0.element))"
          }.joined(separator: ", ")
      case .trend(let title, let detail, let series):
        let inspected =
          selectedPoint.map { point in
            chartFormatter.dateStyle = .short; chartFormatter.timeStyle = .medium
            return " Selected " + chartFormatter.string(from: point.date) + ": "
              + series.map {
                $0.title + " "
                  + (point.values[$0.key].map { String(format: "%.2f", $0) } ?? "Unavailable")
              }.joined(separator: ", ")
          } ?? ""
        label =
          title + ": " + detail + ". History, \(points.count) samples." + inspected
          + " Activate to inspect the middle sample."
      case .metric(let k, let v), .gauge(let k, let v, _, _): label = "\(k): \(v)"
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
      case .clock(let reading, _): label = reading.accessibilityLabel
      case .calendar, .action: label = ""
      }
      let chart: Bool
      switch row {
      case .chart, .trend: chart = true;
      default: chart = false
      }
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
  private func drawClock(_ reading: WorldClockReading, style: WorldClockStyle, in rect: NSRect) {
    var x = rect.minX
    if style == .analog {
      let center = NSPoint(x: rect.minX + 43, y: rect.minY + 48), radius: CGFloat = 35
      NSColor.separatorColor.setStroke()
      let outline = NSBezierPath(
        ovalIn: NSRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      outline.lineWidth = 1; outline.stroke()
      func point(_ angle: Double, _ length: CGFloat) -> NSPoint {
        NSPoint(
          x: center.x + CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
      }
      for index in 0..<12 {
        let angle = Double(index) / 12 * 2 * .pi
        let tick = NSBezierPath(); tick.move(to: point(angle, radius - 3));
        tick.line(to: point(angle, radius - (index % 3 == 0 ? 8 : 5))); tick.stroke()
      }
      for (angle, length, width, color) in [
        (reading.hourAngle, CGFloat(19), CGFloat(3), NSColor.labelColor),
        (reading.minuteAngle, CGFloat(28), CGFloat(2), NSColor.labelColor),
        (reading.secondAngle, CGFloat(30), CGFloat(1), AeriePalette.cpu),
      ] {
        color.setStroke(); let hand = NSBezierPath(); hand.lineWidth = width;
        hand.lineCapStyle = .round
        hand.move(to: center); hand.line(to: point(angle, length)); hand.stroke()
      }
      NSColor.labelColor.setFill();
      NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
      x += 95
    }
    let width = rect.maxX - x
    drawText(
      reading.name,
      rect: NSRect(
        x: x, y: rect.minY + 6, width: style == .compact ? min(120, width) : width, height: 19),
      font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
    if style == .compact {
      drawText(
        reading.time,
        rect: NSRect(x: x + 130, y: rect.minY + 5, width: max(0, width - 130), height: 24),
        font: .monospacedDigitSystemFont(ofSize: 16, weight: .medium), color: .labelColor,
        alignment: .right)
      drawText(
        reading.date + " · " + reading.offset + " · " + reading.day,
        rect: NSRect(x: x, y: rect.minY + 30, width: width, height: 17),
        font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    } else {
      drawText(
        reading.time, rect: NSRect(x: x, y: rect.minY + 27, width: width, height: 35),
        font: .monospacedDigitSystemFont(ofSize: style == .large ? 28 : 23, weight: .regular),
        color: .labelColor)
      drawText(
        reading.date + " · " + reading.day,
        rect: NSRect(x: x, y: rect.minY + 65, width: width, height: 15),
        font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
      drawText(
        reading.offset + " · " + reading.zone,
        rect: NSRect(x: x, y: rect.minY + 81, width: width, height: 15),
        font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
    }
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
      case .trend(let title, let detail, let series):
        drawCompactTrend(
          title, detail: detail, series: series, points: points,
          selected: selectedPoint, interval: expectedInterval, formatter: chartFormatter, in: rect)
      case .facts(let items): drawCompactFacts(items, in: rect)
      case .coreGrid(let values, let detail): drawCompactCores(values, detail: detail, in: rect)
      case .heading(let title):
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 14, y: y + 1))
        line.line(to: NSPoint(x: bounds.width - 14, y: y + 1))
        line.stroke()
        drawText(
          title, rect: rect.insetBy(dx: 0, dy: 5),
          font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
      case .metric(let key, let value):
        drawText(
          key, rect: NSRect(x: 14, y: y + 5, width: 165, height: 20), font: .systemFont(ofSize: 12),
          color: .labelColor)
        drawText(
          value, rect: NSRect(x: 174, y: y + 5, width: bounds.width - 188, height: 20),
          font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: .labelColor,
          alignment: .right)
      case .gauge(let key, let value, let fraction, let color):
        drawText(
          key, rect: NSRect(x: 14, y: y + 4, width: 180, height: 20), font: .systemFont(ofSize: 12),
          color: .labelColor)
        drawText(
          value, rect: NSRect(x: 174, y: y + 4, width: bounds.width - 188, height: 20),
          font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: .labelColor,
          alignment: .right)
        let track = NSRect(x: 14, y: y + 30, width: max(1, bounds.width - 28), height: 8)
        NSColor.quaternaryLabelColor.setFill();
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        if let fraction, fraction.isFinite {
          var fill = track; fill.size.width *= CGFloat(max(0, min(1, fraction)))
          color.setFill(); NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()
        } else {
          let unavailable = NSBezierPath();
          unavailable.move(to: NSPoint(x: track.midX - 12, y: track.midY));
          unavailable.line(to: NSPoint(x: track.midX + 12, y: track.midY))
          NSColor.secondaryLabelColor.setStroke(); unavailable.lineWidth = 2; unavailable.stroke()
        }
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
      case .clock(let reading, let style): drawClock(reading, style: style, in: rect)
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
      switch row {
      case .chart: return point.y >= y + 31 && point.y <= y + 83
      case .trend: return point.y >= y + 37 && point.y <= y + 87
      default: return false
      }
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
  private let historyButton = NSButton(title: "History…", target: nil, action: nil)
  private let exportButton = NSButton(title: "Export…", target: nil, action: nil)
  private(set) var historyExpanded = false
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
  private var presentationReleased = false
  var isPresentationLoaded: Bool { isViewLoaded && !presentationReleased }
  /// Release the native scroll hierarchy between presentations while retaining selection state.
  func releasePresentation() {
    guard isPresentationLoaded else { return }
    canvas.releaseInteractiveRows()
    canvas.enclosingScrollView?.documentView = nil
    view = NSView(frame: .zero)
    presentationReleased = true
  }
  override func loadView() {
    presentationReleased = false
    view = NSView(frame: NSRect(x: 0, y: 0, width: 416, height: 600))
    modules.removeAllItems()
    modules.addItems(withTitles: Module.allCases.map(\.title))
    modules.target = self; modules.action = #selector(selectModule)
    modules.frame = NSRect(x: 54, y: 568, width: 216, height: 26)
    modules.setAccessibilityLabel("Detail module")
    view.addSubview(modules)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 34, width: 416, height: 530))
    scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.documentView = canvas; scroll.drawsBackground = false
    view.addSubview(scroll)
    let selectedZoom = max(0, zoomPicker.indexOfSelectedItem)
    zoomPicker.removeAllItems()
    zoomPicker.addItems(withTitles: ["Full range", "Zoom 2×", "Zoom 4×", "Zoom 8×"])
    zoomPicker.selectItem(at: selectedZoom)
    zoomPicker.frame = NSRect(x: 14, y: 42, width: 105, height: 26)
    zoomPicker.target = self; zoomPicker.action = #selector(changeZoom)
    zoomPicker.setAccessibilityLabel("History zoom")
    historyPosition.frame = NSRect(x: 124, y: 44, width: 130, height: 22)
    historyPosition.target = self; historyPosition.action = #selector(changeZoom)
    historyPosition.isContinuous = true
    historyPosition.setAccessibilityLabel("History position, oldest to latest")
    historyPosition.toolTip = "Pan from oldest to latest; the right edge follows new readings."
    zoomReset.frame = NSRect(x: 258, y: 42, width: 60, height: 26)
    zoomReset.target = self; zoomReset.action = #selector(resetZoom)
    exportButton.frame = NSRect(x: 320, y: 42, width: 82, height: 26)
    exportButton.target = self; exportButton.action = #selector(exportHistory)
    exportButton.toolTip = "Export the selected retained system history as CSV"
    [zoomPicker, historyPosition, zoomReset, exportButton].forEach { view.addSubview($0) }
    let settingsButton = NSButton(title: "Settings…", target: self, action: #selector(openSettings))
    settingsButton.frame = NSRect(x: 10, y: 4, width: 85, height: 26)
    view.addSubview(settingsButton)
    let selectedWindow = max(0, windowPicker.indexOfSelectedItem)
    windowPicker.removeAllItems()
    windowPicker.addItems(withTitles: ["10 minutes", "24 hours", "7 days"])
    windowPicker.selectItem(at: selectedWindow)
    windowPicker.frame = NSRect(x: 275, y: 568, width: 127, height: 26)
    windowPicker.target = self; windowPicker.action = #selector(changeWindow)
    windowPicker.setAccessibilityLabel("History range")
    view.addSubview(windowPicker)
    mapsButton.frame = NSRect(x: 100, y: 4, width: 108, height: 26)
    mapsButton.target = self; mapsButton.action = #selector(openMaps); mapsButton.isHidden = true
    view.addSubview(mapsButton)
    historyButton.frame = NSRect(x: 100, y: 4, width: 108, height: 26)
    historyButton.target = self; historyButton.action = #selector(toggleHistory)
    historyButton.setAccessibilityLabel("Show history tools: zoom, pan, reset and export")
    view.addSubview(historyButton)
    stateLabel.font = .systemFont(ofSize: 10); stateLabel.textColor = .secondaryLabelColor
    stateLabel.alignment = .right
    stateLabel.frame = NSRect(x: 214, y: 9, width: 188, height: 16)
    view.addSubview(stateLabel)
    setHistoryExpanded(historyExpanded)
  }
  @objc private func toggleHistory() { setHistoryExpanded(!historyExpanded) }
  func setHistoryExpanded(_ expanded: Bool) {
    historyExpanded = expanded
    historyButton.title = expanded ? "Hide Tools" : "History…"
    historyButton.setAccessibilityLabel(
      expanded ? "Hide history tools" : "Show history tools: zoom, pan, reset and export")
    let supported = module != .weather && module != .time && module != .sensors
    [zoomPicker, historyPosition, zoomReset, exportButton].forEach {
      $0.isHidden = !expanded || !supported
    }
    canvas.enclosingScrollView?.frame = NSRect(
      x: 0, y: expanded && supported ? 78 : 34,
      width: 416, height: expanded && supported ? 486 : 530)
  }

  @objc private func selectModule() {
    canvas.selectedPoint = nil; setHistoryExpanded(false)
    module = Module.allCases[modules.indexOfSelectedItem]
    view.window?.setAccessibilityLabel("Aerie \(module.title) detail")
    onModule?(module)
    refresh()
    traceRenderedModule()
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
    if presentationReleased { loadView() } else { _ = view }
    if module != .time { releaseDaylight() }
    let changed = self.module != module
    self.module = module
    if changed {
      canvas.selectedPoint = nil; setHistoryExpanded(false)
      canvas.enclosingScrollView?.contentView.scroll(to: .zero)
    }
    modules.selectItem(at: Module.allCases.firstIndex(of: module) ?? 0)
    refresh()
    traceRenderedModule()
  }
  private func traceRenderedModule() {
    let index = modules.indexOfSelectedItem
    let picker = Module.allCases.indices.contains(index) ? Module.allCases[index] : nil
    MenuRoutingTrace.rendered(
      module, picker: picker, metrics: MenuRoutingTrace.metrics(in: canvas.rows))
  }
  func refresh() {
    guard isPresentationLoaded else { return }
    let hasHistory = module != .weather && module != .time && module != .sensors
    mapsButton.isHidden = module != .weather; windowPicker.isHidden = !hasHistory
    historyButton.isHidden = !hasHistory
    setHistoryExpanded(historyExpanded)
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
  private func gpuSummaryRows() -> [DashboardRow] {
    guard !snapshot.gpu.isEmpty else {
      return [.heading("GPU"), .metric("Driver telemetry", "Unavailable")]
    }
    return snapshot.gpu.flatMap { gpu in
      [
        DashboardRow.heading("GPU · " + gpu.name),
        .facts([
          ("Utilization", Format.percent(gpu.utilization)),
          ("Renderer / tiler", Format.percent(gpu.renderer) + " / " + Format.percent(gpu.tiler)),
          ("In-use shared memory", gpu.memory.map { self.bytes($0) } ?? "Unavailable"),
        ]),
      ]
    }
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
      let processes = top({ ($0.cpu ?? 0) > ($1.cpu ?? 0) }, value: { Format.percent($0.cpu) })
      let primaryCount = min(5, processes.count)
      let groups = s.cpu.groups.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
      var rows: [DashboardRow] = [
        .trend(
          "CPU " + Format.percent(s.cpu.total),
          "User " + Format.percent(s.cpu.user) + " · System " + Format.percent(s.cpu.system),
          [DashboardSeries(key: "cpu", title: "CPU %", color: AeriePalette.cpu, maximum: 100)]),
        .coreGrid(
          s.cpu.cores, "\(s.cpu.cores.count) logical cores" + (groups.isEmpty ? "" : " · " + groups)
        ),
        .heading("Top CPU processes"),
      ]
      rows += processes.prefix(primaryCount)
      rows += gpuSummaryRows()
      rows.append(
        .facts([
          (
            "Load · 1 / 5 / 15 min",
            s.cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " / ")
          ),
          ("Uptime", Format.duration(s.cpu.uptime)),
        ]))
      rows += [
        .heading("Processor details"),
        .metric(
          "Nominal frequency",
          s.cpu.frequency.map { String(format: "%.2f GHz", $0) } ?? "Unavailable"),
      ]
      if processes.count > primaryCount {
        rows += [.heading("Process accounting")] + processes.dropFirst(primaryCount)
      }
      rows += clockRows(kinds: [.cpuComplex, .cpuCore])
      rows.append(
        .note(
          "Logical-core indicators show scheduler load. Clock-state residency is separate hardware activity; system channel names do not prove physical core roles. GHz requires named frequency states."
        ))
      return rows
    case .gpu:
      var rows: [DashboardRow] = [
        .trend(
          "GPU " + Format.percent(s.gpu.first?.utilization),
          s.gpu.first?.name ?? "Driver telemetry unavailable",
          [DashboardSeries(key: "gpu", title: "GPU %", color: AeriePalette.cpu, maximum: 100)])
      ]
      for gpu in s.gpu {
        var facts: [(String, String)] = [
          ("Renderer", Format.percent(gpu.renderer)), ("Tiler", Format.percent(gpu.tiler)),
          ("Utilization", Format.percent(gpu.utilization)),
          ("In-use shared memory", gpu.memory.map { self.bytes($0) } ?? "Unavailable"),
        ]
        if let value = gpu.temperature {
          facts.append(("Temperature", Format.temperature(value, unit: settings.temperature)))
        }
        if let value = gpu.frequency {
          facts.append(("Frequency", String(format: "%.2f GHz", value)))
        }
        if let value = gpu.fps { facts.append(("Frame rate", String(format: "%.0f FPS", value))) }
        rows += [.heading(gpu.name), .facts(facts)]
      }
      rows += [
        .heading("CPU context"),
        .facts([
          ("CPU total", Format.percent(s.cpu.total)),
          ("User / system", Format.percent(s.cpu.user) + " / " + Format.percent(s.cpu.system)),
          (
            "Load · 1 / 5 / 15 min",
            s.cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " / ")
          ),
          ("Uptime", Format.duration(s.cpu.uptime)),
        ]), .heading("Advanced GPU telemetry"),
      ]
      rows += clockRows(kinds: [.gpu])
      rows.append(
        .note(
          "Optional temperature, frequency and frame-rate fields appear only when the driver exposes them. Global FPS and per-process GPU utilization remain unavailable without a supported source."
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
        .trend(
          "Memory " + Format.percent(m.usedFraction),
          "Pressure " + m.pressure + " · " + bytes(m.total) + " physical",
          [
            DashboardSeries(
              key: "memory", title: "Memory %", color: AeriePalette.memory, maximum: 100)
          ]),
        .facts([
          ("App", bytes(m.app)), ("Wired", bytes(m.wired)), ("Compressed", bytes(m.compressed)),
          ("File cache", bytes(m.cached)),
        ]),
        .heading("Top memory processes"),
      ] + top({ $0.memory > $1.memory }, value: { bytes($0.memory) }) + [
        .heading("Memory details"),
        .facts([
          ("Physical", bytes(m.total)), ("Free", bytes(m.free)), ("Purgeable", bytes(m.purgeable)),
          ("Swap", bytes(m.swap) + " / " + bytes(m.swapTotal)),
        ]),
        .heading("Virtual memory activity"),
        .facts([
          ("Page in", rate(m.pageIn)), ("Page out", rate(m.pageOut)), ("Swap in", rate(m.swapIn)),
          ("Swap out", rate(m.swapOut)),
        ]),
      ]
    case .storage:
      let ioRows = top(
        { left, right in
          let leftBytes = (left.read ?? 0) + (left.write ?? 0)
          let rightBytes = (right.read ?? 0) + (right.write ?? 0)
          return leftBytes > rightBytes
        }, value: { process in "R \(rate(process.read))  W \(rate(process.write))" })
      var rows: [DashboardRow] = [
        .trend(
          "Disk activity", "↓ Read " + rate(s.diskRead) + " · ↑ Write " + rate(s.diskWrite),
          [
            DashboardSeries(
              key: "diskRead", title: "Read B/s", color: AeriePalette.incoming, maximum: nil),
            DashboardSeries(
              key: "diskWrite", title: "Write B/s", color: AeriePalette.outgoing, maximum: nil),
          ])
      ]
      if let volume = s.volumes.first {
        rows += [
          .heading(volume.name),
          .facts([
            ("Capacity", bytes(volume.total)), ("Available", bytes(volume.free)),
            ("Used", volume.total > 0 ? Format.percent(volume.usedFraction) : "Unavailable"),
          ]),
        ]
      }
      rows += [.heading("Top process I/O")] + ioRows
      rows.append(.heading("Volume details"))
      for v in s.volumes {
        rows += [
          DashboardRow.heading(v.name), DashboardRow.metric("Capacity", bytes(v.total)),
          DashboardRow.metric("Available", bytes(v.free)),
          DashboardRow.gauge(
            "Used", v.total > 0 ? Format.percent(v.usedFraction) : "Unavailable",
            v.total > 0 ? v.usedFraction : nil, AeriePalette.memory),
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
      rows.append(
        .note(
          "Disk rates are physical-device totals; process I/O uses OS accounting. Per-device association uses native whole-media registry records and read-only OS/APFS metadata; unassociated sources remain explicit. No drive scan, repair, device write or elevated helper is performed."
        ))
      return rows
    case .network:
      var rows: [DashboardRow] = [
        .trend(
          "Network traffic",
          "↓ " + rate(s.download, domain: .network) + " · ↑ " + rate(s.upload, domain: .network),
          [
            DashboardSeries(
              key: "download", title: "↓ B/s", color: AeriePalette.incoming, maximum: nil),
            DashboardSeries(
              key: "upload", title: "↑ B/s", color: AeriePalette.outgoing, maximum: nil),
          ]),
        .facts([
          ("Connectivity", s.connectivity), ("Aggregate scope", s.networkSelection.description),
        ]),
      ]
      rows.append(.heading("Process traffic"))
      let networkOrder = settings.processSorts?[.network] ?? .automatic
      let sortedProcesses = ProcessPresentation.network(
        s.networkProcesses, groups: s.networkProcessGroups,
        enabled: settings.effectiveCombineProcesses, sort: networkOrder)
      if sortedProcesses.isEmpty {
        rows.append(.metric("Process traffic", "Waiting for OS reading"))
      }
      for process in sortedProcesses.prefix(settings.processCount) {
        let title = process.members > 1 ? process.name : "\(process.name) · \(process.pid)"
        let incoming = rate(process.download, domain: .network)
        let outgoing = rate(process.upload, domain: .network)
        rows.append(.metric(title, "↓ \(incoming)  ↑ \(outgoing)"))
      }
      var processNotes: [DashboardRow] = [.note(s.processNetworkStatus)]
      if settings.effectiveCombineProcesses {
        let missing = s.networkProcesses.filter {
          s.networkProcessGroups[ProcessIdentity(pid: Int($0.pid), startTime: $0.startTime)] == nil
        }.count
        processNotes.append(
          .note(
            "Combined by application bundle or executable. \(missing) readable traffic identities stay separate. Group rates require every member's baseline."
          ))
      }
      if networkOrder != .automatic {
        processNotes.append(.note("Process order: " + networkOrder.title))
      }
      processNotes.append(
        .note(
          "Process totals cover OS-reported TCP/UDP activity across interfaces, including loopback; they use independent process-start baselines and do not follow the aggregate interface filter. Protected, missing or reset readings have unavailable rates. The app owns one OS logger only while this panel is visible."
        ))
      processNotes.append(
        .note(
          s.networkSelection.description
            + ". Collection includes every reported interface; aggregate rates require every selected active interface baseline."
        ))
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
      rows += [.heading("Traffic accounting")] + processNotes
      rows.append(
        DashboardRow.note(
          "Virtual tunnels may count the same traffic again. Choose aggregate interfaces in Network Settings; all interfaces remain sampled and displayed. Observed sessions rebase after unavailable/reset/disappearing counters."
        ))
      return rows
    case .sensors:
      let primary = s.sensors.filter { $0.unit == "°C" && $0.state == .live && $0.value != nil }.max
      {
        ($0.value ?? 0) < ($1.value ?? 0)
      }
      var rows: [DashboardRow] = [.heading("Menu temperature · highest live reading")]
      if let primary {
        let value =
          primary.state == .live
          ? primary.value.map {
            primary.unit == "°C"
              ? Format.temperature($0, unit: settings.temperature)
              : String(format: "%.1f %@", $0, primary.unit)
          } : nil
        rows.append(
          .metric(
            primary.title(names: settings.sensorNames),
            value ?? (primary.state == .deferred ? "Waiting for live read" : "Unavailable")))
      } else {
        rows.append(.metric("Temperature source", "Unavailable"))
      }
      rows.append(.metric("Thermal state", s.thermal))
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
        .note(s.sensorStatus),
        .note(
          settings.effectiveSensorSampling == .all
            ? "All supported sensors are sampled at the selected system interval."
            : "On-demand sampling keeps temperatures and enabled individual-rule sensors live; other readings wait until this panel opens."
        ),
      ]
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
          .trend(
            "Charge " + Format.percent(p.percent),
            p.sourceLabel + " · "
              + (p.charging.map { $0 ? "Charging" : "Not charging" } ?? "Charging unavailable"),
            [
              DashboardSeries(
                key: "battery", title: "Battery %", color: AeriePalette.power, maximum: 100)
            ]),
          .facts([
            ("Health", Format.percent(p.health)),
            ("Cycles", p.cycles.map { String($0) } ?? "Unavailable"),
            (
              p.charging == true ? "Time to full" : "Time remaining",
              Format.powerTime(
                p.minutes, charging: p.charging,
                input: p.external.map { $0 ? .ac : .battery } ?? .unknown)
            ),
            ("Battery power", p.watts.map { String(format: "%.2f W", $0) } ?? "Unavailable"),
          ]),
          .heading("Electrical details"),
          .facts([
            ("Voltage", p.voltage.map { String(format: "%.2f V", $0) } ?? "Unavailable"),
            ("Current", p.amperage.map { String(format: "%.2f A", $0) } ?? "Unavailable"),
          ]),
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
      LocalClockFormat.configure(formatter, pattern: settings.clockFormat)
      var rows: [DashboardRow] =
        [
          DashboardRow.heading("Local time"),
          DashboardRow.metric(
            formatter.string(from: now), TimeZone.current.abbreviation() ?? "Local"),
          DashboardRow.heading("Calendar"),
        ] + calendarRows + [
          DashboardRow.heading("World clocks")
        ]
      for reading in ClockPresentation.readings(
        settings.clocks, at: now, order: settings.worldClockOrder ?? .manual)
      {
        rows.append(.clock(reading, settings.worldClockStyle ?? .compact))
        if let zone = TimeZone(identifier: reading.zone),
          let next = zone.nextDaylightSavingTimeTransition(after: now)
        {
          let f = DateFormatter(); f.dateStyle = .medium; f.timeZone = zone
          rows.append(.metric("Next daylight saving change", f.string(from: next)))
        }
      }
      rows += [
        .heading("Astronomical estimates"),
        .facts([
          ("Moon phase (approx.)", Astronomy.moonName(at: now)),
          ("Lunar age", String(format: "%.1f days", Astronomy.moonAge(at: now))),
        ]),
      ]
      rows += daylightRows(now: now)
      return rows
    case .weather:
      guard settings.weather.valid else {
        return [
          DashboardRow.heading("Weather is off"),
          DashboardRow.note(
            "Choose a provider and location in Weather Settings, then enable forecasts. Enter coordinates manually, find a city or ZIP, or explicitly choose one Mac location. Choosing a location alone does not enable forecasts or maps."
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
      rows += [
        .facts([
          ("Conditions", w.condition ?? WeatherCondition.describe(w.code)),
          (
            "Temperature",
            w.temperature.map { Format.temperature($0, unit: settings.temperature) }
              ?? "Unavailable"
          ),
          (
            "Feels like",
            w.apparent.map { Format.temperature($0, unit: settings.temperature) } ?? "Unavailable"
          ),
          ("Humidity", w.humidity.map { String(format: "%.0f%%", $0) } ?? "Unavailable"),
        ])
      ]
      if let alerts = w.alertReport {
        rows.append(.metric("Alert refresh", f.string(from: alerts.fetched)))
      }
      if let alerts = w.alertReport, !alerts.alerts.isEmpty {
        rows.append(.heading("Current point alerts"))
        for (index, alert) in alerts.alerts.enumerated() {
          rows.append(.action(alert.event, alert.severity, "weather-alert:\(index)"))
        }
      }
      rows.append(.heading("Hourly forecast"))
      f.dateFormat = "EEE HH:mm"
      let hours = HourlyForecastPresentation.indices(
        w.hours, at: Date(), limit: settings.effectiveHourlyForecastHours)
      if hours.isEmpty { rows.append(.note("No current or upcoming hourly forecast returned.")) }
      for index in hours {
        let h = w.hours[index]
        let chance = h.precipitation.map { String(format: "%.0f%% precipitation", $0) } ?? ""
        rows.append(
          .action(
            f.string(from: h.date),
            (h.temperature.map { Format.temperature($0, unit: settings.temperature) }
              ?? "Unavailable") + "  " + chance, "weather-hour:\(index)"))
        rows.append(
          .note(
            (h.condition ?? WeatherCondition.describe(h.code))
              + (h.windDescription.map { $0.isEmpty ? "" : " · " + $0 } ?? "")))
      }
      rows.append(
        .note(
          "Showing \(hours.count) cached hourly periods, up to \(settings.effectiveHourlyForecastHours). Select an hour for available wind, humidity, precipitation and other details. No extra requests are made."
        ))
      rows.append(.heading("Observation details"))
      f.dateFormat = "EEE d MMM HH:mm z"
      if let station = w.observationStation { rows.append(.metric("Observation station", station)) }
      if let time = w.observationTime {
        rows.append(.metric("Observation time", f.string(from: time)))
      }
      if let time = w.forecastUpdated {
        rows.append(.metric("Forecast updated", f.string(from: time)))
      }
      for note in w.notes { rows.append(.note(note)) }
      rows += [
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
      ]
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
