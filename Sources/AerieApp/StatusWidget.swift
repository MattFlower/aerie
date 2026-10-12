import AerieCore
import AppKit

struct StatusWidget: Equatable {
  let module: Module
  let value: MenuValue
  let style: DisplayStyle
  let label: MenuLabelPlacement
  let colorHex: String?
  var symbol: String?
  var points: [Double?] = []
  var paused = false
  var accessibility: String {
    module.title + ", " + value.full + (paused ? ", sampling paused" : "")
  }
  var defaultSymbol: String {
    switch module {
    case .overview: return "mountain.2"
    case .cpu: return "cpu"
    case .gpu: return "display"
    case .memory: return "memorychip"
    case .storage: return "internaldrive"
    case .network: return "network"
    case .sensors: return "thermometer.medium"
    case .power: return "battery.100percent"
    case .time: return "clock"
    case .weather: return "questionmark.circle"
    }
  }
  var shortLabel: String {
    switch module {
    case .overview: return "AE"
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    case .memory: return "MEM"
    case .storage: return "SSD"
    case .network: return "NET"
    case .sensors: return "SNS"
    case .power: return "BAT"
    case .time: return "CLK"
    case .weather: return "WX"
    }
  }
}

extension MenuRenderer {
  static func weatherSymbol(code: Int?, daylight: Bool? = nil, glyph: WeatherGlyph? = nil) -> String
  {
    if let glyph {
      switch glyph {
      case .clear: return daylight.map { $0 ? "sun.max" : "moon.stars" } ?? "sparkles"
      case .partlyCloudy: return daylight.map { $0 ? "cloud.sun" : "cloud.moon" } ?? "cloud"
      case .cloudy: return "cloud"
      case .fog: return "cloud.fog"
      case .rain: return "cloud.rain"
      case .snow: return "cloud.snow"
      case .sleet, .mixed: return "cloud.sleet"
      case .thunder: return "cloud.bolt.rain"
      case .wind: return "wind"
      case .tornado: return "tornado"
      case .hurricane, .tropicalStorm: return "hurricane"
      case .dust, .haze: return "sun.haze"
      case .smoke: return "smoke"
      case .hot: return "thermometer.sun"
      case .cold: return "thermometer.snowflake"
      case .blizzard: return "wind.snow"
      }
    }
    switch code {
    case 0: return daylight.map { $0 ? "sun.max" : "moon.stars" } ?? "sparkles"
    case 1, 2: return daylight.map { $0 ? "cloud.sun" : "cloud.moon" } ?? "cloud"
    case 3: return "cloud"
    case 45, 48: return "cloud.fog"
    case 51, 53, 55, 56, 57: return "cloud.drizzle"
    case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain"
    case 71, 73, 75, 77, 85, 86: return "cloud.snow"
    case 95, 96, 99: return "cloud.bolt.rain"
    default: return "questionmark.circle"
    }
  }
  static func widget(_ descriptor: StatusWidget, padding: CGFloat) -> NSImage {
    let color = color(descriptor.colorHex) ?? .labelColor
    let label =
      descriptor.label == .automatic
      ? (descriptor.module == .weather || descriptor.module == .overview
        ? MenuLabelPlacement.icon
        : descriptor.module == .time || descriptor.style == .compact ? .none : .inline)
      : descriptor.label
    let fontSize: CGFloat = descriptor.style == .compact ? 9 : 10
    let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let labelWidth: CGFloat =
      label == .vertical
      ? 10
      : label == .icon
        ? 17
        : label == .inline
          ? ceil(
            (descriptor.shortLabel as NSString).size(withAttributes: [
              .font: NSFont.systemFont(ofSize: 8, weight: .semibold)
            ]).width) + 5 : 0
    let isNetwork = descriptor.module == .network
    let stacked = descriptor.style == .stacked || isNetwork
    var content = descriptor.value.compact
    let compact = descriptor.style == .compact
    let iconOnly = compact && descriptor.module == .overview && label == .icon
    if compact {
      if content == "Unavailable" || content == "TEMP —" || content == "WX —" { content = "—" }
      if content.hasSuffix("°C") || content.hasSuffix("°F") { content.removeLast() }
    }
    let width: CGFloat
    if iconOnly {
      width = labelWidth + padding * 2
    } else if isNetwork {
      width = (compact ? 60 : descriptor.style == .graph ? 116 : 90) + labelWidth + padding * 2
    } else if compact,
      [.cpu, .gpu, .memory, .storage, .power, .sensors, .weather].contains(descriptor.module)
    {
      width =
        (descriptor.module == .sensors || descriptor.module == .weather ? 42 : 28) + labelWidth
        + padding * 2
    } else if descriptor.style == .graph {
      width = 58 + labelWidth + padding * 2
    } else {
      let strings =
        stacked ? [descriptor.value.compact, descriptor.value.secondary] : [content]
      width =
        min(
          descriptor.module == .time ? 220 : 120,
          max(
            20,
            ceil(
              strings.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 20)))
        + labelWidth + padding * 2
    }
    let image = NSImage(size: NSSize(width: width, height: 20), flipped: true) { rect in
      NSBezierPath(rect: rect).addClip()
      var x = padding
      if label == .vertical {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: x + 1, yBy: 19);
        transform.rotate(byDegrees: -90); transform.concat()
        (descriptor.shortLabel as NSString).draw(
          at: .zero,
          withAttributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: color,
          ])
        NSGraphicsContext.restoreGraphicsState(); x += 10
      } else if label == .icon {
        let name =
          descriptor.paused ? "pause.fill" : descriptor.symbol ?? descriptor.defaultSymbol
        let symbolRect = NSRect(x: x, y: 2, width: 15, height: 16)
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.draw(in: symbolRect)
        if let context = NSGraphicsContext.current?.cgContext {
          context.saveGState(); context.setBlendMode(.sourceAtop)
          context.setFillColor(color.cgColor); context.fill(symbolRect); context.restoreGState()
        }
        x += 17
      } else if label == .inline {
        (descriptor.shortLabel as NSString).draw(
          at: NSPoint(x: x, y: 5),
          withAttributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: color,
          ])
        x += labelWidth
      }
      let area = NSRect(x: x, y: 0, width: width - x - padding, height: 20)
      func text(_ value: String, rect: NSRect, alignment: NSTextAlignment, size: CGFloat = 10) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment;
        paragraph.lineBreakMode = .byTruncatingTail
        (String(value.prefix(256)) as NSString).draw(
          in: rect,
          withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: color, .paragraphStyle: paragraph,
          ])
      }
      if iconOnly { return true }
      if isNetwork {
        if descriptor.style == .graph {
          let maximum = max(1, descriptor.points.compactMap { $0 }.filter(\.isFinite).max() ?? 1)
          let path = NSBezierPath(); path.lineWidth = 1
          var continuing = false
          for (index, value) in descriptor.points.prefix(48).enumerated() {
            guard let value, value.isFinite else { continuing = false; continue }
            let point = NSPoint(
              x: x + CGFloat(index) / 47 * 22, y: 18 - CGFloat(max(0, value) / maximum) * 16)
            if continuing { path.line(to: point) } else { path.move(to: point); continuing = true }
          }
          color.setStroke(); path.stroke(); x += 26
        }
        // Fixed arrow, numeric and unit columns; geometry never depends on the current rates.
        for (index, source) in [descriptor.value.stackedPrimary, descriptor.value.secondary]
          .enumerated()
        {
          let line = descriptor.paused ? "—" : source
          let body = line.hasPrefix("↓") || line.hasPrefix("↑") ? String(line.dropFirst()) : line
          let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
          let shortened = CompactNetworkColumn(line)
          let y = CGFloat(index) * 10 - 0.5
          text(
            index == 0 ? "↓" : "↑", rect: NSRect(x: x, y: y, width: compact ? 8 : 10, height: 11),
            alignment: .left, size: 9)
          text(
            compact ? shortened.number : parts.first ?? "—",
            rect: NSRect(x: x + (compact ? 8 : 10), y: y, width: compact ? 25 : 43, height: 11),
            alignment: .right, size: compact ? 8.5 : 9)
          text(
            compact ? shortened.unit : parts.count > 1 ? parts[1] : "",
            rect: NSRect(x: x + (compact ? 36 : 57), y: y, width: compact ? 24 : 33, height: 11),
            alignment: .left, size: compact ? 8 : 9)
        }
      } else if descriptor.style == .graph && !descriptor.paused
        && descriptor.points.prefix(48).contains(where: { $0?.isFinite == true })
      {
        let finite = descriptor.points.prefix(48).compactMap { $0 }.filter(\.isFinite)
        let maximum = max(1, finite.max() ?? 1)
        let path = NSBezierPath(); path.lineWidth = 1.2
        var continuing = false
        for (index, value) in descriptor.points.prefix(48).enumerated() {
          guard let value, value.isFinite else { continuing = false; continue }
          let point = NSPoint(
            x: area.minX + CGFloat(index) / 47 * area.width,
            y: 18 - CGFloat(max(0, value) / maximum) * 16)
          if continuing { path.line(to: point) } else { path.move(to: point); continuing = true }
        }
        color.setStroke(); path.stroke()
      } else if stacked {
        let primary = descriptor.value.compact
        text(
          descriptor.paused ? "Paused" : primary,
          rect: NSRect(x: area.minX, y: -0.5, width: area.width, height: 11), alignment: .right,
          size: 9)
        text(
          descriptor.value.secondary,
          rect: NSRect(x: area.minX, y: 9.5, width: area.width, height: 11), alignment: .right,
          size: 9)
      } else {
        let boundedContent =
          compact && (content as NSString).size(withAttributes: attributes).width > area.width
          ? "…" : content
        text(
          descriptor.paused ? (compact ? "Ⅱ" : "Paused") : boundedContent,
          rect: area.insetBy(dx: 0, dy: 3),
          alignment: .center, size: fontSize)
      }
      return true
    }
    image.isTemplate = descriptor.colorHex == nil
    return image
  }
  /// A combined dashboard retains one action while its network component uses reserved columns.
  static func combinedWidgets(
    _ descriptors: [StatusWidget], compactSpacing: Bool,
    leading: NSImage? = nil
  ) -> NSImage {
    let widgets = Array(descriptors.prefix(6))
    let padding: CGFloat = compactSpacing ? 1 : 4, gap: CGFloat = compactSpacing ? 2 : 6
    let images = widgets.map { widget($0, padding: padding) }
    let leadingWidth = leading.map { min(24, max(0, $0.size.width)) } ?? 0
    let prefix = leadingWidth > 0 ? leadingWidth + gap : 0
    let width = max(
      20, prefix + images.reduce(0) { $0 + $1.size.width } + CGFloat(max(0, images.count - 1)) * gap
    )
    let image = NSImage(size: NSSize(width: width, height: 20), flipped: true) { _ in
      if let leading, leadingWidth > 0 {
        let rect = NSRect(x: 0, y: 1, width: leadingWidth, height: 18)
        leading.draw(in: rect)
        if let color = color(widgets.first?.colorHex),
          let context = NSGraphicsContext.current?.cgContext
        {
          context.saveGState(); context.setBlendMode(.sourceAtop)
          context.setFillColor(color.cgColor); context.fill(rect); context.restoreGState()
        }
      }
      var x = prefix
      for part in images {
        part.draw(in: NSRect(x: x, y: 0, width: part.size.width, height: 20));
        x += part.size.width + gap
      }
      return true
    }
    image.isTemplate = widgets.allSatisfy { $0.colorHex == nil }; return image
  }

}
