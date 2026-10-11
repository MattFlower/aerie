import AerieCore
import AppKit

/// Native buttons retain keyboard and accessibility behavior inside the scrolling dashboard.
final class CalendarMonthView: NSView {
  var onSelect: ((Date) -> Void)?
  var onMove: ((Int) -> Void)?
  var onToday: (() -> Void)?
  private var model: CalendarMonth?
  private var dates: [Date] = []
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityRole(.group); setAccessibilityLabel("Calendar date selection")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  static func height(_ model: CalendarMonth) -> CGFloat { 78 + CGFloat(model.weeks.count) * 30 }
  func update(_ value: CalendarMonth) {
    guard model != value else { return }
    let restoreFocus = (window?.firstResponder as? NSView)?.isDescendant(of: self) ?? false
    model = value; dates.removeAll(keepingCapacity: true)
    subviews.forEach { $0.removeFromSuperview() }
    let previous = button(
      "‹", action: #selector(previousMonth), frame: NSRect(x: 0, y: 4, width: 28, height: 28))
    previous.setAccessibilityLabel("Previous month")
    let next = button(
      "›", action: #selector(nextMonth), frame: NSRect(x: 250, y: 4, width: 28, height: 28))
    next.setAccessibilityLabel("Next month")
    let today = button(
      "Today", action: #selector(selectToday), frame: NSRect(x: 294, y: 4, width: 74, height: 28))
    today.setAccessibilityLabel("Select today")
    label(
      value.title, frame: NSRect(x: 35, y: 9, width: 210, height: 20),
      font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
    let margin: CGFloat = value.showsWeekNumbers ? 30 : 0
    let width = (bounds.width - margin) / 7
    if value.showsWeekNumbers {
      label(
        "Wk", frame: NSRect(x: 0, y: 43, width: 26, height: 18), font: .systemFont(ofSize: 9),
        color: .secondaryLabelColor)
    }
    for (column, name) in value.weekdaySymbols.enumerated() {
      label(
        name, frame: NSRect(x: margin + CGFloat(column) * width, y: 41, width: width, height: 20),
        font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
    }
    let formatter = DateFormatter(); formatter.dateStyle = .full
    formatter.calendar = value.calendar; formatter.timeZone = value.calendar.timeZone
    for (row, week) in value.weeks.enumerated() {
      let y: CGFloat = 64 + CGFloat(row) * 30
      if value.showsWeekNumbers {
        label(
          String(week.number), frame: NSRect(x: 0, y: y + 5, width: 26, height: 18),
          font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
          color: .secondaryLabelColor)
      }
      for (column, cell) in week.days.enumerated() {
        let control = button(
          String(cell.day), action: #selector(selectDate(_:)),
          frame: NSRect(x: margin + CGFloat(column) * width + 2, y: y, width: width - 4, height: 27)
        )
        control.tag = dates.count; dates.append(cell.date)
        control.setButtonType(.toggle); control.state = cell.selected ? .on : .off
        control.bezelStyle = .inline; control.isBordered = cell.selected
        control.font = .monospacedDigitSystemFont(ofSize: 11, weight: cell.today ? .bold : .regular)
        control.contentTintColor = cell.inMonth ? .labelColor : .tertiaryLabelColor
        let name = formatter.string(from: cell.date) + (cell.today ? ", today" : "")
        control.setAccessibilityLabel(name); control.toolTip = name
        if restoreFocus && cell.selected { window?.makeFirstResponder(control) }
      }
    }
  }
  @discardableResult private func button(_ title: String, action: Selector, frame: NSRect)
    -> NSButton
  {
    let value = NSButton(title: title, target: self, action: action)
    value.frame = frame; value.bezelStyle = .rounded
    addSubview(value); return value
  }
  private func label(_ text: String, frame: NSRect, font: NSFont, color: NSColor) {
    let value = NSTextField(labelWithString: text)
    value.frame = frame; value.font = font; value.textColor = color; value.alignment = .center
    addSubview(value)
  }
  @objc private func previousMonth() { onMove?(-1) }
  @objc private func nextMonth() { onMove?(1) }
  @objc private func selectToday() { onToday?() }
  @objc private func selectDate(_ sender: NSButton) {
    guard dates.indices.contains(sender.tag) else { return }
    onSelect?(dates[sender.tag])
    // Clicking an already selected toggle must not leave the only selection visually off.
    guard let model else { return }
    for button in subviews.compactMap({ $0 as? NSButton })
    where button.action == #selector(selectDate(_:)) && dates.indices.contains(button.tag) {
      button.state =
        model.calendar.isDate(dates[button.tag], inSameDayAs: model.selection) ? .on : .off
    }
  }
}
