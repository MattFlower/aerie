import AppKit
import AerieCore

struct DashboardSeries {
  let key: String
  let title: String
  let color: NSColor
  let maximum: Double?
}

/// Compact charts reuse retained samples. Missing values and time gaps retain their segments.
func drawCompactTrend(
  _ title: String, detail: String, series: [DashboardSeries], points: [HistoryPoint],
  selected: HistoryPoint?, interval: Double, formatter: DateFormatter, in rect: NSRect
) {
  drawText(
    title, rect: NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: 17),
    font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
  drawText(
    detail, rect: NSRect(x: rect.minX, y: rect.minY + 21, width: rect.width, height: 15),
    font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
  let plot = NSRect(x: rect.minX, y: rect.minY + 37, width: rect.width, height: 50)
  // Duplex rates share a common scale, so neither direction's relative magnitude is disguised.
  var automatic = 1.0
  if series.contains(where: { $0.maximum == nil }) {
    for point in points {
      for item in series {
        if let value = point.values[item.key], value.isFinite { automatic = max(automatic, value) }
      }
    }
  }
  for item in series {
    drawHistoryPlot(
      HistoryPlot.samples(points, metric: item.key, expectedInterval: interval),
      in: plot, color: item.color, maximum: item.maximum ?? automatic)
  }
  guard let first = points.first, let last = points.last else {
    drawText(
      "History awaiting samples",
      rect: NSRect(
        x: rect.minX, y: rect.minY + 89,
        width: rect.width, height: 13), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    return
  }
  let span = max(0, last.date.timeIntervalSince(first.date))
  let left =
    selected.map { formatter.string(from: $0.date) } ?? relativeHistorySpan(span) + " earlier"
  let right =
    selected.map { point in
      series.map { item in
        item.title + " " + (point.values[item.key].map { String(format: "%.2f", $0) } ?? "—")
      }.joined(separator: " · ")
    } ?? "Latest retained"
  drawText(
    left, rect: NSRect(x: rect.minX, y: rect.minY + 89, width: rect.width / 2, height: 13),
    font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
  drawText(
    right, rect: NSRect(x: rect.midX, y: rect.minY + 89, width: rect.width / 2, height: 13),
    font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular), color: .secondaryLabelColor,
    alignment: .right)
}

func relativeHistorySpan(_ span: Double) -> String {
  guard span.isFinite, span >= 0 else { return "Unavailable" }
  let seconds = Int(min(span.rounded(), Double(Int.max / 2)))
  if seconds < 60 { return "\(seconds)s" }
  if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
  if seconds < 86400 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
  return "\(seconds / 86400)d \(seconds % 86400 / 3600)h"
}

func drawCompactFacts(_ items: [(String, String)], in rect: NSRect) {
  let width = (rect.width - 12) / 2
  for (index, item) in items.enumerated() {
    let x = rect.minX + CGFloat(index % 2) * (width + 12)
    let y = rect.minY + CGFloat(index / 2) * 32
    drawText(
      item.0, rect: NSRect(x: x, y: y + 1, width: width, height: 13),
      font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
    drawText(
      item.1, rect: NSRect(x: x, y: y + 13, width: width, height: 18),
      font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: .labelColor)
  }
}

func drawCompactCores(_ values: [Double], detail: String, in rect: NSRect) {
  drawText(
    detail, rect: NSRect(x: rect.minX, y: rect.minY + 3, width: rect.width, height: 17),
    font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
  let columns = min(12, max(1, values.count)), width = rect.width / CGFloat(columns)
  for (index, value) in values.enumerated() {
    let x = rect.minX + CGFloat(index % columns) * width
    let y = rect.minY + 23 + CGFloat(index / columns) * 28
    let base = NSRect(x: x + 2, y: y, width: width - 4, height: 14)
    NSColor.quaternaryLabelColor.setFill(); base.fill()
    if value.isFinite {
      let fraction = CGFloat(max(0, min(1, value)))
      AeriePalette.cpu.setFill()
      NSRect(
        x: base.minX, y: base.maxY - base.height * fraction, width: base.width,
        height: base.height * fraction
      ).fill()
    }
    drawText(
      "\(index + 1)", rect: NSRect(x: x, y: y + 15, width: width, height: 11),
      font: .systemFont(ofSize: 8), color: .secondaryLabelColor, alignment: .center)
  }
}
