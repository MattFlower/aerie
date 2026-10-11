import AerieCore
import AppKit

/// Virtualized rows use the current Settings-open inventory; no sensor reads or timer.
final class SensorNameList: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate
{
  private let sensors: [SensorData]
  private var names: [String: String]
  private let table = NSTableView()
  var onNameChanged: ((String, String?) -> Bool)?
  init(sensors: [SensorData], names: [String: String]) {
    self.sensors = Array(sensors.prefix(4096)).sorted { $0.label < $1.label }
    self.names = names
    super.init(frame: .zero)
    let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.borderType = .bezelBorder; addSubview(scroll)
    for (id, title, width) in [
      ("name", "Sensor name", CGFloat(260)), ("value", "Reading", 100), ("key", "Code", 70),
    ] {
      let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
      column.minWidth = id == "name" ? 120 : 60
      table.addTableColumn(column)
    }
    table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    table.rowHeight = 28; table.usesAlternatingRowBackgroundColors = true
    table.delegate = self; table.dataSource = self;
    table.setAccessibilityLabel("Available sensor names")
    scroll.documentView = table
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      heightAnchor.constraint(equalToConstant: 260),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func numberOfRows(in tableView: NSTableView) -> Int { sensors.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard sensors.indices.contains(row) else { return nil }
    let sensor = sensors[row]; let identifier = tableColumn?.identifier.rawValue ?? "name"
    let field: NSTextField
    if identifier == "name" {
      field = NSTextField(string: names[sensor.key] ?? sensor.label)
      field.isBordered = false; field.drawsBackground = false; field.delegate = self;
      field.tag = row
      field.setAccessibilityLabel("Name for " + sensor.label)
      field.toolTip =
        "Edit this local name. Clear it to restore the supplied name. Firmware code: " + sensor.key
    } else {
      let reading =
        sensor.value.flatMap { $0.isFinite ? String(format: "%.1f", $0) + " " + sensor.unit : nil }
        ?? (sensor.state == .deferred ? "On demand" : "Unavailable")
      field = NSTextField(labelWithString: identifier == "key" ? sensor.key : reading)
      field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
      field.toolTip =
        identifier == "key" ? "Original firmware identifier" : "Latest sample when Settings opened"
    }
    field.lineBreakMode = .byTruncatingTail
    return field
  }
  func controlTextDidEndEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, sensors.indices.contains(field.tag)
    else { return }
    let sensor = sensors[field.tag];
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard name.utf8.count <= 64,
      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      field.stringValue = names[sensor.key] ?? sensor.label; return
    }
    let alias = name.isEmpty || name == sensor.label ? nil : name
    var proposed = names; proposed[sensor.key] = alias
    guard SensorIdentity.valid(names: proposed), onNameChanged?(sensor.key, alias) ?? true else {
      field.stringValue = names[sensor.key] ?? sensor.label; return
    }
    names = proposed; field.stringValue = alias ?? sensor.label
  }
}
