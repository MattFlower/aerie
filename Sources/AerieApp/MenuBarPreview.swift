import AppKit
import AerieCore

/// Uses the same native images and point geometry as the actual grouped status item.
final class MenuBarPreview: NSView {
  private var images: [NSImage] = []
  private var gap: CGFloat = 0
  private(set) var moduleWidths: [(Module, CGFloat)] = []
  @discardableResult func update(_ widgets: [StatusWidget], padding: CGFloat, gap: CGFloat)
    -> CGFloat
  {
    let bounded = Array(widgets.prefix(Module.allCases.count))
    self.gap = gap
    images = bounded.map { MenuRenderer.widget($0, padding: padding) }
    moduleWidths = zip(bounded, images).map { ($0.module, $1.size.width) }
    let width = images.reduce(0) { $0 + $1.size.width } + CGFloat(max(0, images.count - 1)) * gap
    frame.size = NSSize(width: max(20, width), height: 30)
    setAccessibilityElement(true); setAccessibilityRole(.image)
    setAccessibilityLabel("Menu-bar preview, \(Int(ceil(width))) points")
    needsDisplay = true; return width
  }
  override func draw(_ dirtyRect: NSRect) {
    var x: CGFloat = 0
    for image in images {
      image.draw(in: NSRect(x: x, y: 5, width: image.size.width, height: 20))
      x += image.size.width + gap
    }
  }
}
