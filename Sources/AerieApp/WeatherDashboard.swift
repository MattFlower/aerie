import AerieCore
import AppKit

final class WeatherDashboardPresentation {
  struct Input: Equatable {
    let report: WeatherReport
    let name, status: String
    let unit: TemperatureUnit
    let limit: Int
    let hourIndices, activePeriods: [Int]
    let forecastDay, dailyDay: Date
    init(
      report: WeatherReport, name: String, status: String, unit: TemperatureUnit, limit: Int,
      now: Date
    ) {
      self.report = report; self.name = name; self.status = status; self.unit = unit;
      self.limit = limit
      hourIndices = HourlyForecastPresentation.indices(report.hours, at: now, limit: limit)
      activePeriods = report.periods.indices.filter { report.periods[$0].end > now }
      var calendar = Calendar(identifier: .gregorian);
      calendar.timeZone = report.timeContext.instantZone
      forecastDay = calendar.startOfDay(for: now)
      calendar.timeZone = report.timeContext.dailyZone; dailyDay = calendar.startOfDay(for: now)
    }
  }
  struct Hour {
    let identifier, time, temperature, chance, symbol, accessibility: String
    let wet: Bool
    let night: Bool
  }
  struct Day {
    let identifier, title, summary, temperatures, chance, symbol, accessibility: String
    let low, high: Double?
    let basis: WeatherOutlookBasis
    let wet: Bool
  }
  struct Alert {
    let identifier, title, detail: String
  }
  let name, temperature, unit, condition, symbol, status, source, currentAccessibility: String
  let fields: [(String, String)]
  let hours: [Hour]
  let days: [Day]
  let alerts: [Alert]
  let statusWarning: Bool
  let night: Bool
  static let currentHeight: CGFloat = 154
  static let hourlyHeight: CGFloat = 122
  static let dayHeadingHeight: CGFloat = 22
  static let dayHeight: CGFloat = 42
  static let alertHeight: CGFloat = 32
  static let hourWidth: CGFloat = 54
  var hourSectionHeight: CGFloat { hours.isEmpty ? 32 : Self.hourlyHeight }
  var height: CGFloat {
    Self.currentHeight + hourSectionHeight + Self.dayHeadingHeight
      + CGFloat(max(1, days.count)) * Self.dayHeight + CGFloat(alerts.count) * Self.alertHeight
  }

