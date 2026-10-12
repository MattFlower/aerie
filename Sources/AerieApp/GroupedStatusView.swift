import AerieCore
import AppKit

private final class StatusSegmentElement: NSAccessibilityElement {
  weak var owner: GroupedStatusView?
  var index = 0
  override func accessibilityParent() -> Any? { owner }
  override func accessibilityFrame() -> NSRect { owner?.screenFrame(index: index) ?? .zero }
  override func accessibilityPerformPress() -> Bool { owner?.press(index: index) ?? false }
}

/// One native status item with bounded, individually actionable module segments.
final class GroupedStatusView: NSView {
  private(set) var widgets: [StatusWidget] = []
  private(set) var segments: [NSRect] = []
  private var images: [NSImage] = []
  private var elements: [StatusSegmentElement] = []
  private var selected = 0
  private var padding: CGFloat = -1, gap: CGFloat = -1
  var onSelect: ((Module) -> Void)?
  var onContext: (() -> Void)?
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.group);
    setAccessibilityLabel("Aerie menu-bar modules")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var acceptsFirstResponder: Bool { true }
  @discardableResult func update(_ descriptors: [StatusWidget], padding: CGFloat, gap: CGFloat)
    -> CGFloat
  {
    let bounded = Array(descriptors.prefix(Module.allCases.count))
    guard widgets != bounded || self.padding != padding || self.gap != gap else {
      return frame.width
    }
    widgets = bounded; self.padding = padding; self.gap = gap
    images = widgets.map { MenuRenderer.widget($0, padding: padding) }
    segments.removeAll(keepingCapacity: true)
    var x: CGFloat = 0
    for image in images {
      segments.append(NSRect(x: x, y: 0, width: image.size.width, height: 24))
      x += image.size.width + gap
    }
    frame.size = NSSize(width: max(20, x - (images.isEmpty ? 0 : gap)), height: 24)
    elements = widgets.enumerated().map { index, widget in
      let element = StatusSegmentElement(); element.owner = self; element.index = index
      element.setAccessibilityRole(.button); element.setAccessibilityLabel(widget.accessibility)
      return element
    }
    selected = min(selected, max(0, widgets.count - 1)); needsDisplay = true
    return frame.width
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    images = widgets.map { MenuRenderer.widget($0, padding: padding) }; needsDisplay = true
  }
  override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
  override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
  override var focusRingMaskBounds: NSRect {
    segments.indices.contains(selected) ? segments[selected].insetBy(dx: 1, dy: 2) : .zero
  }
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 3, yRadius: 3).fill()
  }
  override func draw(_ dirtyRect: NSRect) {
    for (index, image) in images.enumerated() {
      image.draw(
        in: NSRect(
          x: segments[index].minX, y: (bounds.height - 20) / 2, width: image.size.width, height: 20)
      )
    }
  }
  func module(at point: NSPoint) -> Module? {
    guard let index = segments.firstIndex(where: { $0.contains(point) }),
      widgets.indices.contains(index)
    else { return nil }
    return widgets[index].module
  }
  /// NSStatusBarButton may receive the tracked click instead of its child view.
  /// Pointer activation uses the same rectangles as drawing; gaps never select a neighbor.
  @discardableResult func activate(at point: NSPoint?) -> Bool {
    guard let point else { return press(index: selected) }
    guard let index = segments.firstIndex(where: { $0.contains(point) }) else { return false }
    return press(index: index)
  }
  @discardableResult func activate(from event: NSEvent?) -> Bool {
    guard let event else { return activate(at: nil) }
    switch event.type {
    case .leftMouseDown, .leftMouseUp:
      guard let window else { return false }
      let position =
        event.window === window
        ? event.locationInWindow : window.convertPoint(fromScreen: NSEvent.mouseLocation)
      return activate(at: convert(position, from: nil))
    default: return activate(at: nil)
    }
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
  }
  override func mouseUp(with event: NSEvent) {
    _ = activate(at: convert(event.locationInWindow, from: nil))
  }
  override func rightMouseUp(with event: NSEvent) { onContext?() }
  override func keyDown(with event: NSEvent) {
    guard !widgets.isEmpty else { return }
    switch event.keyCode {
    case 123: selected = max(0, selected - 1)
    case 124: selected = min(widgets.count - 1, selected + 1)
    case 36, 49, 125: _ = press(index: selected)
    default: super.keyDown(with: event)
    }
    needsDisplay = true; noteFocusRingMaskChanged()
  }
  @discardableResult func press(index: Int) -> Bool {
    guard widgets.indices.contains(index), let onSelect else { return false }
    selected = index; onSelect(widgets[index].module); return true
  }
  func screenFrame(index: Int) -> NSRect {
    guard segments.indices.contains(index), let window else { return .zero }
    return window.convertToScreen(convert(segments[index], to: nil))
  }
  override func accessibilityChildren() -> [Any]? { elements }
  override func accessibilityPerformPress() -> Bool { press(index: selected) }
  func releaseContent() {
    widgets.removeAll(); images.removeAll(); segments.removeAll(); elements.removeAll()
    onSelect = nil; onContext = nil
  }
}
