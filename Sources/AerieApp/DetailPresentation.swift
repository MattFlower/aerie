import AerieCore
import AppKit

struct DetailFact {
  let label, value: String
  init(_ label: String, _ value: String) { self.label = label; self.value = value }
}
struct DetailSection {
  var title: String
  var facts: [DetailFact] = []
  var paragraphs: [String] = []
  var bars: [(String, Double?)] = []
}
struct DetailPresentation {
  var title: String
  var subtitle = ""
  var symbol = "info.circle"
  var accent = NSColor.systemBlue
  var hero: DetailFact?
  var highlights: [DetailFact] = []
  var notices: [String] = []
  var sections: [DetailSection] = []
  var source = ""
  var diagnostics = ""
  var chart: DetailForecastChart?
  static func information(title: String, message: String) -> Self {
    Self(
      title: title, sections: [DetailSection(title: "About these readings", paragraphs: [message])],
      diagnostics: message)
  }
}
struct DetailForecastChart {
  let title: String
  let dates: [Date]
  let values: [Double?]
  let unit: TemperatureUnit
  let zone: TimeZone
}

enum SensorMenuPresentation {
  // Keep the existing toolbar's first-live reading. The hottest reading remains separate.
  static func selected(_ sensors: [SensorData]) -> SensorData? {
    sensors.first { $0.unit == "°C" && $0.state == .live && $0.value?.isFinite == true }
  }
  static func name(_ sensor: SensorData, names: [String: String]?) -> String {
    let name = names?[sensor.key] ?? sensor.label
    return name == sensor.key || name.isEmpty ? "Unknown sensor" : name
  }
  static func shortLabel(_ sensor: SensorData?) -> String {
    guard let sensor else { return "TMP" }
    // Only an explicit source label, never the firmware key or temperature, identifies a role.
    let words = sensor.label.lowercased().split { !$0.isLetter }.map(String.init)
    if words.contains("cpu") || words.contains("processor") { return "CPU" }
    if words.contains("gpu") || words.contains("graphics") { return "GPU" }
    return "TMP"
  }
  static func value(_ sensor: SensorData, unit: TemperatureUnit) -> String {
    guard sensor.state == .live, let value = sensor.value, value.isFinite else {
      return sensor.state == .deferred ? "Waiting for live read" : "Unavailable"
    }
    return sensor.unit == "°C"
      ? Format.temperature(value, unit: unit) : String(format: "%.1f %@", value, sensor.unit)
  }
  static func description(_ sensors: [SensorData], names: [String: String]?, unit: TemperatureUnit)
    -> String
  {
    guard let sensor = selected(sensors) else {
      return "Temperature sensor unavailable; no live temperature source."
    }
    return "Temperature from " + name(sensor, names: names) + ". Firmware source " + sensor.key
      + ". First live temperature reading, not a CPU average. " + value(sensor, unit: unit)
  }
  static func detail(
    _ sensor: SensorData, names: [String: String]?, unit: TemperatureUnit, selected: Bool,
    sampledAt: Date? = nil
  ) -> DetailPresentation {
    let name = name(sensor, names: names)
    var result = DetailPresentation(
      title: name,
      subtitle: selected
        ? "Shown in your menu bar · captured reading" : "Captured hardware reading",
      symbol: sensor.unit == "°C"
        ? "thermometer.medium" : sensor.unit == "rpm" ? "fan" : "waveform.path",
      accent: .systemTeal,
      hero: DetailFact(
        sensor.unit == "°C" ? "Temperature" : "Current reading", value(sensor, unit: unit)),
      sections: [
        DetailSection(
          title: "Reading source",
          facts: [
            DetailFact(
              "State",
              sensor.state == .live
                ? "Live at capture" : sensor.state == .deferred ? "Deferred" : "Unavailable"),
            DetailFact("Native unit", sensor.unit),
          ],
          paragraphs: [
            name == "Unknown sensor"
              ? "The firmware exposes this reading without a verified component name. Aerie does not infer a CPU, GPU or other role."
              : "Read-only firmware telemetry. The name is the mapped source label or your local alias."
          ])
      ], source: "On this Mac · read-only hardware sensor")
    result.diagnostics =
      "Sampled UTC: \(sampledAt?.formatted(.iso8601) ?? "Captured when opened")\nFirmware key: \(sensor.key)\nFirmware label: \(sensor.label)\nLocal alias: \(names?[sensor.key] ?? "None")\nNative value: \(sensor.value.map(String.init(describing:)) ?? "Unavailable") \(sensor.unit)\nMenu selection: first finite live temperature in the existing inventory order. Highest-temperature history and rules are separate aggregates; this is not a CPU average."
    return result
  }
}

struct SensorRowPresentation {
  let name, value, key: String
  let selected: Bool
}

extension DetailPresentation {
  var fullText: String {
    var lines = [title, subtitle]
    if let hero { lines.append(hero.label + ": " + hero.value) }
    lines += highlights.map { $0.label + ": " + $0.value }
    lines += notices
    for section in sections {
      lines.append(section.title)
      lines += section.facts.map { $0.label + ": " + $0.value }
      lines += section.paragraphs
      lines += section.bars.map { $0.0 + ": " + Format.percent($0.1) }
    }
    lines += [source, diagnostics]
    return lines.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
}

final class DashboardDetailButton: NSButton {
  var primary = "", secondary = ""
  var selectedReading = false, explanatory = false
  override func draw(_ dirtyRect: NSRect) {
    if selectedReading || isHighlighted {
      (selectedReading ? NSColor.systemTeal : NSColor.controlAccentColor).withAlphaComponent(0.10)
        .setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    let x: CGFloat = selectedReading ? 12 : 0
    if selectedReading {
      NSColor.systemTeal.setFill();
      NSBezierPath(ovalIn: NSRect(x: 4, y: bounds.midY - 2, width: 4, height: 4)).fill()
    }
    let width = bounds.width - x - 18
    drawText(
      primary,
      rect: NSRect(
        x: x, y: explanatory ? 32 : 14, width: explanatory ? width : width * 0.72, height: 18),
      font: .systemFont(ofSize: 12, weight: .medium), color: .labelColor)
    drawText(
      secondary,
      rect: NSRect(
        x: explanatory ? x : x + width * 0.72, y: explanatory ? 1 : 12,
        width: explanatory ? width : width * 0.28, height: explanatory ? 29 : 20),
      font: .systemFont(
        ofSize: explanatory ? 10.5 : 12, weight: explanatory ? .regular : .semibold),
      color: explanatory ? .secondaryLabelColor : .labelColor,
      alignment: explanatory ? .left : .right, wrap: explanatory)
    drawText(
      "›", rect: NSRect(x: bounds.maxX - 12, y: bounds.midY - 10, width: 12, height: 20),
      font: .systemFont(ofSize: 17), color: .secondaryLabelColor, alignment: .right)
    if window?.firstResponder === self {
      NSColor.keyboardFocusIndicatorColor.setStroke();
      let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5);
      outline.lineWidth = 2; outline.stroke()
    }
  }
}