  init(
    report: WeatherReport, name: String, status: String, unit: TemperatureUnit, limit: Int,
    now: Date
  ) {
    self.name = name
    temperature = Self.degrees(report.temperature, unit: unit)
    self.unit = unit == .fahrenheit ? "°F" : "°C"
    condition = report.condition ?? WeatherCondition.describe(report.code)
    symbol = MenuRenderer.weatherSymbol(
      code: report.code, daylight: report.isDay, glyph: report.glyph)
    self.status = status
    statusWarning = status != "Fetching forecast" && !status.hasPrefix("Updated ")
    source = report.source == "NWS" ? "NWS · Public-domain data" : "Open-Meteo · CC BY 4.0"
    night = report.isDay == false
    fields = [
      ("Feels like", Self.degrees(report.apparent, unit: unit)),
      ("Humidity", Self.number(report.humidity, suffix: "%", range: 0...100)),
      ("Wind", Self.number(report.wind, suffix: " km/h", range: 0...1e12)),
      ("Gusts", Self.number(report.gusts, suffix: " km/h", range: 0...1e12)),
      ("Pressure", Self.number(report.pressure, suffix: " hPa", range: 0.0001...1e12)),
      ("Cloud cover", Self.number(report.cloud, suffix: "%", range: 0...100)),
    ]
    currentAccessibility = name + ". " + Self.currentMessage(report, status: status, unit: unit)
    let formatter = DateFormatter()
    formatter.timeZone = report.timeContext.instantZone; formatter.dateFormat = "ha"
    hours = HourlyForecastPresentation.indices(report.hours, at: now, limit: limit).map { index in
      let hour = report.hours[index]
      let chance = Self.number(hour.precipitation, suffix: "%", range: 0...100)
      let daylight = WeatherOutlookPresentation.daylight(hour, report: report)
      let precise = HourlyForecastPresentation.fields(
        hour, zone: report.timeContext.instantZone, temperature: unit
      )
      .filter {
        [
          "Forecast instant", "Valid from", "Conditions", "Temperature",
          "Precipitation probability", "Precipitation / gust timing",
        ].contains($0.0)
      }
      .map { $0.0 + ": " + $0.1 }.joined(separator: ". ")
      return Hour(
        identifier: "weather-hour:\(index)", time: formatter.string(from: hour.date).lowercased(),
        temperature: Self.degrees(hour.temperature, unit: unit), chance: chance,
        symbol: MenuRenderer.weatherSymbol(code: hour.code, daylight: daylight, glyph: hour.glyph),
        accessibility: precise + ". Show all cached details.",
        wet: (hour.precipitation ?? -1) >= 20,
        night: daylight == false)
    }
    days = WeatherOutlookPresentation.outlooks(report, at: now).map { outlook in
      let temperatures =
        Self.degrees(outlook.high, unit: unit) + " / " + Self.degrees(outlook.low, unit: unit)
      let summary = (outlook.qualification.map { $0 + " · " } ?? "") + outlook.summary
      return Day(
        identifier: outlook.identifier, title: outlook.title, summary: summary,
        temperatures: temperatures,
        chance: Self.number(outlook.precipitation, suffix: "%", range: 0...100),
        symbol: MenuRenderer.weatherSymbol(
          code: outlook.code, daylight: outlook.isDay, glyph: outlook.glyph),
        accessibility: outlook.title + ". "
          + WeatherOutlookPresentation.message(outlook, report: report, temperature: unit),
        low: outlook.low, high: outlook.high, basis: outlook.basis,
        wet: (outlook.precipitation ?? -1) >= 20)
    }
    alerts = (report.alertReport?.alerts ?? []).enumerated().map {
      Alert(
        identifier: "weather-alert:\($0.offset)", title: $0.element.event,
        detail: $0.element.severity)
    }
  }
  static func degrees(_ value: Double?, unit: TemperatureUnit) -> String {
    guard let value, value.isFinite else { return "—" }
    let degrees = unit == .fahrenheit ? value * 1.8 + 32 : value
    guard degrees.isFinite else { return "—" }
    return String(format: "%.0f°", degrees.rounded() == 0 ? 0 : degrees)
  }
  static func number(_ value: Double?, suffix: String, range: ClosedRange<Double>) -> String {
    guard let value, value.isFinite, range.contains(value) else { return "—" }
    return String(format: "%.0f", value) + suffix
  }
  static func currentMessage(_ report: WeatherReport, status: String, unit: TemperatureUnit)
    -> String
  {
    func number(_ value: Double?, suffix: String, range: ClosedRange<Double>) -> String {
      guard let value, value.isFinite, range.contains(value) else { return "Unavailable" }
      return String(format: "%.1f", value) + suffix
    }
    func temperature(_ value: Double?) -> String {
      value.flatMap { $0.isFinite ? Format.temperature($0, unit: unit) : nil } ?? "Unavailable"
    }
    let formatter = DateFormatter(); formatter.timeZone = report.timeContext.instantZone
    formatter.dateStyle = .medium; formatter.timeStyle = .short
    var lines = [
      status, "Conditions: " + (report.condition ?? WeatherCondition.describe(report.code)),
      "Temperature: " + temperature(report.temperature),
      "Feels like: " + temperature(report.apparent),
      "Humidity: " + number(report.humidity, suffix: "%", range: 0...100),
      "Wind: " + number(report.wind, suffix: " km/h", range: 0...1e12),
      "Gusts: " + number(report.gusts, suffix: " km/h", range: 0...1e12),
      "Wind direction: " + number(report.direction, suffix: "°", range: 0...360),
      "Surface pressure: " + number(report.pressure, suffix: " hPa", range: 0.0001...1e12),
      "Cloud cover: " + number(report.cloud, suffix: "%", range: 0...100),
      "Current dew point, UV index and visibility: not supplied by the current-condition source. Available forecast values appear in individual hourly details.",
    ]
    if let station = report.observationStation { lines.append("Observation station: " + station) }
    if let date = report.observationTime {
      lines.append("Observation time: " + formatter.string(from: date))
    }
    if let date = report.forecastUpdated {
      lines.append("Forecast updated: " + formatter.string(from: date))
    }
    lines += report.notes + report.alerts
    if let alerts = report.alertReport {
      lines.append("Point alerts fetched: " + formatter.string(from: alerts.fetched))
      lines.append("Alert validity is separate from forecast-period times.")
      if alerts.alerts.isEmpty { lines.append("No active point alerts returned at fetch time.") }
      if alerts.moreAvailable {
        lines.append("Additional provider results exist; this view is bounded to 100 messages.")
      }
    }
    lines += [
      report.timeContext.description,
      report.source == "NWS"
        ? "Weather data: NWS · https://www.weather.gov/ · Station observations and issued forecasts. Public-domain source data; Aerie is not endorsed by NOAA/NWS. Coverage and delivery vary."
        : "Weather data: Open-Meteo · CC BY 4.0 · https://open-meteo.com/ · Model-derived forecasts. Official severe alerts are not supplied by this forecast provider.",
      "Fetched: " + formatter.string(from: report.fetched),
      "Unavailable fields were not supplied or are invalid. This view uses cached forecasts; opening it makes no new requests.",
    ]
    return lines.joined(separator: "\n")
  }
}

