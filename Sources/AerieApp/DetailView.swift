import AppKit
import AerieCore

private final class DetailAccessibilityText: NSAccessibilityElement {
  weak var owner: DetailDocumentView?
  var localFrame = NSRect.zero
  override func accessibilityFrame() -> NSRect {
    guard let owner, let window = owner.window else { return .zero }
    return window.convertToScreen(owner.convert(localFrame, to: nil))
  }
}

/// Lightweight native document: layout and accessibility are rebuilt only when its model changes.
final class DetailDocumentView: NSView {
  private struct Block {
    let text: String
    let rect: NSRect
    let font: NSFont
    let color: NSColor
    var background: NSColor? = nil
  }
  private var blocks: [Block] = []
  private var chartRect: NSRect?
  private var barRects: [(NSRect, Double?)] = []
  private(set) var presentation: DetailPresentation?
  private(set) var measuredHeight: CGFloat = 0
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.group)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func setFrameSize(_ newSize: NSSize) {
    let changed = abs(newSize.width - frame.width) > 0.5
    super.setFrameSize(newSize)
    if changed { layoutPresentation() }
  }
  func update(_ value: DetailPresentation) {
    presentation = value; layoutPresentation()
  }
  func releasePresentation() {
    presentation = nil; blocks.removeAll(); barRects.removeAll(); chartRect = nil
    setAccessibilityChildren([]); setAccessibilityLabel(nil); frame.size.height = 16
  }
  private func layoutPresentation() {
    guard let value = presentation else { return }
    blocks.removeAll(keepingCapacity: true); barRects.removeAll(keepingCapacity: true);
    chartRect = nil
    let width = max(280, bounds.width - 48)
    var y: CGFloat = 24
    func text(
      _ content: String, x: CGFloat = 24, width: CGFloat, size: CGFloat,
      weight: NSFont.Weight = .regular, color: NSColor = .labelColor, minimum: CGFloat = 0
    ) -> CGFloat {
      let font = NSFont.systemFont(ofSize: size, weight: weight)
      let height = max(
        minimum,
        ceil(
          (content as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
          ).height))
      blocks.append(
        Block(
          text: content, rect: NSRect(x: x, y: y, width: width, height: max(height, size + 3)),
          font: font, color: color))
      return max(height, size + 3)
    }
    y += text(value.title, width: width - 62, size: 27, weight: .semibold) + 6
    if !value.subtitle.isEmpty {
      y += text(value.subtitle, width: width, size: 12, color: .secondaryLabelColor) + 16
    }
    for notice in value.notices {
      let index = blocks.count
      let height = text(notice, x: 36, width: width - 24, size: 12, weight: .medium)
      let block = blocks[index]
      blocks[index] = Block(
        text: block.text, rect: block.rect.offsetBy(dx: 0, dy: 12), font: block.font,
        color: block.color, background: value.accent.withAlphaComponent(0.10))
      y += height + 34
    }
    if let hero = value.hero {
      y += text(hero.label, width: width, size: 12, color: .secondaryLabelColor) + 3
      y += text(hero.value, width: width, size: 42, weight: .regular) + 20
    }
    func facts(_ facts: [DetailFact], prominent: Bool) {
      let column = (width - 24) / 2
      for start in stride(from: 0, to: facts.count, by: 2) {
        let base = y
        var heights: [CGFloat] = []
        for index in start..<min(start + 2, facts.count) {
          let x = 24 + CGFloat(index - start) * (column + 24)
          y = base
          y +=
            text(facts[index].label, x: x, width: column, size: 11, color: .secondaryLabelColor) + 4
          y += text(
            facts[index].value, x: x, width: column, size: prominent ? 23 : 14, weight: .semibold)
          heights.append(y - base)
        }
        y = base + (heights.max() ?? 0) + 18
      }
    }
    facts(value.highlights, prominent: true)
    if value.chart != nil {
      chartRect = NSRect(x: 24, y: y, width: width, height: 132); y += 156
    }
    for section in value.sections {
      y += 10
      y += text(section.title, width: width, size: 14, weight: .semibold) + 14
      facts(section.facts, prominent: false)
      for paragraph in section.paragraphs where !paragraph.isEmpty {
        y += text(paragraph, width: width, size: 13) + 12
      }
      for (label, fraction) in section.bars {
        let displayed = fraction.map { Format.percent($0) } ?? "Unavailable"
        _ = text(label, width: width - 94, size: 12)
        _ = text(displayed, x: 24 + width - 84, width: 84, size: 12, weight: .semibold)
        y += 21
        barRects.append((NSRect(x: 24, y: y, width: width, height: 5), fraction)); y += 18
      }
    }
    if !value.source.isEmpty {
      y += 10
      y += text(value.source, width: width, size: 11, color: .secondaryLabelColor)
    }
    measuredHeight = y + 28
    super.setFrameSize(NSSize(width: frame.width, height: measuredHeight))
    updateAccessibility(); needsDisplay = true
  }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAccessibility() }
  private func updateAccessibility() {
    setAccessibilityLabel(presentation?.title)
    let children = blocks.map { block -> NSAccessibilityElement in
      let child = DetailAccessibilityText()
      child.owner = self; child.localFrame = block.rect
      child.setAccessibilityRole(.staticText); child.setAccessibilityLabel(block.text)
      child.setAccessibilityParent(self)
      return child
    }
    if let chart = presentation?.chart {
      let element = DetailAccessibilityText(); element.owner = self;
      element.localFrame = chartRect ?? .zero; element.setAccessibilityRole(.staticText)
      let labels = chart.values.enumerated().map { index, value in
        let date =
          chart.dates.indices.contains(index)
          ? WeatherDetailPresentation.date(chart.dates[index], zone: chart.zone)
          : "Unavailable time"
        return date + ": " + Format.weatherTemperature(value, unit: chart.unit)
      }.joined(separator: "; ")
      element.setAccessibilityLabel(chart.title + ". " + labels);
      element.setAccessibilityParent(self)
      setAccessibilityChildren(children + [element])
    } else {
      setAccessibilityChildren(children)
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill(); dirtyRect.intersection(bounds).fill()
    for block in blocks where block.rect.insetBy(dx: -12, dy: -12).intersects(dirtyRect) {
      if let background = block.background {
        background.setFill();
        NSBezierPath(roundedRect: block.rect.insetBy(dx: -12, dy: -12), xRadius: 8, yRadius: 8)
          .fill()
      }
      drawText(block.text, rect: block.rect, font: block.font, color: block.color, wrap: true)
    }
    if let value = presentation {
      let rect = NSRect(x: bounds.width - 72, y: 25, width: 40, height: 40)
      if rect.intersects(dirtyRect) {
        let image = NSImage(systemSymbolName: value.symbol, accessibilityDescription: nil)?
          .withSymbolConfiguration(.init(pointSize: 30, weight: .regular))?
          .withSymbolConfiguration(.init(paletteColors: [value.accent]))
        image?.draw(in: rect)
      }
      for (rect, fraction) in barRects where rect.intersects(dirtyRect) {
        NSColor.quaternaryLabelColor.setFill();
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
        if let fraction, fraction.isFinite, (0...1).contains(fraction) {
          value.accent.setFill();
          NSBezierPath(
            roundedRect: NSRect(
              x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height),
            xRadius: 2.5, yRadius: 2.5
          ).fill()
        }
      }
      if let chart = value.chart, let rect = chartRect, rect.intersects(dirtyRect) {
        draw(chart, in: rect, accent: value.accent)
      }
    }
  }
  private func draw(_ chart: DetailForecastChart, in rect: NSRect, accent: NSColor) {
    let valid = chart.values.compactMap { $0 }.filter(\.isFinite)
    drawText(
      chart.title, rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20),
      font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
    guard let low = valid.min(), let high = valid.max(), let first = chart.dates.first,
      let last = chart.dates.last, first < last
    else {
      drawText(
        "Forecast trend unavailable", rect: rect.insetBy(dx: 0, dy: 35),
        font: .systemFont(ofSize: 12), color: .secondaryLabelColor);
      return
    }
    let plot = NSRect(x: rect.minX, y: rect.minY + 29, width: rect.width, height: 75)
    let minimum = low - 1, maximum = high + 1
    drawSparkline([], in: plot, color: accent, maximum: 1)
    let line = NSBezierPath(); line.lineWidth = 2; var previous: Date? = nil
    for index in chart.values.indices where chart.dates.indices.contains(index) {
      guard let value = chart.values[index], value.isFinite else { previous = nil; continue }
      let date = chart.dates[index]
      let point = NSPoint(
        x: plot.minX + plot.width * date.timeIntervalSince(first) / last.timeIntervalSince(first),
        y: plot.maxY - plot.height * (value - minimum) / (maximum - minimum))
      if let previous, date.timeIntervalSince(previous) <= 5400 {
        line.line(to: point)
      } else {
        line.move(to: point)
      }
      previous = date
    }
    accent.setStroke(); line.stroke()
    let formatter = DateFormatter(); formatter.timeZone = chart.zone;
    formatter.dateFormat = "EEE ha"
    drawText(
      formatter.string(from: first),
      rect: NSRect(x: rect.minX, y: rect.maxY - 18, width: rect.width / 3, height: 17),
      font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    drawText(
      Format.weatherTemperature(low, unit: chart.unit) + " – "
        + Format.weatherTemperature(high, unit: chart.unit),
      rect: NSRect(
        x: rect.minX + rect.width / 3, y: rect.maxY - 18, width: rect.width / 3, height: 17),
      font: .systemFont(ofSize: 10), color: .secondaryLabelColor, alignment: .center)
    drawText(
      formatter.string(from: last),
      rect: NSRect(
        x: rect.minX + rect.width * 2 / 3, y: rect.maxY - 18, width: rect.width / 3, height: 17),
      font: .systemFont(ofSize: 10), color: .secondaryLabelColor, alignment: .right)
  }
}

final class DetailWindowController: NSWindowController, NSWindowDelegate {
  var onClose: (() -> Void)?
  let detailDocument = DetailDocumentView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
  private let scroll = NSScrollView()
  private let diagnosticScroll = NSScrollView()
  private let diagnostics = NSTextView()
  private let disclosure = NSButton(title: "Source & diagnostic details", target: nil, action: nil)
  private let copy = NSButton(title: "Copy details", target: nil, action: nil)
  private(set) var diagnosticsVisible = false
  init(presentation: DetailPresentation) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = presentation.title; window.isReleasedWhenClosed = false;
    window.minSize = NSSize(width: 500, height: 400)
    super.init(window: window); window.delegate = self
    let content = window.contentView!
    scroll.frame = NSRect(x: 0, y: 48, width: 600, height: 572);
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true; scroll.documentView = detailDocument;
    detailDocument.autoresizingMask = [.width]
    content.addSubview(scroll)
    disclosure.frame = NSRect(x: 18, y: 10, width: 300, height: 28);
    disclosure.bezelStyle = .inline; disclosure.alignment = .left
    disclosure.target = self; disclosure.action = #selector(toggleDiagnostics);
    content.addSubview(disclosure)
    copy.frame = NSRect(x: 466, y: 10, width: 118, height: 28);
    copy.autoresizingMask = [.minXMargin]
    copy.bezelStyle = .rounded; copy.target = self; copy.action = #selector(copyDetails);
    content.addSubview(copy)
    diagnostics.isEditable = false; diagnostics.isSelectable = true; diagnostics.isRichText = false
    diagnostics.font = .systemFont(ofSize: 12);
    diagnostics.textContainerInset = NSSize(width: 18, height: 16)
    diagnostics.isVerticallyResizable = true; diagnostics.isHorizontallyResizable = false;
    diagnostics.autoresizingMask = [.width]
    diagnostics.textContainer?.widthTracksTextView = true
    diagnosticScroll.hasVerticalScroller = true; diagnosticScroll.documentView = diagnostics
    diagnosticScroll.autoresizingMask = [.width, .height]; diagnosticScroll.isHidden = true;
    content.addSubview(diagnosticScroll)
    update(presentation); window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func update(_ value: DetailPresentation) {
    window?.title = value.title; detailDocument.update(value)
    if diagnosticsVisible { diagnostics.string = value.diagnostics }
    window?.setAccessibilityLabel(value.title + " details")
  }
  @objc func toggleDiagnostics() {
    diagnosticsVisible.toggle()
    disclosure.title = diagnosticsVisible ? "Back to summary" : "Source & diagnostic details"
    scroll.isHidden = diagnosticsVisible; diagnosticScroll.isHidden = !diagnosticsVisible
    diagnosticScroll.frame = scroll.frame
    diagnostics.string = diagnosticsVisible ? detailDocument.presentation?.diagnostics ?? "" : ""
    if diagnosticsVisible {
      diagnostics.frame.size.width = diagnosticScroll.contentSize.width;
      window?.makeFirstResponder(diagnostics)
    }
  }
  @objc private func copyDetails() {
    guard let value = detailDocument.presentation else { return }
    NSPasteboard.general.clearContents();
    NSPasteboard.general.setString(value.fullText, forType: .string)
  }
  func windowWillClose(_ notification: Notification) {
    diagnostics.string = ""; detailDocument.releasePresentation()
    if let window { MenuPanel.releaseContent(of: window) }
    onClose?()
  }
}
