import AerieCore
import AppKit
import ImageIO

final class MapHTTPClient: NSObject, URLSessionTaskDelegate {
  private var session: URLSession?
  private var closed = false
  private var generation = 0
  private let sessionConfiguration: URLSessionConfiguration?
  init(configuration: URLSessionConfiguration? = nil) {
    sessionConfiguration = configuration; super.init()
  }
  private var lastRequest = 0.0
  private func makeSession() -> URLSession {
    let configuration = sessionConfiguration ?? URLSessionConfiguration.ephemeral
    configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
    configuration.httpMaximumConnectionsPerHost = 2
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }
  @MainActor func data(_ url: URL) async throws -> Data {
    guard !closed, WMS.allowed(url) else { throw MapError.invalidResponse }
    let token = generation
    if session == nil { session = makeSession() }
    guard let session else { throw MapError.invalidResponse }
    let delay = 0.75 - (ProcessInfo.processInfo.systemUptime - lastRequest)
    if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
    try Task.checkCancellation()
    guard !closed, generation == token else { throw CancellationError() }
    lastRequest = ProcessInfo.processInfo.systemUptime
    var request = URLRequest(url: url)
    request.setValue(
      "Aerie/0.1 (+https://github.com/MattFlower/aerie)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    guard !closed, generation == token else { throw CancellationError() }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw MapError.invalidResponse
    }
    guard data.count <= 2_000_000 else { throw MapError.oversized }; return data
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(request.url.map(WMS.allowed) == true ? request : nil)
  }
  func suspendRequests() { generation += 1; session?.invalidateAndCancel(); session = nil }
  func close() { closed = true; suspendRequests() }
  deinit { close() }
}

struct MapRaster {
  let image: NSImage
  let cost: Int
  static func decode(_ data: Data) throws -> MapRaster {
    guard data.count <= 2_000_000,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 1024, height <= 2048,
      width * height <= 1_048_576,
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { throw MapError.invalidResponse }
    let cost = max(image.bytesPerRow * image.height, width * height * 4)
    guard cost <= 8 * 1_048_576 else { throw MapError.oversized }
    return MapRaster(
      image: NSImage(cgImage: image, size: NSSize(width: width, height: height)), cost: cost)
  }
}

final class MapLegendView: NSImageView { override var isFlipped: Bool { true } }

final class MapRasterView: NSView {
  override var isFlipped: Bool { true }
  var base: NSImage?
  var raster: NSImage?
  var alerts: NSImage?
  var onPan: ((Double, Double) -> Void)?
  private var dragStart: NSPoint?
  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlBackgroundColor.setFill(); bounds.fill()
    for image in [raster, base, alerts].compactMap({ $0 }) {
      image.draw(
        in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
        hints: nil)
    }
    if raster == nil {
      let text = "Select a layer to load its available imagery"
      text.draw(
        at: NSPoint(x: 26, y: 26), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }
  }
  override func mouseDown(with event: NSEvent) {
    dragStart = convert(event.locationInWindow, from: nil)
  }
  override func mouseUp(with event: NSEvent) {
    guard let start = dragStart else { return }; dragStart = nil
    let end = convert(event.locationInWindow, from: nil)
    if abs(end.x - start.x) + abs(end.y - start.y) > 4 {
      onPan?(Double((end.x - start.x) / bounds.width), Double((end.y - start.y) / bounds.height))
    }
  }
  func clear() { base = nil; raster = nil; alerts = nil; needsDisplay = true }
}

/// Created only after explicit map/provider/location consent, released on close.
final class WeatherMapWindowController: NSWindowController, NSWindowDelegate {
  private let configuration: WeatherConfiguration
  private let client = MapHTTPClient()
  private var task: Task<Void, Never>?
  private var generation = 0
  private var animation: Timer?
  private var refreshTimer: Timer?
  private var cache = CostCache<String, MapRaster>(maximumCost: 16 * 1_048_576, maximumCount: 12)
  private var metadata: [WeatherMapKind: [WMSLayer]] = [:]
  private var selection = MapSelection()
  private var activity = MapActivity()
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var alertDetailsWindow: NSWindow?
  private weak var alertDetailsText: NSTextView?
  private var selected: WMSLayer? { selection.layer }
  private var times: [Date] { selection.timeline.times }
  private var frame: Int { selection.frame }
  private var kind: WeatherMapKind { selection.kind }
  private var latitude: Double
  private var longitude: Double
  private var span = 16.0
  private var closed = false
  private let canvas = MapRasterView(frame: NSRect(x: 16, y: 125, width: 512, height: 512))
  private let picker = NSPopUpButton(
    frame: NSRect(x: 16, y: 652, width: 260, height: 28), pullsDown: false)
  private let variants = NSPopUpButton(
    frame: NSRect(x: 290, y: 652, width: 398, height: 28), pullsDown: false)
  private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let timestamp = NSTextField(labelWithString: "")
  private let alertTimestamp = NSTextField(labelWithString: "")
  private let status = NSTextField(wrappingLabelWithString: "Loading metadata…")
  private let legend = MapLegendView(frame: NSRect(x: 0, y: 0, width: 145, height: 395))
  private let caption = NSTextField(wrappingLabelWithString: "")
  private let play = NSButton(title: "Play", target: nil, action: nil)
  private let alertToggle = NSButton(
    checkboxWithTitle: "Official alert overlay", target: nil, action: nil)
  private let formatter = DateFormatter()
  var onClose: (() -> Void)?