private enum WeatherDrawing {
  static let rain = NSColor.systemBlue
  static let sunshine = NSColor.systemOrange
  static let night = NSColor.systemIndigo
  static func accent(symbol: String, night: Bool = false) -> NSColor {
    if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("snow") {
      return rain
    }
    if night || symbol.contains("moon") { return self.night }
    if symbol.contains("sun") { return sunshine }
    return .secondaryLabelColor
  }
  static func symbol(_ name: String, in rect: NSRect, color: NSColor) {
    guard
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    else { return }
    image.draw(
      in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
  }
  static func text(
    _ text: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor, alignment: NSTextAlignment = .left, wrap: Bool = false
  ) {
    drawText(
      text, rect: rect, font: .systemFont(ofSize: size, weight: weight), color: color,
      alignment: alignment, wrap: wrap)
  }
}

final class WeatherForecastButton: NSButton {
  var actionIdentifier = ""
  var render: ((NSRect) -> Void)?
  override var isFlipped: Bool { true }
  override func accessibilityPerformPress() -> Bool {
    guard isEnabled, let action else { return false }
    return sendAction(action, to: target)
  }
  override func draw(_ dirtyRect: NSRect) {
    render?(bounds)
    if isHighlighted || window?.firstResponder === self {
      NSColor.keyboardFocusIndicatorColor.setStroke()
      let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
      path.lineWidth = 2; path.stroke()
    }
  }
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { scrollToVisible(bounds); needsDisplay = true }
    return accepted
  }
  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted
  }
}

private final class WeatherHourlyDocument: NSView {
  override var isFlipped: Bool { true }
}

