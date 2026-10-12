import AppKit

/// Forms use native intrinsic sizes and scroll; no collector or timer belongs to a page.
final class SettingsForm: NSView {
  let stack = NSStackView()
  init(title: String, detail: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    let availableWidth = stack.widthAnchor.constraint(equalTo: widthAnchor, constant: -48)
    availableWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 820),
      availableWidth,
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
    ])
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 24, weight: .semibold)
    heading.setAccessibilityRole(.staticText)
    append(heading); note(detail)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var isFlipped: Bool { true }
  func append(_ view: NSView, fullWidth: Bool = true) {
    view.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(view)
    if fullWidth { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
  }
  func section(_ title: String) {
    let divider = NSBox(); divider.boxType = .separator
    append(divider)
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 15, weight: .semibold)
    heading.setAccessibilityRole(.staticText); append(heading)
    stack.setCustomSpacing(6, after: heading)
  }
  func note(_ text: String) {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    append(label)
  }
  func row(_ title: String, control: NSView) {
    let label = NSTextField(wrappingLabelWithString: title)
    label.font = .systemFont(ofSize: 13)
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    label.translatesAutoresizingMaskIntoConstraints = false
    control.translatesAutoresizingMaskIntoConstraints = false
    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal; row.alignment = .firstBaseline; row.spacing = 20
    NSLayoutConstraint.activate([
      label.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.43),
      control.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.57, constant: -20),
    ])
    append(row)
  }
  func buttons(_ buttons: [NSButton]) {
    let row = NSStackView(views: buttons)
    row.orientation = .horizontal; row.spacing = 8; row.alignment = .centerY
    append(row, fullWidth: false)
  }
  func editor(_ editor: NSTextView, height: CGFloat) {
    let scroll = NSScrollView(); scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
    editor.isRichText = false; editor.font = .systemFont(ofSize: 13)
    editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    scroll.documentView = editor
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    append(scroll)
  }
}

enum SettingsSection: String, CaseIterable {
  case general = "General", menus = "Menu Bar", network = "Network", weather = "Weather"
  case time = "Date & Time", sensors = "Sensors", notifications = "Notifications"
  case shortcuts = "Shortcuts", permissions = "Permissions"
  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .menus: return "menubar.rectangle"
    case .network: return "network"
    case .weather: return "cloud.sun"
    case .time: return "clock"
    case .sensors: return "thermometer.medium"
    case .notifications: return "bell"
    case .shortcuts: return "keyboard"
    case .permissions: return "hand.raised"
    }
  }
}

final class SettingsSidebar: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let table = NSTableView()
  var onSelect: ((SettingsSection) -> Void)?
  override func loadView() {
    let material = NSVisualEffectView(); material.material = .sidebar
    material.blendingMode = .behindWindow; material.state = .followsWindowActiveState
    view = material
    let brand = NSTextField(labelWithString: "Aerie")
    brand.font = .systemFont(ofSize: 24, weight: .semibold)
    brand.translatesAutoresizingMaskIntoConstraints = false
    material.addSubview(brand)
    let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.drawsBackground = false; scroll.hasVerticalScroller = true
    material.addSubview(scroll)
    table.addTableColumn(NSTableColumn(identifier: .init("section")))
    table.headerView = nil; table.backgroundColor = .clear; table.rowHeight = 36
    table.style = .sourceList; table.delegate = self; table.dataSource = self
    table.setAccessibilityLabel("Settings sections")
    scroll.documentView = table
    NSLayoutConstraint.activate([
      brand.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 20),
      brand.topAnchor.constraint(equalTo: material.topAnchor, constant: 26),
      scroll.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 8),
      scroll.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -8),
      scroll.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 24),
      scroll.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -16),
    ])
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  }
  func numberOfRows(in tableView: NSTableView) -> Int { SettingsSection.allCases.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard SettingsSection.allCases.indices.contains(row) else { return nil }
    let section = SettingsSection.allCases[row]
    let cell = NSTableCellView(); cell.identifier = .init(section.rawValue)
    let icon = NSImageView();
    icon.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
    icon.contentTintColor = .secondaryLabelColor
    let text = NSTextField(labelWithString: section.rawValue); text.font = .systemFont(ofSize: 13)
    icon.translatesAutoresizingMaskIntoConstraints = false;
    text.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(icon); cell.addSubview(text); cell.textField = text; cell.imageView = icon
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
      icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 18),
      icon.heightAnchor.constraint(equalToConstant: 18),
      text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
      text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
    ])
    return cell
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard SettingsSection.allCases.indices.contains(table.selectedRow) else { return }
    onSelect?(SettingsSection.allCases[table.selectedRow])
  }
}