  init(configuration: WeatherConfiguration) throws {
    guard configuration.mapsValid else { throw MapError.consentRequired }
    self.configuration = configuration
    latitude = (configuration.latitude * 100).rounded() / 100
    longitude = (configuration.longitude * 100).rounded() / 100
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 710, height: 702),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Aerie Weather Maps · \(configuration.name)"; window.isReleasedWhenClosed = false
    super.init(window: window); window.delegate = self
    formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE d MMM HH:mm 'UTC'"
    build(); window.center(); observeLifecycle()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private var bounds: MapBounds { .centered(latitude: latitude, longitude: longitude, span: span) }
  private func build() {
    guard let view = window?.contentView else { return }
    picker.addItems(withTitles: WeatherMapKind.allCases.map(\.title)); picker.target = self;
    picker.action = #selector(changeKind)
    variants.target = self; variants.action = #selector(changeVariant)
    view.addSubview(picker); view.addSubview(variants); view.addSubview(canvas)
    canvas.onPan = { [weak self] dx, dy in
      guard let self else { return };
      self.longitude = min(180, max(-180, self.longitude - dx * self.span))
      self.latitude = min(85, max(-85, self.latitude + dy * self.span));
      self.load(metadataNeeded: false)
    }
    slider.frame = NSRect(x: 16, y: 87, width: 512, height: 24); slider.isContinuous = false
    slider.target = self; slider.action = #selector(changeFrame); view.addSubview(slider)
    timestamp.frame = NSRect(x: 16, y: 61, width: 510, height: 20);
    timestamp.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    view.addSubview(timestamp)
    alertTimestamp.frame = NSRect(x: 16, y: 111, width: 512, height: 13)
    alertTimestamp.font = .systemFont(ofSize: 10); view.addSubview(alertTimestamp)
    status.frame = NSRect(x: 16, y: 12, width: 670, height: 42);
    status.font = .systemFont(ofSize: 11)
    view.addSubview(status)
    let legendScroll = NSScrollView(frame: NSRect(x: 545, y: 308, width: 145, height: 327))
    legendScroll.documentView = legend; legendScroll.hasVerticalScroller = true
    legendScroll.autohidesScrollers = true; legendScroll.drawsBackground = false
    view.addSubview(legendScroll); legend.imageScaling = .scaleNone;
    legend.imageAlignment = .alignTop
    caption.frame = NSRect(x: 545, y: 212, width: 145, height: 90);
    caption.font = .systemFont(ofSize: 11)
    view.addSubview(caption)
    play.frame = NSRect(x: 545, y: 87, width: 65, height: 28); play.target = self;
    play.action = #selector(togglePlay); view.addSubview(play)
    let refresh = NSButton(title: "Refresh", target: self, action: #selector(refresh))
    refresh.frame = NSRect(x: 616, y: 87, width: 73, height: 28); view.addSubview(refresh)
    alertToggle.frame = NSRect(x: 540, y: 186, width: 170, height: 24); alertToggle.target = self
    alertToggle.action = #selector(changeOverlay); view.addSubview(alertToggle)
    let details = NSButton(
      title: "Alert details at center…", target: self, action: #selector(showAlerts))
    details.frame = NSRect(x: 539, y: 160, width: 166, height: 24); view.addSubview(details)
    let zoomIn = NSButton(title: "+", target: self, action: #selector(zoomIn))
    zoomIn.frame = NSRect(x: 548, y: 131, width: 60, height: 24); view.addSubview(zoomIn)
    let zoomOut = NSButton(title: "−", target: self, action: #selector(zoomOut))
    zoomOut.frame = NSRect(x: 616, y: 131, width: 60, height: 24); view.addSubview(zoomOut)
    let source = NSButton(title: "NOAA/NWS sources", target: self, action: #selector(openSource))
    source.frame = NSRect(x: 542, y: 58, width: 155, height: 26); view.addSubview(source)
    canvas.setAccessibilityLabel(
      "NOAA weather imagery. Drag to pan; plus and minus change map extent.")
  }
  @objc private func openSource() {
    NSWorkspace.shared.open(URL(string: "https://www.weather.gov/gis/cloudgiswebservices")!)
  }
  @objc private func showAlerts() {
    guard activity.active else { return }
    selection.playing = false; stopAnimation()
    if alertDetailsWindow == nil {
      let panel = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 580, height: 480),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      panel.title = "Aerie · Current NWS alerts at map center"; panel.isReleasedWhenClosed = false
      panel.delegate = self
      let scroll = NSScrollView(frame: panel.contentView!.bounds)
      scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
      let text = NSTextView(frame: scroll.bounds)
      text.isEditable = false; text.isSelectable = true; text.isRichText = false
      text.font = .systemFont(ofSize: 13); text.textContainerInset = NSSize(width: 14, height: 14)
      text.autoresizingMask = [.width]; text.isVerticallyResizable = true;
      text.isHorizontallyResizable = false
      text.textContainer?.widthTracksTextView = true
      scroll.documentView = text; panel.contentView?.addSubview(scroll)
      alertDetailsWindow = panel; alertDetailsText = text; panel.center()
    }
    alertDetailsText?.string = "Loading current NWS alerts for the map center…"
    alertDetailsWindow?.makeKeyAndOrderFront(nil)
    run { controller in
      do {
        let url = try WeatherAlerts.request(
          latitude: controller.latitude, longitude: controller.longitude)
        let data = try await controller.client.data(url); try Task.checkCancellation()
        let report = try WeatherAlerts.parse(data, fetched: Date())
        controller.alertDetailsText?.string = AlertPresentation.text(report)
      } catch is CancellationError { throw CancellationError() } catch {
        controller.alertDetailsText?.string =
          "Current alert details are unavailable. Close this view and retry later. Map coverage and point-message coverage may differ."
      }
    }
  }
  @objc private func changeKind() {
    selection.select(kind: WeatherMapKind.allCases[picker.indexOfSelectedItem])
    load(metadataNeeded: true)
  }
  @objc private func changeVariant() {
    if let layers = metadata[kind], layers.indices.contains(variants.indexOfSelectedItem) {
      selection.select(layer: layers[variants.indexOfSelectedItem]); load(metadataNeeded: false)
    }
  }
  @objc private func zoomIn() { span = max(1, span / 2); load(metadataNeeded: false) }
  @objc private func zoomOut() { span = min(160, span * 2); load(metadataNeeded: false) }
  @objc private func changeOverlay() { load(metadataNeeded: false) }
  @objc private func refresh() {
    guard activity.active else { return }
    metadata.removeValue(forKey: kind)
    if kind != .alerts { metadata.removeValue(forKey: .alerts) }
    load(metadataNeeded: true)
  }
  @objc private func changeFrame() {
    selection.playing = false; stopAnimation()
    selection.select(frame: Int(slider.doubleValue.rounded()))
    run { controller in try await controller.showFrame(controller.frame) }
  }
  private func stopAnimation() { animation?.invalidate(); animation = nil; play.title = "Play" }
  private func run(
    _ operation: @escaping @MainActor (WeatherMapWindowController) async throws -> Void
  ) {
    guard !closed, activity.active else { return }
    task?.cancel(); generation += 1; let token = generation
    task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { if self.generation == token { self.task = nil } }
      do { try await operation(self); try Task.checkCancellation() } catch is CancellationError {
        return
      } catch {
        if self.generation == token && !self.closed && self.activity.active {
          self.status.stringValue =
            "Layer request unavailable. Check coverage or refresh later."
        }
      }
    }
  }
  private func load(metadataNeeded: Bool) {
    guard activity.active else { return }
    stopAnimation(); canvas.clear(); legend.image = nil; alertTimestamp.stringValue = "";
    cache.clear()
    timestamp.stringValue = "Loading valid times…"
    status.stringValue = "Loading NOAA/NWS layer…"
    run { controller in
      if metadataNeeded && controller.metadata[controller.kind] == nil {
        let url = try WMS.capabilities(controller.kind.endpoint)
        let data = try await controller.client.data(url); try Task.checkCancellation()
        controller.metadata[controller.kind] = try WMS.parse(data)
      }
      try Task.checkCancellation()
      guard let layers = controller.metadata[controller.kind] else {
        throw MapError.invalidMetadata
      }
      try controller.selection.reconcile(layers: layers, now: Date())
      guard let selected = controller.selected else { throw MapError.unavailableLayer }
      controller.variants.removeAllItems()
      if controller.kind == .stormTracks {
        controller.variants.addItem(withTitle: selected.title);
        controller.variants.isEnabled = false
      } else {
        controller.variants.addItems(withTitles: layers.map(\.title));
        controller.variants.isEnabled = layers.count > 1
        controller.variants.selectItem(
          at: layers.firstIndex(where: { $0.name == selected.name }) ?? 0)
      }
      controller.slider.maxValue = Double(max(1, controller.times.count - 1));
      controller.slider.isEnabled = controller.times.count > 1
      controller.play.isEnabled = controller.times.count > 1
      controller.caption.stringValue =
        controller.kind == .rain
        ? "US · 6-hour precipitation forecast (inches), ending at selected valid time."
        : controller.kind == .snow
          ? "US · 6-hour snow forecast (inches), ending at selected valid time."
          : controller.kind.coverage
      controller.caption.toolTip = selected.abstract
      guard controller.selection.timeline.available else {
        if case .unavailable(let latest) = controller.selection.timeline {
          controller.timestamp.stringValue =
            latest.map {
              "Latest advertised: " + controller.formatter.string(from: $0)
            } ?? "No usable advertised valid time"
        }
        controller.status.stringValue =
          "No current frames available for this time-enabled layer. Refresh later."
        return
      }
      let baseURL = try WMS.image(
        endpoint: WMS.baseEndpoint, layer: WMSLayer(name: "3", title: "NWS state boundaries"),
        bounds: controller.bounds, time: nil)
      if let base = try? await controller.client.data(baseURL), !Task.isCancelled {
        controller.canvas.base = try? MapRaster.decode(base).image
      }
      try Task.checkCancellation()
      if controller.alertToggle.state == .on {
        if controller.metadata[.alerts] == nil {
          let data = try await controller.client.data(
            WMS.capabilities(WeatherMapKind.alerts.endpoint))
          try Task.checkCancellation(); controller.metadata[.alerts] = try WMS.parse(data)
        }
        let layer = try WeatherMapKind.alerts.preferred(controller.metadata[.alerts] ?? [])
        let url = try WMS.image(
          endpoint: WeatherMapKind.alerts.endpoint,
          layer: layer, bounds: controller.bounds,
          time: nil)
        let data = try await controller.client.data(url); try Task.checkCancellation()
        controller.canvas.alerts = try MapRaster.decode(data).image
        controller.alertTimestamp.stringValue =
          "Current NWS watches/warnings/advisories · fetched \(controller.formatter.string(from: Date()))"
      }
      try Task.checkCancellation(); try await controller.showFrame(controller.frame)
      do {
        let url = try WMS.legend(endpoint: controller.kind.endpoint, layer: selected)
        if let data = try? await controller.client.data(url), !Task.isCancelled {
          if let raster = try? MapRaster.decode(data) {
            controller.legend.image = raster.image
            controller.legend.setFrameSize(
              NSSize(width: 145, height: max(395, raster.image.size.height)))
          }
        }
      }
      try Task.checkCancellation()
      if controller.selection.playing { controller.startPlayback() }
    }
  }
  @MainActor private func raster(at index: Int) async throws -> MapRaster {
    guard activity.active, selection.timeline.available, let selected else {
      throw MapError.unavailableLayer
    }
    let time = times.indices.contains(index) ? times[index] : nil
    let key = time.map { ISO8601DateFormatter().string(from: $0) } ?? "latest"
    let raster: MapRaster
    if let cached = cache.value(for: key) {
      raster = cached
    } else {
      let url = try WMS.image(endpoint: kind.endpoint, layer: selected, bounds: bounds, time: time)
      raster = try MapRaster.decode(await client.data(url)); try Task.checkCancellation()
      guard !closed, activity.active else { throw CancellationError() }
      cache.insert(raster, for: key, cost: raster.cost)
    }
    try Task.checkCancellation(); return raster
  }
  @MainActor private func showFrame(_ index: Int) async throws {
    let raster = try await raster(at: index)
    canvas.raster = raster.image; canvas.needsDisplay = true
    selection.select(frame: index); slider.doubleValue = Double(index)
    let time = selection.time
    timestamp.stringValue =
      time.map {
        (kind.forecast ? "Forecast valid/end: " : "Observation: ") + formatter.string(from: $0)
      } ?? "No service valid time · fetched \(formatter.string(from: Date()))"
    let product =
      kind == .stormTracks
      ? "Past observations + forecast tracks"
      : kind.forecast ? "Forecast" : "Observed/current product"
    status.stringValue =
      "NOAA/NWS · \(selected?.title ?? kind.title) · \(product) · \(cache.count) cached frames. Drag to pan."
  }
  @objc private func togglePlay() {
    if selection.playing { selection.playing = false; task?.cancel(); stopAnimation(); return }
    guard times.count > 1, activity.active else { return }
    selection.playing = true; startPlayback()
  }
  private func startPlayback() {
    guard selection.playing, times.count > 1, activity.active else { return }
    let initial = frame
    let first = kind.forecast ? min(frame, max(0, times.count - 12)) : max(0, frame - 11)
    let indices = Array(first..<min(times.count, first + 12))
    run { controller in
      for (offset, index) in indices.enumerated() {
        controller.status.stringValue = "Loading animation \(offset + 1)/\(indices.count)…"
        _ = try await controller.raster(at: index)
      }
      try Task.checkCancellation()
      try await controller.showFrame(initial)
      var position = indices.firstIndex(of: initial) ?? 0; controller.play.title = "Pause"
      controller.animation = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) {
        [weak controller] _ in
        guard let controller, !controller.closed, controller.activity.active else { return }
        let index = indices[position % indices.count]; position += 1
        controller.run { try await $0.showFrame(index) }
      }
      controller.animation?.tolerance = 0.05
    }
  }
  override func showWindow(_ sender: Any?) { super.showWindow(sender); updateVisibility() }
  func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
  func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
  func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
  private func observeLifecycle() {
    for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
      let center = NotificationCenter.default
      let token = center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
        self?.updateVisibility()
      }
      observers.append((center, token))
    }
    let center = NSWorkspace.shared.notificationCenter
    for (name, sleeping) in [
      (NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
    ] {
      let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }; self.activity.sleeping = sleeping; self.updateVisibility()
      }
      observers.append((center, token))
    }
  }
  private func updateVisibility() {
    activity.windowVisible =
      window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    activity.miniaturized = window?.isMiniaturized == true
    activity.applicationHidden = NSApp.isHidden; activity.closed = closed
    switch activity.reconcile() {
    case .suspend:
      generation += 1; task?.cancel(); task = nil; stopAnimation()
      refreshTimer?.invalidate(); refreshTimer = nil; client.suspendRequests()
      cache.clear(); canvas.clear(); legend.image = nil; alertTimestamp.stringValue = ""
      alertDetailsText?.string =
        "Map requests are paused. Close and reopen alert details after the map is visible to refresh current messages."
      status.stringValue =
        "Map requests paused while this window is not visible or the Mac is asleep."
    case .resume:
      refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
        self?.refresh()
      }
      refreshTimer?.tolerance = 5; refresh()
    case .unchanged: break
    }
  }
  func windowWillClose(_ notification: Notification) {
    if let closing = notification.object as? NSWindow, closing === alertDetailsWindow {
      generation += 1; task?.cancel(); task = nil; client.suspendRequests()
      alertDetailsText?.string = ""; alertDetailsText = nil; alertDetailsWindow = nil; return
    }
    releaseResources(); onClose?()
  }
  func releaseResources() {
    closed = true; generation += 1; task?.cancel(); task = nil; stopAnimation()
    refreshTimer?.invalidate(); refreshTimer = nil; client.close()
    activity.closed = true; activity.reconcile()
    for (center, token) in observers { center.removeObserver(token) }; observers.removeAll()
    cache.clear(); metadata.removeAll(); selection = MapSelection()
    canvas.clear(); legend.image = nil; alertTimestamp.stringValue = ""
    alertDetailsText?.string = ""; alertDetailsText = nil
    alertDetailsWindow?.delegate = nil; alertDetailsWindow?.close(); alertDetailsWindow = nil
  }
  deinit {
    task?.cancel(); animation?.invalidate(); refreshTimer?.invalidate(); client.close()
    for (center, token) in observers { center.removeObserver(token) }
  }
}