final class WeatherDashboardView: NSView {
  private let hourlyScroll = NSScrollView()
  private let hourlyDocument = WeatherHourlyDocument()
  private var buttons: [String: WeatherForecastButton] = [:]
  private var labels: [String: NSTextField] = [:]
  private(set) var presentation: WeatherDashboardPresentation?
  var onAction: ((String) -> Void)?
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.group);
    setAccessibilityLabel("Weather outlook")
    hourlyScroll.hasHorizontalScroller = true; hourlyScroll.hasVerticalScroller = false
    hourlyScroll.autohidesScrollers = true; hourlyScroll.drawsBackground = false
    hourlyScroll.documentView = hourlyDocument; addSubview(hourlyScroll)
    hourlyScroll.setAccessibilityLabel("Hourly forecast, scroll horizontally for more cached hours")
  }
  override var isOpaque: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill(); dirtyRect.intersection(bounds).fill()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func label(_ key: String, text: String, frame: NSRect) -> NSTextField {
    let label = labels[key] ?? NSTextField(labelWithString: "")
    labels[key] = label; label.stringValue = text; label.frame = frame
    label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = .secondaryLabelColor
    if label.superview == nil { addSubview(label) }
    return label
  }
  private func button(
    _ identifier: String, accessibility: String, frame: NSRect, parent: NSView? = nil,
    render: @escaping (NSRect) -> Void
  ) -> WeatherForecastButton {
    let button =
      buttons[identifier]
      ?? WeatherForecastButton(title: "", target: self, action: #selector(activate(_:)))
    buttons[identifier] = button; button.actionIdentifier = identifier; button.frame = frame
    button.isBordered = false; button.title = ""; button.render = render;
    button.focusRingType = .none
    button.setAccessibilityLabel(accessibility); button.toolTip = accessibility
    let parent = parent ?? self
    if button.superview !== parent { button.removeFromSuperview(); parent.addSubview(button) }
    return button
  }
  @objc private func activate(_ sender: WeatherForecastButton) {
    onAction?(sender.actionIdentifier)
  }
  /// Native controls can survive removal until AppKit drains autoreleased objects.
  /// Clear copied forecast payloads immediately, independent of native view lifetime.
  func releasePresentation() {
    presentation = nil; onAction = nil
    for button in buttons.values {
      button.render = nil; button.toolTip = nil; button.setAccessibilityLabel(nil)
      button.target = nil; button.removeFromSuperview()
    }
    buttons.removeAll()
    for label in labels.values { label.stringValue = ""; label.removeFromSuperview() }
    labels.removeAll()
    hourlyDocument.setAccessibilityChildren([]); hourlyScroll.documentView = nil
    setAccessibilityChildren([])
  }
  func update(_ value: WeatherDashboardPresentation) {
    guard presentation !== value else { return }
    presentation = value
    var active: Set<String> = ["weather-current"]
    var children: [Any] = []
    let width = bounds.width
    children.append(
      button(
        "weather-current",
        accessibility: value.currentAccessibility + ". Show observation and source details.",
        frame: NSRect(x: 0, y: 0, width: width, height: WeatherDashboardPresentation.currentHeight)
      ) { rect in
        let accent = WeatherDrawing.accent(symbol: value.symbol, night: value.night)
        accent.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 2), xRadius: 10, yRadius: 10).fill()
        WeatherDrawing.text(
          value.name, NSRect(x: 12, y: 5, width: width - 24, height: 17), size: 12,
          weight: .semibold)
        WeatherDrawing.text(
          value.temperature, NSRect(x: 11, y: 19, width: 147, height: 54), size: 44, weight: .light)
        WeatherDrawing.text(
          value.unit.replacingOccurrences(of: "°", with: ""),
          NSRect(x: 137, y: 31, width: 20, height: 17), size: 10,
          color: .secondaryLabelColor)
        WeatherDrawing.text(
          value.condition, NSRect(x: 190, y: 33, width: width - 267, height: 31), size: 12,
          weight: .medium, wrap: true)
        WeatherDrawing.symbol(
          value.symbol, in: NSRect(x: width - 61, y: 26, width: 43, height: 38), color: accent)
        let column = (width - 46) / 2
        for (index, field) in value.fields.enumerated() {
          let x = 12 + CGFloat(index % 2) * (column + 22), y = 72 + CGFloat(index / 2) * 17
          WeatherDrawing.text(
            field.0, NSRect(x: x, y: y, width: 71, height: 16), size: 10,
            color: .secondaryLabelColor)
          WeatherDrawing.text(
            field.1, NSRect(x: x + 72, y: y, width: column - 72, height: 16), size: 11,
            weight: .medium, alignment: .right)
        }
        WeatherDrawing.text(
          value.status, NSRect(x: 12, y: 124, width: width - 24, height: 14), size: 10,
          color: value.statusWarning ? .systemOrange : .secondaryLabelColor)
        WeatherDrawing.text(
          value.source, NSRect(x: 12, y: 138, width: width - 90, height: 14), size: 9,
          color: .secondaryLabelColor)
        WeatherDrawing.text(
          "Details ›", NSRect(x: width - 77, y: 137, width: 65, height: 15), size: 10,
          color: .secondaryLabelColor, alignment: .right)
      })
    var y = WeatherDashboardPresentation.currentHeight
    for alert in value.alerts {
      active.insert(alert.identifier)
      children.append(
        button(
          alert.identifier,
          accessibility: alert.title + ", " + alert.detail + ", show full point alert.",
          frame: NSRect(x: 0, y: y, width: width, height: WeatherDashboardPresentation.alertHeight)
        ) { rect in
          NSColor.systemOrange.withAlphaComponent(0.12).setFill()
          NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 2), xRadius: 6, yRadius: 6).fill()
          WeatherDrawing.symbol(
            "exclamationmark.triangle", in: NSRect(x: 8, y: 8, width: 16, height: 16),
            color: .systemOrange)
          WeatherDrawing.text(
            alert.title, NSRect(x: 31, y: 7, width: width - 117, height: 18), size: 11,
            weight: .semibold)
          WeatherDrawing.text(
            alert.detail + " ›", NSRect(x: width - 83, y: 8, width: 75, height: 17), size: 10,
            alignment: .right)
        })
      y += WeatherDashboardPresentation.alertHeight
    }
    children.append(
      label(
        "hours",
        text: value.hours.isEmpty
          ? "Hourly forecast unavailable" : "Hourly · \(value.hours.count) cached hours   ↔",
        frame: NSRect(x: 0, y: y + 3, width: width, height: 17)))
    hourlyScroll.isHidden = value.hours.isEmpty
    hourlyScroll.frame = NSRect(x: 0, y: y + 22, width: width, height: 100)
    hourlyDocument.frame = NSRect(
      x: 0, y: 0,
      width: max(width, CGFloat(value.hours.count) * WeatherDashboardPresentation.hourWidth),
      height: 80)
    var hourChildren: [Any] = []
    for (index, hour) in value.hours.enumerated() {
      active.insert(hour.identifier)
      hourChildren.append(
        button(
          hour.identifier, accessibility: hour.accessibility,
          frame: NSRect(
            x: CGFloat(index) * WeatherDashboardPresentation.hourWidth, y: 0,
            width: WeatherDashboardPresentation.hourWidth, height: 80), parent: hourlyDocument
        ) { rect in
          if index == 0 {
            NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
          }
          WeatherDrawing.text(
            hour.time, NSRect(x: 1, y: 3, width: rect.width - 2, height: 15), size: 10,
            color: .secondaryLabelColor, alignment: .center)
          WeatherDrawing.text(
            hour.chance, NSRect(x: 1, y: 19, width: rect.width - 2, height: 15), size: 10,
            weight: .medium, color: hour.wet ? WeatherDrawing.rain : .secondaryLabelColor,
            alignment: .center)
          WeatherDrawing.symbol(
            hour.symbol, in: NSRect(x: (rect.width - 22) / 2, y: 37, width: 22, height: 19),
            color: WeatherDrawing.accent(symbol: hour.symbol, night: hour.night))
          WeatherDrawing.text(
            hour.temperature, NSRect(x: 1, y: 59, width: rect.width - 2, height: 19), size: 13,
            weight: .semibold, alignment: .center)
        })
    }
    hourlyDocument.setAccessibilityElement(true); hourlyDocument.setAccessibilityRole(.group)
    hourlyDocument.setAccessibilityLabel("Cached hourly forecasts");
    hourlyDocument.setAccessibilityChildren(hourChildren)
    if !hourlyScroll.isHidden { children.append(hourlyScroll) }
    y += value.hourSectionHeight
    children.append(
      label(
        "days",
        text: value.days.contains(where: { $0.basis == .unclassifiedPeriods })
          ? "Outlook · period details"
          : value.days.contains(where: { $0.basis == .daytimeAndOvernight })
            ? "Daily outlook · overnight lows" : "Daily outlook",
        frame: NSRect(x: 0, y: y + 4, width: width, height: 17)))
    let units = label(
      "dayUnits", text: "High / Low",
      frame: NSRect(x: width - 124, y: y + 4, width: 124, height: 17))
    units.alignment = .right; units.isHidden = value.days.isEmpty
    if !units.isHidden { children.append(units) }
    y += WeatherDashboardPresentation.dayHeadingHeight
    if value.days.isEmpty {
      children.append(
        label(
          "empty", text: "No upcoming daily or named-period forecast returned.",
          frame: NSRect(x: 0, y: y + 8, width: width, height: 22)))
    } else {
      labels.removeValue(forKey: "empty")?.removeFromSuperview()
    }
    for day in value.days {
      active.insert(day.identifier)
      children.append(
        button(
          day.identifier, accessibility: day.accessibility + ". Show complete cached outlook.",
          frame: NSRect(x: 0, y: y, width: width, height: WeatherDashboardPresentation.dayHeight)
        ) { rect in
          NSColor.separatorColor.withAlphaComponent(0.5).setFill()
          NSRect(x: 0, y: 0, width: width, height: 0.5).fill()
          WeatherDrawing.symbol(
            day.symbol, in: NSRect(x: 4, y: 8, width: 19, height: 17),
            color: WeatherDrawing.accent(symbol: day.symbol))
          WeatherDrawing.text(
            day.title, NSRect(x: 31, y: 5, width: 77, height: 18), size: 12, weight: .semibold)
          WeatherDrawing.text(
            day.chance, NSRect(x: 110, y: 6, width: 40, height: 17), size: 11, weight: .medium,
            color: day.wet ? WeatherDrawing.rain : .secondaryLabelColor)
          let extrema = day.temperatures.components(separatedBy: " / ")
          if extrema.count == 2 {
            WeatherDrawing.text(
              extrema[0], NSRect(x: width - 91, y: 5, width: 40, height: 19), size: 12,
              weight: .semibold, alignment: .right)
            WeatherDrawing.text(
              extrema[1], NSRect(x: width - 43, y: 6, width: 39, height: 18), size: 11,
              color: .secondaryLabelColor, alignment: .right)
          } else {
            WeatherDrawing.text(
              day.temperatures, NSRect(x: 160, y: 5, width: width - 164, height: 19), size: 12,
              weight: .medium, alignment: .right)
          }
          WeatherDrawing.text(
            day.summary, NSRect(x: 31, y: 23, width: width - 35, height: 16), size: 11,
            color: .secondaryLabelColor)
        })
      y += WeatherDashboardPresentation.dayHeight
    }
    for key in Array(buttons.keys) where !active.contains(key) {
      if let button = buttons.removeValue(forKey: key) {
        button.render = nil; button.toolTip = nil; button.setAccessibilityLabel(nil)
        button.target = nil; button.removeFromSuperview()
      }
    }
    setAccessibilityChildren(children)
  }
}
