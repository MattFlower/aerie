import AerieCore
import AppKit

enum ReadingTarget {
  case processor, graphics(Int), memory, volume(Int), interface(String), power, powerSource(Int)
  case process(ProcessData), networkProcess(ProcessPresentation.NetworkRow), peripheral(Int), wifi
}
struct ReadingCard {
  let title, subtitle, symbol: String
  let facts: [(String, String)]
  let target: ReadingTarget
  var accent = NSColor.systemBlue
  var gauge: (String, Double?)? = nil
  var compact = false
  var height: CGFloat {
    compact ? 28 : 42 + CGFloat((facts.count + 1) / 2) * 32 + (gauge == nil ? 0 : 32)
  }
  var accessibility: String {
    title + ". " + subtitle + ". " + facts.map { $0.0 + ": " + $0.1 }.joined(separator: "; ")
      + (gauge.map { ". " + $0.0 } ?? "") + ". Show captured details."
  }
}

func drawReadingCard(_ card: ReadingCard, in rect: NSRect, focused: Bool) {
  let body = rect.insetBy(dx: 0, dy: 3)
  if !card.compact {
    NSColor.labelColor.withAlphaComponent(0.045).setFill()
    NSBezierPath(roundedRect: body, xRadius: 7, yRadius: 7).fill()
  }
  if focused {
    NSColor.keyboardFocusIndicatorColor.setStroke()
    let outline = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
    outline.lineWidth = 2; outline.stroke()
  }
  let inset: CGFloat = card.compact ? 0 : 10
  let width = rect.width - inset * 2 - 14
  if card.compact {
    drawText(
      card.title, rect: NSRect(x: rect.minX, y: rect.minY + 5, width: width * 0.53, height: 19),
      font: .systemFont(ofSize: 12), color: .labelColor)
    drawText(
      card.facts.first?.1 ?? "",
      rect: NSRect(x: rect.minX + width * 0.53, y: rect.minY + 5, width: width * 0.47, height: 19),
      font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor,
      alignment: .right)
  } else {
    drawText(
      card.title, rect: NSRect(x: rect.minX + inset, y: rect.minY + 8, width: width, height: 18),
      font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
    drawText(
      card.subtitle,
      rect: NSRect(x: rect.minX + inset, y: rect.minY + 26, width: width, height: 13),
      font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    drawCompactFacts(
      card.facts,
      in: NSRect(
        x: rect.minX + inset, y: rect.minY + 42, width: rect.width - inset * 2,
        height: CGFloat((card.facts.count + 1) / 2) * 32))
    if let (label, fraction) = card.gauge {
      let track = NSRect(
        x: rect.minX + inset, y: rect.maxY - 12, width: rect.width - inset * 2, height: 5)
      NSColor.quaternaryLabelColor.setFill();
      NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
      if let fraction, fraction.isFinite, (0...1).contains(fraction) {
        card.accent.setFill();
        NSBezierPath(
          roundedRect: NSRect(
            x: track.minX, y: track.minY, width: track.width * fraction, height: 5), xRadius: 2.5,
          yRadius: 2.5
        ).fill()
      }
      drawText(
        label,
        rect: NSRect(
          x: rect.minX + inset, y: rect.maxY - 30, width: rect.width - inset * 2, height: 13),
        font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    }
  }
  drawText(
    "›", rect: NSRect(x: rect.maxX - 13, y: rect.minY + 5, width: 11, height: 20),
    font: .systemFont(ofSize: 17), color: .secondaryLabelColor)
}

func powerKindName(_ kind: PowerSourceKind) -> String {
  switch kind {
  case .internalBattery: return "Internal battery";
  case .ups: return "UPS";
  case .unknown: return "Unclassified source"
  }
}
func powerInputName(_ input: PowerInputState) -> String {
  switch input {
  case .ac: return "External AC";
  case .battery: return "Battery";
  case .offline: return "Offline";
  case .unknown: return "Unavailable"
  }
}
enum ReadingDetails {
  static func make(_ target: ReadingTarget, snapshot s: Snapshot, settings: Settings)
    -> DetailPresentation?
  {
    func bytes(_ value: Double) -> String { Format.bytes(value, binary: settings.binaryBytes) }
    func rate(_ value: Double?, network: Bool = false) -> String {
      Format.rate(
        value, domain: network ? .network : .storage, binary: settings.binaryBytes,
        networkBits: settings.networkBits)
    }
    func number(_ value: Double?, unit: String) -> String {
      value.flatMap { $0.isFinite ? String(format: "%.2f %@", $0, unit) : nil } ?? "Unavailable"
    }
    let captured = "Captured " + s.date.formatted(.iso8601)
    var result: DetailPresentation
    switch target {
    case .processor:
      result = DetailPresentation(
        title: "Processor", subtitle: captured, symbol: "cpu",
        highlights: [
          DetailFact("Scheduler load", Format.percent(s.cpu.total)),
          DetailFact("Logical cores", String(s.cpu.cores.count)),
        ],
        sections: [
          DetailSection(
            title: "Activity & topology",
            facts: [
              DetailFact("User", Format.percent(s.cpu.user)),
              DetailFact("System", Format.percent(s.cpu.system)),
              DetailFact("Nominal frequency", number(s.cpu.frequency, unit: "GHz")),
              DetailFact("Uptime", Format.duration(s.cpu.uptime)),
            ]),
          DetailSection(
            title: "Load averages",
            facts: zip(["1 minute", "5 minutes", "15 minutes"], s.cpu.load).map {
              DetailFact($0.0, String(format: "%.2f", $0.1))
            }),
          DetailSection(
            title: "Logical-core load",
            bars: s.cpu.cores.enumerated().map {
              ("Logical core \($0.offset + 1)", Optional($0.element))
            }),
        ], source: "On this Mac · OS scheduler counters",
        diagnostics: "Reported topology: "
          + s.cpu.groups.map { "\($0.0): \($0.1)" }.joined(separator: "; ")
          + "\nClock-state distributions remain separate hardware readings. Logical indices do not identify physical core roles."
      )
    case .graphics(let index):
      guard s.gpu.indices.contains(index) else { return nil }; let gpu = s.gpu[index]
      var facts = [
        DetailFact("Renderer", Format.percent(gpu.renderer)),
        DetailFact("Tiler", Format.percent(gpu.tiler)),
        DetailFact("Shared memory in use", gpu.memory.map(bytes) ?? "Unavailable"),
      ]
      facts += [
        DetailFact(
          "Temperature",
          gpu.temperature.map { Format.temperature($0, unit: settings.temperature) }
            ?? "Unavailable"), DetailFact("Frequency", number(gpu.frequency, unit: "GHz")),
        DetailFact("Frame rate", number(gpu.fps, unit: "FPS")),
      ]
      result = DetailPresentation(
        title: gpu.name, subtitle: captured, symbol: "display",
        hero: DetailFact("Driver utilization", Format.percent(gpu.utilization)),
        sections: [DetailSection(title: "Driver telemetry", facts: facts)],
        source: "On this Mac · exposed driver counters",
        diagnostics:
          "Optional values are unavailable when the driver does not expose them. Per-process GPU utilization and a global frame-rate estimate are not inferred. Hardware clock-state distributions are separate from this utilization sample."
      )
    case .memory:
      let m = s.memory
      guard m.validity == .fresh else {
        return .information(
          title: "Memory sample unavailable",
          message:
            "The latest OS memory sample failed. Old categories are not presented as current readings."
        )
      }
      let categories = [
        ("App", m.app), ("Wired", m.wired), ("Compressed", m.compressed), ("File cache", m.cached),
      ]
      result = DetailPresentation(
        title: "Memory", subtitle: captured, symbol: "memorychip", accent: .systemTeal,
        highlights: [
          DetailFact("Used memory", Format.percent(m.usedFraction)),
          DetailFact("OS pressure", m.pressure),
        ],
        sections: [
          DetailSection(
            title: "OS categories · share of physical memory",
            facts: categories.map { DetailFact($0.0, bytes($0.1)) },
            paragraphs: [
              "Bars show each category relative to physical memory independently; these are not a partition. Purgeable memory overlaps other categories."
            ],
            bars: categories.map {
              ($0.0, m.total > 0 && $0.1 >= 0 && $0.1 <= m.total ? $0.1 / m.total : nil)
            }),
          DetailSection(
            title: "Capacity & swap",
            facts: [
              DetailFact("Physical", bytes(m.total)), DetailFact("Free", bytes(m.free)),
              DetailFact("Purgeable", bytes(m.purgeable)),
              DetailFact("Swap used / total", bytes(m.swap) + " / " + bytes(m.swapTotal)),
            ]),
          DetailSection(
            title: "Virtual memory activity",
            facts: [
              DetailFact("Page in", rate(m.pageIn)), DetailFact("Page out", rate(m.pageOut)),
              DetailFact("Swap in", rate(m.swapIn)), DetailFact("Swap out", rate(m.swapOut)),
            ]),
        ], source: "On this Mac · Mach and OS memory counters",
        diagnostics:
          "Used-memory percentage is not memory-pressure percentage. Process footprints can include shared-accounting overlap and are not summed to derive these categories."
      )
    case .volume(let index):
      guard s.volumes.indices.contains(index) else { return nil }; let v = s.volumes[index]
      let backing =
        v.device.map { s.storageMetadata.topology?.underlyingDisks(for: $0) ?? [] } ?? []
      result = DetailPresentation(
        title: v.name, subtitle: captured, symbol: v.local ? "internaldrive" : "network",
        accent: .systemTeal,
        highlights: [
          DetailFact("Available", bytes(v.free)),
          DetailFact("Used", v.total > 0 ? Format.percent(v.usedFraction) : "Unavailable"),
        ],
        sections: [
          DetailSection(
            title: "Capacity & access",
            facts: [
              DetailFact("Capacity", bytes(v.total)),
              DetailFact("Important-use available", v.important.map(bytes) ?? "Unavailable"),
              DetailFact("Location", v.local ? "Local" : "Network"),
              DetailFact("Removable", v.removable ? "Yes" : "No"),
              DetailFact("Access", v.readOnly ? "Read only" : "Writable"),
            ])
        ], source: "On this Mac · mounted-volume and read-only metadata",
        diagnostics:
          "Mount path: \(v.path)\nOS device: \(v.device ?? "Unavailable")\nBacking sources: \(backing.isEmpty ? "Unavailable" : backing.joined(separator: ", "))\n\(s.storageMetadata.status)\nSMART reports a threshold status; it does not estimate remaining life. No scan or device write is performed."
      )
      for identifier in backing {
        guard let drive = s.storageMetadata.drives[identifier] else { continue }
        result.sections.append(
          DetailSection(
            title: "OS drive status · " + identifier,
            facts: [
              DetailFact("SMART", String(describing: drive.smart)),
              DetailFact("Bus", drive.bus ?? "Unavailable"),
              DetailFact(
                "Media", drive.solidState.map { $0 ? "Solid state" : "Rotating" } ?? "Unavailable"),
            ]))
      }
    case .interface(let name):
      guard let i = s.interfaces.first(where: { $0.name == name }) else { return nil }
      var facts = [
        DetailFact(
          i.counterBits == 64 ? "OS received" : "Limited received counter",
          bytes(Double(i.received))),
        DetailFact(i.counterBits == 64 ? "OS sent" : "Limited sent counter", bytes(Double(i.sent))),
        DetailFact("Errors", String(i.errors)),
        DetailFact("State", i.active ? "Active" : "Inactive"),
      ]
      if let session = i.session {
        facts += [
          DetailFact(
            "Observed session received", session.received.map { bytes(Double($0)) } ?? "Unavailable"
          ),
          DetailFact(
            "Observed session sent", session.sent.map { bytes(Double($0)) } ?? "Unavailable"),
        ]
      }
      result = DetailPresentation(
        title: i.name, subtitle: captured + " · interface scope", symbol: "network",
        highlights: [
          DetailFact("Download", rate(i.download, network: true)),
          DetailFact("Upload", rate(i.upload, network: true)),
        ],
        sections: [
          DetailSection(title: "Counters & observed session", facts: facts),
          DetailSection(
            title: "Assigned addresses",
            paragraphs: [i.addresses.isEmpty ? "No assigned IP address" : i.addresses]),
        ], source: "On this Mac · reported interface counters",
        diagnostics:
          "Counter width: \(i.counterBits) bits\nReceived raw bytes: \(i.received)\nSent raw bytes: \(i.sent)\n"
          + (i.session.map {
            "Session baseline: \($0.started.formatted(.iso8601)); rebased: \($0.rebased)"
          } ?? "Observed session unavailable")
          + "\nAggregate selection: \(s.networkSelection.description). Interface readings do not change the aggregate selection. Limited route counters are rounded to 1 KiB and can wrap; observed sessions rebase after source/counter loss."
      )
    case .power:
      let p = s.power
      result = DetailPresentation(
        title: "Battery & power", subtitle: captured, symbol: "battery.100percent",
        accent: .systemOrange,
        highlights: [
          DetailFact("Charge", Format.percent(p.percent)),
          DetailFact("Supply", p.source ?? "Unavailable"),
        ],
        sections: [
          DetailSection(
            title: "Battery condition",
            facts: [
              DetailFact("Health", Format.percent(p.health)),
              DetailFact("Cycles", p.cycles.map(String.init) ?? "Unavailable"),
              DetailFact(
                "Time",
                Format.powerTime(
                  p.minutes, charging: p.charging,
                  input: p.external.map { $0 ? .ac : .battery } ?? .unknown)),
              DetailFact("Charging", p.charging.map { $0 ? "Yes" : "No" } ?? "Unavailable"),
            ]),
          DetailSection(
            title: "Electrical & system",
            facts: [
              DetailFact("Voltage", number(p.voltage, unit: "V")),
              DetailFact("Current", number(p.amperage, unit: "A")),
              DetailFact("Battery power", number(p.watts, unit: "W")),
              DetailFact("Low Power Mode", s.lowPower ? "On" : "Off"),
              DetailFact("Thermal state", s.thermal),
            ]),
        ], source: "On this Mac · OS power-source descriptions",
        diagnostics:
          "No combined capacity is inferred across battery/UPS sources. Electrical readings are source-reported values. Interrupt wakeups are not a whole-system energy score. Changing power modes or fan controls is not performed."
      )
      if p.present && p.inventory.primaryBattery == nil {
        result.notices.append(
          "Battery summary is incomplete or ambiguous. Inspect each OS source separately.")
      }
    case .powerSource(let index):
      guard s.power.inventory.sources.indices.contains(index) else { return nil };
      let p = s.power.inventory.sources[index]
      result = DetailPresentation(
        title: p.name, subtitle: captured + " · individual source",
        symbol: p.kind == .ups ? "powerplug" : "battery.100percent", accent: .systemOrange,
        highlights: [
          DetailFact("Charge", Format.percent(p.percent)),
          DetailFact("Input", powerInputName(p.input)),
        ],
        sections: [
          DetailSection(
            title: "Source facts",
            facts: [
              DetailFact("Type", powerKindName(p.kind)),
              DetailFact("Present", p.present.map { $0 ? "Yes" : "No" } ?? "Unavailable"),
              DetailFact("Charging", p.charging.map { $0 ? "Yes" : "No" } ?? "Unavailable"),
              DetailFact("Time", Format.powerTime(p.minutes, charging: p.charging, input: p.input)),
              DetailFact("Transport", p.transport ?? "Unavailable"),
              DetailFact("Voltage", number(p.voltage, unit: "V")),
              DetailFact("Current", number(p.amperage, unit: "A")),
              DetailFact("Power", number(p.watts, unit: "W")),
              DetailFact(
                "Temperature",
                p.temperature.map { Format.temperature($0, unit: settings.temperature) }
                  ?? "Unavailable"),
            ])
        ], source: "On this Mac · individual OS power-source record",
        diagnostics:
          "Compatible capacities are evaluated within this source only. Multiple sources are never averaged. This is a captured reading; opening it creates no power-control request."
      )
    case .peripheral(let index):
      guard s.power.peripherals.indices.contains(index) else { return nil }
      let value = s.power.peripherals[index]
      result = DetailPresentation(
        title: value.0, subtitle: captured, symbol: "battery.100percent", accent: .systemOrange,
        hero: DetailFact("Exposed peripheral charge", Format.percent(value.1)),
        source: "On this Mac · exposed device-registry battery reading",
        diagnostics:
          "Only this charge reading is exposed by the current source. Capacity, cycles and device health are not inferred."
      )
    case .wifi:
      guard let wifi = s.wifi else { return nil }
      result = DetailPresentation(
        title: "Wi-Fi radio", subtitle: "Captured " + wifi.fetched.formatted(.iso8601),
        symbol: "wifi",
        sections: [
          DetailSection(
            title: "Passive radio facts",
            facts: wifi.fields.filter { !["SSID", "BSSID", "Country"].contains($0.0) }.map {
              DetailFact($0.0, $0.1)
            })
        ], source: "On this Mac · passive CoreWLAN reading",
        diagnostics:
          "No network scan is performed. SSID, BSSID and country are shown only in the live Network panel when already authorized, then discarded when that panel closes. This captured view retains no Wi-Fi identity."
      )
    case .networkProcess(let p):
      result = DetailPresentation(
        title: p.name, subtitle: captured + " · captured TCP/UDP process scope", symbol: "app",
        highlights: [
          DetailFact("Download", rate(p.download, network: true)),
          DetailFact("Upload", rate(p.upload, network: true)),
        ],
        sections: [
          DetailSection(
            title: "Process scope", facts: [DetailFact("Members", String(p.members))],
            paragraphs: [
              "Traffic covers OS-reported TCP/UDP across interfaces, including loopback. It does not follow the aggregate interface filter."
            ])
        ], source: "On this Mac · captured OS process-traffic logger",
        diagnostics:
          "PID at capture: \(p.pid)\nNo later PID lookup is performed. Missing/reset baselines and protected members keep rates unavailable. Opening details stops the live panel logger; this is a captured reading."
      )
    case .process(let p):
      result = DetailPresentation(
        title: p.name,
        subtitle: captured
          + (p.members > 1 ? " · combined application/executable reading" : " · process reading"),
        symbol: "app",
        highlights: [
          DetailFact("CPU", Format.percent(p.cpu)),
          DetailFact("Physical footprint", bytes(p.memory)),
        ],
        sections: [
          DetailSection(
            title: "Captured activity",
            facts: [
              DetailFact("Read", rate(p.read)), DetailFact("Write", rate(p.write)),
              DetailFact("Interrupt wakeups", number(p.wakeups, unit: "/s")),
              DetailFact("Members", String(p.members)),
            ])
        ], source: "On this Mac · captured process accounting",
        diagnostics:
          "PID at capture: \(p.pid)\nCPU scale: \(settings.normalizedProcessCPU ? "0–100% of the machine" : "100% per logical core")\nNo later PID lookup is performed. Group memory is summed footprint and can include shared-accounting overlap. Protected or unavailable members remain unavailable in aggregate rates."
      )
    }
    result.diagnostics = captured + "\n" + result.diagnostics
    return result
  }
}
